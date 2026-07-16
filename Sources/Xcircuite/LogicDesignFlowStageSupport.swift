import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicDesign
import LogicIR
import DesignFlowKernel

struct LogicDesignFlowStageSupport: Sendable {
    let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func validate(stage: FlowStageDefinition, stageID: String, toolID: String) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    func writeResult<Value: Encodable>(
        _ result: Value,
        stageID: String,
        context: FlowExecutionContext,
        fileName: String
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            result,
            artifactID: "\(stageID)-result",
            stageID: stageID,
            fileName: fileName,
            kind: .report,
            mode: .replaceable
        )
    }

    func stageResult(
        resultArtifact: ArtifactReference,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic],
        stageID: String,
        artifacts: [ArtifactReference],
        context: FlowExecutionContext
    ) throws -> FlowStageResult {
        let flowDiagnostics = diagnostics.map { diagnostic in
            let severity: FlowDiagnosticSeverity
            switch diagnostic.severity {
            case .information: severity = .info
            case .warning: severity = .warning
            case .error: severity = .error
            }
            return FlowDiagnostic(
                severity: severity,
                code: diagnostic.code,
                message: diagnostic.message
            )
        }
        let allArtifacts = artifacts + [resultArtifact]
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: allArtifacts,
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let domainStageStatus: FlowStageStatus
        let gateStatus: FlowGateStatus
        switch status {
        case .completed:
            domainStageStatus = integrityGate.status == .passed ? .succeeded : .failed
            gateStatus = integrityGate.status == .passed ? .passed : .failed
        case .blocked:
            domainStageStatus = .blocked
            gateStatus = .blocked
        case .failed:
            domainStageStatus = .failed
            gateStatus = .failed
        case .cancelled:
            domainStageStatus = .blocked
            gateStatus = .incomplete
        }
        return FlowStageResult(
            stageID: stageID,
            status: domainStageStatus,
            diagnostics: flowDiagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: flowDiagnostics),
                integrityGate,
            ],
            artifacts: allArtifacts
        )
    }

    func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: stageID, status: .failed, diagnostics: [diagnostic])]
        )
    }

}
