import Foundation
import CircuiteFoundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func nativeLVSArtifactReferences(
        summaryURL: URL,
        executionResult: LVSExecutionResult,
        projectRoot: URL
    ) throws -> [ArtifactReference] {
        var artifacts = [
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-summary",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ),
        ]
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-report",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let manifestURL = executionResult.artifactManifestURL {
            artifacts.append(try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-manifest",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let correspondenceURL = executionResult.correspondenceURL {
            artifacts.append(try artifactBuilder.reference(
                for: correspondenceURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-correspondence",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let extractionReportURL = executionResult.extractionReportURL {
            artifacts.append(try artifactBuilder.reference(
                for: extractionReportURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-extraction-report",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let transformLedgerURL = executionResult.transformLedgerURL {
            artifacts.append(try artifactBuilder.reference(
                for: transformLedgerURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-transform-ledger",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: projectRoot,
            artifactID: "planning-native-lvs-log",
            kind: ArtifactKind.report,
            format: ArtifactFormat.text
        ) {
            artifacts.append(log)
        }
        if let extracted = executionResult.extractedLayoutNetlistURL {
            artifacts.append(try artifactBuilder.reference(
                for: extracted,
                projectRoot: projectRoot,
                artifactID: "planning-native-lvs-extracted-layout-netlist",
                kind: ArtifactKind.netlist,
                format: ArtifactFormat.spice
            ))
        }
        return artifacts
    }

    func nativeLVSExecutionSpec(
        from plan: XcircuiteCandidatePlan,
        problem: XcircuiteCircuitPlanningProblem
    ) throws -> NativeLVSExecutionSpec? {
        let hint = try nativeLVSInputHint(from: plan)
        let references = problem.sourceRefs + problem.initialStateRefs
        let layoutNetlistRef = planningReference(
            explicitID: hint.layoutNetlistRefID ?? hint.layoutNetlistRef,
            fallbackIDs: ["layout-netlist-ref", "extracted-layout-netlist-ref"],
            fallbackKinds: ["layout-netlist", "extracted-layout-netlist"],
            references: references
        )
        let layoutGDSRef = layoutNetlistRef == nil
            ? planningReference(
                explicitID: hint.layoutGDSRefID ?? hint.layoutGDSRef,
                fallbackIDs: ["layout-gds-ref", "layout-ref"],
                fallbackKinds: ["layout-gds"],
                references: references
            )
            : nil
        guard let schematicNetlistRef = planningReference(
            explicitID: hint.schematicNetlistRefID ?? hint.schematicNetlistRef,
            fallbackIDs: ["schematic-netlist-ref", "source-netlist-ref"],
            fallbackKinds: ["schematic-netlist"],
            references: references
        ) else {
            return nil
        }
        let technologyRef = planningReference(
            explicitID: hint.technologyRefID ?? hint.technologyRef,
            fallbackIDs: ["technology-ref", "layout-technology-ref"],
            fallbackKinds: ["technology", "layout-technology"],
            references: references
        )
        let extractionDeckRef = planningReference(
            explicitID: hint.extractionDeckRefID ?? hint.extractionDeckRef,
            fallbackIDs: ["extraction-deck-ref", "lvs-extraction-deck-ref"],
            fallbackKinds: ["lvs-extraction-deck", "extraction-deck"],
            references: references
        )
        let backendID = hint.backendID ?? (layoutNetlistRef == nil ? "native-gds" : "native")
        guard backendID == "native" || backendID == "native-gds" else {
            throw CandidatePlanGateExecutionError.unsupportedLVSBackend(backendID)
        }
        return NativeLVSExecutionSpec(
            layoutNetlistRef: layoutNetlistRef,
            layoutGDSRef: layoutGDSRef,
            layoutFormat: try lvsLayoutFormat(from: hint.layoutFormat),
            schematicNetlistRef: schematicNetlistRef,
            topCell: hint.topCell ?? "top",
            technologyRef: technologyRef,
            extractionDeckRef: extractionDeckRef,
            processProfileID: hint.processProfileID,
            waiverRef: planningReference(
                explicitID: hint.waiverRefID ?? hint.waiverRef,
                fallbackIDs: ["lvs-waiver-ref"],
                fallbackKinds: ["lvs-waiver"],
                references: references
            ),
            modelEquivalenceRef: planningReference(
                explicitID: hint.modelEquivalenceRefID ?? hint.modelEquivalenceRef,
                fallbackIDs: ["model-equivalence-ref", "lvs-model-equivalence-ref"],
                fallbackKinds: ["model-equivalence", "lvs-model-equivalence"],
                references: references
            ),
            terminalEquivalenceRef: planningReference(
                explicitID: hint.terminalEquivalenceRefID ?? hint.terminalEquivalenceRef,
                fallbackIDs: ["terminal-equivalence-ref", "lvs-terminal-equivalence-ref"],
                fallbackKinds: ["terminal-equivalence", "lvs-terminal-equivalence"],
                references: references
            ),
            backendID: backendID
        )
    }

    func nativeLVSInputHint(from plan: XcircuiteCandidatePlan) throws -> CandidatePlanLVSInputHint {
        var hint = CandidatePlanLVSInputHint()
        for step in plan.steps.sorted(by: { $0.order < $1.order })
            where step.verificationGates.contains("native-lvs") {
            if let decoded: CandidatePlanLVSInputHint = try decodedHint("lvsInputs", from: step) {
                hint.merge(decoded)
            }
            hint.merge(CandidatePlanLVSInputHint(
                layoutNetlistRef: stringHint("layoutNetlistRef", step: step),
                layoutNetlistRefID: stringHint("layoutNetlistRefID", step: step),
                layoutGDSRef: stringHint("layoutGDSRef", step: step),
                layoutGDSRefID: stringHint("layoutGDSRefID", step: step),
                schematicNetlistRef: stringHint("schematicNetlistRef", step: step),
                schematicNetlistRefID: stringHint("schematicNetlistRefID", step: step),
                technologyRef: stringHint("technologyRef", step: step),
                technologyRefID: stringHint("technologyRefID", step: step),
                extractionDeckRef: stringHint("extractionDeckRef", step: step),
                extractionDeckRefID: stringHint("extractionDeckRefID", step: step),
                processProfileID: stringHint("processProfileID", step: step),
                waiverRef: stringHint("waiverRef", step: step),
                waiverRefID: stringHint("waiverRefID", step: step),
                modelEquivalenceRef: stringHint("modelEquivalenceRef", step: step),
                modelEquivalenceRefID: stringHint("modelEquivalenceRefID", step: step),
                terminalEquivalenceRef: stringHint("terminalEquivalenceRef", step: step),
                terminalEquivalenceRefID: stringHint("terminalEquivalenceRefID", step: step),
                topCell: stringHint("topCell", step: step),
                layoutFormat: stringHint("layoutFormat", step: step),
                backendID: stringHint("lvsBackendID", step: step) ?? stringHint("backendID", step: step)
            ))
        }
        return hint
    }

    func planningReference(
        explicitID: String?,
        fallbackIDs: [String],
        fallbackKinds: [String],
        references: [XcircuitePlanningReference]
    ) -> XcircuitePlanningReference? {
        if let explicitID,
           let reference = references.first(where: { $0.refID == explicitID || $0.artifactID == explicitID }) {
            return reference
        }
        for refID in fallbackIDs {
            if let reference = references.first(where: { $0.refID == refID }) {
                return reference
            }
        }
        return references.first { fallbackKinds.contains($0.kind) }
    }

    func sourcePlanningProblem(
        for plan: XcircuiteCandidatePlan,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> XcircuiteCircuitPlanningProblem? {
        let problemURL: URL
        if let path = plan.sourceProblemRef.path {
            problemURL = try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        } else if let artifactID = plan.sourceProblemRef.artifactID,
                  let artifact = manifest.artifacts.first(where: { $0.artifactID == artifactID }) {
            problemURL = try workspaceStore.url(forProjectRelativePath: artifact.path, inProjectAt: projectRoot)
        } else {
            return nil
        }
        let problem = try workspaceStore.readJSON(XcircuiteCircuitPlanningProblem.self, from: problemURL)
        guard problem.runID == plan.runID else {
            throw CandidatePlanGateExecutionError.sourceProblemRunMismatch(
                expected: plan.runID,
                actual: problem.runID
            )
        }
        return problem
    }

    func url(
        for reference: XcircuitePlanningReference,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) throws -> URL {
        if let path = reference.path {
            return try workspaceStore.url(forProjectRelativePath: path, inProjectAt: projectRoot)
        }
        if let artifactID = reference.artifactID,
           let artifact = manifest.artifacts.first(where: { $0.artifactID == artifactID }) {
            return try workspaceStore.url(forProjectRelativePath: artifact.path, inProjectAt: projectRoot)
        }
        throw CandidatePlanGateExecutionError.planningReferencePathMissing(reference.refID)
    }

    func lvsLayoutFormat(from value: String?) throws -> LVSLayoutFormat? {
        guard let value else {
            return nil
        }
        guard let format = LVSLayoutFormat(rawValue: value) else {
            throw CandidatePlanGateExecutionError.unsupportedLVSLayoutFormat(value)
        }
        return format
    }

    func lvsLayoutFormat(from reference: XcircuitePlanningReference) throws -> LVSLayoutFormat? {
        switch reference.path?.split(separator: ".").last?.lowercased() {
        case "gds", "gdsii":
            return .gds
        case "oas", "oasis":
            return .oasis
        case "cif":
            return .cif
        case "dxf":
            return .dxf
        default:
            if reference.kind == "layout-gds" {
                return .gds
            }
            if reference.kind == "layout-oasis" {
                return .oasis
            }
            throw CandidatePlanGateExecutionError.unsupportedLVSLayoutFormat(reference.path ?? reference.refID)
        }
    }

    func nativeDRCArtifactReferences(
        drcLayoutURL: URL,
        summaryURL: URL,
        executionResult: DRCExecutionResult,
        projectRoot: URL
    ) throws -> [ArtifactReference] {
        var artifacts = [
            try artifactBuilder.reference(
                for: drcLayoutURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-drc-layout",
                kind: ArtifactKind.layout,
                format: ArtifactFormat.json
            ),
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-drc-summary",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ),
        ]
        if let reportURL = executionResult.reportURL {
            artifacts.append(try artifactBuilder.reference(
                for: reportURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-drc-report",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let manifestURL = executionResult.artifactManifestURL {
            artifacts.append(try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: projectRoot,
                artifactID: "planning-native-drc-manifest",
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        if let log = try artifactBuilder.optionalReference(
            for: executionResult.result.logPath,
            projectRoot: projectRoot,
            artifactID: "planning-native-drc-log",
            kind: ArtifactKind.report,
            format: ArtifactFormat.text
        ) {
            artifacts.append(log)
        }
        return artifacts
    }

    func nativeDRCExportSpec(from plan: XcircuiteCandidatePlan) throws -> LayoutCommandDRCExportSpec? {
        for step in plan.steps.sorted(by: { $0.order < $1.order }) {
            if let spec: LayoutCommandDRCExportSpec = try decodedHint("drcExportSpec", from: step) {
                return spec
            }
            if let rules: [NativeDRCRule] = try decodedHint("drcRules", from: step) {
                guard !rules.isEmpty else {
                    continue
                }
                return LayoutCommandDRCExportSpec(
                    technologyID: stringHint("technologyID", step: step) ?? "planning-native-drc",
                    topCell: stringHint("topCell", step: step) ?? stringHint("cellName", step: step) ?? "top",
                    unit: stringHint("unit", step: step) ?? "micrometer",
                    viaDefinitions: (try decodedHint("viaDefinitions", from: step)) ?? [],
                    rules: rules
                )
            }
        }
        return nil
    }

    func latestLayoutDocumentRef(
        from execution: XcircuiteCandidatePlanExecution
    ) -> XcircuiteFileReference? {
        execution.stepResults
            .sorted { $0.order > $1.order }
            .lazy
            .compactMap { result in
                legacyArtifactReferences(result.artifactReferences).first { reference in
                    reference.artifactID?.hasSuffix("layout-document") == true
                }
            }
            .first
    }

    func nativeDRCLayout(
        from document: LayoutDocument,
        spec: LayoutCommandDRCExportSpec
    ) throws -> NativeDRCLayout {
        let cell = try topCell(named: spec.topCell, in: document)
        let viaDefinitions = try viaDefinitionMap(from: spec.viaDefinitions)
        var rectangles = try cell.shapes.map { try nativeDRCRectangle(from: $0) }
        for via in cell.vias {
            guard let definition = viaDefinitions[via.viaDefinitionID] else {
                throw CandidatePlanGateExecutionError.missingViaDefinition(
                    viaID: via.id,
                    definitionID: via.viaDefinitionID
                )
            }
            rectangles.append(nativeDRCRectangle(from: via, definition: definition))
        }
        return NativeDRCLayout(
            technologyID: spec.technologyID,
            topCell: spec.topCell,
            unit: spec.unit,
            rectangles: rectangles,
            rules: spec.rules
        )
    }

    func viaDefinitionMap(
        from definitions: [LayoutCommandDRCViaDefinition]
    ) throws -> [String: LayoutCommandDRCViaDefinition] {
        var map: [String: LayoutCommandDRCViaDefinition] = [:]
        for definition in definitions {
            guard map[definition.id] == nil else {
                throw CandidatePlanGateExecutionError.duplicateViaDefinition(definition.id)
            }
            map[definition.id] = definition
        }
        return map
    }

    func topCell(named name: String, in document: LayoutDocument) throws -> LayoutCell {
        if let cell = document.cells.first(where: { $0.name == name }) {
            return cell
        }
        throw CandidatePlanGateExecutionError.layoutCellNotFound(name)
    }

    func nativeDRCRectangle(from shape: LayoutShape) throws -> NativeDRCRectangle {
        guard case .rect(let rect) = shape.geometry else {
            throw CandidatePlanGateExecutionError.unsupportedGeometry(shapeID: shape.id)
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

    func nativeDRCRectangle(
        from via: LayoutVia,
        definition: LayoutCommandDRCViaDefinition
    ) -> NativeDRCRectangle {
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
}
