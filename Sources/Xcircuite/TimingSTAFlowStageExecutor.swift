import CryptoKit
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import STAEngine
import TimingCore

public struct TimingSTAFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let inputs: TimingSTAFlowInputs
    public let engine: (any STAFoundationEngine)?

    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        inputs: TimingSTAFlowInputs,
        stageID: String = "timing.sta",
        toolID: String = "native-sta",
        engine: (any STAFoundationEngine)? = nil
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
            let executingEngine: any STAFoundationEngine
            if let engine {
                executingEngine = engine
            } else {
                executingEngine = NativeSTAEngine(
                    reader: ProjectTimingArtifactReader(projectRoot: context.projectRoot),
                    artifactStore: nil
                )
            }
            let result = try await executingEngine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try persistResult(result, context: context)
            return makeStageResult(result: result, resultArtifact: resultArtifact)
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

    private func makeRequest(context: FlowExecutionContext) throws -> STAFoundationRequest {
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
            return STAFoundationLibraryReference(artifact: reference, cornerIDs: inputs.cornerIDs)
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
                kind: .parasitics,
                formatFallback: .spef
            )
        }
        return STAFoundationRequest(
            runID: context.runID,
            design: design,
            topDesignName: inputs.topDesignName,
            libraries: libraries,
            constraints: constraints,
            requestedModeIDs: inputs.modeIDs,
            requestedCornerIDs: inputs.cornerIDs,
            pdkManifest: pdkManifest,
            processID: inputs.processID,
            pdkVersion: inputs.pdkVersion,
            pdkDigest: try ContentDigest(algorithm: .sha256, hexadecimalValue: inputs.pdkDigest),
            parasitics: parasitics,
            analysisKinds: inputs.analysisKinds,
            requiresSignoff: inputs.requiresSignoff
        )
    }

    private func reference(
        input: XcircuiteFlowInputReference,
        context: FlowExecutionContext,
        artifactID: String,
        kind: ArtifactKind,
        formatFallback: ArtifactFormat
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
                format: format(for: url, fallback: formatFallback)
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func persistResult(
        _ result: STAExecutionResult,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: "timing-sta-result.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "timing-sta-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func makeStageResult(
        result: STAExecutionResult,
        resultArtifact: ArtifactReference
    ) -> FlowStageResult {
        let diagnostics = result.diagnostics.map { diagnostic in
            FlowDiagnostic(
                severity: flowSeverity(diagnostic.severity),
                code: diagnostic.code.rawValue,
                message: diagnostic.summary
            )
        }
        let gateStatus: FlowGateStatus
        switch result.status {
        case .completed:
            gateStatus = result.payload.violations.isEmpty ? .passed : .failed
        case .failed:
            gateStatus = .failed
        case .blocked:
            gateStatus = .blocked
        case .cancelled:
            gateStatus = .incomplete
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
