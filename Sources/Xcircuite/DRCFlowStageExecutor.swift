import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation

public struct DRCFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let layoutInput: XcircuiteFlowInputReference
    private let topCell: String
    private let layoutFormat: DRCLayoutFormat?
    private let technologyInput: XcircuiteFlowInputReference?
    private let backendSelection: DRCBackendSelection
    private let options: DRCOptions
    private let engine: any DRCExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: DRCRequest,
        engine: any DRCExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutInput = .path(request.layoutURL.path(percentEncoded: false))
        self.topCell = request.topCell
        self.layoutFormat = request.layoutFormat
        self.technologyInput = request.technologyURL.map { .path($0.path(percentEncoded: false)) }
        self.backendSelection = request.backendSelection
        self.options = request.options
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public init(
        stageID: String,
        toolID: String,
        layoutInput: XcircuiteFlowInputReference,
        topCell: String,
        layoutFormat: DRCLayoutFormat? = nil,
        technologyInput: XcircuiteFlowInputReference? = nil,
        backendSelection: DRCBackendSelection = DRCBackendSelection(backendID: "magic"),
        options: DRCOptions = DRCOptions(),
        engine: any DRCExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutInput = layoutInput
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.technologyInput = technologyInput
        self.backendSelection = backendSelection
        self.options = options
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func native(
        stageID: String,
        layoutURL: URL,
        topCell: String,
        layoutFormat: DRCLayoutFormat? = nil,
        technologyURL: URL? = nil,
        options: DRCOptions = DRCOptions()
    ) -> DRCFlowStageExecutor {
        let backendID = technologyURL == nil ? "native" : "native-gds"
        return DRCFlowStageExecutor(
            stageID: stageID,
            toolID: "native-drc",
            request: DRCRequest(
                layoutURL: layoutURL,
                topCell: topCell,
                layoutFormat: layoutFormat,
                technologyURL: technologyURL,
                backendSelection: DRCBackendSelection(backendID: backendID),
                options: options
            ),
            engine: DefaultDRCEngine(backend: nil)
        )
    }

    public static func native(
        stageID: String,
        layoutInput: XcircuiteFlowInputReference,
        topCell: String,
        layoutFormat: DRCLayoutFormat? = nil,
        technologyInput: XcircuiteFlowInputReference? = nil,
        options: DRCOptions = DRCOptions()
    ) -> DRCFlowStageExecutor {
        let backendID = technologyInput == nil ? "native" : "native-gds"
        return DRCFlowStageExecutor(
            stageID: stageID,
            toolID: "native-drc",
            layoutInput: layoutInput,
            topCell: topCell,
            layoutFormat: layoutFormat,
            technologyInput: technologyInput,
            backendSelection: DRCBackendSelection(backendID: backendID),
            options: options,
            engine: DefaultDRCEngine(backend: nil)
        )
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

            let request = try preparedRequest(
                context: context,
                workingDirectory: rawDirectory
            )
            try context.checkCancellation()
            let executionResult = try await engine.run(
                request,
                cancellationCheck: FlowExecutionCancellationProbe.make(context: context)
            )
            try context.checkCancellation()
            let persistedSummary = try persistSummaryArtifact(
                from: executionResult,
                projectRoot: context.projectRoot
            )
            try context.checkCancellation()
            var artifacts = try artifactReferences(
                from: executionResult,
                summaryURL: persistedSummary.url,
                context: context
            )
            let gateStatus = gateStatus(from: executionResult.result)
            let flowDiagnostics = executionResult.result.diagnostics.map(flowDiagnostic)
            let envelopeArtifact = try DRCSummaryEnvelopeBuilder().envelopeReference(
                summary: persistedSummary.summary,
                summaryArtifactID: "drc-summary",
                stageArtifacts: artifacts,
                gateStatus: gateStatus,
                diagnostics: flowDiagnostics,
                stageID: stage.stageID,
                toolID: toolID,
                context: context
            )
            artifacts.append(envelopeArtifact)
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: context.projectRoot
            )
            let artifactManifestGate = StageArtifactManifestCoverageGateBuilder().drcGate(
                manifestURL: executionResult.artifactManifestURL,
                artifacts: artifacts,
                projectRoot: context.projectRoot
            )
            let diagnostics = flowDiagnostics
                + artifactManifestGate.diagnostics
                + artifactIntegrityGate.diagnostics
            let stageStatus: FlowStageStatus = gateStatus == .passed
                && artifactManifestGate.status == .passed
                && artifactIntegrityGate.status == .passed
                ? .succeeded
                : .failed

            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "drc",
                        status: gateStatus,
                        diagnostics: flowDiagnostics
                    ),
                    artifactManifestGate,
                    artifactIntegrityGate,
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as XcircuiteRuntimeError {
            switch error {
            case .artifactOutsideProject:
                return failureResult(
                    stageID: stage.stageID,
                    code: "DRC_ARTIFACT_OUTPUT_OUTSIDE_PROJECT",
                    message: error.localizedDescription
                )
            default:
                return failureResult(
                    stageID: stage.stageID,
                    code: "DRC_EXECUTION_ERROR",
                    message: error.localizedDescription
                )
            }
        } catch let error as DRCError {
            switch error {
            case .cancelled:
                do {
                    try context.checkCancellation()
                } catch let cancellationError as FlowRunCancellationError {
                    throw cancellationError
                }
                return failureResult(
                    stageID: stage.stageID,
                    code: "DRC_EXECUTION_CANCELLED",
                    message: error.localizedDescription
                )
            default:
                return failureResult(
                    stageID: stage.stageID,
                    code: "DRC_EXECUTION_ERROR",
                    message: error.localizedDescription
                )
            }
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "DRC_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(
            severity: .error,
            code: code,
            message: message
        )
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "drc",
                    status: .failed,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func preparedRequest(
        context: FlowExecutionContext,
        workingDirectory: URL
    ) throws -> DRCRequest {
        DRCRequest(
            layoutURL: try layoutInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            topCell: topCell,
            layoutFormat: layoutFormat,
            technologyURL: try technologyInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            workingDirectory: workingDirectory,
            backendSelection: backendSelection,
            options: options
        )
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stage.stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from executionResult: DRCExecutionResult,
        summaryURL: URL,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        var artifacts: [ArtifactReference] = []
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json
            ))
        }
        if let manifestURL = executionResult.artifactManifestURL {
            artifacts.append(try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json
            ))
        }
        artifacts.append(try artifactBuilder.reference(
            for: summaryURL,
            projectRoot: context.projectRoot,
            artifactID: "drc-summary",
            kind: .report,
            format: .json
        ))
        artifacts.append(try persistRepairHintArtifact(
            from: executionResult,
            summaryURL: summaryURL,
            context: context
        ))
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: context.projectRoot,
            kind: .report,
            format: .text
        ) {
            artifacts.append(log)
        }
        return artifacts
    }

    private func persistSummaryArtifact(
        from executionResult: DRCExecutionResult,
        projectRoot: URL
    ) throws -> (summary: DRCRunSummaryReport, url: URL) {
        guard let manifestURL = executionResult.artifactManifestURL else {
            throw DRCError.artifactWriteFailed("Missing DRC artifact manifest URL for summary artifact")
        }
        let outputDirectory = try StageArtifactOutputPathGuard()
            .validateOutputDirectory(for: manifestURL, projectRoot: projectRoot)
        let summary = DRCRunSummaryBuilder().build(result: executionResult)
        let summaryURL = outputDirectory
            .appending(path: "drc-summary.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: summaryURL, options: .atomic)
        return (summary, summaryURL)
    }

    private func persistRepairHintArtifact(
        from executionResult: DRCExecutionResult,
        summaryURL: URL,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let report = DRCRepairHintBuilder().build(
            result: executionResult,
            reportURL: executionResult.reportURL
        )
        let url = summaryURL
            .deletingLastPathComponent()
            .appending(path: "drc-repair-hints.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: "drc-repair-hints",
            kind: .report,
            format: .json
        )
    }

    private func gateStatus(from result: DRCResult) -> FlowGateStatus {
        if result.passed {
            return .passed
        }
        if !result.completed {
            return .incomplete
        }
        return .failed
    }

    private func flowDiagnostic(_ diagnostic: DRCDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.ruleID ?? "DRC_DIAGNOSTIC",
            message: diagnostic.message
        )
    }

    private func flowSeverity(_ severity: DRCDiagnostic.Severity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}
