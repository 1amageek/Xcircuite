import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LVSEngine

public struct LVSFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let layoutNetlistInput: XcircuiteFlowInputReference?
    private let layoutGDSInput: XcircuiteFlowInputReference?
    private let layoutFormat: LVSLayoutFormat?
    private let schematicNetlistInput: XcircuiteFlowInputReference
    private let topCell: String
    private let technologyInput: XcircuiteFlowInputReference?
    private let extractionProfileInput: XcircuiteFlowInputReference?
    private let extractionDeckInput: XcircuiteFlowInputReference?
    private let processProfileID: String?
    private let waiverInput: XcircuiteFlowInputReference?
    private let modelEquivalenceInput: XcircuiteFlowInputReference?
    private let terminalEquivalenceInput: XcircuiteFlowInputReference?
    private let devicePolicyInput: XcircuiteFlowInputReference?
    private let backendSelection: LVSBackendSelection
    private let options: LVSOptions
    private let engine: any LVSEngine.LVSExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: LVSRequest,
        engine: any LVSEngine.LVSExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutNetlistInput = request.layoutNetlistURL.map { .path($0.path(percentEncoded: false)) }
        self.layoutGDSInput = request.layoutGDSURL.map { .path($0.path(percentEncoded: false)) }
        self.layoutFormat = request.layoutFormat
        self.schematicNetlistInput = .path(request.schematicNetlistURL.path(percentEncoded: false))
        self.topCell = request.topCell
        self.technologyInput = request.technologyURL.map { .path($0.path(percentEncoded: false)) }
        self.extractionProfileInput = request.extractionProfileURL.map { .path($0.path(percentEncoded: false)) }
        self.extractionDeckInput = request.extractionDeckURL.map { .path($0.path(percentEncoded: false)) }
        self.processProfileID = request.processProfileID
        self.waiverInput = request.waiverURL.map { .path($0.path(percentEncoded: false)) }
        self.modelEquivalenceInput = request.modelEquivalenceURL.map { .path($0.path(percentEncoded: false)) }
        self.terminalEquivalenceInput = request.terminalEquivalenceURL.map { .path($0.path(percentEncoded: false)) }
        self.devicePolicyInput = request.devicePolicyURL.map { .path($0.path(percentEncoded: false)) }
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
        extractionProfileInput: XcircuiteFlowInputReference? = nil,
        extractionDeckInput: XcircuiteFlowInputReference? = nil,
        processProfileID: String? = nil,
        waiverInput: XcircuiteFlowInputReference? = nil,
        modelEquivalenceInput: XcircuiteFlowInputReference? = nil,
        terminalEquivalenceInput: XcircuiteFlowInputReference? = nil,
        devicePolicyInput: XcircuiteFlowInputReference? = nil,
        backendSelection: LVSBackendSelection = LVSBackendSelection(backendID: "netgen"),
        options: LVSOptions = LVSOptions(),
        engine: any LVSEngine.LVSExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutNetlistInput = layoutNetlistInput
        self.layoutGDSInput = layoutGDSInput
        self.layoutFormat = layoutFormat
        self.schematicNetlistInput = schematicNetlistInput
        self.topCell = topCell
        self.technologyInput = technologyInput
        self.extractionProfileInput = extractionProfileInput
        self.extractionDeckInput = extractionDeckInput
        self.processProfileID = processProfileID
        self.waiverInput = waiverInput
        self.modelEquivalenceInput = modelEquivalenceInput
        self.terminalEquivalenceInput = terminalEquivalenceInput
        self.devicePolicyInput = devicePolicyInput
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
        extractionProfileURL: URL? = nil,
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
                extractionProfileURL: extractionProfileURL,
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
        extractionProfileInput: XcircuiteFlowInputReference? = nil,
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
            extractionProfileInput: extractionProfileInput,
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
            try await context.checkCancellation()
            try validate(stage: stage)
            let rawDirectory = try context.xcircuiteRunDirectory()
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
            try await context.checkCancellation()

            let request = try preparedRequest(
                context: context,
                workingDirectory: rawDirectory
            )
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "lvs-request",
                stageID: stage.stageID,
                fileName: "lvs-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )
            try await context.checkCancellation()
            let executionResult = try await engine.run(
                request,
                cancellationCheck: FlowExecutionCancellationProbe.make(context: context)
            )
            guard executionResult.request == request else {
                throw LVSError.backendFailed(
                    "LVS execution result does not retain the verified flow request."
                )
            }
            try validateExecutionProvenance(
                executionResult.provenance,
                request: request,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            try await context.checkCancellation()
            let executionResultArtifact = try await context.persistJSONArtifact(
                executionResult,
                artifactID: "lvs-execution-result",
                stageID: stage.stageID,
                fileName: "lvs-execution-result.json",
                kind: .report,
                producer: executionResult.provenance.producer,
                mode: .replaceable
            )
            let persistedSummary = try persistSummaryArtifact(
                from: executionResult,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            try await context.checkCancellation()
            var artifacts = try artifactReferences(
                from: executionResult,
                summaryURL: persistedSummary.url,
                context: context
            )
            artifacts.append(requestArtifact)
            artifacts.append(executionResultArtifact)
            let gateStatus = gateStatus(from: executionResult.result)
            let flowDiagnostics = executionResult.result.diagnostics.map(flowDiagnostic)
            let envelopeArtifact = try await LVSSummaryEnvelopeBuilder().envelopeReference(
                summary: persistedSummary.summary,
                summaryArtifactID: "lvs-summary",
                stageArtifacts: artifacts,
                gateStatus: gateStatus,
                diagnostics: flowDiagnostics,
                stageID: stage.stageID,
                toolID: toolID,
                producer: executionResult.provenance.producer,
                context: context
            )
            artifacts.append(envelopeArtifact)
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let artifactManifestGate = StageArtifactManifestCoverageGateBuilder().lvsGate(
                manifestURL: executionResult.artifactManifestURL,
                artifacts: artifacts,
                projectRoot: try context.xcircuiteProjectRoot(),
                expectedProducer: executionResult.provenance.producer
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
                    try await context.checkCancellation()
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
        let projectRoot = try context.xcircuiteProjectRoot()
        let runDirectory = try context.xcircuiteRunDirectory()
        let layoutNetlistArtifact = try layoutNetlistInput.map {
            try $0.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                artifactID: "lvs-layout-netlist-input",
                kind: .netlist,
                format: .spice
            )
        }
        let layoutGDSArtifact = try layoutGDSInput.map {
            try $0.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                artifactID: "lvs-layout-input",
                kind: .layout,
                format: try artifactFormat(for: layoutFormat)
            )
        }
        let schematicArtifact = try schematicNetlistInput.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-schematic-netlist-input",
            kind: .netlist,
            format: .spice
        )
        let technologyArtifact = try resolveOptionalInput(
            technologyInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-technology-input",
            kind: .technology,
            format: .json
        )
        let extractionProfileArtifact = try resolveOptionalInput(
            extractionProfileInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-extraction-profile-input",
            kind: .technology,
            format: .json
        )
        let extractionDeckArtifact = try resolveOptionalInput(
            extractionDeckInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-extraction-deck-input",
            kind: .ruleDeck,
            format: nil
        )
        let waiverArtifact = try resolveOptionalInput(
            waiverInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-waiver-input",
            kind: .constraint,
            format: .json
        )
        let modelEquivalenceArtifact = try resolveOptionalInput(
            modelEquivalenceInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-model-equivalence-input",
            kind: .constraint,
            format: .json
        )
        let terminalEquivalenceArtifact = try resolveOptionalInput(
            terminalEquivalenceInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-terminal-equivalence-input",
            kind: .constraint,
            format: .json
        )
        let devicePolicyArtifact = try resolveOptionalInput(
            devicePolicyInput,
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            artifactID: "lvs-device-policy-input",
            kind: .constraint,
            format: .json
        )
        let optionalArtifacts = [
            layoutNetlistArtifact,
            layoutGDSArtifact,
            technologyArtifact,
            extractionProfileArtifact,
            extractionDeckArtifact,
            waiverArtifact,
            modelEquivalenceArtifact,
            terminalEquivalenceArtifact,
            devicePolicyArtifact,
        ].compactMap { $0 }
        return LVSRequest(
            layoutNetlistURL: try layoutNetlistArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            layoutGDSURL: try layoutGDSArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            layoutFormat: layoutFormat,
            schematicNetlistURL: try schematicArtifact.locator.location.resolvedFileURL(relativeTo: projectRoot),
            topCell: topCell,
            technologyURL: try technologyArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            extractionProfileURL: try extractionProfileArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            extractionDeckURL: try extractionDeckArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            processProfileID: processProfileID,
            waiverURL: try waiverArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            modelEquivalenceURL: try modelEquivalenceArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            terminalEquivalenceURL: try terminalEquivalenceArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            devicePolicyURL: try devicePolicyArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            workingDirectory: workingDirectory,
            backendSelection: backendSelection,
            options: options,
            executionInputArtifacts: [schematicArtifact] + optionalArtifacts
        )
    }

    private func resolveOptionalInput(
        _ input: XcircuiteFlowInputReference?,
        projectRoot: URL,
        runDirectory: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat?
    ) throws -> ArtifactReference? {
        try input.map {
            try $0.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                artifactID: artifactID,
                kind: kind,
                format: format
            )
        }
    }

    private func artifactFormat(for format: LVSLayoutFormat?) throws -> ArtifactFormat? {
        switch format {
        case .gds: .gdsii
        case .oasis: .oasis
        case .cif: try ArtifactFormat(rawValue: "cif")
        case .dxf: try ArtifactFormat(rawValue: "dxf")
        case .auto, nil: nil
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = FlowIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func validateExecutionProvenance(
        _ provenance: ExecutionProvenance,
        request: LVSRequest,
        projectRoot: URL
    ) throws {
        guard provenance.producer.kind == .engine,
              let build = provenance.producer.build,
              isSHA256(build),
              provenance.invocation != nil,
              provenance.environment != nil,
              provenance.inputs == request.executionInputArtifacts,
              provenance.inputs.allSatisfy({
                  LocalArtifactVerifier().verify($0, relativeTo: projectRoot).isVerified
              }) else {
            throw LVSError.backendFailed(
                "LVS execution provenance does not match the verified request inputs and executable identity."
            )
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private func artifactReferences(
        from executionResult: LVSExecutionResult,
        summaryURL: URL,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        var artifacts: [ArtifactReference] = []
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                kind: .report,
                format: .json,
                producer: executionResult.provenance.producer
            ))
        }
        if let manifestURL = executionResult.artifactManifestURL {
            artifacts.append(try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                kind: .report,
                format: .json,
                producer: executionResult.provenance.producer
            ))
        }
        artifacts.append(try artifactBuilder.reference(
            for: summaryURL,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "lvs-summary",
            kind: .report,
            format: .json,
            producer: executionResult.provenance.producer
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
            projectRoot: try context.xcircuiteProjectRoot(),
                kind: .report,
                format: .text,
                producer: executionResult.provenance.producer
        ) {
            artifacts.append(log)
        }
        if let extracted = executionResult.extractedLayoutNetlistURL {
            artifacts.append(try artifactBuilder.reference(
                for: extracted,
                projectRoot: try context.xcircuiteProjectRoot(),
                kind: .netlist,
                format: .spice,
                producer: executionResult.provenance.producer
            ))
        }
        if let correspondenceURL = executionResult.correspondenceURL {
            artifacts.append(try artifactBuilder.reference(
                for: correspondenceURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: "lvs-correspondence",
                kind: .report,
                format: .json,
                producer: executionResult.provenance.producer
            ))
        }
        if let extractionReportURL = executionResult.extractionReportURL {
            artifacts.append(try artifactBuilder.reference(
                for: extractionReportURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: "lvs-extraction-report",
                kind: .report,
                format: .json,
                producer: executionResult.provenance.producer
            ))
        }
        if let transformLedgerURL = executionResult.transformLedgerURL {
            artifacts.append(try artifactBuilder.reference(
                for: transformLedgerURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: "lvs-transform-ledger",
                kind: .report,
                format: .json,
                producer: executionResult.provenance.producer
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
    ) throws -> ArtifactReference? {
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
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "lvs-device-policy-application-report",
            kind: .report,
            format: .json,
            producer: executionResult.provenance.producer
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
