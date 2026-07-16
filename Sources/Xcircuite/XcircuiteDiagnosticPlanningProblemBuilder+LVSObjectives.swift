import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func cleanLVSObjective(summaryRefID: String) -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: "lvs.no-active-mismatches",
            kind: "satisfy",
            domain: "lvs",
            priority: "info",
            sourceRefIDs: [summaryRefID],
            target: "layout-and-schematic-equivalent",
            currentValue: .scalar(0),
            requiredValue: .scalar(0),
            description: "No active LVS mismatches were present in the source summary."
        )
    }

    func lvsObjective(
        bucket: LVSMismatchBucketSummary,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        let label = [
            bucket.ruleID,
            bucket.category,
            bucket.componentSignature,
            bucket.parameterName,
        ].compactMap { $0 }.joined(separator: "-")
        let objectiveID = try identifier("lvs-\(label.isEmpty ? "mismatch" : label)-\(index + 1)")
        var evidence: [String: PlanningParameterValue] = [
            "activeCount": .scalar(Double(bucket.activeCount)),
            "waivedCount": .scalar(Double(bucket.waivedCount)),
            "problemSourceOperation": .text("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .text("lvs.run-native"),
            "symbolicGoalAtoms": .textList(lvsGoalAtoms(for: bucket)),
            "layoutPorts": .textList(bucket.layoutPorts),
            "schematicPorts": .textList(bucket.schematicPorts),
        ]
        insertOptional(bucket.ruleID, key: "ruleID", into: &evidence)
        insertOptional(bucket.category, key: "category", into: &evidence)
        insertOptional(bucket.componentSignature, key: "componentSignature", into: &evidence)
        insertOptional(bucket.parameterName, key: "parameterName", into: &evidence)
        insertOptional(bucket.layoutModel, key: "layoutModel", into: &evidence)
        insertOptional(bucket.schematicModel, key: "schematicModel", into: &evidence)
        insertOptional(bucket.layoutCount, key: "layoutCount", into: &evidence)
        insertOptional(bucket.schematicCount, key: "schematicCount", into: &evidence)

        return XcircuitePlanningObjective(
            objectiveID: objectiveID,
            kind: "satisfy",
            domain: "lvs",
            priority: "error",
            sourceRefIDs: [summaryRefID],
            target: "layout-and-schematic-equivalent-for-bucket",
            currentValue: .scalar(Double(bucket.activeCount)),
            requiredValue: .scalar(0),
            description: "Repair LVS bucket \(label.isEmpty ? "unknown" : label) with \(bucket.activeCount) active mismatch(es).",
            evidence: evidence,
            suggestedActions: bucket.suggestedFixes
        )
    }

    func lvsObjective(
        hint: LVSRepairHint,
        index: Int,
        summaryRefID: String,
        repairHintRefID: String?
    ) throws -> XcircuitePlanningObjective {
        let label = [
            hint.ruleID,
            hint.category,
            hint.componentSignature,
            hint.parameterName,
        ].compactMap { $0 }.joined(separator: "-")
        let objectiveID = try identifier("lvs-\(label.isEmpty ? hint.hintID : label)-hint-\(index + 1)")
        var sourceRefIDs = [summaryRefID]
        if let repairHintRefID {
            sourceRefIDs.append(repairHintRefID)
        }
        var evidence: [String: PlanningParameterValue] = [
            "activeCount": .scalar(1),
            "problemSourceOperation": .text("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .text("lvs.export-repair-hints"),
            "sourceRepairHintID": .text(hint.hintID),
            "sourceDiagnosticIndex": .scalar(Double(hint.sourceDiagnosticIndex)),
            "repairHintConfidence": .text(hint.confidence),
            "repairHintOperationID": .text(hint.operationID),
            "symbolicGoalAtoms": .textList(lvsGoalAtoms(forOperationID: hint.operationID)),
            "layoutPorts": .textList(hint.layoutPorts),
            "schematicPorts": .textList(hint.schematicPorts),
        ]
        insertOptional(hint.ruleID, key: "ruleID", into: &evidence)
        insertOptional(hint.category, key: "category", into: &evidence)
        insertOptional(hint.componentSignature, key: "componentSignature", into: &evidence)
        insertOptional(hint.parameterName, key: "parameterName", into: &evidence)
        insertOptional(hint.layoutModel, key: "layoutModel", into: &evidence)
        insertOptional(hint.schematicModel, key: "schematicModel", into: &evidence)
        insertOptional(hint.layoutValue, key: "layoutValue", into: &evidence)
        insertOptional(hint.schematicValue, key: "schematicValue", into: &evidence)
        insertOptional(hint.layoutCount, key: "layoutCount", into: &evidence)
        insertOptional(hint.schematicCount, key: "schematicCount", into: &evidence)

        return XcircuitePlanningObjective(
            objectiveID: objectiveID,
            kind: "satisfy",
            domain: "lvs",
            priority: "error",
            sourceRefIDs: sourceRefIDs,
            target: "layout-and-schematic-equivalent-for-repair-hint",
            currentValue: .scalar(1),
            requiredValue: .scalar(0),
            description: "Repair LVS diagnostic \(hint.sourceDiagnosticIndex) using engine-owned repair hint \(hint.hintID).",
            evidence: evidence,
            suggestedActions: [hint.rationale]
        )
    }

    func lvsCandidateActions(
        bucket: LVSMismatchBucketSummary,
        objectiveID: String,
        index: Int,
        includesLVSRefs: Bool,
        topCell: String
    ) throws -> [XcircuitePlanningCandidateAction] {
        var actions = try lvsConcreteLayoutActions(
            bucket: bucket,
            objectiveID: objectiveID,
            index: index,
            includesLVSRefs: includesLVSRefs,
            topCell: topCell
        )
        if requiresPolicyRepair(bucket) {
            actions.append(
                XcircuitePlanningCandidateAction(
                    actionID: try identifier("lvs-policy-\(index + 1)"),
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "implemented",
                    reason: "The mismatch may be resolved by an auditable model or terminal equivalence policy update.",
                    sourceObjectiveIDs: [objectiveID],
                    requiredInputRefs: ["lvs-summary", "schematic-netlist-ref"],
                    verificationGates: ["approval-gate", "native-lvs", "artifact-integrity"],
                    parameterHints: addingSymbolicEffects(
                        lvsGoalAtoms(for: bucket),
                        to: lvsHints(
                            bucket,
                            includesLVSRefs: includesLVSRefs,
                            topCell: topCell
                        )
                    )
                )
            )
        }
        return actions
    }

    func lvsCandidateAction(
        hint: LVSRepairHint,
        objectiveID: String,
        index: Int,
        includesLVSRefs: Bool,
        topCell: String
    ) throws -> XcircuitePlanningCandidateAction {
        XcircuitePlanningCandidateAction(
            actionID: try identifier("\(lvsActionDomainID(forOperationID: hint.operationID))-\(hint.operationID)-hint-\(index + 1)"),
            domainID: lvsActionDomainID(forOperationID: hint.operationID),
            operationID: hint.operationID,
            maturity: lvsMaturity(forOperationID: hint.operationID),
            reason: hint.rationale,
            sourceObjectiveIDs: [objectiveID],
            requiredInputRefs: lvsRequiredInputRefs(forOperationID: hint.operationID),
            verificationGates: lvsVerificationGates(
                from: hint.verificationGates,
                operationID: hint.operationID
            ),
            parameterHints: addingSymbolicEffects(
                lvsGoalAtoms(forOperationID: hint.operationID),
                to: lvsHints(
                    hint,
                    includesLVSRefs: includesLVSRefs,
                    topCell: topCell
                )
            )
        )
    }

    func lvsConcreteLayoutActions(
        bucket: LVSMismatchBucketSummary,
        objectiveID: String,
        index: Int,
        includesLVSRefs: Bool,
        topCell: String
    ) throws -> [XcircuitePlanningCandidateAction] {
        guard isPortMismatch(bucket) else {
            return []
        }
        return [
            XcircuitePlanningCandidateAction(
                actionID: try identifier("layout-lvs-add-label-\(index + 1)"),
                domainID: "layout-edit",
                operationID: "layout.add-label",
                maturity: "implemented",
                reason: "Create or correct layout labels so extracted ports can match the schematic port set.",
                sourceObjectiveIDs: [objectiveID],
                requiredInputRefs: ["layout-ref"],
                verificationGates: ["artifact-integrity", "native-lvs", "native-drc"],
                parameterHints: addingSymbolicEffects(
                    lvsGoalAtoms(forOperationID: "layout.add-label"),
                    to: lvsHints(
                        bucket,
                        includesLVSRefs: includesLVSRefs,
                        topCell: topCell
                    )
                )
            ),
            XcircuitePlanningCandidateAction(
                actionID: try identifier("layout-lvs-add-net-\(index + 1)"),
                domainID: "layout-edit",
                operationID: "layout.add-net",
                maturity: "implemented",
                reason: "Create a missing layout net before labeling or reconnecting LVS-visible ports.",
                sourceObjectiveIDs: [objectiveID],
                requiredInputRefs: ["layout-ref"],
                verificationGates: ["artifact-integrity", "native-lvs", "native-drc"],
                parameterHints: addingSymbolicEffects(
                    lvsGoalAtoms(forOperationID: "layout.add-net"),
                    to: lvsHints(
                        bucket,
                        includesLVSRefs: includesLVSRefs,
                        topCell: topCell
                    )
                )
            ),
        ]
    }
}
