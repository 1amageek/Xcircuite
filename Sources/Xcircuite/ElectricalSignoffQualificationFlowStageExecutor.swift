import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import QualificationEngine
import ReleaseCore
import ToolQualification
import XcircuitePackage

public struct ElectricalSignoffQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let requestInput: XcircuiteFlowInputReference
    public let qualificationScope: ToolQualificationScope
    private let runner: ElectricalSignoffQualificationRunner

    public init(
        stageID: String = "electrical-signoff.qualification",
        toolID: String = "native-electrical-signoff-qualification",
        requestInput: XcircuiteFlowInputReference,
        qualificationScope: ToolQualificationScope,
        runner: ElectricalSignoffQualificationRunner
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.qualificationScope = qualificationScope
        self.runner = runner
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let specURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let specData = try Data(contentsOf: specURL)
            let spec = try JSONDecoder().decode(ElectricalSignoffQualificationSpec.self, from: specData)
            guard spec.cases.allSatisfy({ $0.request.runID == context.runID }) else {
                return failureResult(
                    stageID: stage.stageID,
                    code: "ELECTRICAL_SIGNOFF_QUALIFICATION_RUN_ID_MISMATCH",
                    message: "Every qualification case request must use the flow run ID."
                )
            }
            let report = try await runner.run(spec: spec)
            try context.checkCancellation()
            let artifactRoot = ".xcircuite/runs/\(context.runID)/qualification"
            let specPath = "\(artifactRoot)/electrical-signoff-spec.json"
            let reportPath = "\(artifactRoot)/electrical-signoff-report.json"
            let specOutputURL = try context.packageStore.url(
                forProjectRelativePath: specPath,
                inProjectAt: context.projectRoot
            )
            let reportURL = try context.packageStore.url(
                forProjectRelativePath: reportPath,
                inProjectAt: context.projectRoot
            )
            try context.packageStore.ensureDirectory(at: reportURL.deletingLastPathComponent())
            try context.packageStore.writeJSON(spec, to: specOutputURL, forProjectAt: context.projectRoot)
            let specReference = try context.packageStore.fileReference(
                forProjectRelativePath: specPath,
                artifactID: "electrical-signoff-qualification-spec",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )
            try context.packageStore.writeJSON(report, to: reportURL, forProjectAt: context.projectRoot)
            let reportReference = try context.packageStore.fileReference(
                forProjectRelativePath: reportPath,
                artifactID: "electrical-signoff-qualification-report",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )

            let evidence = report.toolEvidence(
                reportPath: reportPath,
                reportSHA256: reportReference.sha256,
                scope: qualificationScope,
                checkedAt: report.generatedAt
            )
            let evidencePath = "\(artifactRoot)/electrical-signoff-tool-evidence.json"
            let evidenceURL = try context.packageStore.url(
                forProjectRelativePath: evidencePath,
                inProjectAt: context.projectRoot
            )
            try context.packageStore.writeJSON(evidence, to: evidenceURL, forProjectAt: context.projectRoot)
            let evidenceReference = try context.packageStore.fileReference(
                forProjectRelativePath: evidencePath,
                artifactID: "electrical-signoff-tool-evidence",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )

            let retainedArtifacts = try persistRetainedQualification(
                report: report,
                spec: spec,
                specReference: specReference,
                reportReference: reportReference,
                evidenceReference: evidenceReference,
                artifactRoot: artifactRoot,
                context: context
            )
            let artifacts = [specReference, reportReference, evidenceReference] + retainedArtifacts
            let gate = FlowGateResult(
                gateID: "qualification",
                status: report.passed ? .passed : .failed,
                diagnostics: report.failureCodes.map { code in
                    FlowDiagnostic(
                        severity: .error,
                        code: "ELECTRICAL_SIGNOFF_QUALIFICATION_\(code.uppercased().replacingOccurrences(of: "-", with: "_"))",
                        message: "Electrical signoff qualification failed: \(code)."
                    )
                }
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: report.passed ? .succeeded : .failed,
                diagnostics: gate.diagnostics,
                gates: [gate],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "ELECTRICAL_SIGNOFF_QUALIFICATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw ElectricalSignoffQualificationFlowError.stageMismatch
        }
        guard context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ElectricalSignoffQualificationFlowError.invalidRunID
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        guard qualificationScope.isComplete else {
            throw ElectricalSignoffQualificationFlowError.incompleteScope
        }
    }

    private func persistRetainedQualification(
        report: ElectricalSignoffQualificationReport,
        spec: ElectricalSignoffQualificationSpec,
        specReference: XcircuiteFileReference,
        reportReference: XcircuiteFileReference,
        evidenceReference: XcircuiteFileReference,
        artifactRoot: String,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        let nativeLane = ReleaseQualificationLane(
            laneID: "electrical-signoff-native-corpus",
            domain: "electrical-signoff",
            kind: .nativeCorpus,
            corpusSpecPath: specReference.path,
            reportPath: reportReference.path,
            evidenceExportPath: evidenceReference.path
        )
        var lanes = [nativeLane]
        if report.qualificationLevel >= .oracleChecked {
            let oracleID = report.caseResults.compactMap(\.oracle?.oracleID).sorted().first
            lanes.append(ReleaseQualificationLane(
                laneID: "electrical-signoff-independent-oracle",
                domain: "electrical-signoff",
                kind: .externalOracle,
                corpusSpecPath: specReference.path,
                reportPath: reportReference.path,
                evidenceExportPath: evidenceReference.path,
                oracleBackendID: oracleID
            ))
        }
        let suite = RetainedCorpusSuite(
            suiteID: "\(spec.corpusID):\(spec.corpusVersion)",
            lanes: lanes,
            createdAt: iso8601String(from: report.generatedAt),
            sourceDashboardPath: reportReference.path,
            requirements: RetainedCorpusSuite.Requirements(
                domainIDs: ["electrical-signoff"],
                requireExternalOracles: report.qualificationLevel >= .oracleChecked,
                requiredArtifacts: [specReference.path, reportReference.path, evidenceReference.path]
            )
        )
        let domainResult = RetainedCorpusReport.DomainResult(
            domain: "electrical-signoff",
            status: report.passed ? "passed" : "failed",
            qualified: report.passed,
            caseCount: report.caseCount,
            coverageTagCount: Set(report.caseResults.map { $0.axis.rawValue }).count,
            coveredRequiredCoverageTagCount: Set(report.caseResults.map { $0.axis.rawValue }).count,
            passRate: report.caseCount == 0 ? 0 : Double(report.matchedCaseCount) / Double(report.caseCount),
            oracleAgreementRate: report.oracleCaseCount == 0 ? nil : Double(report.oracleAgreementCount) / Double(report.oracleCaseCount),
            durationBudgetPassRate: 1,
            report: RetainedCorpusReport.ArtifactIdentity(path: reportReference.path, sha256: reportReference.sha256, byteCount: reportReference.byteCount, status: "verified"),
            toolEvidence: RetainedCorpusReport.ToolEvidenceObservation(evidenceID: "electrical-signoff:\(spec.corpusID):\(spec.corpusVersion)", checkedAt: iso8601String(from: report.generatedAt), failureCodes: report.failureCodes),
            toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(path: evidenceReference.path, sha256: evidenceReference.sha256, byteCount: evidenceReference.byteCount, status: "verified")
        )
        var externalResults: [RetainedCorpusReport.ExternalOracleResult] = []
        if report.qualificationLevel >= .oracleChecked {
            externalResults.append(RetainedCorpusReport.ExternalOracleResult(
                domain: "electrical-signoff",
                oracleBackendID: report.caseResults.compactMap(\.oracle?.oracleID).sorted().first,
                status: report.passed ? "passed" : "failed",
                qualified: report.passed,
                caseCount: report.caseCount,
                coverageTagCount: domainResult.coverageTagCount,
                coveredRequiredCoverageTagCount: domainResult.coveredRequiredCoverageTagCount,
                passRate: domainResult.passRate,
                oracleAgreementRate: domainResult.oracleAgreementRate,
                durationBudgetPassRate: domainResult.durationBudgetPassRate,
                report: domainResult.report,
                toolEvidence: domainResult.toolEvidence,
                toolEvidenceExport: domainResult.toolEvidenceExport
            ))
        }
        let retainedReport = RetainedCorpusReport(
            status: report.passed ? "passed" : "failed",
            createdAt: iso8601String(from: report.generatedAt),
            domainResults: [domainResult],
            externalOracleResults: externalResults
        )

        let suitePath = "\(artifactRoot)/electrical-signoff-suite.json"
        let reportPath = "\(artifactRoot)/electrical-signoff-retained-report.json"
        let suiteURL = try context.packageStore.url(forProjectRelativePath: suitePath, inProjectAt: context.projectRoot)
        let retainedReportURL = try context.packageStore.url(forProjectRelativePath: reportPath, inProjectAt: context.projectRoot)
        try context.packageStore.writeJSON(suite, to: suiteURL, forProjectAt: context.projectRoot)
        try context.packageStore.writeJSON(retainedReport, to: retainedReportURL, forProjectAt: context.projectRoot)
        let suiteReference = try context.packageStore.fileReference(
            forProjectRelativePath: suitePath,
            artifactID: "electrical-signoff-retained-suite",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
        let retainedReportReference = try context.packageStore.fileReference(
            forProjectRelativePath: reportPath,
            artifactID: "electrical-signoff-retained-report",
            kind: .report,
            format: .json,
            inProjectAt: context.projectRoot,
            producedByRunID: context.runID,
            verifiedByRunID: context.runID
        )
        return [suiteReference, retainedReportReference]
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "qualification", status: .failed, diagnostics: [diagnostic])]
        )
    }
}

private enum ElectricalSignoffQualificationFlowError: Error, LocalizedError {
    case stageMismatch
    case invalidRunID
    case incompleteScope

    var errorDescription: String? {
        switch self {
        case .stageMismatch:
            return "The configured electrical signoff qualification stage does not match the requested stage."
        case .invalidRunID:
            return "The flow run ID is required for electrical signoff qualification."
        case .incompleteScope:
            return "A complete ToolQualification scope is required for electrical signoff qualification."
        }
    }
}
