import DesignFlowKernel
import Foundation
import PEXEngine
import XcircuitePackage

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

    public static func mock(
        stageID: String,
        layoutURL: URL,
        layoutFormat: LayoutFormat,
        sourceNetlistURL: URL,
        sourceNetlistFormat: NetlistFormat = .spice,
        topCell: String,
        corners: [PEXCorner],
        technology: TechnologyInput,
        technologyByCorner: [String: TechnologyInput] = [:],
        processProfile: PEXProcessProfileReference? = nil,
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
                technologyByCorner: technologyByCorner,
                processProfile: processProfile,
                backendSelection: .mock(),
                options: options
            ),
            engine: DefaultPEXEngine.withDefaults()
        )
    }

    public static func mock(
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
        options: PEXRunOptions = .default
    ) -> PEXFlowStageExecutor {
        PEXFlowStageExecutor(
            stageID: stageID,
            toolID: "mock-pex",
            layoutInput: layoutInput,
            layoutFormat: layoutFormat,
            sourceNetlistInput: sourceNetlistInput,
            sourceNetlistFormat: sourceNetlistFormat,
            topCell: topCell,
            corners: corners,
            technology: technology,
            technologyByCorner: technologyByCorner,
            processProfile: processProfile,
            backendSelection: .mock(),
            options: options,
            engine: DefaultPEXEngine.withDefaults()
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
            let runResult = try await engine.run(
                request,
                cancellationCheck: FlowExecutionCancellationProbe.make(context: context)
            )
            try context.checkCancellation()
            let artifactCompleteness = try artifactCompletenessReport(
                from: runResult,
                projectRoot: context.projectRoot
            )
            let persistedSummary = try persistSummaryArtifact(
                from: runResult,
                projectRoot: context.projectRoot
            )
            try context.checkCancellation()
            var artifacts = try artifactReferences(
                from: runResult,
                summaryURL: persistedSummary.url,
                context: context
            )
            let pexDiagnostics = flowDiagnostics(from: runResult, artifactCompleteness: artifactCompleteness)
            let overallGateStatus = gateStatus(
                runStatus: runResult.status,
                artifactCompletenessStatus: artifactCompleteness.status
            )
            let preEnvelopeArtifactIntegrityGate = StageArtifactIntegrityGateBuilder().gate(
                for: artifacts,
                projectRoot: context.projectRoot
            )
            let preEnvelopeFlowArtifactGate = StageArtifactManifestCoverageGateBuilder().pexGate(
                manifestURL: runResult.manifestURL,
                artifacts: artifacts,
                projectRoot: context.projectRoot
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
            let envelopeArtifact = try PEXSummaryEnvelopeBuilder().envelopeReference(
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
                projectRoot: context.projectRoot
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

    private func preparedRequest(
        context: FlowExecutionContext,
        workingDirectory: URL
    ) throws -> PEXRunRequest {
        PEXRunRequest(
            layoutURL: try layoutInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            layoutFormat: layoutFormat,
            sourceNetlistURL: try sourceNetlistInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            sourceNetlistFormat: sourceNetlistFormat,
            topCell: topCell,
            corners: corners,
            technology: try technology.makeTechnologyInput(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ),
            technologyByCorner: try resolvedTechnologyByCorner(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
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
        let validator = XcircuiteIdentifierValidator()
        try validator.validate(stage.stageID, kind: .stageID)
        try validator.validate(toolID, kind: .toolID)
    }

    private func artifactReferences(
        from result: PEXRunResult,
        summaryURL: URL,
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
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: context.projectRoot,
                artifactID: "pex-summary",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ),
        ]

        for artifact in result.artifacts.artifacts where artifact.status == .available {
            let url = pexRunDirectory.appending(path: artifact.relativePath.value)
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
    ) throws -> XcircuiteFileReference {
        do {
            return try artifactBuilder.reference(
                for: url,
                projectRoot: context.projectRoot,
                artifactID: artifact.id,
                kind: fileKind(for: artifact.kind),
                format: fileFormat(for: artifact, url: url),
                producedByRunID: context.runID
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
    ) throws -> XcircuiteFileReference {
        try XcircuiteIdentifierValidator().validate(artifact.id, kind: .artifactID)
        let relativePath = try lexicalProjectRelativePath(
            for: url,
            projectRoot: context.projectRoot
        )
        return XcircuiteFileReference(
            artifactID: artifact.id,
            path: relativePath,
            kind: fileKind(for: artifact.kind),
            format: fileFormat(for: artifact, url: url),
            sha256: artifact.sha256,
            byteCount: artifact.byteCount.map(Int64.init),
            producedByRunID: context.runID
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
        if let path = issue.path {
            parts.append("path=\(path.value)")
        }
        return parts.joined(separator: " ")
    }

    private func fileKind(for kind: PEXArtifactKind) -> XcircuiteFileKind {
        switch kind {
        case .layoutInput:
            .layout
        case .netlistInput:
            .netlist
        case .technologyInput, .processProfileDeckInput:
            .technology
        case .request, .log, .report, .sourceConnectivityReport:
            .report
        case .rawOutput, .spefRoundTrip, .spiceBackannotation, .parasiticIR:
            .parasitic
        }
    }

    private func fileFormat(for artifact: PEXArtifactRecord, url: URL) -> XcircuiteFileFormat {
        switch artifact.kind {
        case .rawOutput, .spefRoundTrip:
            .spef
        case .parasiticIR, .request, .technologyInput, .sourceConnectivityReport:
            .json
        case .spiceBackannotation:
            .spice
        case .log, .report, .processProfileDeckInput:
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
