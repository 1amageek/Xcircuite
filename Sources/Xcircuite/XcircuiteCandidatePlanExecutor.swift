import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanExecutor: Sendable {
    let workspaceStore: XcircuiteWorkspaceStore
    let artifactStore: XcircuitePlanningArtifactStore
    let layoutRunner: any LayoutCommandRunning
    let artifactBuilder: StageArtifactReferenceBuilder
    let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        layoutRunner: any LayoutCommandRunning = LayoutCommandRunner(),
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.layoutRunner = layoutRunner
        self.artifactBuilder = StageArtifactReferenceBuilder()
        self.artifactVerifier = artifactVerifier
    }

    public func executeCandidatePlan(
        request: XcircuiteCandidatePlanExecutionRequest,
        projectRoot: URL
    ) async throws -> XcircuiteCandidatePlanExecutionResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try await loadRunManifest(runID: request.runID)
        let expectedCandidatePlanArtifactID: String?
        if let artifactID = request.candidatePlanArtifactID {
            expectedCandidatePlanArtifactID = artifactID
        } else if request.candidatePlanPath == nil {
            let generatedReferences = XcircuitePlanningArtifactStore
                .generatedCandidatePlanReferences(in: manifest)
            guard generatedReferences.count <= 1 else {
                throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                    path: XcircuitePlanningArtifactStore.generatedCandidatePlanDirectory,
                    reason: "multiple generated candidate plans are retained; specify an artifact ID or path."
                )
            }
            expectedCandidatePlanArtifactID = generatedReferences.first?.artifactID
                ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID
        } else {
            expectedCandidatePlanArtifactID = nil
        }
        let currentCandidatePlanRef = try requiredCandidatePlanReference(
            explicitPath: request.candidatePlanPath,
            artifactID: expectedCandidatePlanArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let candidatePlanContent = try await workspaceStore.loadArtifactContent(
            for: currentCandidatePlanRef
        )
        let plan = try JSONDecoder().decode(XcircuiteCandidatePlan.self, from: candidatePlanContent)
        guard plan.runID == request.runID else {
            throw XcircuiteCandidatePlanExecutionError.runMismatch(
                expected: request.runID,
                actual: plan.runID
            )
        }
        let candidatePlanRef = try await artifactStore.persistCandidatePlanSnapshot(
            plan,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let riskReviewer = XcircuiteCandidatePlanRiskReviewer()
        let approvals = try await workspaceStore.loadRunApprovals(runID: request.runID)
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
                artifactReferences: [],
                executionCoverage: executionCoverage(stepResults: stepResults, artifactReferences: []),
                diagnostics: diagnostics,
                nextActions: riskReviewer.nextActions(from: riskReviews)
            )
            let executionRef = try await artifactStore.persistPlanExecution(
                execution,
                runID: plan.runID,
                projectRoot: projectRoot
            )
            try await appendActionRecord(
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
            latestLayoutDocumentPath: try await initialLayoutDocumentPathIfNeeded(
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
        let producedArtifactReferences = stepResults.flatMap(\.artifactReferences)
        let coverage = executionCoverage(
            stepResults: stepResults,
            artifactReferences: producedArtifactReferences
        )
        let diagnostics = stepResults.flatMap(\.diagnostics)
        let nextActions = unique(stepResults.flatMap(\.nextActions) + signoffNextActions(for: plan))
        let status = executionStatus(stepResults)

        let designDiffRef = try await writeDesignDiff(
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
            artifactReferences: producedArtifactReferences,
            executionCoverage: coverage,
            designDiffRef: designDiffRef,
            diagnostics: diagnostics,
            nextActions: nextActions
        )
        let executionRef = try await artifactStore.persistPlanExecution(
            execution,
            runID: plan.runID,
            projectRoot: projectRoot
        )
        try await appendActionRecord(
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
            producedArtifacts: producedArtifactReferences,
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
    var format: ArtifactFormat
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
