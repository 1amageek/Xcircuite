import CryptoKit
import DesignFlowKernel
import Foundation
import LogicIR
import PDKCore
import STAEngine
import TimingCore
import XcircuitePackage

public struct TimingSTAFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let inputs: TimingSTAFlowInputs
    public let engine: (any STAAnalyzing)?

    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        inputs: TimingSTAFlowInputs,
        stageID: String = "timing.sta",
        toolID: String = "native-sta",
        engine: (any STAAnalyzing)? = nil
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
            let executingEngine: any STAAnalyzing
            if let engine {
                executingEngine = engine
            } else {
                executingEngine = NativeSTAEngine(
                    reader: ProjectTimingArtifactReader(projectRoot: context.projectRoot),
                    artifactStore: nil
                )
            }
            let envelope = try await executingEngine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try persistEnvelope(envelope, context: context)
            return makeStageResult(envelope: envelope, resultArtifact: resultArtifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "TIMING_STA_EXECUTION_ERROR",
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
        guard !inputs.libraries.isEmpty else {
            throw XcircuiteRuntimeError.invalidInputReference("Timing STA requires at least one timing library input.")
        }
    }

    private func makeRequest(context: FlowExecutionContext) throws -> STARequest {
        let design = try reference(
            input: inputs.design,
            context: context,
            artifactID: "timing-design",
            kind: .netlist,
            formatFallback: .json
        )
        let libraries = try inputs.libraries.enumerated().map { index, input in
            let reference = try reference(
                input: input,
                context: context,
                artifactID: "timing-library-\(index)",
                kind: .timingLibrary,
                formatFallback: .liberty
            )
            return TimingLibraryReference(artifact: reference, cornerIDs: inputs.cornerIDs)
        }
        let constraints = try reference(
            input: inputs.constraints,
            context: context,
            artifactID: "timing-constraints",
            kind: .constraint,
            formatFallback: .sdc
        )
        let pdkManifest = try reference(
            input: inputs.pdkManifest,
            context: context,
            artifactID: "pdk-manifest",
            kind: .technology,
            formatFallback: .json
        )
        let parasitics = try inputs.parasitics.map {
            try reference(
                input: $0,
                context: context,
                artifactID: "timing-parasitics",
                kind: .parasitic,
                formatFallback: .spef
            )
        }
        let pdk = PDKReference(
            manifest: pdkManifest,
            processID: inputs.processID,
            version: inputs.pdkVersion,
            digest: inputs.pdkDigest
        )
        return STARequest(
            runID: context.runID,
            inputs: [design] + libraries.map(\.artifact) + [constraints, pdkManifest] + (parasitics.map { [$0] } ?? []),
            design: LogicDesignReference(
                artifact: design,
                topDesignName: inputs.topDesignName,
                designDigest: design.sha256 ?? ""
            ),
            libraries: libraries,
            constraints: TimingConstraintReference(artifact: constraints, modeIDs: inputs.modeIDs),
            pdk: pdk,
            parasitics: parasitics,
            requestedModeIDs: inputs.modeIDs,
            requestedCornerIDs: inputs.cornerIDs,
            analysisKinds: inputs.analysisKinds,
            requiresSignoff: inputs.requiresSignoff
        )
    }

    private func reference(
        input: XcircuiteFlowInputReference,
        context: FlowExecutionContext,
        artifactID: String,
        kind: XcircuiteFileKind,
        formatFallback: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: format(for: url, fallback: formatFallback),
            producedByRunID: context.runID
        )
    }

    private func persistEnvelope(
        _ envelope: XcircuiteEngineResultEnvelope<STAPayload>,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: "timing-sta-result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: url, options: .atomic)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "timing-sta-result",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func makeStageResult(
        envelope: XcircuiteEngineResultEnvelope<STAPayload>,
        resultArtifact: XcircuiteFileReference
    ) -> FlowStageResult {
        let diagnostics = envelope.diagnostics.map { diagnostic in
            FlowDiagnostic(
                severity: flowSeverity(diagnostic.severity),
                code: diagnostic.code,
                message: diagnostic.message
            )
        }
        let gateStatus: FlowGateStatus
        switch envelope.status {
        case .completed:
            gateStatus = envelope.payload.violations.isEmpty ? .passed : .failed
        case .failed:
            gateStatus = .failed
        case .blocked:
            gateStatus = .blocked
        case .cancelled:
            gateStatus = .incomplete
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
        case "lib": return .liberty
        case "sdc": return .sdc
        case "spef": return .spef
        case "sdf": return .sdf
        case "json": return .json
        case "v", "vh": return .verilog
        case "sv", "svh": return .systemVerilog
        default: return fallback
        }
    }
}

private struct ProjectTimingArtifactReader: TimingArtifactReading {
    let projectRoot: URL

    func read(_ reference: XcircuiteFileReference) async throws -> Data {
        let url: URL
        if reference.path.hasPrefix("/") {
            url = URL(filePath: reference.path)
        } else {
            url = projectRoot.appending(path: reference.path)
        }
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
