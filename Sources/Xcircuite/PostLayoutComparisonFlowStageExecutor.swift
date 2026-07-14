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
    private let artifactBuilder: StageArtifactReferenceBuilder

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
        self.artifactBuilder = StageArtifactReferenceBuilder()
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
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try context.storage.ensureDirectory(at: rawDirectory)
            try context.checkCancellation()

            let preLayoutWaveformURL = try preLayoutWaveformInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let postLayoutWaveformURL = try postLayoutWaveformInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let preLayoutCSV = try String(contentsOf: preLayoutWaveformURL, encoding: .utf8)
            let postLayoutCSV = try String(contentsOf: postLayoutWaveformURL, encoding: .utf8)
            try context.checkCancellation()
            let report = try service.compare(
                preLayoutCSV: preLayoutCSV,
                postLayoutCSV: postLayoutCSV,
                options: options
            )
            try context.checkCancellation()
            let reportURL = rawDirectory.appending(path: "comparison-report.json")
            try context.storage.writeJSON(
                report,
                to: reportURL,
                forProjectAt: context.projectRoot
            )

            let diagnostics = diagnostics(from: report)
            let gateStatus: FlowGateStatus = report.gateViolations.isEmpty ? .passed : .failed
            let artifacts = [
                try artifactBuilder.reference(
                    for: reportURL,
                    projectRoot: context.projectRoot,
                    artifactID: "post-layout-comparison",
                    kind: ArtifactKind.report,
                    format: ArtifactFormat.json
                ),
            ]
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: context.projectRoot
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
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }
}
