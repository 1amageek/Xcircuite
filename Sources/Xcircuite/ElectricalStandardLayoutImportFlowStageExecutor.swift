import DesignFlowKernel
import Foundation
import LayoutCore
import LayoutIO
import LayoutTech
import PhysicalDesignCore
import XcircuitePackage

public struct ElectricalStandardLayoutImportFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    public let layoutFormat: LayoutFileFormat
    public let technologyFormat: LayoutFileFormat
    public let connectivityFormat: LayoutFileFormat
    public let topCellName: String?
    private let layoutInput: XcircuiteFlowInputReference
    private let technologyInput: XcircuiteFlowInputReference?
    private let connectivityInput: XcircuiteFlowInputReference?
    private let injectedTechnology: LayoutTechDatabase?

    public init(
        stageID: String = "electrical-signoff.standard-layout-import",
        toolID: String = "native-electrical-standard-layout-import",
        layoutInput: XcircuiteFlowInputReference,
        layoutFormat: LayoutFileFormat,
        technologyInput: XcircuiteFlowInputReference? = nil,
        technologyFormat: LayoutFileFormat = .lef,
        connectivityInput: XcircuiteFlowInputReference? = nil,
        connectivityFormat: LayoutFileFormat = .def,
        topCellName: String? = nil,
        technology: LayoutTechDatabase? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.layoutFormat = layoutFormat
        self.technologyFormat = technologyFormat
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
                artifacts: [reference]
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
        if let injectedTechnology {
            return injectedTechnology
        }
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
        return try TechFormatConverter().loadTech(from: url)
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
