import CircuiteFoundation
import DesignFlowKernel
import Foundation
import STAEngine
import TimingCore

public struct TimingSTAFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let inputs: TimingSTAFlowInputs
    public let engine: (any STAExecuting)?

    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        inputs: TimingSTAFlowInputs,
        stageID: String = "timing.sta",
        toolID: String = "native-sta",
        engine: (any STAExecuting)? = nil
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
            try await context.checkCancellation()
            try validate(stage: stage)
            let request = try await makeRequest(context: context)
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "timing-sta-request",
                stageID: stageID,
                fileName: "timing-sta-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )
            let executingEngine: any STAExecuting
            if let engine {
                executingEngine = engine
            } else {
                executingEngine = NativeSTAEngine(
                    reader: ProjectTimingArtifactReader(projectRoot: try context.xcircuiteProjectRoot()),
                    artifactStore: nil
                )
            }
            let result = try await executingEngine.execute(request)
            try await context.checkCancellation()
            let resultArtifact = try await persistResult(result, context: context)
            return makeStageResult(
                result: result,
                requestArtifact: requestArtifact,
                resultArtifact: resultArtifact
            )
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
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        guard !inputs.libraries.isEmpty else {
            throw XcircuiteRuntimeError.invalidInputReference("Timing STA requires at least one timing library input.")
        }
    }

    private func makeRequest(context: FlowExecutionContext) async throws -> STARequest {
        let design = try await reference(
            input: inputs.design,
            context: context,
            artifactID: "timing-design",
            kind: .netlist,
            formatFallback: .json
        )
        var libraries: [TimingLibraryReference] = []
        libraries.reserveCapacity(inputs.libraries.count)
        for (index, input) in inputs.libraries.enumerated() {
            let reference = try await reference(
                input: input,
                context: context,
                artifactID: "timing-library-\(index)",
                kind: .timingLibrary,
                formatFallback: .liberty
            )
            libraries.append(
                TimingLibraryReference(artifact: reference, cornerIDs: inputs.cornerIDs)
            )
        }
        let constraints = try await reference(
            input: inputs.constraints,
            context: context,
            artifactID: "timing-constraints",
            kind: .constraint,
            formatFallback: .sdc
        )
        let pdkManifest = try await reference(
            input: inputs.pdkManifest,
            context: context,
            artifactID: "pdk-manifest",
            kind: .technology,
            formatFallback: .json
        )
        let parasitics: ArtifactReference?
        if let parasiticsInput = inputs.parasitics {
            parasitics = try await reference(
                input: parasiticsInput,
                context: context,
                artifactID: "timing-parasitics",
                kind: .parasitics,
                formatFallback: .spef
            )
        } else {
            parasitics = nil
        }
        return STARequest(
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
            requiresPostLayoutInputs: inputs.requiresPostLayoutInputs
        )
    }

    private func reference(
        input: XcircuiteFlowInputReference,
        context: FlowExecutionContext,
        artifactID: String,
        kind: ArtifactKind,
        formatFallback: ArtifactFormat
    ) async throws -> ArtifactReference {
        try await input.resolveArtifactReference(
            projectRoot: try context.xcircuiteProjectRoot(),
            runDirectory: try context.xcircuiteRunDirectory(),
            infrastructure: context.infrastructure,
            artifactID: artifactID,
            kind: kind,
            format: formatFallback
        )
    }

    private func persistResult(
        _ result: STAExecutionResult,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await context.persistArtifact(
            encoder.encode(result),
            artifactID: "timing-sta-result",
            stageID: stageID,
            fileName: "timing-sta-result.json",
            kind: .report,
            format: .json,
            producer: result.evidence.provenance.producer,
            mode: .replaceable
        )
    }

    private func makeStageResult(
        result: STAExecutionResult,
        requestArtifact: ArtifactReference,
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
            artifacts: [requestArtifact] + result.artifacts + [resultArtifact]
        )
    }

    private func flowSeverity(_ severity: DiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .information: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

}

private struct ProjectTimingArtifactReader: TimingArtifactReading {
    let projectRoot: URL
    let artifactVerifier = LocalArtifactVerifier()

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
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        if let issue = integrity.issues.first {
            switch issue.code {
            case .byteCountMismatch:
                throw TimingError.artifactSizeMismatch(
                    path: reference.path,
                    expected: Int64(clamping: issue.expectedByteCount ?? reference.byteCount),
                    actual: Int64(clamping: issue.actualByteCount ?? 0)
                )
            case .digestMismatch:
                throw TimingError.artifactDigestMismatch(path: reference.path)
            default:
                throw TimingError.artifactReadFailed(
                    path: reference.path,
                    message: issue.detail ?? issue.location ?? issue.code.rawValue
                )
            }
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TimingError.artifactReadFailed(path: reference.path, message: error.localizedDescription)
        }
    }
}
