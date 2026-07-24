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
    private let waiverInput: XcircuiteFlowInputReference?
    private let backendSelection: DRCBackendSelection
    private let options: DRCOptions
    private let designRevision: String?
    private let canonicalStateDigest: String?
    private let engine: any DRCEngine.DRCExecuting
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String,
        request: DRCRequest,
        engine: any DRCEngine.DRCExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutInput = .path(request.layoutURL.path(percentEncoded: false))
        self.topCell = request.topCell
        self.layoutFormat = request.layoutFormat
        self.technologyInput = request.technologyURL.map { .path($0.path(percentEncoded: false)) }
        self.waiverInput = request.waiverURL.map { .path($0.path(percentEncoded: false)) }
        self.backendSelection = request.backendSelection
        self.options = request.options
        self.designRevision = request.designRevision
        self.canonicalStateDigest = request.canonicalStateDigest
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
        waiverInput: XcircuiteFlowInputReference? = nil,
        backendSelection: DRCBackendSelection = DRCBackendSelection(backendID: "magic"),
        options: DRCOptions = DRCOptions(),
        designRevision: String? = nil,
        canonicalStateDigest: String? = nil,
        engine: any DRCEngine.DRCExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutInput = layoutInput
        self.topCell = topCell
        self.layoutFormat = layoutFormat
        self.technologyInput = technologyInput
        self.waiverInput = waiverInput
        self.backendSelection = backendSelection
        self.options = options
        self.designRevision = designRevision
        self.canonicalStateDigest = canonicalStateDigest
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
            try await context.checkCancellation()
            try validate(stage: stage)
            let rawDirectory = try context.xcircuiteRunDirectory()
                .appending(path: "stages")
                .appending(path: stage.stageID)
                .appending(path: "raw")
            try FileManager.default.createDirectory(
                at: rawDirectory,
                withIntermediateDirectories: true
            )
            try await context.checkCancellation()

            let request = try await preparedRequest(
                context: context,
                workingDirectory: rawDirectory
            )
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "drc-request",
                stageID: stage.stageID,
                fileName: "drc-request.json",
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
                throw DRCError.backendFailed(
                    "DRC execution result does not retain the verified flow request."
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
                artifactID: "drc-execution-result",
                stageID: stage.stageID,
                fileName: "drc-execution-result.json",
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
            let envelopeArtifact = try await DRCSummaryEnvelopeBuilder().envelopeReference(
                summary: persistedSummary.summary,
                summaryArtifactID: "drc-summary",
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
            let artifactManifestGate = StageArtifactManifestCoverageGateBuilder().drcGate(
                manifestURL: executionResult.artifactManifestURL,
                artifacts: artifacts,
                projectRoot: try context.xcircuiteProjectRoot(),
                expectedProducer: executionResult.provenance.producer
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
                    try await context.checkCancellation()
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
    ) async throws -> DRCRequest {
        let projectRoot = try context.xcircuiteProjectRoot()
        let runDirectory = try context.xcircuiteRunDirectory()
        let layoutArtifact = try await layoutInput.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            infrastructure: context.infrastructure,
            artifactID: "drc-layout-input",
            kind: .layout,
            format: try artifactFormat(for: layoutFormat)
        )
        let technologyArtifact: ArtifactReference?
        if let technologyInput {
            technologyArtifact = try await technologyInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "drc-technology-input",
                kind: .technology,
                format: .json
            )
        } else {
            technologyArtifact = nil
        }
        let waiverArtifact: ArtifactReference?
        if let waiverInput {
            waiverArtifact = try await waiverInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "drc-waiver-input",
                kind: .constraint,
                format: .json
            )
        } else {
            waiverArtifact = nil
        }
        return DRCRequest(
            layoutURL: try layoutArtifact.locator.location.resolvedFileURL(relativeTo: projectRoot),
            topCell: topCell,
            layoutFormat: layoutFormat,
            technologyURL: try technologyArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            waiverURL: try waiverArtifact?.locator.location.resolvedFileURL(relativeTo: projectRoot),
            workingDirectory: workingDirectory,
            backendSelection: backendSelection,
            options: options,
            designRevision: designRevision,
            canonicalStateDigest: canonicalStateDigest,
            executionInputArtifacts: [layoutArtifact] + [technologyArtifact, waiverArtifact].compactMap { $0 }
        )
    }

    private func artifactFormat(for format: DRCLayoutFormat?) throws -> ArtifactFormat? {
        switch format {
        case .gds: .gdsii
        case .oasis: .oasis
        case .nativeJSON: .json
        case .cif: try ArtifactFormat(rawValue: "cif")
        case .dxf: try ArtifactFormat(rawValue: "dxf")
        case .magicLayout: try ArtifactFormat(rawValue: "magic-layout")
        case .auto, nil: nil
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stage.stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func validateExecutionProvenance(
        _ provenance: ExecutionProvenance,
        request: DRCRequest,
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
            throw DRCError.backendFailed(
                "DRC execution provenance does not match the verified request inputs and executable identity."
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
        from executionResult: DRCExecutionResult,
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
            artifactID: "drc-summary",
            kind: .report,
            format: .json,
            producer: executionResult.provenance.producer
        ))
        artifacts.append(try persistRepairHintArtifact(
            from: executionResult,
            summaryURL: summaryURL,
            context: context
        ))
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: try context.xcircuiteProjectRoot(),
            kind: .report,
            format: .text,
            producer: executionResult.provenance.producer
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
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "drc-repair-hints",
            kind: .report,
            format: .json,
            producer: executionResult.provenance.producer
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
