import DesignFlowKernel
import Foundation
import LayoutCore
import LayoutIO
import LayoutTech
import PhysicalDesignCore
import DesignFlowKernel

public struct ElectricalStandardLayoutImportFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let layoutFormat: LayoutFileFormat
    public let technologyFormat: LayoutFileFormat
    public let connectivityFormat: LayoutFileFormat
    public let topCellName: String?
    private let layoutInput: XcircuiteFlowInputReference
    private let technologyInput: XcircuiteFlowInputReference?
    private let technologyLayerMappingInput: XcircuiteFlowInputReference?
    private let connectivityInput: XcircuiteFlowInputReference?
    private let injectedTechnology: LayoutTechDatabase?

    public init(
        stageID: String = "electrical-signoff.standard-layout-import",
        toolID: String = "native-electrical-standard-layout-import",
        layoutInput: XcircuiteFlowInputReference,
        layoutFormat: LayoutFileFormat,
        technologyInput: XcircuiteFlowInputReference? = nil,
        technologyFormat: LayoutFileFormat = .lef,
        technologyLayerMappingInput: XcircuiteFlowInputReference? = nil,
        connectivityInput: XcircuiteFlowInputReference? = nil,
        connectivityFormat: LayoutFileFormat = .def,
        topCellName: String? = nil,
        technology: LayoutTechDatabase? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutFormat = layoutFormat
        self.technologyFormat = technologyFormat
        self.technologyLayerMappingInput = technologyLayerMappingInput
        self.connectivityFormat = connectivityFormat
        self.topCellName = topCellName
        self.layoutInput = layoutInput
        self.technologyInput = technologyInput
        self.connectivityInput = connectivityInput
        self.injectedTechnology = technology
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let layoutURL = try layoutInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let technology = try loadTechnology(context: context)
            var inputArtifacts = [try inputReference(
                layoutInput,
                artifactID: "electrical-standard-layout-input",
                kind: .layout,
                format: xcircuiteFileFormat(for: layoutFormat),
                context: context
            )]
            if let technologyInput {
                inputArtifacts.append(try inputReference(
                    technologyInput,
                    artifactID: "electrical-standard-technology-input",
                    kind: .technology,
                    format: xcircuiteFileFormat(for: technologyFormat),
                    context: context
                ))
            }
            if let technologyLayerMappingInput {
                inputArtifacts.append(try inputReference(
                    technologyLayerMappingInput,
                    artifactID: "electrical-standard-technology-layer-mapping-input",
                    kind: .technology,
                    format: .json,
                    context: context
                ))
            }
            let document = try MaskDataFormatConverter(tech: technology).importDocument(
                from: layoutURL,
                format: layoutFormat
            )
            let connectivityDocument: LayoutDocument?
            if let connectivityInput {
                let connectivityURL = try connectivityInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                connectivityDocument = try MaskDataFormatConverter(tech: technology).importDocument(
                    from: connectivityURL,
                    format: connectivityFormat
                )
                inputArtifacts.append(try inputReference(
                    connectivityInput,
                    artifactID: "electrical-standard-connectivity-input",
                    kind: .layout,
                    format: xcircuiteFileFormat(for: connectivityFormat),
                    context: context
                ))
            } else {
                connectivityDocument = nil
            }
            let snapshot = try ElectricalStandardLayoutSnapshotBuilder().build(
                document: document,
                technology: technology,
                topCellName: topCellName,
                sourceFormat: layoutFormat.rawValue,
                connectivityDocument: connectivityDocument,
                connectivitySourceFormat: connectivityInput == nil ? nil : connectivityFormat.rawValue
            )
            try context.checkCancellation()
            let relativePath = ".xcircuite/runs/\(context.runID)/electrical-signoff/physical-design-snapshot.json"
            let url = try context.packageStore.url(
                forProjectRelativePath: relativePath,
                inProjectAt: context.projectRoot
            )
            try context.packageStore.ensureDirectory(at: url.deletingLastPathComponent())
            try context.packageStore.writeJSON(snapshot, to: url, forProjectAt: context.projectRoot)
            let inputManifest = ElectricalSignoffInputArtifactManifest(
                runID: context.runID,
                stageID: stage.stageID,
                inputArtifacts: inputArtifacts
            )
            try inputManifest.validate()
            let manifestPath = ".xcircuite/runs/\(context.runID)/electrical-signoff/standard-layout-inputs.json"
            let manifestURL = try context.packageStore.url(
                forProjectRelativePath: manifestPath,
                inProjectAt: context.projectRoot
            )
            try context.packageStore.writeJSON(inputManifest, to: manifestURL, forProjectAt: context.projectRoot)
            let manifestReference = try context.packageStore.fileReference(
                forProjectRelativePath: manifestPath,
                artifactID: "electrical-standard-layout-input-manifest",
                kind: .report,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )
            let reference = try context.packageStore.fileReference(
                forProjectRelativePath: relativePath,
                artifactID: "electrical-standard-physical-snapshot",
                kind: .layout,
                format: .json,
                inProjectAt: context.projectRoot,
                producedByRunID: context.runID,
                verifiedByRunID: context.runID
            )
            let gate = FlowGateResult(
                gateID: "electrical-standard-layout-import",
                status: .passed,
                diagnostics: []
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                diagnostics: [],
                gates: [gate],
                artifacts: [manifestReference, reference]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as ElectricalStandardLayoutImportError {
            return blockedResult(stageID: stage.stageID, code: "ELECTRICAL_STANDARD_LAYOUT_IMPORT_BLOCKED", message: error.localizedDescription)
        } catch {
            return failureResult(stageID: stage.stageID, code: "ELECTRICAL_STANDARD_LAYOUT_IMPORT_FAILED", message: error.localizedDescription)
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw ElectricalStandardLayoutImportError.stageMismatch
        }
        guard !context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalStandardLayoutImportError.stageMismatch
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        guard [.gds, .oasis, .def].contains(layoutFormat) else {
            throw ElectricalStandardLayoutImportError.unsupportedLayoutFormat(layoutFormat.rawValue)
        }
        if connectivityInput != nil, connectivityFormat != .def {
            throw ElectricalStandardLayoutImportError.unsupportedLayoutFormat(connectivityFormat.rawValue)
        }
    }

    private func loadTechnology(context: FlowExecutionContext) throws -> LayoutTechDatabase {
        let technology: LayoutTechDatabase
        if let injectedTechnology {
            technology = injectedTechnology
        } else {
            guard let technologyInput else {
                throw ElectricalStandardLayoutImportError.missingTechnology
            }
            guard technologyFormat == .lef || technologyFormat == .json else {
                throw ElectricalStandardLayoutImportError.unsupportedLayoutFormat(technologyFormat.rawValue)
            }
            let url = try technologyInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            technology = try TechFormatConverter().loadTech(from: url)
        }

        guard let technologyLayerMappingInput else {
            let missingLayers = technology.layers
                .filter { $0.gdsLayer <= 0 }
                .map { $0.id.name }
            guard missingLayers.isEmpty else {
                throw ElectricalStandardLayoutImportError.missingTechnologyLayerMapping(missingLayers.sorted())
            }
            return technology
        }

        let mappingURL = try technologyLayerMappingInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        )
        let mapping: ElectricalStandardLayoutLayerMapping
        do {
            mapping = try JSONDecoder().decode(
                ElectricalStandardLayoutLayerMapping.self,
                from: Data(contentsOf: mappingURL)
            )
        } catch {
            throw ElectricalStandardLayoutImportError.invalidTechnologyLayerMapping(
                error.localizedDescription
            )
        }
        return try mapping.apply(to: technology)
    }

    private func inputReference(
        _ input: XcircuiteFlowInputReference,
        artifactID: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        switch input {
        case .artifact(let suppliedReference):
            _ = try input.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            var reference = suppliedReference
            reference.artifactID = artifactID
            reference.kind = kind
            reference.format = format
            reference.verifiedByRunID = context.runID
            return reference
        case .path, .stageArtifact, .stageRawArtifact:
            let url = try input.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let path = try projectRelativePath(for: url, projectRoot: context.projectRoot)
            return try context.packageStore.fileReference(
                forProjectRelativePath: path,
                artifactID: artifactID,
                kind: kind,
                format: format,
                inProjectAt: context.projectRoot,
                verifiedByRunID: context.runID
            )
        }
    }

    private func xcircuiteFileFormat(for format: LayoutFileFormat) -> XcircuiteFileFormat {
        switch format {
        case .json:
            return .json
        case .gds:
            return .gdsii
        case .oasis:
            return .oasis
        case .lef:
            return .lef
        case .def:
            return .def
        case .cif, .dxf, .odb:
            return .raw
        }
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let rootPath = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let artifactPath = url.standardizedFileURL.path(percentEncoded: false)
        guard artifactPath.hasPrefix("\(rootPath)/") else {
            throw ElectricalStandardLayoutImportError.artifactOutsideProject(artifactPath)
        }
        let relativePath = String(artifactPath.dropFirst(rootPath.count + 1))
        guard !relativePath.isEmpty else {
            throw ElectricalStandardLayoutImportError.artifactOutsideProject(artifactPath)
        }
        return relativePath
    }

    private func blockedResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-standard-layout-import", status: .blocked, diagnostics: [diagnostic])]
        )
    }

    private func failureResult(stageID: String, code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-standard-layout-import", status: .failed, diagnostics: [diagnostic])]
        )
    }
}
