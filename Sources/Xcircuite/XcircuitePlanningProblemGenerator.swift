import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel
import CircuiteFoundation

public struct XcircuitePlanningProblemGenerator: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let builder: XcircuiteDiagnosticPlanningProblemBuilder
    private let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        builder: XcircuiteDiagnosticPlanningProblemBuilder = XcircuiteDiagnosticPlanningProblemBuilder(),
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.builder = builder
        self.artifactVerifier = artifactVerifier
    }

    public func generateRepairProblem(
        request: XcircuitePlanningProblemGenerationRequest,
        projectRoot: URL
    ) async throws -> XcircuitePlanningProblemGenerationResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try await loadRunManifest(runID: request.runID)
        let summaryPath = try await requiredPath(
            explicitPath: request.summaryPath,
            artifactID: request.summaryArtifactID ?? request.source.rawValue,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let layoutPath = try await optionalPath(
            explicitPath: request.layoutPath,
            artifactID: request.layoutArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let actionDomainPath = try await optionalPath(
            explicitPath: request.actionDomainPath,
            artifactID: request.actionDomainArtifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            missingDefaultIsAllowed: true
        )
        let technologyPath = try await optionalPath(
            explicitPath: request.technologyPath,
            artifactID: request.technologyArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let repairHintPath = try await optionalPath(
            explicitPath: request.repairHintPath,
            artifactID: request.repairHintArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problem: XcircuiteCircuitPlanningProblem
        switch request.source {
        case .drcSummary:
            let summary = try await loadProjectJSON(
                DRCRunSummaryReport.self,
                from: summaryPath
            )
            let repairHints = try await loadDRCRepairHintsIfPresent(
                path: repairHintPath
            )
            problem = try builder.makeDRCRepairProblem(
                runID: request.runID,
                summary: summary,
                summaryArtifactPath: summaryPath,
                layoutArtifactPath: layoutPath,
                layoutNetlistPath: request.layoutNetlistPath,
                schematicNetlistPath: request.schematicNetlistPath,
                repairHints: repairHints,
                repairHintArtifactPath: repairHintPath,
                actionDomainArtifactPath: actionDomainPath
            )
        case .lvsSummary:
            let summary = try await loadProjectJSON(
                LVSRunSummaryReport.self,
                from: summaryPath
            )
            let repairHints = try await loadLVSRepairHintsIfPresent(
                path: repairHintPath
            )
            problem = try builder.makeLVSRepairProblem(
                runID: request.runID,
                summary: summary,
                summaryArtifactPath: summaryPath,
                layoutArtifactPath: layoutPath,
                layoutNetlistPath: request.layoutNetlistPath,
                schematicNetlistPath: request.schematicNetlistPath,
                repairHints: repairHints,
                repairHintArtifactPath: repairHintPath,
                actionDomainArtifactPath: actionDomainPath
            )
        case .pexSummary:
            let summary = try await loadProjectJSON(
                PEXRunSummaryReport.self,
                from: summaryPath
            )
            let metricReport = try await loadPostLayoutMetricReportIfPresent(
                path: request.metricReportPath
            )
            problem = try builder.makePEXRecoveryProblem(
                runID: request.runID,
                summary: summary,
                summaryArtifactPath: summaryPath,
                layoutArtifactPath: layoutPath,
                sourceNetlistPath: request.sourceNetlistPath,
                technologyArtifactPath: technologyPath,
                metricReportPath: request.metricReportPath,
                metricReport: metricReport,
                actionDomainArtifactPath: actionDomainPath
            )
        }

        let problemArtifact = try await artifactStore.persistPlanningProblem(
            problem,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuitePlanningProblemGenerationResult(
            status: "generated",
            runID: request.runID,
            source: request.source,
            problemID: problem.problemID,
            summaryPath: summaryPath,
            layoutPath: layoutPath,
            layoutNetlistPath: request.layoutNetlistPath,
            schematicNetlistPath: request.schematicNetlistPath,
            sourceNetlistPath: request.sourceNetlistPath,
            technologyPath: technologyPath,
            metricReportPath: request.metricReportPath,
            repairHintPath: repairHintPath,
            actionDomainPath: actionDomainPath,
            problemArtifact: problemArtifact
        )
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    private func loadPostLayoutMetricReportIfPresent(
        path: String?
    ) async throws -> PostLayoutComparisonReport? {
        guard let path else {
            return nil
        }
        let validatedPath = try await validateExplicitPathExists(path)
        return try await loadProjectJSON(PostLayoutComparisonReport.self, from: validatedPath)
    }

    private func loadDRCRepairHintsIfPresent(
        path: String?
    ) async throws -> DRCRepairHintReport? {
        guard let path else {
            return nil
        }
        return try await loadProjectJSON(DRCRepairHintReport.self, from: path)
    }

    private func loadLVSRepairHintsIfPresent(
        path: String?
    ) async throws -> LVSRepairHintReport? {
        guard let path else {
            return nil
        }
        return try await loadProjectJSON(LVSRepairHintReport.self, from: path)
    }

    private func loadProjectJSON<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from path: String
    ) async throws -> Value {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: .other,
            format: .json
        )
        guard let content = try await workspaceStore.loadProjectArtifactContent(at: locator) else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(path)
        }
        do {
            return try JSONDecoder().decode(type, from: content)
        } catch {
            throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> String {
        if let explicitPath {
            return try await validateExplicitPathExists(explicitPath)
        }
        guard let artifactID else {
            throw XcircuitePlanningProblemGenerationError.missingSummaryReference
        }
        let reference = try uniqueVerifiedArtifactReference(
            artifactID: artifactID,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference.path
    }

    private func optionalPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL,
        missingDefaultIsAllowed: Bool = false
    ) async throws -> String? {
        if let explicitPath {
            return try await validateExplicitPathExists(explicitPath)
        }
        guard let artifactID else {
            return nil
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            if missingDefaultIsAllowed {
                return nil
            }
            throw XcircuitePlanningProblemGenerationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        guard matches.count == 1 else {
            throw XcircuitePlanningProblemGenerationError.duplicateArtifactReference(
                runID: runID,
                artifactID: artifactID,
                count: matches.count
            )
        }
        let reference = matches[0]
        try validateArtifactIntegrity(reference, projectRoot: projectRoot)
        return reference.path
    }

    private func validateExplicitPathExists(_ path: String) async throws -> String {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: .other,
            format: .json
        )
        guard try await workspaceStore.projectArtifactExists(at: locator) else {
            throw XcircuitePlanningProblemGenerationError.explicitPathNotFound(path: path)
        }
        return path
    }

    private func uniqueVerifiedArtifactReference(
        artifactID: String,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuitePlanningProblemGenerationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        guard matches.count == 1 else {
            throw XcircuitePlanningProblemGenerationError.duplicateArtifactReference(
                runID: runID,
                artifactID: artifactID,
                count: matches.count
            )
        }
        let reference = matches[0]
        try validateArtifactIntegrity(reference, projectRoot: projectRoot)
        return reference
    }

    private func validateArtifactIntegrity(
        _ reference: ArtifactReference,
        projectRoot: URL
    ) throws {
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuitePlanningProblemGenerationError.artifactIntegrityFailed(
                artifactID: reference.artifactID,
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }
}
