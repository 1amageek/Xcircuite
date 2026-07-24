import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct PostLayoutComparisonFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let preLayoutWaveformInput: XcircuiteFlowInputReference
    private let postLayoutWaveformInput: XcircuiteFlowInputReference
    private let options: PostLayoutComparisonOptions
    private let service: PostLayoutComparisonService

    public init(
        stageID: String,
        toolID: String = "post-layout-comparison",
        preLayoutWaveformURL: URL,
        postLayoutWaveformURL: URL,
        options: PostLayoutComparisonOptions = PostLayoutComparisonOptions(),
        service: PostLayoutComparisonService = PostLayoutComparisonService()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.preLayoutWaveformInput = .path(preLayoutWaveformURL.path(percentEncoded: false))
        self.postLayoutWaveformInput = .path(postLayoutWaveformURL.path(percentEncoded: false))
        self.options = options
        self.service = service
    }

    public init(
        stageID: String,
        toolID: String = "post-layout-comparison",
        preLayoutWaveformInput: XcircuiteFlowInputReference,
        postLayoutWaveformInput: XcircuiteFlowInputReference,
        options: PostLayoutComparisonOptions = PostLayoutComparisonOptions(),
        service: PostLayoutComparisonService = PostLayoutComparisonService()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.preLayoutWaveformInput = preLayoutWaveformInput
        self.postLayoutWaveformInput = postLayoutWaveformInput
        self.options = options
        self.service = service
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let projectRoot = try context.xcircuiteProjectRoot()
            let runDirectory = try context.xcircuiteRunDirectory()
            let preLayoutWaveform = try await preLayoutWaveformInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "pre-layout-waveform",
                kind: .waveform,
                format: .csv
            )
            let postLayoutWaveform = try await postLayoutWaveformInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "post-layout-waveform",
                kind: .waveform,
                format: .csv
            )
            let preLayoutWaveformURL = try preLayoutWaveform.locator.location
                .resolvedFileURL(relativeTo: projectRoot)
            let postLayoutWaveformURL = try postLayoutWaveform.locator.location
                .resolvedFileURL(relativeTo: projectRoot)
            let preLayoutCSV = try String(contentsOf: preLayoutWaveformURL, encoding: .utf8)
            let postLayoutCSV = try String(contentsOf: postLayoutWaveformURL, encoding: .utf8)
            try await context.checkCancellation()
            let producer = try ProducerIdentity(
                kind: .engine,
                identifier: toolID,
                version: "1.0.0"
            )
            let report = try service.compare(
                preLayoutCSV: preLayoutCSV,
                postLayoutCSV: postLayoutCSV,
                options: options,
                inputs: [preLayoutWaveform, postLayoutWaveform],
                producer: producer
            )
            try await context.checkCancellation()
            let reportArtifact = try await context.persistJSONArtifact(
                report,
                artifactID: "post-layout-comparison",
                stageID: stageID,
                fileName: "comparison-report.json",
                producer: report.provenance.producer,
                mode: .replaceable
            )

            let diagnostics = diagnostics(from: report)
            let gateStatus: FlowGateStatus = report.gateViolations.isEmpty ? .passed : .failed
            let artifacts = [reportArtifact]
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let stageStatus: FlowStageStatus = gateStatus == .passed
                && artifactIntegrityGate.status == .passed
                ? .succeeded
                : .failed
            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics + artifactIntegrityGate.diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "comparison",
                        status: gateStatus,
                        diagnostics: diagnostics
                    ),
                    artifactIntegrityGate,
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "POST_LAYOUT_COMPARISON_ERROR",
                message: error.localizedDescription
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "comparison",
                        status: .failed,
                        diagnostics: [diagnostic]
                    ),
                ]
            )
        }
    }

    private func diagnostics(from report: PostLayoutComparisonReport) -> [FlowDiagnostic] {
        var diagnostics = [
            FlowDiagnostic(
                severity: .info,
                code: "POST_LAYOUT_COMPARISON_SUMMARY",
                message: "compared \(report.comparedVariables.count) variable(s), maxAbs=\(report.maxAbsoluteDelta), maxRel=\(report.maxRelativeDelta)"
            ),
        ]
        diagnostics.append(contentsOf: report.diagnostics.map {
            FlowDiagnostic(severity: .warning, code: "POST_LAYOUT_COMPARISON_DIAGNOSTIC", message: $0)
        })
        diagnostics.append(contentsOf: report.gateViolations.map {
            FlowDiagnostic(severity: .error, code: "POST_LAYOUT_COMPARISON_GATE_VIOLATION", message: $0)
        })
        return diagnostics
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = FlowIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }
}
