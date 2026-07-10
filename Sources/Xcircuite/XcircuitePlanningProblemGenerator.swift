import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import XcircuitePackage

public struct XcircuitePlanningProblemGenerator: Sendable {
    private let packageStore: XcircuitePackageStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let builder: XcircuiteDiagnosticPlanningProblemBuilder
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        artifactStore: XcircuitePlanningArtifactStore = XcircuitePlanningArtifactStore(),
        builder: XcircuiteDiagnosticPlanningProblemBuilder = XcircuiteDiagnosticPlanningProblemBuilder(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.artifactStore = artifactStore
        self.builder = builder
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func generateRepairProblem(
        request: XcircuitePlanningProblemGenerationRequest,
        projectRoot: URL
    ) throws -> XcircuitePlanningProblemGenerationResult {
        try XcircuiteIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try loadRunManifest(runID: request.runID, projectRoot: projectRoot)
        let summaryPath = try requiredPath(
            explicitPath: request.summaryPath,
            artifactID: request.summaryArtifactID ?? request.source.rawValue,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let layoutPath = try optionalPath(
            explicitPath: request.layoutPath,
            artifactID: request.layoutArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let actionDomainPath = try optionalPath(
            explicitPath: request.actionDomainPath,
            artifactID: request.actionDomainArtifactID ?? XcircuitePlanningArtifactStore.actionDomainArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot,
            missingDefaultIsAllowed: true
        )
        let technologyPath = try optionalPath(
            explicitPath: request.technologyPath,
            artifactID: request.technologyArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let repairHintPath = try optionalPath(
            explicitPath: request.repairHintPath,
            artifactID: request.repairHintArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problem: XcircuiteCircuitPlanningProblem
        switch request.source {
        case .drcSummary:
            let summary = try packageStore.readJSON(
                DRCRunSummaryReport.self,
                from: packageStore.url(forProjectRelativePath: summaryPath, inProjectAt: projectRoot)
            )
            let repairHints = try loadDRCRepairHintsIfPresent(
                path: repairHintPath,
                projectRoot: projectRoot
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
            let summary = try packageStore.readJSON(
                LVSRunSummaryReport.self,
                from: packageStore.url(forProjectRelativePath: summaryPath, inProjectAt: projectRoot)
            )
            let repairHints = try loadLVSRepairHintsIfPresent(
                path: repairHintPath,
                projectRoot: projectRoot
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
            let summary = try packageStore.readJSON(
                PEXRunSummaryReport.self,
                from: packageStore.url(forProjectRelativePath: summaryPath, inProjectAt: projectRoot)
            )
            let metricReport = try loadPostLayoutMetricReportIfPresent(
                path: request.metricReportPath,
                projectRoot: projectRoot
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

        let problemArtifact = try artifactStore.persistPlanningProblem(
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

    private func loadRunManifest(runID: String, projectRoot: URL) throws -> XcircuiteRunManifest {
        try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
    }

    private func loadPostLayoutMetricReportIfPresent(
        path: String?,
        projectRoot: URL
    ) throws -> PostLayoutComparisonReport? {
        guard let path else {
            return nil
        }
        let validatedPath = try validateExplicitPathExists(path, projectRoot: projectRoot)
        let url = try packageStore.url(forProjectRelativePath: validatedPath, inProjectAt: projectRoot)
        return try packageStore.readJSON(PostLayoutComparisonReport.self, from: url)
    }

    private func loadDRCRepairHintsIfPresent(
        path: String?,
        projectRoot: URL
    ) throws -> DRCRepairHintReport? {
        guard let path else {
            return nil
        }
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        return try packageStore.readJSON(DRCRepairHintReport.self, from: url)
    }

    private func loadLVSRepairHintsIfPresent(
        path: String?,
        projectRoot: URL
    ) throws -> LVSRepairHintReport? {
        guard let path else {
            return nil
        }
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        return try packageStore.readJSON(LVSRepairHintReport.self, from: url)
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> String {
        if let explicitPath {
            return try validateExplicitPathExists(explicitPath, projectRoot: projectRoot)
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
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL,
        missingDefaultIsAllowed: Bool = false
    ) throws -> String? {
        if let explicitPath {
            return try validateExplicitPathExists(explicitPath, projectRoot: projectRoot)
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

    private func validateExplicitPathExists(
        _ path: String,
        projectRoot: URL
    ) throws -> String {
        let url = try packageStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw XcircuitePlanningProblemGenerationError.explicitPathNotFound(path: path)
        }
        return path
    }

    private func uniqueVerifiedArtifactReference(
        artifactID: String,
        manifest: XcircuiteRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference {
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
        _ reference: XcircuiteFileReference,
        projectRoot: URL
    ) throws {
        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            throw XcircuitePlanningProblemGenerationError.artifactIntegrityFailed(
                artifactID: reference.artifactID,
                path: reference.path,
                status: integrity.status,
                message: integrity.message
            )
        }
    }
}
