import DFTCore
import DesignFlowKernel
import CircuiteFoundation
import Foundation
import ReleaseCore
import ReleaseEngine
import SignoffEngine
import TapeoutEngine

protocol ReleaseStageExecutionResult: Sendable {
    var status: ReleaseExecutionStatus { get }
    var diagnostics: [DesignDiagnostic] { get }
}

extension SignoffResult: ReleaseStageExecutionResult {}
extension TapeoutResult: ReleaseStageExecutionResult {}

struct ReleaseStageExecutionSupport: Sendable {
    private let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func persistResult<Result: Encodable>(
        _ result: Result,
        stageID: String,
        artifactID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try await context.persistArtifact(
            encoder.encode(result),
            artifactID: artifactID,
            stageID: stageID,
            fileName: "result.json",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json,
            mode: .replaceable
        )
    }

    func stageResult<Result: ReleaseStageExecutionResult>(
        result: Result,
        stageID: String,
        artifacts: [ArtifactReference],
        approved: Bool
    ) -> FlowStageResult {
        let diagnostics = result.diagnostics.map(flowDiagnostic)
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch result.status {
        case .completed:
            gateStatus = approved ? .passed : .failed
            stageStatus = approved ? .succeeded : .failed
        case .blocked:
            gateStatus = .blocked
            stageStatus = .blocked
        case .failed:
            gateStatus = .failed
            stageStatus = .failed
        case .cancelled:
            gateStatus = .incomplete
            stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: diagnostics)],
            artifacts: uniqueArtifacts(artifacts)
        )
    }

    func validate(stage: FlowStageDefinition, stageID: String, toolID: String) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
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

    private func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .information:
            severity = .info
        case .warning:
            severity = .warning
        case .error:
            severity = .error
        }
        return FlowDiagnostic(
            severity: severity,
            code: diagnostic.code.rawValue,
            message: diagnostic.summary
        )
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }
}
