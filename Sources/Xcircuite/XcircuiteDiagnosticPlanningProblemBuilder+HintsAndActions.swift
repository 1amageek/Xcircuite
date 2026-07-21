import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func drcHints(
        _ bucket: DRCViolationBucketSummary,
        includesLVSRefs: Bool = false,
        topCell: String
    ) -> [String: PlanningParameterValue] {
        var hints: [String: PlanningParameterValue] = [
            "relatedShapeIDs": .textList(bucket.relatedShapeIDs),
            "relatedNetIDs": .textList(bucket.relatedNetIDs),
            "activeCount": .scalar(Double(bucket.activeCount)),
        ]
        if includesLVSRefs {
            hints["lvsInputs"] = lvsInputs(topCell: topCell)
        }
        let operationID = layoutOperationID(for: bucket)
        if operationTargetsExistingShape(operationID), let shapeID = bucket.relatedShapeIDs.first {
            hints["shapeID"] = .text(shapeID)
        }
        if operationID == "layout.add-rect", let region = bucket.representativeRegion {
            hints["originX"] = .scalar(region.x)
            hints["originY"] = .scalar(region.y)
            hints["width"] = .scalar(region.width)
            hints["height"] = .scalar(region.height)
        }
        if operationID == "layout.resize-shape" {
            let growth = resizeGrowth(for: bucket)
            hints["deltaMinX"] = .scalar(0)
            hints["deltaMinY"] = .scalar(0)
            hints["deltaMaxX"] = .scalar(growth.width)
            hints["deltaMaxY"] = .scalar(growth.height)
        }
        if operationID == "layout.split-shape" {
            hints["axis"] = .text(splitAxis(for: bucket))
        }
        insertOptional(bucket.ruleID, key: "ruleID", into: &hints)
        insertOptional(bucket.kind, key: "kind", into: &hints)
        insertOptional(bucket.layer, key: "layer", into: &hints)
        insertOptional(bucket.maxMeasured, key: "maxMeasured", into: &hints)
        insertOptional(bucket.required, key: "required", into: &hints)
        if let ruleHint = nativeDRCRuleHint(for: bucket) {
            hints["drcRules"] = .drcRules([ruleHint])
        }
        return hints
    }

    func drcHints(
        _ hint: DRCRepairHint,
        includesLVSRefs: Bool = false,
        topCell: String
    ) -> [String: PlanningParameterValue] {
        var hints: [String: PlanningParameterValue] = [
            "sourceRepairHintID": .text(hint.hintID),
            "sourceDiagnosticIndex": .scalar(Double(hint.sourceDiagnosticIndex)),
            "repairHintConfidence": .text(hint.confidence),
            "relatedShapeIDs": .textList(hint.targetShapeIDs),
            "relatedViaIDs": .textList(hint.relatedViaIDs),
            "relatedNetIDs": .textList(hint.relatedNetIDs),
            "activeCount": .scalar(1),
        ]
        if includesLVSRefs {
            hints["lvsInputs"] = lvsInputs(topCell: topCell)
        }
        if operationTargetsExistingShape(hint.operationID), let shapeID = hint.targetShapeIDs.first {
            hints["shapeID"] = .text(shapeID)
        }
        for (key, value) in hint.numericParameters {
            hints[key] = .scalar(value)
        }
        for (key, value) in hint.stringParameters {
            hints[key] = .text(value)
        }
        if let region = hint.region {
            hints["region"] = .region(
                PlanningRegion(x: region.x, y: region.y, width: region.width, height: region.height)
            )
        }
        insertOptional(hint.ruleID, key: "ruleID", into: &hints)
        insertOptional(hint.kind, key: "kind", into: &hints)
        insertOptional(hint.layer, key: "layer", into: &hints)
        insertOptional(hint.measured, key: "measured", into: &hints)
        insertOptional(hint.required, key: "required", into: &hints)
        if let ruleHint = nativeDRCRuleHint(for: hint) {
            hints["drcRules"] = .drcRules([ruleHint])
        }
        return hints
    }

    func nativeDRCRuleHint(for bucket: DRCViolationBucketSummary) -> PlanningDRCRule? {
        guard let kind = bucket.kind,
              let layer = bucket.layer,
              let required = bucket.required else {
            return nil
        }
        let ruleID = bucket.ruleID ?? "\(layer).\(kind)"
        return PlanningDRCRule(ruleID: ruleID, kind: kind, layer: layer, requiredValue: required)
    }

    func nativeDRCRuleHint(for hint: DRCRepairHint) -> PlanningDRCRule? {
        guard let kind = hint.kind,
              let layer = hint.layer,
              let required = hint.required else {
            return nil
        }
        let ruleID = hint.ruleID ?? "\(layer).\(kind)"
        return PlanningDRCRule(ruleID: ruleID, kind: kind, layer: layer, requiredValue: required)
    }

    func lvsHints(
        _ bucket: LVSMismatchBucketSummary,
        includesLVSRefs: Bool = false,
        topCell: String = "top"
    ) -> [String: PlanningParameterValue] {
        var hints: [String: PlanningParameterValue] = [
            "layoutPorts": .textList(bucket.layoutPorts),
            "schematicPorts": .textList(bucket.schematicPorts),
            "activeCount": .scalar(Double(bucket.activeCount)),
        ]
        if includesLVSRefs {
            hints["lvsInputs"] = lvsInputs(topCell: topCell)
        }
        insertOptional(bucket.ruleID, key: "ruleID", into: &hints)
        insertOptional(bucket.category, key: "category", into: &hints)
        insertOptional(bucket.componentSignature, key: "componentSignature", into: &hints)
        insertOptional(bucket.parameterName, key: "parameterName", into: &hints)
        insertOptional(bucket.layoutModel, key: "layoutModel", into: &hints)
        insertOptional(bucket.schematicModel, key: "schematicModel", into: &hints)
        insertOptional(bucket.layoutCount, key: "layoutCount", into: &hints)
        insertOptional(bucket.schematicCount, key: "schematicCount", into: &hints)
        return hints
    }

    func lvsHints(
        _ hint: LVSRepairHint,
        includesLVSRefs: Bool = false,
        topCell: String = "top"
    ) -> [String: PlanningParameterValue] {
        var hints: [String: PlanningParameterValue] = [
            "sourceRepairHintID": .text(hint.hintID),
            "sourceDiagnosticIndex": .scalar(Double(hint.sourceDiagnosticIndex)),
            "repairHintConfidence": .text(hint.confidence),
            "repairHintOperationID": .text(hint.operationID),
            "layoutPorts": .textList(hint.layoutPorts),
            "schematicPorts": .textList(hint.schematicPorts),
            "activeCount": .scalar(1),
        ]
        if includesLVSRefs {
            hints["lvsInputs"] = lvsInputs(topCell: topCell)
        }
        for (key, value) in hint.stringParameters {
            hints[key] = .text(value)
        }
        for (key, value) in hint.numericParameters ?? [:] {
            hints[key] = .scalar(value)
        }
        if hint.operationID == "simulation.set-netlist-parameters",
           let assignmentName = hint.stringParameters["assignmentName"],
           let assignmentValue = hint.numericParameters?["assignmentValue"] {
            hints["assignments"] = .parameterAssignments([
                XcircuiteParameterAssignment(name: assignmentName, value: assignmentValue),
            ])
            if hints["lvsEditedNetlistRole"] == nil {
                hints["lvsEditedNetlistRole"] = .text("layout")
            }
        }
        insertOptional(hint.ruleID, key: "ruleID", into: &hints)
        insertOptional(hint.category, key: "category", into: &hints)
        insertOptional(hint.componentSignature, key: "componentSignature", into: &hints)
        insertOptional(hint.parameterName, key: "parameterName", into: &hints)
        insertOptional(hint.layoutModel, key: "layoutModel", into: &hints)
        insertOptional(hint.schematicModel, key: "schematicModel", into: &hints)
        insertOptional(hint.layoutValue, key: "layoutValue", into: &hints)
        insertOptional(hint.schematicValue, key: "schematicValue", into: &hints)
        insertOptional(hint.layoutCount, key: "layoutCount", into: &hints)
        insertOptional(hint.schematicCount, key: "schematicCount", into: &hints)
        return hints
    }

    private func lvsInputs(topCell: String) -> PlanningParameterValue {
        .lvsInputs(
            PlanningLVSInputs(
                layoutNetlistReferenceID: "layout-netlist-ref",
                schematicNetlistReferenceID: "schematic-netlist-ref",
                topCell: topCell
            )
        )
    }

    func layoutOperationID(for bucket: DRCViolationBucketSummary) -> String {
        let normalized = (bucket.kind ?? bucket.ruleID ?? "").lowercased()
        if normalized.contains("cut") || normalized.contains("via") {
            return "layout.add-via"
        }
        if shouldFillNotch(for: normalized), bucket.representativeRegion != nil {
            return "layout.add-rect"
        }
        if shouldDeleteShape(for: normalized), !bucket.relatedShapeIDs.isEmpty {
            return "layout.delete-shape"
        }
        if shouldSplitShape(for: normalized), !bucket.relatedShapeIDs.isEmpty {
            return "layout.split-shape"
        }
        if normalized.contains("width")
            || normalized.contains("area")
            || normalized.contains("enclosure")
            || normalized.contains("extension") {
            if !bucket.relatedShapeIDs.isEmpty {
                return "layout.resize-shape"
            }
            return "layout.add-rect"
        }
        if !bucket.relatedShapeIDs.isEmpty {
            return "layout.translate-shape"
        }
        return "layout-command-replay"
    }

    func shouldDeleteShape(for normalizedKind: String) -> Bool {
        if normalizedKind.contains("density") {
            return normalizedKind.contains("max") || normalizedKind.contains("maximum")
        }
        return normalizedKind.contains("excess")
            || normalizedKind.contains("redundant")
            || normalizedKind.contains("floatingfill")
            || normalizedKind.contains("floating-fill")
    }

    func shouldFillNotch(for normalizedKind: String) -> Bool {
        normalizedKind.contains("notch")
            || normalizedKind.contains("slot")
    }

    func shouldSplitShape(for normalizedKind: String) -> Bool {
        normalizedKind.contains("notch")
            || normalizedKind.contains("slot")
            || normalizedKind.contains("minstep")
            || normalizedKind.contains("minimumstep")
            || normalizedKind.contains("jog")
    }

    func operationTargetsExistingShape(_ operationID: String) -> Bool {
        operationID == "layout.translate-shape"
            || operationID == "layout.resize-shape"
            || operationID == "layout.delete-shape"
            || operationID == "layout.split-shape"
    }

    func splitAxis(for bucket: DRCViolationBucketSummary) -> String {
        let normalized = (bucket.kind ?? bucket.ruleID ?? "").lowercased()
        if normalized.contains("horizontal") || normalized.contains("y-") || normalized.contains("y_") {
            return "horizontal"
        }
        return "vertical"
    }

    func drcGoalAtoms(for bucket: DRCViolationBucketSummary) -> [String] {
        drcGoalAtoms(forOperationID: layoutOperationID(for: bucket))
    }

    func drcGoalAtoms(forOperationID operationID: String) -> [String] {
        switch operationID {
        case "layout.add-via":
            return ["via-created", "artifact:layout-document"]
        case "layout.add-rect":
            return ["rect-shape-created", "artifact:layout-document"]
        case "layout.translate-shape":
            return ["shape-position-updated", "artifact:layout-document"]
        case "layout.resize-shape":
            return ["shape-size-updated", "artifact:layout-document"]
        case "layout.delete-shape":
            return ["shape-deleted", "artifact:layout-document"]
        case "layout.split-shape":
            return ["shape-split", "artifact:layout-document"]
        default:
            return ["layout-document-updated", "artifact:layout-document"]
        }
    }

    func drcVerificationGates(
        from hintGates: [String],
        includesLVSRefs: Bool
    ) -> [String] {
        var gates: [String] = []
        for gate in hintGates where !gates.contains(gate) {
            gates.append(gate)
        }
        for requiredGate in ["artifact-integrity", "native-drc"] where !gates.contains(requiredGate) {
            gates.append(requiredGate)
        }
        if includesLVSRefs && !gates.contains("native-lvs") {
            gates.append("native-lvs")
        }
        return gates
    }

    func resizeGrowth(for bucket: DRCViolationBucketSummary) -> (width: Double, height: Double) {
        let measured = bucket.maxMeasured ?? 0
        let required = bucket.required ?? measured
        let missing = max(0.0, required - measured)
        guard missing > 0 else {
            return (width: 0.0, height: 0.0)
        }
        let normalized = (bucket.kind ?? bucket.ruleID ?? "").lowercased()
        if normalized.contains("area") || normalized.contains("enclosure") || normalized.contains("extension") {
            if normalized.contains("area") {
                let measuredSide = sqrt(max(0.0, measured))
                let requiredSide = sqrt(max(0.0, required))
                let sideGrowth = max(0.0, requiredSide - measuredSide)
                return (width: sideGrowth, height: sideGrowth)
            }
            return (width: missing / 2.0, height: missing / 2.0)
        }
        return (width: missing, height: 0.0)
    }

    func lvsGoalAtoms(for bucket: LVSMismatchBucketSummary) -> [String] {
        if isPortMismatch(bucket) {
            return ["label-created", "artifact:layout-document"]
        }
        if requiresPolicyRepair(bucket) {
            return ["model-or-terminal-equivalence-policy-updated", "artifact:policy-artifact"]
        }
        return ["layout-document-updated", "artifact:layout-document"]
    }

    func lvsGoalAtoms(forOperationID operationID: String) -> [String] {
        switch operationID {
        case "layout.add-label":
            return ["label-created", "artifact:layout-document"]
        case "layout.add-net":
            return ["net-created", "artifact:layout-document"]
        case "lvs.policy-repair":
            return ["model-or-terminal-equivalence-policy-updated", "artifact:policy-artifact"]
        case "simulation.set-netlist-parameters":
            return ["edited-spice-netlist-produced", "parameter-edit-report-produced"]
        default:
            return ["layout-and-schematic-equivalence-updated", "artifact:layout-document"]
        }
    }

    func lvsActionDomainID(forOperationID operationID: String) -> String {
        if operationID.hasPrefix("layout.") {
            return "layout-edit"
        }
        if operationID.hasPrefix("simulation.") {
            return "simulation-analysis"
        }
        return "lvs-signoff"
    }

    func lvsMaturity(forOperationID _: String) -> XcircuiteOperationMaturity {
        .implemented
    }

    func lvsRequiredInputRefs(forOperationID operationID: String) -> [String] {
        if operationID.hasPrefix("layout.") {
            return ["layout-ref"]
        }
        if operationID == "simulation.set-netlist-parameters" {
            return ["layout-netlist-ref", "schematic-netlist-ref"]
        }
        return ["lvs-summary", "schematic-netlist-ref"]
    }

    func lvsVerificationGates(
        from hintGates: [String],
        operationID: String
    ) -> [String] {
        var gates: [String] = []
        for gate in hintGates where !gates.contains(gate) {
            gates.append(gate)
        }
        for requiredGate in ["artifact-integrity", "native-lvs"] where !gates.contains(requiredGate) {
            gates.append(requiredGate)
        }
        if operationID == "lvs.policy-repair" && !gates.contains("approval-gate") {
            gates.insert("approval-gate", at: 0)
        }
        return gates
    }

    func isPortMismatch(_ bucket: LVSMismatchBucketSummary) -> Bool {
        let normalized = [
            bucket.ruleID,
            bucket.category,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return normalized.contains("port")
            || bucket.layoutPorts != bucket.schematicPorts
    }

    func requiresPolicyRepair(_ bucket: LVSMismatchBucketSummary) -> Bool {
        let normalized = [
            bucket.ruleID,
            bucket.category,
            bucket.componentSignature,
            bucket.parameterName,
            bucket.layoutModel,
            bucket.schematicModel,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return normalized.contains("model")
            || normalized.contains("terminal")
            || normalized.contains("equivalence")
    }
}
