import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanExecutor {
    func executeNetlistParameterEdit(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        projectRoot: URL,
        context: inout CandidatePlanExecutionContext
    ) async throws -> XcircuiteCandidatePlanExecutionStepResult {
        let executionDirectory = try executionDirectoryURL(plan: plan, step: step, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: executionDirectory)
        guard let sourceNetlistPath = stringHint("netlistPath", step: step)
            ?? stringHint("inputNetlistPath", step: step)
            ?? context.latestNetlistPath else {
            throw XcircuiteCandidatePlanExecutionError.missingNetlistInput(stepID: step.stepID)
        }
        let sourceNetlistURL = try packageStore.url(
            forProjectRelativePath: sourceNetlistPath,
            inProjectAt: projectRoot
        )
        let source = try String(contentsOf: sourceNetlistURL, encoding: .utf8)
        let parsed = try await SPICEIO.parse(
            source,
            fileName: sourceNetlistURL.lastPathComponent
        ).get()
        let assignments = try parameterAssignments(step: step)
        let edited = try applyParameterAssignments(
            assignments,
            to: parsed,
            stepID: step.stepID
        )

        let outputNetlistURL = executionDirectory.appending(path: "netlist.spice")
        let outputNetlistPath = try projectRelativePath(for: outputNetlistURL, projectRoot: projectRoot)
        let serialized = SPICESerializer().serialize(edited.netlist, options: .default)
        try packageStore.writeText(serialized, to: outputNetlistURL)
        context.latestNetlistPath = outputNetlistPath
        let outputNetlistRef = try artifactBuilder.reference(
            for: outputNetlistURL,
            projectRoot: projectRoot,
            artifactID: "candidate-step-\(step.order)-edited-netlist",
            kind: .netlist,
            format: .spice,
            producedByRunID: plan.runID
        )

        let reportURL = executionDirectory.appending(path: "netlist-parameter-edit-report.json")
        let report = XcircuiteNetlistParameterEditReport(
            runID: plan.runID,
            problemID: plan.problemID,
            planID: plan.planID,
            stepID: step.stepID,
            sourceParameterCandidateID: stringHint("sourceParameterCandidateID", step: step),
            sourceNetlistPath: sourceNetlistPath,
            outputNetlistPath: outputNetlistPath,
            outputNetlistArtifactID: outputNetlistRef.artifactID ?? "candidate-step-\(step.order)-edited-netlist",
            edits: edited.edits
        )
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)
        let reportRef = try artifactBuilder.reference(
            for: reportURL,
            projectRoot: projectRoot,
            artifactID: "candidate-step-\(step.order)-netlist-parameter-edit-report",
            kind: .report,
            format: .json,
            producedByRunID: plan.runID
        )
        let artifacts = [outputNetlistRef, reportRef]
        for artifact in artifacts {
            try packageStore.upsertRunArtifact(artifact, runID: plan.runID, inProjectAt: projectRoot)
        }
        let artifactReferences = try foundationArtifactReferences(
            artifacts,
            field: "candidate-step-netlist-parameter-edit"
        )
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "executed",
            artifactReferences: artifactReferences,
            nextActions: signoffNextActions(for: step)
        )
    }

    func layoutCommandRequest(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        executionDirectory: URL,
        projectRoot: URL,
        context: CandidatePlanExecutionContext
    ) throws -> LayoutCommandRequest {
        let inputDocumentPath = stringHint("inputDocumentPath", step: step)
            ?? stringHint("layoutDocumentPath", step: step)
            ?? context.latestLayoutDocumentPath
        var commands: [LayoutCommand] = []
        if shouldBootstrapCell(for: step, inputDocumentPath: inputDocumentPath) {
            commands.append(.createCell(CreateCellCommand(
                cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
                name: stringHint("cellName", step: step) ?? "top",
                makeTop: true
            )))
        }

        let commandStep = try stepWithInferredCellID(
            step,
            inputDocumentPath: inputDocumentPath,
            projectRoot: projectRoot
        )

        switch commandStep.operationID {
        case "layout.add-rect":
            commands.append(try layoutAddRectCommand(step: commandStep))
        case "layout.create-cell":
            commands.append(try layoutCreateCellCommand(step: commandStep))
        case "layout.add-net":
            commands.append(try layoutAddNetCommand(step: commandStep))
        case "layout.translate-shape":
            commands.append(try layoutTranslateShapeCommand(step: commandStep))
        case "layout.resize-shape":
            commands.append(try layoutResizeShapeCommand(step: commandStep))
        case "layout.delete-shape":
            commands.append(try layoutDeleteShapeCommand(step: commandStep))
        case "layout.split-shape":
            commands.append(try layoutSplitShapeCommand(
                step: commandStep,
                inputDocumentPath: inputDocumentPath,
                projectRoot: projectRoot
            ))
        case "layout.add-label":
            commands.append(try layoutAddLabelCommand(step: commandStep))
        case "layout.add-via":
            commands.append(try layoutAddViaCommand(step: commandStep))
        default:
            throw XcircuiteCandidatePlanExecutionError.unsupportedOperation(
                domainID: commandStep.domainID,
                operationID: commandStep.operationID
            )
        }

        let outputPath = try projectRelativePath(
            for: executionDirectory.appending(path: "layout-document.json"),
            projectRoot: projectRoot
        )
        let manifestPath = try projectRelativePath(
            for: executionDirectory.appending(path: "layout-command-artifact-manifest.json"),
            projectRoot: projectRoot
        )
        let resultPath = try projectRelativePath(
            for: executionDirectory.appending(path: "layout-command-result.json"),
            projectRoot: projectRoot
        )
        return LayoutCommandRequest(
            documentID: try uuidHint("documentID", step: step, fallbackIndex: 0),
            documentName: stringHint("documentName", step: step) ?? "\(plan.planID)-layout",
            inputDocumentPath: inputDocumentPath,
            outputDocumentPath: outputPath,
            artifactManifestPath: manifestPath,
            resultPath: resultPath,
            commands: commands
        )
    }

    func stepWithInferredCellID(
        _ step: XcircuiteCandidatePlanStep,
        inputDocumentPath: String?,
        projectRoot: URL
    ) throws -> XcircuiteCandidatePlanStep {
        guard stringHint("cellID", step: step) == nil else {
            return step
        }
        guard let inputDocumentPath else {
            return step
        }
        guard requiresExistingCell(step.operationID) else {
            return step
        }
        let documentURL = try packageStore.url(
            forProjectRelativePath: inputDocumentPath,
            inProjectAt: projectRoot
        )
        let documentData = try Data(contentsOf: documentURL)
        let document = try LayoutDocumentSerializer().decodeDocument(documentData)
        guard let cellID = document.topCellID ?? document.cells.first?.id else {
            return step
        }
        var inferred = step
        inferred.parameterHints["cellID"] = .string(cellID.uuidString)
        return inferred
    }

    func requiresExistingCell(_ operationID: String) -> Bool {
        switch operationID {
        case "layout.add-net",
             "layout.add-rect",
             "layout.translate-shape",
             "layout.resize-shape",
             "layout.delete-shape",
             "layout.split-shape",
             "layout.add-label",
             "layout.add-via":
            return true
        default:
            return false
        }
    }

    func shouldBootstrapCell(
        for step: XcircuiteCandidatePlanStep,
        inputDocumentPath: String?
    ) -> Bool {
        guard inputDocumentPath == nil else {
            return false
        }
        switch step.operationID {
        case "layout.add-net", "layout.add-rect", "layout.add-label", "layout.add-via":
            return boolHint("bootstrapCell", step: step) ?? true
        default:
            return false
        }
    }

    func layoutCreateCellCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .createCell(CreateCellCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            name: stringHint("cellName", step: step) ?? stringHint("name", step: step) ?? "cell_\(step.order)",
            makeTop: boolHint("makeTop", step: step) ?? true
        ))
    }

    func layoutAddNetCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .addNet(AddNetCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            netID: try uuidHint("netID", step: step, fallbackIndex: step.order * 10 + 2),
            name: stringHint("netName", step: step) ?? stringHint("name", step: step) ?? "net_\(step.order)",
            currentSpec: try optionalNumberHint("currentSpec", step: step)
        ))
    }

    func layoutAddRectCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .addRect(AddRectCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            shapeID: try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3),
            layer: layerHint(step: step),
            origin: LayoutPoint(
                x: try numberHint("originX", step: step, defaultValue: 0),
                y: try numberHint("originY", step: step, defaultValue: 0)
            ),
            size: LayoutSize(
                width: try numberHint("width", step: step, defaultValue: 1),
                height: try numberHint("height", step: step, defaultValue: 1)
            ),
            netID: try optionalUUIDHint("netID", step: step),
            properties: layoutProperties(step: step)
        ))
    }

    func layoutTranslateShapeCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .translateShape(TranslateShapeCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            shapeID: try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3),
            delta: LayoutPoint(
                x: try numberHint("deltaX", step: step, defaultValue: 0),
                y: try numberHint("deltaY", step: step, defaultValue: 0)
            )
        ))
    }

    func layoutResizeShapeCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .resizeShape(ResizeShapeCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            shapeID: try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3),
            deltaMinX: try numberHint("deltaMinX", step: step, defaultValue: 0),
            deltaMinY: try numberHint("deltaMinY", step: step, defaultValue: 0),
            deltaMaxX: try numberHint("deltaMaxX", step: step, defaultValue: 0),
            deltaMaxY: try numberHint("deltaMaxY", step: step, defaultValue: 0)
        ))
    }

    func layoutDeleteShapeCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .deleteShape(DeleteShapeCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            shapeID: try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3)
        ))
    }

    func layoutSplitShapeCommand(
        step: XcircuiteCandidatePlanStep,
        inputDocumentPath: String?,
        projectRoot: URL
    ) throws -> LayoutCommand {
        let axis = try splitAxisHint(step: step)
        let coordinate = try optionalNumberHint("coordinate", step: step)
            ?? optionalNumberHint("splitCoordinate", step: step)
            ?? inferredSplitCoordinate(
                step: step,
                axis: axis,
                inputDocumentPath: inputDocumentPath,
                projectRoot: projectRoot
            )
        return .splitShape(SplitShapeCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            shapeID: try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3),
            firstShapeID: try uuidHint("firstShapeID", step: step, fallbackIndex: step.order * 10 + 6),
            secondShapeID: try uuidHint("secondShapeID", step: step, fallbackIndex: step.order * 10 + 7),
            axis: axis,
            coordinate: coordinate
        ))
    }

    func splitAxisHint(step: XcircuiteCandidatePlanStep) throws -> SplitShapeAxis {
        let raw = stringHint("axis", step: step)
            ?? stringHint("splitAxis", step: step)
            ?? "vertical"
        guard let axis = SplitShapeAxis(rawValue: raw.lowercased()) else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "axis",
                expected: "vertical or horizontal"
            )
        }
        return axis
    }

    func inferredSplitCoordinate(
        step: XcircuiteCandidatePlanStep,
        axis: SplitShapeAxis,
        inputDocumentPath: String?,
        projectRoot: URL
    ) throws -> Double {
        guard let inputDocumentPath else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "coordinate",
                expected: "finite number or input LayoutDocument with target rectangle"
            )
        }
        let cellID = try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1)
        let shapeID = try uuidHint("shapeID", step: step, fallbackIndex: step.order * 10 + 3)
        let documentURL = try packageStore.url(
            forProjectRelativePath: inputDocumentPath,
            inProjectAt: projectRoot
        )
        let documentData = try Data(contentsOf: documentURL)
        let document = try LayoutDocumentSerializer().decodeDocument(documentData)
        guard let cell = document.cell(withID: cellID),
              let shape = cell.shapes.first(where: { $0.id == shapeID }),
              case .rect(let rect) = shape.geometry else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "coordinate",
                expected: "finite number or input LayoutDocument with target rectangle"
            )
        }
        switch axis {
        case .vertical:
            return rect.center.x
        case .horizontal:
            return rect.center.y
        }
    }

    func layoutAddLabelCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .addLabel(AddLabelCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            labelID: try uuidHint("labelID", step: step, fallbackIndex: step.order * 10 + 4),
            text: stringHint("text", step: step) ?? stringHint("labelText", step: step) ?? "label_\(step.order)",
            position: LayoutPoint(
                x: try numberHint("positionX", step: step, defaultValue: try numberHint("originX", step: step, defaultValue: 0)),
                y: try numberHint("positionY", step: step, defaultValue: try numberHint("originY", step: step, defaultValue: 0))
            ),
            layer: layerHint(step: step),
            netID: try optionalUUIDHint("netID", step: step)
        ))
    }

    func layoutAddViaCommand(step: XcircuiteCandidatePlanStep) throws -> LayoutCommand {
        .addVia(AddViaCommand(
            cellID: try uuidHint("cellID", step: step, fallbackIndex: step.order * 10 + 1),
            viaID: try uuidHint("viaID", step: step, fallbackIndex: step.order * 10 + 5),
            viaDefinitionID: stringHint("viaDefinitionID", step: step) ?? "VIA1",
            position: LayoutPoint(
                x: try numberHint("positionX", step: step, defaultValue: try numberHint("originX", step: step, defaultValue: 0)),
                y: try numberHint("positionY", step: step, defaultValue: try numberHint("originY", step: step, defaultValue: 0))
            ),
            netID: try optionalUUIDHint("netID", step: step)
        ))
    }

    func layerHint(step: XcircuiteCandidatePlanStep) -> LayoutLayerID {
        LayoutLayerID(
            name: stringHint("layer", step: step) ?? "M1",
            purpose: stringHint("layerPurpose", step: step) ?? "drawing"
        )
    }

    func layoutProperties(step: XcircuiteCandidatePlanStep) -> [String: String] {
        var properties: [String: String] = [
            "candidatePlanStepID": step.stepID,
            "candidateActionID": step.actionID,
        ]
        if let ruleID = stringHint("ruleID", step: step) {
            properties["ruleID"] = ruleID
        }
        if let role = stringHint("role", step: step) {
            properties["role"] = role
        }
        return properties
    }
}
