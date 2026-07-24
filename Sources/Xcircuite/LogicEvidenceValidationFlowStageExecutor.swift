import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicEngineCore
import LogicEvidence

public struct LogicEvidenceValidationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let reportInput: XcircuiteFlowInputReference
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "logic.evidence-validation",
        toolID: String = "logic-evidence-validation",
        reportInput: XcircuiteFlowInputReference
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.reportInput = reportInput
        self.support = LogicEngineStageExecutionSupport()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let reportURL = try await reportInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let report = try JSONDecoder().decode(
                LogicEvidenceReport.self,
                from: Data(contentsOf: reportURL)
            )
            try report.validate()
            let additionalArtifacts: [ArtifactReference] = [try reference(
                for: reportURL,
                artifactID: "logic-evidence-validation-report",
                context: context
            )]
            let diagnostics = diagnostics(for: report)
            let resultArtifact = try await support.persistResult(
                report,
                fileName: "logic-evidence-validation-result.json",
                artifactID: "logic-evidence-validation-result",
                stageID: stageID,
                context: context
            )
            let flowDiagnostics = diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: .error,
                    code: diagnostic.code.rawValue,
                    message: diagnostic.summary
                )
            }
            let allArtifacts = additionalArtifacts + [resultArtifact]
            let integrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: allArtifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let accepted = report.state == .oracleCorrelated && report.blockers.isEmpty
            let stageStatus: FlowStageStatus = accepted
                ? (integrityGate.status == .passed ? .succeeded : .failed)
                : .blocked
            let gateStatus: FlowGateStatus = accepted
                ? (integrityGate.status == .passed ? .passed : .failed)
                : .blocked
            return FlowStageResult(
                stageID: stageID,
                status: stageStatus,
                diagnostics: flowDiagnostics + integrityGate.diagnostics,
                gates: [
                    FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: flowDiagnostics),
                    integrityGate,
                ],
                artifacts: allArtifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as LogicEvidenceError {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_EVIDENCE_VALIDATION_ARTIFACT_INVALID",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_EVIDENCE_VALIDATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func reference(
        for url: URL,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: artifactID,
            role: .input,
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func diagnostics(
        for report: LogicEvidenceReport
    ) -> [DesignDiagnostic] {
        guard report.state != .oracleCorrelated || !report.blockers.isEmpty else {
            return []
        }
        if report.state == .oracleCorrelated, !report.blockers.isEmpty {
            return report.blockers.sorted().map { blocker in
                DesignDiagnostic(
                    code: .trusted(diagnosticCode(for: blocker)),
                    severity: .error,
                    summary: blocker
                )
            }
        }
        let code: String
        switch report.state {
        case .unassessed:
            code = "LOGIC_EVIDENCE_VALIDATION_CORPUS_REQUIRED"
        case .corpusChecked:
            code = "LOGIC_EVIDENCE_VALIDATION_ORACLE_REQUIRED"
        case .oracleCorrelated:
            code = "LOGIC_EVIDENCE_VALIDATION_BLOCKED"
        }
        let message = report.blockers.sorted().joined(separator: ", ")
        return [DesignDiagnostic(
            code: .trusted(code),
            severity: .error,
            summary: message.isEmpty ? "Logic evidence validation has not reached release eligibility." : message
        )]
    }

    private func diagnosticCode(for blocker: String) -> String {
        switch blocker {
        case "process_qualification_required":
            return "LOGIC_EVIDENCE_VALIDATION_PROCESS_REQUIRED"
        default:
            return "LOGIC_EVIDENCE_VALIDATION_BLOCKED"
        }
    }
}
