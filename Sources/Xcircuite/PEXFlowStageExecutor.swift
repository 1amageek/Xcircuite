import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PEXEngine

public struct PEXFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let layoutInput: XcircuiteFlowInputReference
    private let layoutFormat: LayoutFormat
    private let sourceNetlistInput: XcircuiteFlowInputReference
    private let sourceNetlistFormat: NetlistFormat
    private let topCell: String
    private let corners: [PEXCorner]
    private let technology: XcircuitePEXTechnologySpec
    private let technologyByCorner: [String: XcircuitePEXTechnologySpec]
    private let processProfile: PEXProcessProfileReference?
    private let backendSelection: PEXBackendSelection
    private let options: PEXRunOptions
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
        self.layoutInput = .path(request.layoutURL.path(percentEncoded: false))
        self.layoutFormat = request.layoutFormat
        self.sourceNetlistInput = .path(request.sourceNetlistURL.path(percentEncoded: false))
        self.sourceNetlistFormat = request.sourceNetlistFormat
        self.topCell = request.topCell
        self.corners = request.corners
        self.technology = Self.technologySpec(from: request.technology)
        self.technologyByCorner = request.technologyByCorner.mapValues { Self.technologySpec(from: $0) }
        self.processProfile = request.processProfile
        self.backendSelection = request.backendSelection
        self.options = request.options
        self.engine = engine
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func production(
        stageID: String,
        layoutInput: XcircuiteFlowInputReference,
        layoutFormat: LayoutFormat,
        sourceNetlistInput: XcircuiteFlowInputReference,
        sourceNetlistFormat: NetlistFormat = .spice,
        topCell: String,
        corners: [PEXCorner],
        technology: XcircuitePEXTechnologySpec,
        technologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
        processProfile: PEXProcessProfileReference? = nil,
        backendSelection: PEXBackendSelection = PEXBackendSelection(backendID: "magic"),
        options: PEXRunOptions = .default
    ) -> PEXFlowStageExecutor {
        PEXFlowStageExecutor(
            stageID: stageID,
            toolID: SignoffToolDescriptors.pexToolID(
                backendID: backendSelection.backendID
            ),
            layoutInput: layoutInput,
            layoutFormat: layoutFormat,
            sourceNetlistInput: sourceNetlistInput,
            sourceNetlistFormat: sourceNetlistFormat,
            topCell: topCell,
            corners: corners,
            technology: technology,
            technologyByCorner: technologyByCorner,
            processProfile: processProfile,
            backendSelection: backendSelection,
            options: options,
            engine: DefaultPEXEngine.withDefaults()
        )
    }

    public init(
        stageID: String,
        toolID: String,
        layoutInput: XcircuiteFlowInputReference,
        layoutFormat: LayoutFormat,
        sourceNetlistInput: XcircuiteFlowInputReference,
        sourceNetlistFormat: NetlistFormat = .spice,
        topCell: String,
        corners: [PEXCorner],
        technology: XcircuitePEXTechnologySpec,
        technologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
        processProfile: PEXProcessProfileReference? = nil,
        backendSelection: PEXBackendSelection,
        options: PEXRunOptions = .default,
        engine: any PEXExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutInput = layoutInput
        self.layoutFormat = layoutFormat
        self.sourceNetlistInput = sourceNetlistInput
        self.sourceNetlistFormat = sourceNetlistFormat
        self.topCell = topCell
        self.corners = corners
        self.technology = technology
        self.technologyByCorner = technologyByCorner
        self.processProfile = processProfile
        self.backendSelection = backendSelection
        self.options = options
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
            try await context.checkCancellation()
            let runResult = try await engine.run(
                request,
                cancellationCheck: FlowExecutionCancellationProbe.make(context: context)
            )
            try await context.checkCancellation()
            let artifactCompleteness = try artifactCompletenessReport(
                from: runResult,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let pexDiagnostics = flowDiagnostics(
                from: runResult,
                artifactCompleteness: artifactCompleteness
            )
            if let blockedKind = blockedErrorKind(from: runResult) {
                let artifacts = try artifactReferences(
                    from: runResult,
                    summaryURL: nil,
                    context: context
                )
                let flowArtifactGate = StageArtifactManifestCoverageGateBuilder().pexGate(
                    manifestURL: runResult.manifestURL,
                    artifacts: artifacts,
                    projectRoot: try context.xcircuiteProjectRoot()
                )
                let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                    for: artifacts,
                    projectRoot: try context.xcircuiteProjectRoot()
                )
                let blockedDiagnostic = FlowDiagnostic(
                    severity: .error,
                    code: diagnosticCode(for: blockedKind),
                    message: blockedMessage(for: runResult, kind: blockedKind)
                )
                let diagnostics = [blockedDiagnostic]
                    + pexDiagnostics
                    + flowArtifactGate.diagnostics
                    + artifactIntegrityGate.diagnostics
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .blocked,
                    diagnostics: diagnostics,
                    gates: [
                        FlowGateResult(
                            gateID: "pex",
                            status: .blocked,
                            diagnostics: [blockedDiagnostic] + pexDiagnostics
                        ),
                        FlowGateResult(
                            gateID: "pex-artifacts",
                            status: gateStatus(from: artifactCompleteness.status),
                            diagnostics: artifactDiagnostics(from: artifactCompleteness)
                        ),
                        flowArtifactGate,
                        artifactIntegrityGate,
                    ],
                    artifacts: artifacts
                )
            }
            let persistedSummary = try persistSummaryArtifact(
                from: runResult,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            try await context.checkCancellation()
            var artifacts = try artifactReferences(
                from: runResult,
                summaryURL: persistedSummary.url,
                context: context
            )
            let overallGateStatus = gateStatus(
                runStatus: runResult.status,
                artifactCompletenessStatus: artifactCompleteness.status
            )
            let preEnvelopeArtifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let preEnvelopeFlowArtifactGate = StageArtifactManifestCoverageGateBuilder().pexGate(
                manifestURL: runResult.manifestURL,
                artifacts: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            if preEnvelopeArtifactIntegrityGate.status != .passed {
                let diagnostics = pexDiagnostics
                    + preEnvelopeFlowArtifactGate.diagnostics
                    + preEnvelopeArtifactIntegrityGate.diagnostics
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .failed,
                    diagnostics: diagnostics,
                    gates: [
                        FlowGateResult(
                            gateID: "pex",
                            status: overallGateStatus,
                            diagnostics: pexDiagnostics
                        ),
                        FlowGateResult(
                            gateID: "pex-artifacts",
                            status: gateStatus(from: artifactCompleteness.status),
                            diagnostics: artifactDiagnostics(from: artifactCompleteness)
                        ),
                        preEnvelopeFlowArtifactGate,
                        preEnvelopeArtifactIntegrityGate,
                    ],
                    artifacts: artifacts
                )
            }
            let envelopeArtifact = try await PEXSummaryEnvelopeBuilder().envelopeReference(
                summary: persistedSummary.summary,
                summaryArtifactID: "pex-summary",
                stageArtifacts: artifacts,
                gateStatus: overallGateStatus,
                diagnostics: pexDiagnostics,
                stageID: stage.stageID,
                toolID: toolID,
                context: context
            )
            artifacts.append(envelopeArtifact)
            let artifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: try context.xcircuiteProjectRoot()
            )
            let flowArtifactGate = preEnvelopeFlowArtifactGate
            let diagnostics = pexDiagnostics
                + flowArtifactGate.diagnostics
                + artifactIntegrityGate.diagnostics
            let stageStatus: FlowStageStatus = overallGateStatus == .passed
                && flowArtifactGate.status == .passed
                && artifactIntegrityGate.status == .passed
                ? .succeeded
                : .failed

            return FlowStageResult(
                stageID: stage.stageID,
                status: stageStatus,
                diagnostics: diagnostics,
                gates: [
                    FlowGateResult(
                        gateID: "pex",
                        status: overallGateStatus,
                        diagnostics: pexDiagnostics
                    ),
                    FlowGateResult(
                        gateID: "pex-artifacts",
                        status: gateStatus(from: artifactCompleteness.status),
                        diagnostics: artifactDiagnostics(from: artifactCompleteness)
                    ),
                    flowArtifactGate,
                    artifactIntegrityGate,
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as PEXError {
            return pexErrorResult(stageID: stage.stageID, error: error)
        } catch let error as XcircuiteRuntimeError {
            switch error {
            case .artifactOutsideProject:
                return failureResult(
                    stageID: stage.stageID,
                    code: "PEX_ARTIFACT_OUTPUT_OUTSIDE_PROJECT",
                    message: error.localizedDescription
                )
            default:
                return failureResult(
                    stageID: stage.stageID,
                    code: "PEX_EXECUTION_ERROR",
                    message: error.localizedDescription
                )
            }
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "PEX_EXECUTION_ERROR",
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
                    gateID: "pex",
                    status: .failed,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func pexErrorResult(
        stageID: String,
        error: PEXError
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(
            severity: .error,
            code: diagnosticCode(for: error.kind),
            message: error.description
        )
        let status: FlowStageStatus = isBlocked(error.kind) ? .blocked : .failed
        let gateStatus: FlowGateStatus = isBlocked(error.kind) ? .blocked : .failed
        return FlowStageResult(
            stageID: stageID,
            status: status,
            diagnostics: [diagnostic],
            gates: [
                FlowGateResult(
                    gateID: "pex",
                    status: gateStatus,
                    diagnostics: [diagnostic]
                ),
            ]
        )
    }

    private func blockedErrorKind(from result: PEXRunResult) -> PEXErrorKind? {
        if let failureKind = result.artifactManifest.corners
            .compactMap({ $0.failure?.failureKind })
            .first(where: isBlocked)
        {
            return failureKind
        }
        if result.extractorRun?.readiness.status == .blocked {
            return .adapterUnavailable
        }
        return nil
    }

    private func blockedMessage(
        for result: PEXRunResult,
        kind: PEXErrorKind
    ) -> String {
        if let failure = result.artifactManifest.corners
            .compactMap(\.failure)
            .first(where: { $0.failureKind == kind })
        {
            return failure.message
        }
        if let readiness = result.extractorRun?.readiness {
            return readiness.reason
        }
        return "PEX backend is unavailable."
    }

    private func isBlocked(_ kind: PEXErrorKind) -> Bool {
        switch kind {
        case .adapterUnavailable, .technologyResolutionFailed:
            true
        case .invalidInput, .backendExecutionFailed, .cancelled, .parseFailed,
             .irValidationFailed, .persistenceFailed, .internalInvariantViolation:
            false
        }
    }

    private func diagnosticCode(for kind: PEXErrorKind) -> String {
        switch kind {
        case .adapterUnavailable:
            "PEX_BACKEND_UNAVAILABLE"
        case .technologyResolutionFailed:
            "PEX_TECHNOLOGY_BLOCKED"
        case .invalidInput:
            "PEX_INPUT_INVALID"
        case .backendExecutionFailed:
            "PEX_BACKEND_EXECUTION_FAILED"
        case .cancelled:
            "PEX_EXECUTION_CANCELLED"
        case .parseFailed:
            "PEX_PARSE_FAILED"
        case .irValidationFailed:
            "PEX_IR_VALIDATION_FAILED"
        case .persistenceFailed:
            "PEX_PERSISTENCE_FAILED"
        case .internalInvariantViolation:
            "PEX_INTERNAL_INVARIANT_FAILED"
        }
    }

    private func preparedRequest(
        context: FlowExecutionContext,
        workingDirectory: URL
    ) throws -> PEXRunRequest {
        PEXRunRequest(
            layoutURL: try layoutInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            ),
            layoutFormat: layoutFormat,
            sourceNetlistURL: try sourceNetlistInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            ),
            sourceNetlistFormat: sourceNetlistFormat,
            topCell: topCell,
            corners: corners,
            technology: try technology.makeTechnologyInput(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            ),
            technologyByCorner: try resolvedTechnologyByCorner(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            ),
            processProfile: processProfile,
            backendSelection: backendSelection,
            options: options,
            workingDirectory: workingDirectory
        )
    }

    private static func technologySpec(from input: TechnologyInput) -> XcircuitePEXTechnologySpec {
        switch input {
        case .jsonFile(let url):
            .jsonFile(path: url.path(percentEncoded: false))
        case .inline(let technology):
            .inline(technology)
        }
    }

    private func resolvedTechnologyByCorner(
        projectRoot: URL,
        runDirectory: URL
    ) throws -> [String: TechnologyInput] {
        var resolved: [String: TechnologyInput] = [:]
        for cornerID in technologyByCorner.keys.sorted() {
            guard let technology = technologyByCorner[cornerID] else {
                continue
            }
            resolved[cornerID] = try technology.makeTechnologyInput(
                projectRoot: projectRoot,
                runDirectory: runDirectory
            )
        }
        return resolved
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        let validator = FlowIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from result: PEXRunResult,
        summaryURL: URL?,
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        let pexRunDirectory = result.manifestURL.deletingLastPathComponent()
        var artifacts = [
            try artifactBuilder.reference(
                for: result.manifestURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                kind: .report,
                format: .json
            ),
        ]
        if let summaryURL {
            artifacts.append(try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: "pex-summary",
                kind: .report,
                format: .json
            ))
        }

        for artifact in result.artifactManifest.artifacts where artifact.availability == .available {
            let url = pexRunDirectory.appending(path: artifact.locator.location.value)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            artifacts.append(try artifactReference(
                for: artifact,
                url: url,
                context: context
            ))
        }
        return artifacts
    }

    private func artifactReference(
        for artifact: PEXArtifactRecord,
        url: URL,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        do {
            return try artifactBuilder.reference(
                for: url,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: artifact.id.rawValue,
                kind: artifact.locator.kind,
                format: artifact.locator.format
            )
        } catch let error as XcircuiteRuntimeError {
            switch error {
            case .artifactOutsideProject:
                return try manifestDeclaredArtifactReference(
                    for: artifact,
                    url: url,
                    context: context
                )
            default:
                throw error
            }
        }
    }

    private func manifestDeclaredArtifactReference(
        for artifact: PEXArtifactRecord,
        url: URL,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        guard let declaredReference = artifact.reference else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "Available PEX artifact \(artifact.id.rawValue) has no canonical reference."
            )
        }
        let relativePath = try lexicalProjectRelativePath(
            for: url,
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: relativePath),
            role: .output,
            kind: artifact.locator.kind,
            format: artifact.locator.format
        )
        return ArtifactReference(
            id: artifact.id,
            locator: locator,
            digest: declaredReference.digest,
            byteCount: declaredReference.byteCount
        )
    }

    private func lexicalProjectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let rootPath = normalizedDirectoryPath(
            projectRoot.standardizedFileURL.path(percentEncoded: false)
        )
        let artifactPath = normalizedDirectoryPath(
            url.standardizedFileURL.path(percentEncoded: false)
        )
        guard artifactPath != rootPath, artifactPath.hasPrefix(rootPath + "/") else {
            throw XcircuiteRuntimeError.artifactOutsideProject(
                path: artifactPath,
                projectRoot: rootPath
            )
        }
        return String(artifactPath.dropFirst(rootPath.count + 1))
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private func persistSummaryArtifact(
        from result: PEXRunResult,
        projectRoot: URL
    ) throws -> (summary: PEXRunSummaryReport, url: URL) {
        let outputDirectory = try StageArtifactOutputPathGuard()
            .validateOutputDirectory(for: result.manifestURL, projectRoot: projectRoot)
        let summary = try PEXRunSummaryBuilder().build(
            manifestURL: result.manifestURL,
            topNets: 10
        )
        let summaryURL = outputDirectory
            .appending(path: "pex-summary.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        try data.write(to: summaryURL, options: .atomic)
        return (summary, summaryURL)
    }

    private func artifactCompletenessReport(
        from result: PEXRunResult,
        projectRoot: URL
    ) throws -> PEXArtifactCompletenessReport {
        _ = try StageArtifactOutputPathGuard()
            .validateOutputDirectory(for: result.manifestURL, projectRoot: projectRoot)
        return try PEXArtifactResolver(manifestURL: result.manifestURL).completenessReport()
    }

    private func gateStatus(
        runStatus: PEXRunStatus,
        artifactCompletenessStatus: PEXArtifactCompletenessStatus
    ) -> FlowGateStatus {
        let artifactStatus = gateStatus(from: artifactCompletenessStatus)
        guard artifactStatus == .passed else {
            return artifactStatus
        }
        return gateStatus(from: runStatus)
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

    private func gateStatus(from status: PEXArtifactCompletenessStatus) -> FlowGateStatus {
        switch status {
        case .complete:
            .passed
        case .incomplete:
            .incomplete
        case .invalid:
            .failed
        }
    }

    private func flowDiagnostics(
        from result: PEXRunResult,
        artifactCompleteness: PEXArtifactCompletenessReport
    ) -> [FlowDiagnostic] {
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
        diagnostics.append(contentsOf: artifactDiagnostics(from: artifactCompleteness))
        return diagnostics
    }

    private func artifactDiagnostics(from report: PEXArtifactCompletenessReport) -> [FlowDiagnostic] {
        report.issues.map { issue in
            FlowDiagnostic(
                severity: flowSeverity(for: issue, reportStatus: report.status),
                code: "PEX_ARTIFACT_\(issue.kind.rawValue)",
                message: artifactDiagnosticMessage(for: issue)
            )
        }
    }

    private func flowSeverity(
        for issue: PEXArtifactCompletenessIssue,
        reportStatus: PEXArtifactCompletenessStatus
    ) -> FlowDiagnosticSeverity {
        switch reportStatus {
        case .complete:
            .info
        case .incomplete:
            issue.kind == .failedCorner ? .error : .warning
        case .invalid:
            .error
        }
    }

    private func artifactDiagnosticMessage(for issue: PEXArtifactCompletenessIssue) -> String {
        var parts = [issue.message]
        if let artifactID = issue.artifactID {
            parts.append("artifact=\(artifactID)")
        }
        if let cornerID = issue.cornerID {
            parts.append("corner=\(cornerID.value)")
        }
        if let location = issue.location {
            parts.append("path=\(location.value)")
        }
        return parts.joined(separator: " ")
    }
}
