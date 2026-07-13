import DesignFlowKernel
import Foundation
import LVSEngine
import DesignFlowKernel

public struct LVSFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let layoutNetlistInput: XcircuiteFlowInputReference?
    private let layoutGDSInput: XcircuiteFlowInputReference?
    private let layoutFormat: LVSLayoutFormat?
    private let schematicNetlistInput: XcircuiteFlowInputReference
    private let topCell: String
    private let technologyInput: XcircuiteFlowInputReference?
    private let extractionDeckInput: XcircuiteFlowInputReference?
    private let processProfileID: String?
    private let waiverInput: XcircuiteFlowInputReference?
    private let modelEquivalenceInput: XcircuiteFlowInputReference?
    private let terminalEquivalenceInput: XcircuiteFlowInputReference?
    private let backendSelection: LVSBackendSelection
    private let options: LVSOptions
    private let engine: any LVSExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: LVSRequest,
        engine: any LVSExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutNetlistInput = request.layoutNetlistURL.map { .path($0.path(percentEncoded: false)) }
        self.layoutGDSInput = request.layoutGDSURL.map { .path($0.path(percentEncoded: false)) }
        self.layoutFormat = request.layoutFormat
        self.schematicNetlistInput = .path(request.schematicNetlistURL.path(percentEncoded: false))
        self.topCell = request.topCell
        self.technologyInput = request.technologyURL.map { .path($0.path(percentEncoded: false)) }
        self.extractionDeckInput = request.extractionDeckURL.map { .path($0.path(percentEncoded: false)) }
        self.processProfileID = request.processProfileID
        self.waiverInput = request.waiverURL.map { .path($0.path(percentEncoded: false)) }
        self.modelEquivalenceInput = request.modelEquivalenceURL.map { .path($0.path(percentEncoded: false)) }
        self.terminalEquivalenceInput = request.terminalEquivalenceURL.map { .path($0.path(percentEncoded: false)) }
        self.backendSelection = request.backendSelection
        self.options = request.options
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public init(
        stageID: String,
        toolID: String,
        layoutNetlistInput: XcircuiteFlowInputReference? = nil,
        layoutGDSInput: XcircuiteFlowInputReference? = nil,
        layoutFormat: LVSLayoutFormat? = nil,
        schematicNetlistInput: XcircuiteFlowInputReference,
        topCell: String,
        technologyInput: XcircuiteFlowInputReference? = nil,
        extractionDeckInput: XcircuiteFlowInputReference? = nil,
        processProfileID: String? = nil,
        waiverInput: XcircuiteFlowInputReference? = nil,
        modelEquivalenceInput: XcircuiteFlowInputReference? = nil,
        terminalEquivalenceInput: XcircuiteFlowInputReference? = nil,
        backendSelection: LVSBackendSelection = LVSBackendSelection(backendID: "netgen"),
        options: LVSOptions = LVSOptions(),
        engine: any LVSExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutNetlistInput = layoutNetlistInput
        self.layoutGDSInput = layoutGDSInput
        self.layoutFormat = layoutFormat
        self.schematicNetlistInput = schematicNetlistInput
        self.topCell = topCell
        self.technologyInput = technologyInput
        self.extractionDeckInput = extractionDeckInput
        self.processProfileID = processProfileID
        self.waiverInput = waiverInput
        self.modelEquivalenceInput = modelEquivalenceInput
        self.terminalEquivalenceInput = terminalEquivalenceInput
        self.backendSelection = backendSelection
        self.options = options
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func native(
        stageID: String,
        layoutNetlistURL: URL? = nil,
        layoutGDSURL: URL? = nil,
        layoutFormat: LVSLayoutFormat? = nil,
        schematicNetlistURL: URL,
        topCell: String,
        technologyURL: URL? = nil,
        extractionDeckURL: URL? = nil,
        processProfileID: String? = nil,
        terminalEquivalenceURL: URL? = nil,
        options: LVSOptions = LVSOptions()
    ) -> LVSFlowStageExecutor {
        let backendID = layoutNetlistURL == nil ? "native-gds" : "native"
        return LVSFlowStageExecutor(
            stageID: stageID,
            toolID: "native-lvs",
            request: LVSRequest(
                layoutNetlistURL: layoutNetlistURL,
                layoutGDSURL: layoutGDSURL,
                layoutFormat: layoutFormat,
                schematicNetlistURL: schematicNetlistURL,
                topCell: topCell,
                technologyURL: technologyURL,
                extractionDeckURL: extractionDeckURL,
                processProfileID: processProfileID,
                terminalEquivalenceURL: terminalEquivalenceURL,
                backendSelection: LVSBackendSelection(backendID: backendID),
                options: options
            ),
            engine: DefaultLVSEngine(backend: nil, layoutNetlistExtractor: nil)
        )
    }

    public static func native(
        stageID: String,
        layoutNetlistInput: XcircuiteFlowInputReference? = nil,
        layoutGDSInput: XcircuiteFlowInputReference? = nil,
        layoutFormat: LVSLayoutFormat? = nil,
        schematicNetlistInput: XcircuiteFlowInputReference,
        topCell: String,
        technologyInput: XcircuiteFlowInputReference? = nil,
        extractionDeckInput: XcircuiteFlowInputReference? = nil,
        processProfileID: String? = nil,
        terminalEquivalenceInput: XcircuiteFlowInputReference? = nil,
        options: LVSOptions = LVSOptions()
    ) -> LVSFlowStageExecutor {
        let backendID = layoutNetlistInput == nil ? "native-gds" : "native"
        return LVSFlowStageExecutor(
            stageID: stageID,
            toolID: "native-lvs",
            layoutNetlistInput: layoutNetlistInput,
            layoutGDSInput: layoutGDSInput,
            layoutFormat: layoutFormat,
            schematicNetlistInput: schematicNetlistInput,
            topCell: topCell,
            technologyInput: technologyInput,
            extractionDeckInput: extractionDeckInput,
            processProfileID: processProfileID,
            terminalEquivalenceInput: terminalEquivalenceInput,
            backendSelection: LVSBackendSelection(backendID: backendID),
            options: options,
            engine: DefaultLVSEngine(backend: nil, layoutNetlistExtractor: nil)
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
            try context.packageStore.ensureDirectory(at: rawDirectory)
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
            let envelopeArtifact = try LVSSummaryEnvelopeBuilder().envelopeReference(
                summary: persistedSummary.summary,
                summaryArtifactID: "lvs-summary",
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
            let artifactManifestGate = StageArtifactManifestCoverageGateBuilder().lvsGate(
                manifestURL: executionResult.artifactManifestURL,
                artifacts: artifacts,
                projectRoot: context.projectRoot
            )
            let diagnostics = flowDiagnostics
                + artifactManifestGate.diagnostics
                + artifactIntegrityGate.diagnostics
            let artifactsPassed = artifactManifestGate.status == .passed
                && artifactIntegrityGate.status == .passed
            let stageStatus: FlowStageStatus
            if !artifactsPassed {
                stageStatus = .failed
            } else {
                switch gateStatus {
                case .passed, .waived:
                    stageStatus = .succeeded
                case .blocked, .incomplete:
                    stageStatus = .blocked
                case .failed:
                    stageStatus = .failed
                }
            }

            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "lvs",
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
                    code: "LVS_ARTIFACT_OUTPUT_OUTSIDE_PROJECT",
                    message: error.localizedDescription
                )
            default:
                return failureResult(
                    stageID: stage.stageID,
                    code: "LVS_EXECUTION_ERROR",
                    message: error.localizedDescription
                )
            }
        } catch let error as LVSError {
            switch error {
            case .cancelled:
                do {
                    try context.checkCancellation()
                } catch let cancellationError as FlowRunCancellationError {
                    throw cancellationError
                }
                return failureResult(
                    stageID: stage.stageID,
                    code: "LVS_EXECUTION_CANCELLED",
                    message: error.localizedDescription
                )
            default:
                return failureResult(
                    stageID: stage.stageID,
                    code: "LVS_EXECUTION_ERROR",
                    message: error.localizedDescription
                )
            }
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "LVS_EXECUTION_ERROR",
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
                    gateID: "lvs",
                    status: .failed,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func preparedRequest(
        context: FlowExecutionContext,
        workingDirectory: URL
    ) throws -> LVSRequest {
        LVSRequest(
            layoutNetlistURL: try layoutNetlistInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            layoutGDSURL: try layoutGDSInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            layoutFormat: layoutFormat,
            schematicNetlistURL: try schematicNetlistInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            topCell: topCell,
            technologyURL: try technologyInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            extractionDeckURL: try extractionDeckInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            processProfileID: processProfileID,
            waiverURL: try waiverInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            modelEquivalenceURL: try modelEquivalenceInput?.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            terminalEquivalenceURL: try terminalEquivalenceInput?.resolveExisting(
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
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from executionResult: LVSExecutionResult,
        summaryURL: URL,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        var artifacts: [XcircuiteFileReference] = []
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        if let manifestURL = executionResult.artifactManifestURL {
            artifacts.append(try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: context.projectRoot,
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        artifacts.append(try artifactBuilder.reference(
            for: summaryURL,
            projectRoot: context.projectRoot,
            artifactID: "lvs-summary",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        ))
        if let devicePolicyReport = try persistDevicePolicyReportArtifact(
            from: executionResult,
            summaryURL: summaryURL,
            context: context
        ) {
            artifacts.append(devicePolicyReport)
        }
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: context.projectRoot,
            kind: .report,
            format: .text,
            producedByRunID: context.runID
        ) {
            artifacts.append(log)
        }
        if let extracted = executionResult.extractedLayoutNetlistURL {
            artifacts.append(try artifactBuilder.reference(
                for: extracted,
                projectRoot: context.projectRoot,
                kind: .netlist,
                format: .spice,
                producedByRunID: context.runID
            ))
        }
        if let correspondenceURL = executionResult.correspondenceURL {
            artifacts.append(try artifactBuilder.reference(
                for: correspondenceURL,
                projectRoot: context.projectRoot,
                artifactID: "lvs-correspondence",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        if let extractionReportURL = executionResult.extractionReportURL {
            artifacts.append(try artifactBuilder.reference(
                for: extractionReportURL,
                projectRoot: context.projectRoot,
                artifactID: "lvs-extraction-report",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        if let transformLedgerURL = executionResult.transformLedgerURL {
            artifacts.append(try artifactBuilder.reference(
                for: transformLedgerURL,
                projectRoot: context.projectRoot,
                artifactID: "lvs-transform-ledger",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        return artifacts
    }

    private func persistSummaryArtifact(
        from executionResult: LVSExecutionResult,
        projectRoot: URL
    ) throws -> (summary: LVSRunSummaryReport, url: URL) {
        guard let manifestURL = executionResult.artifactManifestURL else {
            throw LVSError.artifactWriteFailed("Missing LVS artifact manifest URL for summary artifact")
        }
        let outputDirectory = try StageArtifactOutputPathGuard()
            .validateOutputDirectory(for: manifestURL, projectRoot: projectRoot)
        let summary = LVSRunSummaryBuilder().build(result: executionResult)
        let summaryURL = outputDirectory
            .appending(path: "lvs-summary.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: summaryURL, options: .atomic)
        return (summary, summaryURL)
    }

    private func persistDevicePolicyReportArtifact(
        from executionResult: LVSExecutionResult,
        summaryURL: URL,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference? {
        guard let report = executionResult.devicePolicyReport else {
            return nil
        }
        let reportURL = summaryURL
            .deletingLastPathComponent()
            .appending(path: "lvs-device-policy-application-report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: reportURL, options: .atomic)
        return try artifactBuilder.reference(
            for: reportURL,
            projectRoot: context.projectRoot,
            artifactID: "lvs-device-policy-application-report",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func gateStatus(from result: LVSResult) -> FlowGateStatus {
        guard result.executionStatus == .completed else {
            return .blocked
        }
        guard result.readiness == .ready else {
            return .blocked
        }
        switch result.verdict {
        case .match:
            return result.passed ? .passed : .failed
        case .mismatch:
            return .failed
        case .blocked:
            return .blocked
        }
    }

    private func flowDiagnostic(_ diagnostic: LVSDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: flowSeverity(diagnostic.severity),
            code: diagnostic.ruleID ?? "LVS_DIAGNOSTIC",
            message: diagnostic.message
        )
    }

    private func flowSeverity(_ severity: LVSDiagnostic.Severity) -> FlowDiagnosticSeverity {
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
