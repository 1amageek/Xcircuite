import DesignFlowKernel
import DRCEngine
import Foundation
import LayoutCore
import LayoutCommands
import LayoutIO
import LayoutTech
import DesignFlowKernel

public protocol LayoutCommandRunning: Sendable {
    func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult
}

extension LayoutCommandRunner: LayoutCommandRunning {}

public struct LayoutCommandFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestURL: URL
    private let drcExport: LayoutCommandDRCExportSpec?
    private let standardLayoutExports: [LayoutCommandStandardLayoutExportSpec]
    private let runner: any LayoutCommandRunning
    private let artifactBuilder: StageArtifactReferenceBuilder
    private let outputPathGuard: StageArtifactOutputPathGuard
    private let layoutDocumentSerializer: LayoutDocumentSerializer
    private let hasher: XcircuiteHasher
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        stageID: String,
        toolID: String = "layout-command",
        requestURL: URL,
        drcExport: LayoutCommandDRCExportSpec? = nil,
        standardLayoutExports: [LayoutCommandStandardLayoutExportSpec] = [],
        runner: any LayoutCommandRunning = LayoutCommandRunner()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestURL = requestURL
        self.drcExport = drcExport
        self.standardLayoutExports = standardLayoutExports
        self.runner = runner
        self.artifactBuilder = StageArtifactReferenceBuilder()
        self.outputPathGuard = StageArtifactOutputPathGuard()
        self.layoutDocumentSerializer = LayoutDocumentSerializer()
        self.hasher = XcircuiteHasher()
        self.decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
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
            let expectedPaths = LayoutCommandArtifactPaths(rawDirectory: rawDirectory)
            try validateOutputDirectories(expectedPaths, projectRoot: context.projectRoot)
            try context.packageStore.ensureDirectory(at: rawDirectory)
            try context.checkCancellation()

            let request = try loadRequest()
            let effectiveRequest = preparedRequest(request, expectedPaths: expectedPaths)
            try encoder.encode(effectiveRequest).write(to: expectedPaths.effectiveRequestURL, options: [.atomic])
            try context.checkCancellation()

            let result = try runner.run(
                request: effectiveRequest,
                baseURL: requestURL.deletingLastPathComponent()
            )
            try validateResult(result, expectedPaths: expectedPaths, projectRoot: context.projectRoot)
            try context.checkCancellation()
            let document = try loadOutputDocument(at: expectedPaths.outputDocumentURL)
            let drcLayoutURL = try drcExport.map {
                try exportDRCLayout(from: document, spec: $0, rawDirectory: rawDirectory)
            }
            let standardLayoutArtifacts = try standardLayoutExports.map {
                try exportStandardLayout(
                    document,
                    spec: $0,
                    rawDirectory: rawDirectory,
                    context: context
                )
            }
            let artifacts = try artifactReferences(
                result: result,
                expectedPaths: expectedPaths,
                drcLayoutURL: drcLayoutURL,
                standardLayoutArtifacts: standardLayoutArtifacts,
                context: context
            )
            let diagnostic = FlowDiagnostic(
                severity: .info,
                code: "LAYOUT_COMMAND_APPLIED",
                message: "Applied \(result.commandCount) layout commands."
            )

            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "layout-command",
                        status: .passed,
                        diagnostics: [diagnostic]
                    ),
                ],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = failureDiagnostic(for: error)
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "layout-command",
                        status: .failed,
                        diagnostics: [diagnostic]
                    ),
                ]
            )
        }
    }

    private func loadRequest() throws -> LayoutCommandRequest {
        let data = try Data(contentsOf: requestURL)
        return try decoder.decode(LayoutCommandRequest.self, from: data)
    }

    private func preparedRequest(
        _ request: LayoutCommandRequest,
        expectedPaths: LayoutCommandArtifactPaths
    ) -> LayoutCommandRequest {
        LayoutCommandRequest(
            schemaVersion: request.schemaVersion,
            documentID: request.documentID,
            documentName: request.documentName,
            inputDocumentPath: request.inputDocumentPath,
            outputDocumentPath: expectedPaths.outputDocumentURL.path(percentEncoded: false),
            artifactManifestPath: expectedPaths.artifactManifestURL.path(percentEncoded: false),
            resultPath: expectedPaths.resultURL.path(percentEncoded: false),
            commands: request.commands
        )
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stage.stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func validateOutputDirectories(
        _ expectedPaths: LayoutCommandArtifactPaths,
        projectRoot: URL
    ) throws {
        _ = try outputPathGuard.validateOutputDirectory(
            for: expectedPaths.effectiveRequestURL,
            projectRoot: projectRoot
        )
        _ = try outputPathGuard.validateOutputDirectory(
            for: expectedPaths.outputDocumentURL,
            projectRoot: projectRoot
        )
        _ = try outputPathGuard.validateOutputDirectory(
            for: expectedPaths.artifactManifestURL,
            projectRoot: projectRoot
        )
        _ = try outputPathGuard.validateOutputDirectory(
            for: expectedPaths.resultURL,
            projectRoot: projectRoot
        )
    }

    private func validateResult(
        _ result: LayoutCommandResult,
        expectedPaths: LayoutCommandArtifactPaths,
        projectRoot: URL
    ) throws {
        guard result.status == "passed" else {
            throw LayoutCommandFlowStageExecutorError.runnerReportedUnpassedStatus(result.status)
        }
        try validateOutputDirectories(expectedPaths, projectRoot: projectRoot)
        try requirePath(
            result.outputDocumentPath,
            equals: expectedPaths.outputDocumentURL,
            field: "outputDocumentPath"
        )
        try requirePath(
            result.artifactManifestPath,
            equals: expectedPaths.artifactManifestURL,
            field: "artifactManifestPath"
        )
        try validateOutputDocumentIntegrity(result, expectedOutputURL: expectedPaths.outputDocumentURL)
    }

    private func requirePath(_ actualPath: String, equals expectedURL: URL, field: String) throws {
        let actualURL = URL(filePath: actualPath)
        let expectedPath = canonicalPath(expectedURL)
        let actualPath = canonicalPath(actualURL)
        guard actualPath == expectedPath else {
            throw LayoutCommandFlowStageExecutorError.resultPathMismatch(
                field: field,
                expected: expectedPath,
                actual: actualPath
            )
        }
    }

    private func validateOutputDocumentIntegrity(
        _ result: LayoutCommandResult,
        expectedOutputURL: URL
    ) throws {
        let actualByteCount = try hasher.byteCount(fileAt: expectedOutputURL)
        guard actualByteCount == Int64(result.outputDocumentByteCount) else {
            throw LayoutCommandFlowStageExecutorError.outputDocumentByteCountMismatch(
                path: canonicalPath(expectedOutputURL),
                expected: Int64(result.outputDocumentByteCount),
                actual: actualByteCount
            )
        }

        let actualDigest = try hasher.sha256(fileAt: expectedOutputURL)
        guard actualDigest == result.outputDocumentSHA256 else {
            throw LayoutCommandFlowStageExecutorError.outputDocumentDigestMismatch(
                path: canonicalPath(expectedOutputURL),
                expected: result.outputDocumentSHA256,
                actual: actualDigest
            )
        }
    }

    private func exportDRCLayout(
        from document: LayoutDocument,
        spec: LayoutCommandDRCExportSpec,
        rawDirectory: URL
    ) throws -> URL {
        let cell = try topCell(named: spec.topCell, in: document)
        let viaDefinitions = try viaDefinitionMap(from: spec.viaDefinitions)
        var rectangles = try cell.shapes.map { shape in
            try drcRectangle(from: shape)
        }
        for via in cell.vias {
            let definition = try viaDefinition(for: via, in: viaDefinitions)
            rectangles.append(try drcRectangle(from: via, definition: definition))
        }
        let drcLayout = NativeDRCLayout(
            technologyID: spec.technologyID,
            topCell: spec.topCell,
            unit: spec.unit,
            rectangles: rectangles,
            rules: spec.rules
        )
        let exportURL = rawDirectory.appending(path: "drc-layout.json")
        try encoder.encode(drcLayout).write(to: exportURL, options: [.atomic])
        return exportURL
    }

    private func loadOutputDocument(at outputDocumentURL: URL) throws -> LayoutDocument {
        let documentData = try Data(contentsOf: outputDocumentURL)
        return try layoutDocumentSerializer.decodeDocument(documentData)
    }

    private func exportStandardLayout(
        _ document: LayoutDocument,
        spec: LayoutCommandStandardLayoutExportSpec,
        rawDirectory: URL,
        context: FlowExecutionContext
    ) throws -> StandardLayoutArtifact {
        try XcircuiteIdentifierValidator().validate(spec.artifactID, kind: .artifactID)
        let exportURL = rawDirectory.appending(
            path: "\(spec.artifactID).\(try standardLayoutFileExtension(for: spec.format))"
        )
        let technologyURL = try spec.technologyInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        )
        let converter = MaskDataFormatConverter(tech: try loadTechnology(from: technologyURL))
        try converter.exportDocument(document, to: exportURL, format: spec.format)
        return StandardLayoutArtifact(
            url: exportURL,
            artifactID: spec.artifactID,
            format: try xcircuiteFileFormat(for: spec.format)
        )
    }

    private func loadTechnology(from url: URL) throws -> LayoutTechDatabase {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(LayoutTechDatabase.self, from: data)
        } catch {
            throw LayoutCommandStandardLayoutExportError.technologyLoadFailed(
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
    }

    private func standardLayoutFileExtension(for format: LayoutFileFormat) throws -> String {
        switch format {
        case .gds:
            return "gds"
        case .oasis:
            return "oas"
        case .cif:
            return "cif"
        case .dxf:
            return "dxf"
        case .json, .lef, .def, .odb:
            throw LayoutCommandStandardLayoutExportError.unsupportedFormat(format.rawValue)
        }
    }

    private func xcircuiteFileFormat(for format: LayoutFileFormat) throws -> XcircuiteFileFormat {
        switch format {
        case .gds:
            return .gdsii
        case .oasis:
            return .oasis
        case .cif, .dxf:
            return .raw
        case .json, .lef, .def, .odb:
            throw LayoutCommandStandardLayoutExportError.unsupportedFormat(format.rawValue)
        }
    }

    private func topCell(named name: String, in document: LayoutDocument) throws -> LayoutCell {
        if let cell = document.cells.first(where: { $0.name == name }) {
            return cell
        }
        throw LayoutCommandDRCExportError.topCellNotFound(name)
    }

    private func viaDefinitionMap(
        from definitions: [LayoutCommandDRCViaDefinition]
    ) throws -> [String: LayoutCommandDRCViaDefinition] {
        var result: [String: LayoutCommandDRCViaDefinition] = [:]
        for definition in definitions {
            try validateViaDefinition(definition)
            guard result[definition.id] == nil else {
                throw LayoutCommandDRCExportError.duplicateViaDefinition(definition.id)
            }
            result[definition.id] = definition
        }
        return result
    }

    private func validateViaDefinition(_ definition: LayoutCommandDRCViaDefinition) throws {
        guard !definition.id.isEmpty else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "id must not be empty"
            )
        }
        guard !definition.cutLayer.isEmpty else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "cutLayer must not be empty"
            )
        }
        guard !definition.bottomLayer.isEmpty else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "bottomLayer must not be empty"
            )
        }
        guard !definition.topLayer.isEmpty else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "topLayer must not be empty"
            )
        }
        guard definition.cutWidth.isFinite, definition.cutWidth > 0 else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "cutWidth must be positive and finite"
            )
        }
        guard definition.cutHeight.isFinite, definition.cutHeight > 0 else {
            throw LayoutCommandDRCExportError.invalidViaDefinition(
                id: definition.id,
                reason: "cutHeight must be positive and finite"
            )
        }
    }

    private func viaDefinition(
        for via: LayoutVia,
        in definitions: [String: LayoutCommandDRCViaDefinition]
    ) throws -> LayoutCommandDRCViaDefinition {
        guard let definition = definitions[via.viaDefinitionID] else {
            throw LayoutCommandDRCExportError.missingViaDefinition(
                viaID: via.id,
                definitionID: via.viaDefinitionID
            )
        }
        return definition
    }

    private func drcRectangle(from shape: LayoutShape) throws -> NativeDRCRectangle {
        guard case .rect(let rect) = shape.geometry else {
            throw LayoutCommandDRCExportError.unsupportedGeometry(
                shapeID: shape.id,
                kind: geometryKindName(shape.geometry)
            )
        }
        return NativeDRCRectangle(
            id: shape.id.uuidString,
            layer: shape.layer.name,
            xMin: rect.minX,
            yMin: rect.minY,
            xMax: rect.maxX,
            yMax: rect.maxY,
            netID: shape.netID?.uuidString
        )
    }

    private func drcRectangle(
        from via: LayoutVia,
        definition: LayoutCommandDRCViaDefinition
    ) throws -> NativeDRCRectangle {
        NativeDRCRectangle(
            id: "\(via.id.uuidString).cut",
            layer: definition.cutLayer,
            xMin: via.position.x - definition.cutWidth / 2,
            yMin: via.position.y - definition.cutHeight / 2,
            xMax: via.position.x + definition.cutWidth / 2,
            yMax: via.position.y + definition.cutHeight / 2,
            netID: via.netID?.uuidString
        )
    }

    private func geometryKindName(_ geometry: LayoutGeometry) -> String {
        switch geometry {
        case .rect:
            return "rect"
        case .polygon:
            return "polygon"
        case .path:
            return "path"
        }
    }

    private func artifactReferences(
        result: LayoutCommandResult,
        expectedPaths: LayoutCommandArtifactPaths,
        drcLayoutURL: URL?,
        standardLayoutArtifacts: [StandardLayoutArtifact],
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        var artifacts = [
            try artifactBuilder.reference(
                for: expectedPaths.outputDocumentURL,
                projectRoot: context.projectRoot,
                artifactID: "layout-document",
                kind: .layout,
                format: .json,
                producedByRunID: context.runID
            ),
            try artifactBuilder.reference(
                for: expectedPaths.artifactManifestURL,
                projectRoot: context.projectRoot,
                artifactID: "layout-command-manifest",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ),
            try artifactBuilder.reference(
                for: expectedPaths.resultURL,
                projectRoot: context.projectRoot,
                artifactID: "layout-command-result",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ),
            try artifactBuilder.reference(
                for: expectedPaths.effectiveRequestURL,
                projectRoot: context.projectRoot,
                artifactID: "layout-command-effective-request",
                kind: .other,
                format: .json,
                producedByRunID: context.runID
            ),
        ]
        if let drcLayoutURL {
            artifacts.append(try artifactBuilder.reference(
                for: drcLayoutURL,
                projectRoot: context.projectRoot,
                artifactID: "drc-layout",
                kind: .layout,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        for artifact in standardLayoutArtifacts {
            artifacts.append(try artifactBuilder.reference(
                for: artifact.url,
                projectRoot: context.projectRoot,
                artifactID: artifact.artifactID,
                kind: .layout,
                format: artifact.format,
                producedByRunID: context.runID
            ))
        }
        return artifacts
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    private func failureDiagnostic(for error: Error) -> FlowDiagnostic {
        if let flowError = error as? LayoutCommandFlowStageExecutorError {
            return FlowDiagnostic(
                severity: .error,
                code: flowError.diagnosticCode,
                message: flowError.localizedDescription
            )
        }
        if let runtimeError = error as? XcircuiteRuntimeError {
            switch runtimeError {
            case .artifactOutsideProject:
                return FlowDiagnostic(
                    severity: .error,
                    code: "LAYOUT_COMMAND_ARTIFACT_OUTPUT_OUTSIDE_PROJECT",
                    message: runtimeError.localizedDescription
                )
            default:
                break
            }
        }
        return FlowDiagnostic(
            severity: .error,
            code: "LAYOUT_COMMAND_EXECUTION_ERROR",
            message: error.localizedDescription
        )
    }
}

private struct LayoutCommandArtifactPaths: Sendable, Hashable {
    var rawDirectory: URL
    var effectiveRequestURL: URL
    var outputDocumentURL: URL
    var artifactManifestURL: URL
    var resultURL: URL

    init(rawDirectory: URL) {
        self.rawDirectory = rawDirectory
        self.effectiveRequestURL = rawDirectory.appending(path: "layout-command-effective-request.json")
        self.outputDocumentURL = rawDirectory.appending(path: "layout-document.json")
        self.artifactManifestURL = rawDirectory.appending(path: "layout-command-artifact-manifest.json")
        self.resultURL = rawDirectory.appending(path: "layout-command-result.json")
    }
}

private struct StandardLayoutArtifact: Sendable, Hashable {
    var url: URL
    var artifactID: String
    var format: XcircuiteFileFormat
}

private enum LayoutCommandFlowStageExecutorError: LocalizedError, Equatable {
    case runnerReportedUnpassedStatus(String)
    case resultPathMismatch(field: String, expected: String, actual: String)
    case outputDocumentByteCountMismatch(path: String, expected: Int64, actual: Int64)
    case outputDocumentDigestMismatch(path: String, expected: String, actual: String)

    var diagnosticCode: String {
        switch self {
        case .runnerReportedUnpassedStatus:
            "LAYOUT_COMMAND_RESULT_STATUS_NOT_PASSED"
        case .resultPathMismatch:
            "LAYOUT_COMMAND_RESULT_PATH_MISMATCH"
        case .outputDocumentByteCountMismatch:
            "LAYOUT_COMMAND_OUTPUT_BYTE_COUNT_MISMATCH"
        case .outputDocumentDigestMismatch:
            "LAYOUT_COMMAND_OUTPUT_SHA256_MISMATCH"
        }
    }

    var errorDescription: String? {
        switch self {
        case .runnerReportedUnpassedStatus(let status):
            "Layout command runner returned status \(status), expected passed."
        case .resultPathMismatch(let field, let expected, let actual):
            "Layout command runner returned \(field) \(actual), expected \(expected)."
        case .outputDocumentByteCountMismatch(let path, let expected, let actual):
            "Layout command output byte count mismatch for \(path): expected \(expected), got \(actual)."
        case .outputDocumentDigestMismatch(let path, let expected, let actual):
            "Layout command output SHA-256 mismatch for \(path): expected \(expected), got \(actual)."
        }
    }
}

private enum LayoutCommandStandardLayoutExportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case technologyLoadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Layout command standard layout export does not support format \(format)."
        case .technologyLoadFailed(let path, let reason):
            "Layout command standard layout export could not load technology \(path): \(reason)."
        }
    }
}

private enum LayoutCommandDRCExportError: LocalizedError, Equatable {
    case topCellNotFound(String)
    case unsupportedGeometry(shapeID: UUID, kind: String)
    case duplicateViaDefinition(String)
    case invalidViaDefinition(id: String, reason: String)
    case missingViaDefinition(viaID: UUID, definitionID: String)

    var errorDescription: String? {
        switch self {
        case .topCellNotFound(let name):
            "Layout command DRC export could not find top cell \(name)."
        case .unsupportedGeometry(let shapeID, let kind):
            "Layout command DRC export only supports rect geometry; shape \(shapeID) is \(kind)."
        case .duplicateViaDefinition(let id):
            "Layout command DRC export has duplicate via definition \(id)."
        case .invalidViaDefinition(let id, let reason):
            "Layout command DRC export has invalid via definition \(id): \(reason)."
        case .missingViaDefinition(let viaID, let definitionID):
            "Layout command DRC export cannot expand via \(viaID) because definition \(definitionID) is missing."
        }
    }
}
