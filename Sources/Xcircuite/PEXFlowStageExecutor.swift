import DesignFlowKernel
import Foundation
import PEXEngine
import XcircuitePackage

public struct PEXFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let request: PEXRunRequest
    private let engine: any PEXExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: PEXRunRequest,
        engine: any PEXExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.request = request
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func mock(
        stageID: String,
        layoutURL: URL,
        layoutFormat: LayoutFormat,
        sourceNetlistURL: URL,
        sourceNetlistFormat: NetlistFormat = .spice,
        topCell: String,
        corners: [PEXCorner],
        technology: TechnologyInput,
        options: PEXRunOptions = .default
    ) -> PEXFlowStageExecutor {
        PEXFlowStageExecutor(
            stageID: stageID,
            toolID: "mock-pex",
            request: PEXRunRequest(
                layoutURL: layoutURL,
                layoutFormat: layoutFormat,
                sourceNetlistURL: sourceNetlistURL,
                sourceNetlistFormat: sourceNetlistFormat,
                topCell: topCell,
                corners: corners,
                technology: technology,
                backendSelection: .mock(),
                options: options
            ),
            engine: DefaultPEXEngine.withDefaults()
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try validate(stage: stage)
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try context.packageStore.ensureDirectory(at: rawDirectory)

            let runResult = try await engine.run(preparedRequest(workingDirectory: rawDirectory))
            let diagnostics = flowDiagnostics(from: runResult)
            let gateStatus = gateStatus(from: runResult.status)

            return FlowStageResult(
                stageID: stage.stageID,
                status: gateStatus == .passed ? .succeeded : .failed,
                diagnostics: diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "pex",
                        status: gateStatus,
                        diagnostics: diagnostics
                    ),
                ],
                artifacts: try artifactReferences(from: runResult, context: context)
            )
        } catch {
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [
                    FlowDiagnostic(
                        severity: .error,
                        code: "PEX_EXECUTION_ERROR",
                        message: error.localizedDescription
                    ),
                ],
                gates: [
                    FlowGateResult(
                        gateID: "pex",
                        status: .failed,
                        diagnostics: [
                            FlowDiagnostic(
                                severity: .error,
                                code: "PEX_EXECUTION_ERROR",
                                message: error.localizedDescription
                            ),
                        ]
                    ),
                ]
            )
        }
    }

    private func preparedRequest(workingDirectory: URL) -> PEXRunRequest {
        PEXRunRequest(
            layoutURL: request.layoutURL,
            layoutFormat: request.layoutFormat,
            sourceNetlistURL: request.sourceNetlistURL,
            sourceNetlistFormat: request.sourceNetlistFormat,
            topCell: request.topCell,
            corners: request.corners,
            technology: request.technology,
            backendSelection: request.backendSelection,
            options: request.options,
            workingDirectory: workingDirectory
        )
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from result: PEXRunResult,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        let pexRunDirectory = result.manifestURL.deletingLastPathComponent()
        var artifacts = [
            try artifactBuilder.reference(
                for: result.manifestURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ),
        ]

        for artifact in result.artifacts.artifacts where artifact.status == .available {
            let url = pexRunDirectory.appending(path: artifact.relativePath.value)
            artifacts.append(try artifactBuilder.reference(
                for: url,
                projectRoot: context.projectRoot,
                kind: fileKind(for: artifact.kind),
                format: fileFormat(for: artifact, url: url),
                producedByRunID: context.runID
            ))
        }
        return artifacts
    }

    private func gateStatus(from status: PEXRunStatus) -> FlowGateStatus {
        switch status {
        case .success:
            .passed
        case .partialSuccess:
            .incomplete
        case .failed:
            .failed
        }
    }

    private func flowDiagnostics(from result: PEXRunResult) -> [FlowDiagnostic] {
        var diagnostics = result.warnings.map { warning in
            FlowDiagnostic(
                severity: .warning,
                code: "PEX_WARNING",
                message: warning.message
            )
        }
        for corner in result.cornerResults where corner.status == .failed {
            diagnostics.append(FlowDiagnostic(
                severity: .error,
                code: "PEX_CORNER_FAILED",
                message: "PEX failed for corner \(corner.cornerID.value)."
            ))
        }
        return diagnostics
    }

    private func fileKind(for kind: PEXArtifactKind) -> XcircuiteFileKind {
        switch kind {
        case .layoutInput:
            .layout
        case .netlistInput:
            .netlist
        case .technologyInput:
            .technology
        case .request, .log, .report:
            .report
        case .rawOutput, .parasiticIR:
            .parasitic
        }
    }

    private func fileFormat(for artifact: PEXArtifactRecord, url: URL) -> XcircuiteFileFormat {
        switch artifact.kind {
        case .rawOutput:
            .spef
        case .parasiticIR, .request, .technologyInput:
            .json
        case .log, .report:
            .text
        case .layoutInput:
            layoutFormat(from: url)
        case .netlistInput:
            netlistFormat(from: url)
        }
    }

    private func layoutFormat(from url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "oas", "oasis":
            .oasis
        case "gds":
            .gdsii
        default:
            .unknown
        }
    }

    private func netlistFormat(from url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "sp", "spi", "cir", "net", "spice":
            .spice
        default:
            .unknown
        }
    }
}
