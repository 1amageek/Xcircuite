import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import XcircuitePackage

public struct XcircuiteCandidatePlanExecutor: Sendable {
    let packageStore: XcircuitePackageStore
    let artifactStore: XcircuitePlanningArtifactStore
    let layoutRunner: any LayoutCommandRunning
    let artifactBuilder: StageArtifactReferenceBuilder
    let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        layoutRunner: any LayoutCommandRunning = LayoutCommandRunner(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.layoutRunner = layoutRunner
        self.artifactBuilder = StageArtifactReferenceBuilder()
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func executeCandidatePlan(
        request: XcircuiteCandidatePlanExecutionRequest,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanExecutionResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let candidatePlanRef = try requiredCandidatePlanReference(
            explicitPath: request.candidatePlanPath,
            artifactID: request.candidatePlanArtifactID ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        guard let candidatePlanURL = fileReferenceVerifier.resolvedURL(
            for: candidatePlanRef,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                path: candidatePlanRef.path,
                reason: "candidate plan path cannot be resolved inside the project root."
            )
        }
        let plan = try packageStore.readJSON(
            XcircuiteCandidatePlan.self,
            from: candidatePlanURL
        )
        guard plan.runID == request.runID else {
            throw XcircuiteCandidatePlanExecutionError.runMismatch(
                expected: request.runID,
                actual: plan.runID
            )
        }
        let riskReviewer = XcircuiteCandidatePlanRiskReviewer()
        let approvals = try packageStore.loadApprovals(
            runID: request.runID,
            inProjectAt: projectRoot
        )
        let riskReviews = riskReviewer.riskReviews(for: plan, approvals: approvals)
        if riskReviewer.blocksExecution(riskReviews) {
            let diagnostics = riskReviewer.blockingDiagnostics(from: riskReviews)
            let stepResults = policyBlockedStepResults(
                plan: plan,
                riskReviews: riskReviews,
                diagnostics: diagnostics
            )
            let execution = XcircuiteCandidatePlanExecution(
                runID: plan.runID,
                problemID: plan.problemID,
                planID: plan.planID,
                status: "blocked",
                candidatePlanRef: candidatePlanRef,
                stepResults: stepResults,
                artifactRefs: [],
                executionCoverage: executionCoverage(stepResults: stepResults, artifactRefs: []),
                diagnostics: diagnostics,
                nextActions: riskReviewer.nextActions(from: riskReviews)
            )
            let executionRef = try artifactStore.persistPlanExecution(
                execution,
                runID: plan.runID,
                projectRoot: projectRoot
            )
            try appendActionRecord(
                execution: execution,
                candidatePlanRef: candidatePlanRef,
                executionRef: executionRef,
                designDiffRef: nil,
                projectRoot: projectRoot
            )
            return XcircuiteCandidatePlanExecutionResult(
                status: execution.status,
                runID: plan.runID,
                problemID: plan.problemID,
                planID: plan.planID,
                candidatePlanPath: candidatePlanRef.path,
                planExecutionArtifact: executionRef,
                producedArtifacts: [],
                nextActions: execution.nextActions
            )
        }

        var context = CandidatePlanExecutionContext(
            latestLayoutDocumentPath: try initialLayoutDocumentPathIfNeeded(
                for: plan,
                projectRoot: projectRoot
            ),
            latestNetlistPath: nil
        )
        var stepResults: [XcircuiteCandidatePlanExecutionStepResult] = []
        for step in plan.steps.sorted(by: { $0.order < $1.order }) {
            stepResults.append(try await execute(
                step: step,
                plan: plan,
                projectRoot: projectRoot,
                context: &context
            ))
        }
        let producedArtifacts = stepResults.flatMap(\.artifactRefs)
        let coverage = executionCoverage(stepResults: stepResults, artifactRefs: producedArtifacts)
        let diagnostics = stepResults.flatMap(\.diagnostics)
        let nextActions = unique(stepResults.flatMap(\.nextActions) + signoffNextActions(for: plan))
        let status = executionStatus(stepResults)

        let designDiffRef = try writeDesignDiff(
            plan: plan,
            stepResults: stepResults,
            actor: request.actor,
            projectRoot: projectRoot
        )
        let execution = XcircuiteCandidatePlanExecution(
            runID: plan.runID,
            problemID: plan.problemID,
            planID: plan.planID,
            status: status,
            candidatePlanRef: candidatePlanRef,
            stepResults: stepResults,
            artifactRefs: producedArtifacts,
            executionCoverage: coverage,
            designDiffRef: designDiffRef,
            diagnostics: diagnostics,
            nextActions: nextActions
        )
        let executionRef = try artifactStore.persistPlanExecution(
            execution,
            runID: plan.runID,
            projectRoot: projectRoot
        )
        try appendActionRecord(
            execution: execution,
            candidatePlanRef: candidatePlanRef,
            executionRef: executionRef,
            designDiffRef: designDiffRef,
            projectRoot: projectRoot
        )
        return XcircuiteCandidatePlanExecutionResult(
            status: status,
            runID: plan.runID,
            problemID: plan.problemID,
            planID: plan.planID,
            candidatePlanPath: candidatePlanRef.path,
            planExecutionArtifact: executionRef,
            designDiffArtifact: designDiffRef,
            producedArtifacts: producedArtifacts,
            nextActions: nextActions
        )
    }
}

struct CandidatePlanExecutionContext {
    var latestLayoutDocumentPath: String?
    var latestNetlistPath: String?
}

struct CandidatePlanStandardLayoutArtifact: Sendable, Hashable {
    var url: URL
    var artifactID: String
    var format: XcircuiteFileFormat
}

struct CandidatePlanLayoutCommandArtifacts: Sendable, Hashable {
    var outputDocumentURL: URL
    var manifestURL: URL
    var resultURL: URL
}

enum CandidatePlanStandardLayoutExportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case technologyLoadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Candidate plan standard layout export does not support format \(format)."
        case .technologyLoadFailed(let path, let reason):
            "Failed to load standard layout export technology at \(path): \(reason)."
        }
    }
}

extension ParsedSubcircuit {
    func replacingBody(
        components: [ParsedComponent]? = nil,
        subcircuits: [ParsedSubcircuit]? = nil
    ) -> ParsedSubcircuit {
        ParsedSubcircuit(
            name: name,
            ports: ports,
            parameters: parameters,
            body: ParsedNetlistBody(
                components: components ?? body.components,
                models: body.models,
                subcircuits: subcircuits ?? body.subcircuits,
                parameters: body.parameters,
                parameterDefinitions: body.parameterDefinitions
            ),
            location: location
        )
    }
}

struct EditedNetlist {
    var netlist: ParsedNetlist
    var edits: [XcircuiteNetlistParameterEdit]
}
