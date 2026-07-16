import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import RTLVerificationCore

struct LogicEngineStageExecutionSupport: Sendable {
    private let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func persistResult<Value: Encodable>(
        _ result: Value,
        fileName: String,
        artifactID: String,
        stageID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            result,
            artifactID: artifactID,
            stageID: stageID,
            fileName: fileName,
            kind: .report,
            mode: .replaceable
        )
    }

    func result(
        status: LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference],
        resultArtifact: ArtifactReference,
        stageID: String,
        gateID: String,
        context: FlowExecutionContext
    ) throws -> FlowStageResult {
        let flowDiagnostics = diagnostics.map(Self.flowDiagnostic)
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: artifacts + [resultArtifact],
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch status {
        case .completed:
            gateStatus = integrityGate.status == .passed ? .passed : .failed
            stageStatus = integrityGate.status == .passed ? .succeeded : .failed
        case .failed:
            gateStatus = .failed
            stageStatus = .failed
        case .blocked:
            gateStatus = .blocked
            stageStatus = .blocked
        case .cancelled:
            gateStatus = .incomplete
            stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: flowDiagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: gateID, status: gateStatus, diagnostics: flowDiagnostics),
                integrityGate,
            ],
            artifacts: artifacts + [resultArtifact]
        )
    }

    func rtlResult(
        _ result: RTLVerificationResult,
        resultArtifact: ArtifactReference,
        stageID: String,
        gateID: String,
        context: FlowExecutionContext,
        additionalArtifacts: [ArtifactReference] = [],
        additionalDiagnostics: [DesignDiagnostic] = [],
        stageStatusOverride: FlowStageStatus? = nil,
        gateStatusOverride: FlowGateStatus? = nil
    ) throws -> FlowStageResult {
        let diagnostics = result.rtlDiagnostics.map { diagnostic in
            let severity: FlowDiagnosticSeverity
            switch diagnostic.severity {
            case .info: severity = .info
            case .warning: severity = .warning
            case .error: severity = .error
            }
            return FlowDiagnostic(severity: severity, code: diagnostic.code, message: diagnostic.message)
        } + additionalDiagnostics.map(Self.flowDiagnostic)
        let artifacts = result.artifacts + [resultArtifact] + additionalArtifacts
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: artifacts,
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch result.status {
        case .completed:
            gateStatus = integrityGate.status == .passed ? .passed : .failed
            stageStatus = integrityGate.status == .passed ? .succeeded : .failed
        case .failed:
            gateStatus = .failed
            stageStatus = .failed
        case .blocked:
            gateStatus = .blocked
            stageStatus = .blocked
        case .cancelled:
            gateStatus = .incomplete
            stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatusOverride ?? stageStatus,
            diagnostics: diagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: gateID, status: gateStatusOverride ?? gateStatus, diagnostics: diagnostics),
                integrityGate,
            ],
            artifacts: artifacts
        )
    }

    func failure(
        stageID: String,
        gateID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: gateID, status: .failed, diagnostics: [diagnostic])]
        )
    }

    func blocked(
        stageID: String,
        gateID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: gateID, status: .blocked, diagnostics: [diagnostic])]
        )
    }

    func validate(stage: FlowStageDefinition, stageID: String, toolID: String) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private static func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .information: severity = .info
        case .warning: severity = .warning
        case .error: severity = .error
        }
        let detail = diagnostic.detail.map { value in " (\(value))" } ?? ""
        return FlowDiagnostic(
            severity: severity,
            code: diagnostic.code.rawValue,
            message: diagnostic.summary + detail
        )
    }
}
