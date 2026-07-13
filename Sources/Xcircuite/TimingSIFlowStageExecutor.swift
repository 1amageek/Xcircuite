import CryptoKit
import DesignFlowKernel
import Foundation
import LogicIR
import PDKCore
import SignalIntegrityEngine
import TimingCore
import XcircuitePackage

public struct TimingSIFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let inputs: TimingSIFlowInputs
    public let engine: (any SignalIntegrityAnalyzing)?

    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        inputs: TimingSIFlowInputs,
        stageID: String = "timing.signal-integrity",
        toolID: String = "native-signal-integrity",
        engine: (any SignalIntegrityAnalyzing)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.inputs = inputs
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let request = try makeRequest(context: context)
            let executingEngine: any SignalIntegrityAnalyzing = engine ?? NativeSignalIntegrityEngine(
                reader: ProjectSITimingArtifactReader(projectRoot: context.projectRoot),
                artifactStore: nil
            )
            let envelope = try await executingEngine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try persistEnvelope(envelope, context: context)
            return makeStageResult(envelope: envelope, resultArtifact: resultArtifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "TIMING_SI_EXECUTION_ERROR",
                message: error.localizedDescription
            )
            return FlowStageResult(
                stageID: stageID,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [FlowGateResult(gateID: stageID, status: .failed, diagnostics: [diagnostic])]
            )
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func makeRequest(context: FlowExecutionContext) throws -> SignalIntegrityRequest {
        let design = try reference(input: inputs.design, context: context, artifactID: "timing-si-design", kind: .netlist, fallback: .json)
        let constraints = try reference(input: inputs.constraints, context: context, artifactID: "timing-si-constraints", kind: .constraint, fallback: .sdc)
        let pdkManifest = try reference(input: inputs.pdkManifest, context: context, artifactID: "timing-si-pdk-manifest", kind: .technology, fallback: .json)
        let parasitics = try reference(input: inputs.parasitics, context: context, artifactID: "timing-si-parasitics", kind: .parasitic, fallback: .spef)
        let pdk = PDKReference(
            manifest: pdkManifest,
            processID: inputs.processID,
            version: inputs.pdkVersion,
            digest: inputs.pdkDigest
        )
        return SignalIntegrityRequest(
            runID: context.runID,
            inputs: [design, constraints, pdkManifest, parasitics],
            design: LogicDesignReference(
                artifact: design,
                topDesignName: inputs.topDesignName,
                designDigest: design.sha256 ?? ""
            ),
            constraints: TimingConstraintReference(artifact: constraints, modeIDs: inputs.modeIDs),
            pdk: pdk,
            parasitics: parasitics,
            maxDeltaDelay: inputs.maxDeltaDelay,
            maxNoiseRatio: inputs.maxNoiseRatio
        )
    }

    private func reference(
        input: XcircuiteFlowInputReference,
        context: FlowExecutionContext,
        artifactID: String,
        kind: XcircuiteFileKind,
        fallback: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format(for: url, fallback: fallback),
            producedByRunID: context.runID
        )
    }

    private func persistEnvelope(
        _ envelope: XcircuiteEngineResultEnvelope<SignalIntegrityPayload>,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let directory = context.runDirectory.appending(path: "stages").appending(path: stageID).appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: "timing-signal-integrity-result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: url, options: .atomic)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "timing-signal-integrity-result",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func makeStageResult(
        envelope: XcircuiteEngineResultEnvelope<SignalIntegrityPayload>,
        resultArtifact: XcircuiteFileReference
    ) -> FlowStageResult {
        let diagnostics = envelope.diagnostics.map {
            FlowDiagnostic(severity: flowSeverity($0.severity), code: $0.code, message: $0.message)
        }
        let gateStatus: FlowGateStatus
        switch envelope.status {
        case .completed: gateStatus = envelope.payload.violations.isEmpty ? .passed : .failed
        case .blocked: gateStatus = .blocked
        case .failed: gateStatus = .failed
        case .cancelled: gateStatus = .incomplete
        }
        let stageStatus: FlowStageStatus
        switch envelope.status {
        case .completed: stageStatus = .succeeded
        case .blocked: stageStatus = .blocked
        case .failed, .cancelled: stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: diagnostics)],
            artifacts: envelope.artifacts + [resultArtifact]
        )
    }

    private func flowSeverity(_ severity: XcircuiteEngineDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func format(for url: URL, fallback: XcircuiteFileFormat) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "spef": return .spef
        case "sdc": return .sdc
        case "json": return .json
        default: return fallback
        }
    }
}

private struct ProjectSITimingArtifactReader: TimingArtifactReading {
    let projectRoot: URL

    func read(_ reference: XcircuiteFileReference) async throws -> Data {
        let url = reference.path.hasPrefix("/")
            ? URL(filePath: reference.path)
            : projectRoot.appending(path: reference.path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TimingError.artifactReadFailed(path: reference.path, message: error.localizedDescription)
        }
        if let byteCount = reference.byteCount, byteCount != Int64(data.count) {
            throw TimingError.artifactSizeMismatch(path: reference.path, expected: byteCount, actual: Int64(data.count))
        }
        if let digest = reference.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual.caseInsensitiveCompare(digest) == .orderedSame else {
                throw TimingError.artifactDigestMismatch(path: reference.path)
            }
        }
        return data
    }
}
