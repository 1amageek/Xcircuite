import DesignFlowKernel
import Foundation
import XcircuitePackage

struct LogicEngineStageExecutionAdapterSupport: Sendable {
    private let artifactBuilder: StageArtifactReferenceBuilder

    init(artifactBuilder: StageArtifactReferenceBuilder = StageArtifactReferenceBuilder()) {
        self.artifactBuilder = artifactBuilder
    }

    func persistEnvelope<Payload: Sendable & Hashable & Codable>(
        _ envelope: XcircuiteEngineResultEnvelope<Payload>,
        fileName: String,
        artifactID: String,
        stageID: String,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let outputDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: outputDirectory)
        let outputURL = outputDirectory.appending(path: fileName)
        try context.packageStore.writeJSON(envelope, to: outputURL, forProjectAt: context.projectRoot)
        return try artifactBuilder.reference(
            for: outputURL,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    func result<Payload: Sendable & Hashable & Codable>(
        envelope: XcircuiteEngineResultEnvelope<Payload>,
        resultArtifact: XcircuiteFileReference,
        stageID: String,
        gateID: String,
        context: FlowExecutionContext,
        additionalArtifacts: [XcircuiteFileReference] = [],
        additionalDiagnostics: [XcircuiteEngineDiagnostic] = [],
        stageStatusOverride: FlowStageStatus? = nil,
        gateStatusOverride: FlowGateStatus? = nil
    ) -> FlowStageResult {
        let diagnostics = (envelope.diagnostics + additionalDiagnostics).map { diagnostic in
            FlowDiagnostic(
                severity: FlowDiagnosticSeverity(rawValue: diagnostic.severity.rawValue) ?? .error,
                code: diagnostic.code,
                message: diagnostic.message
            )
        }
        let artifacts = envelope.artifacts + [resultArtifact] + additionalArtifacts
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: artifacts,
            projectRoot: context.projectRoot
        )
        let allDiagnostics = diagnostics + integrityGate.diagnostics
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch envelope.status {
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
            diagnostics: allDiagnostics,
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
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }
}
