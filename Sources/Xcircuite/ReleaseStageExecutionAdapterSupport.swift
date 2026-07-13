import DesignFlowKernel
import Foundation
import XcircuitePackage

struct ReleaseStageExecutionAdapterSupport: Sendable {
    private let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func persistEnvelope<Payload: Sendable & Hashable & Codable>(
        _ envelope: XcircuiteEngineResultEnvelope<Payload>,
        stageID: String,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let stageDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: stageDirectory)
        let outputURL = stageDirectory.appending(path: "result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: outputURL, options: .atomic)
        return try artifactBuilder.reference(
            for: outputURL,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    func stageResult<Payload: Sendable & Hashable & Codable>(
        envelope: XcircuiteEngineResultEnvelope<Payload>,
        stageID: String,
        artifacts: [XcircuiteFileReference],
        approved: Bool
    ) -> FlowStageResult {
        let diagnostics = envelope.diagnostics.map(flowDiagnostic)
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch envelope.status {
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
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
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

    private func flowDiagnostic(_ diagnostic: XcircuiteEngineDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .info:
            severity = .info
        case .warning:
            severity = .warning
        case .error:
            severity = .error
        }
        return FlowDiagnostic(
            severity: severity,
            code: diagnostic.code,
            message: diagnostic.message
        )
    }

    private func uniqueArtifacts(_ artifacts: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }
}
