import CryptoKit
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicIR
import SignalIntegrityEngine
import TimingCore

public struct TimingSIFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let inputs: TimingSIFlowInputs
    public let engine: (any SignalIntegrityFoundationEngine)?

    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        inputs: TimingSIFlowInputs,
        stageID: String = "timing.signal-integrity",
        toolID: String = "native-signal-integrity",
        engine: (any SignalIntegrityFoundationEngine)? = nil
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
            let executingEngine: any SignalIntegrityFoundationEngine = engine ?? NativeSignalIntegrityEngine(
                reader: ProjectSITimingArtifactReader(projectRoot: context.projectRoot),
                artifactStore: nil
            )
            let result = try await executingEngine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try persistResult(result, context: context)
            return makeStageResult(result: result, resultArtifact: resultArtifact)
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

    private func makeRequest(context: FlowExecutionContext) throws -> SignalIntegrityFoundationRequest {
        let design = try reference(input: inputs.design, context: context, artifactID: "timing-si-design", kind: .netlist, fallback: .json)
        let constraints = try reference(input: inputs.constraints, context: context, artifactID: "timing-si-constraints", kind: .constraint, fallback: .sdc)
        let pdkManifest = try reference(input: inputs.pdkManifest, context: context, artifactID: "timing-si-pdk-manifest", kind: .technology, fallback: .json)
        let parasitics = try reference(input: inputs.parasitics, context: context, artifactID: "timing-si-parasitics", kind: .parasitics, fallback: .spef)
        return SignalIntegrityFoundationRequest(
            runID: context.runID,
            design: design,
            topDesignName: inputs.topDesignName,
            constraints: constraints,
            requestedModeIDs: inputs.modeIDs,
            pdkManifest: pdkManifest,
            processID: inputs.processID,
            pdkVersion: inputs.pdkVersion,
            pdkDigest: try ContentDigest(algorithm: .sha256, hexadecimalValue: inputs.pdkDigest),
            parasitics: parasitics,
            maxDeltaDelay: inputs.maxDeltaDelay,
            maxNoiseRatio: inputs.maxNoiseRatio
        )
    }

    private func reference(
        input: XcircuiteFlowInputReference,
        context: FlowExecutionContext,
        artifactID: String,
        kind: ArtifactKind,
        fallback: ArtifactFormat
    ) throws -> ArtifactReference {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        let path = try ProjectPathBoundary().relativePath(for: url, projectRoot: context.projectRoot)
        let data = try Data(contentsOf: url)
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format(for: url, fallback: fallback)
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func persistResult(
        _ result: SignalIntegrityExecutionResult,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let directory = context.runDirectory.appending(path: "stages").appending(path: stageID).appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: "timing-signal-integrity-result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "timing-signal-integrity-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func makeStageResult(
        result: SignalIntegrityExecutionResult,
        resultArtifact: ArtifactReference
    ) -> FlowStageResult {
        let diagnostics = result.diagnostics.map {
            FlowDiagnostic(severity: flowSeverity($0.severity), code: $0.code.rawValue, message: $0.summary)
        }
        let gateStatus: FlowGateStatus
        switch result.status {
        case .completed: gateStatus = result.payload.violations.isEmpty ? .passed : .failed
        case .blocked: gateStatus = .blocked
        case .failed: gateStatus = .failed
        case .cancelled: gateStatus = .incomplete
        }
        let stageStatus: FlowStageStatus
        switch result.status {
        case .completed: stageStatus = .succeeded
        case .blocked: stageStatus = .blocked
        case .failed, .cancelled: stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: diagnostics)],
            artifacts: [resultArtifact]
        )
    }

    private func flowSeverity(_ severity: DiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .information: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func format(for url: URL, fallback: ArtifactFormat) -> ArtifactFormat {
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

    func read(_ reference: ArtifactReference) async throws -> Data {
        let url: URL
        do {
            url = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            throw TimingError.artifactReadFailed(
                path: reference.path,
                message: error.localizedDescription
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TimingError.artifactReadFailed(path: reference.path, message: error.localizedDescription)
        }
        if reference.byteCount != UInt64(data.count) {
            throw TimingError.artifactSizeMismatch(
                path: reference.path,
                expected: Int64(reference.byteCount),
                actual: Int64(data.count)
            )
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(reference.sha256) == .orderedSame else {
            throw TimingError.artifactDigestMismatch(path: reference.path)
        }
        return data
    }
}
