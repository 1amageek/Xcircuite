import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func cleanDRCObjective(summaryRefID: String) -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: "drc.no-active-violations",
            kind: "satisfy",
            domain: "drc",
            priority: "info",
            sourceRefIDs: [summaryRefID],
            target: "no-active-drc-violations",
            currentValue: .scalar(0),
            requiredValue: .scalar(0),
            description: "No active DRC violations were present in the source summary."
        )
    }

    func drcObjective(
        bucket: DRCViolationBucketSummary,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        let label = [bucket.ruleID, bucket.kind, bucket.layer]
            .compactMap { $0 }
            .joined(separator: "-")
        let objectiveID = try identifier("drc-\(label.isEmpty ? "violation" : label)-\(index + 1)")
        var evidence: [String: PlanningParameterValue] = [
            "activeCount": .scalar(Double(bucket.activeCount)),
            "waivedCount": .scalar(Double(bucket.waivedCount)),
            "problemSourceOperation": .text("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .text("drc.run-native"),
            "symbolicGoalAtoms": .textList(drcGoalAtoms(for: bucket)),
            "relatedShapeIDs": .textList(bucket.relatedShapeIDs),
            "relatedNetIDs": .textList(bucket.relatedNetIDs),
        ]
        insertOptional(bucket.ruleID, key: "ruleID", into: &evidence)
        insertOptional(bucket.kind, key: "kind", into: &evidence)
        insertOptional(bucket.layer, key: "layer", into: &evidence)
        insertOptional(bucket.maxMeasured, key: "maxMeasured", into: &evidence)
        insertOptional(bucket.required, key: "required", into: &evidence)

        return XcircuitePlanningObjective(
            objectiveID: objectiveID,
            kind: "satisfy",
            domain: "drc",
            priority: "error",
            sourceRefIDs: [summaryRefID],
            target: "no-active-violations-for-bucket",
            currentValue: .scalar(Double(bucket.activeCount)),
            requiredValue: .scalar(0),
            unit: nil,
            description: "Repair DRC bucket \(label.isEmpty ? "unknown" : label) with \(bucket.activeCount) active violation(s).",
            evidence: evidence,
            suggestedActions: bucket.suggestedFixes
        )
    }

    func drcObjective(
        hint: DRCRepairHint,
        index: Int,
        summaryRefID: String,
        repairHintRefID: String?
    ) throws -> XcircuitePlanningObjective {
        let label = [hint.ruleID, hint.kind, hint.layer]
            .compactMap { $0 }
            .joined(separator: "-")
        let objectiveID = try identifier("drc-\(label.isEmpty ? hint.hintID : label)-hint-\(index + 1)")
        var sourceRefIDs = [summaryRefID]
        if let repairHintRefID {
            sourceRefIDs.append(repairHintRefID)
        }
        var evidence: [String: PlanningParameterValue] = [
            "activeCount": .scalar(1),
            "problemSourceOperation": .text("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .text("drc.export-repair-hints"),
            "sourceRepairHintID": .text(hint.hintID),
            "sourceDiagnosticIndex": .scalar(Double(hint.sourceDiagnosticIndex)),
            "repairHintConfidence": .text(hint.confidence),
            "repairHintOperationID": .text(hint.operationID),
            "symbolicGoalAtoms": .textList(drcGoalAtoms(forOperationID: hint.operationID)),
            "relatedShapeIDs": .textList(hint.targetShapeIDs),
            "relatedViaIDs": .textList(hint.relatedViaIDs),
            "relatedNetIDs": .textList(hint.relatedNetIDs),
        ]
        insertOptional(hint.ruleID, key: "ruleID", into: &evidence)
        insertOptional(hint.kind, key: "kind", into: &evidence)
        insertOptional(hint.layer, key: "layer", into: &evidence)
        insertOptional(hint.measured, key: "measured", into: &evidence)
        insertOptional(hint.required, key: "required", into: &evidence)

        return XcircuitePlanningObjective(
            objectiveID: objectiveID,
            kind: "satisfy",
            domain: "drc",
            priority: "error",
            sourceRefIDs: sourceRefIDs,
            target: "no-active-violation-for-repair-hint",
            currentValue: .scalar(1),
            requiredValue: .scalar(0),
            unit: nil,
            description: "Repair DRC diagnostic \(hint.sourceDiagnosticIndex) using engine-owned repair hint \(hint.hintID).",
            evidence: evidence,
            suggestedActions: [hint.rationale]
        )
    }

    func drcCandidateActions(
        bucket: DRCViolationBucketSummary,
        objectiveID: String,
        index: Int,
        includesLVSRefs: Bool,
        topCell: String
    ) throws -> [XcircuitePlanningCandidateAction] {
        [
            XcircuitePlanningCandidateAction(
                actionID: try identifier("layout-\(layoutOperationID(for: bucket))-\(index + 1)"),
                domainID: "layout-edit",
                operationID: layoutOperationID(for: bucket),
                maturity: "implemented",
                reason: "Provide the planner with an available layout edit operation family for this DRC bucket.",
                sourceObjectiveIDs: [objectiveID],
                requiredInputRefs: ["layout-ref"],
                verificationGates: ["artifact-integrity", "native-drc", "native-lvs"],
                parameterHints: addingSymbolicEffects(
                    drcGoalAtoms(for: bucket),
                    to: drcHints(
                        bucket,
                        includesLVSRefs: includesLVSRefs,
                        topCell: topCell
                    )
                )
            )
        ]
    }

    func drcCandidateAction(
        hint: DRCRepairHint,
        objectiveID: String,
        index: Int,
        includesLVSRefs: Bool,
        topCell: String
    ) throws -> XcircuitePlanningCandidateAction {
        XcircuitePlanningCandidateAction(
            actionID: try identifier("layout-\(hint.operationID)-hint-\(index + 1)"),
            domainID: "layout-edit",
            operationID: hint.operationID,
            maturity: "implemented",
            reason: hint.rationale,
            sourceObjectiveIDs: [objectiveID],
            requiredInputRefs: ["layout-ref"],
            verificationGates: drcVerificationGates(
                from: hint.verificationGates,
                includesLVSRefs: includesLVSRefs
            ),
            parameterHints: addingSymbolicEffects(
                drcGoalAtoms(forOperationID: hint.operationID),
                to: drcHints(
                    hint,
                    includesLVSRefs: includesLVSRefs,
                    topCell: topCell
                )
            )
        )
    }

    func addingSymbolicEffects(
        _ atoms: [String],
        to hints: [String: PlanningParameterValue]
    ) -> [String: PlanningParameterValue] {
        var result = hints
        if !atoms.isEmpty {
            result["symbolicEffects"] = .textList(atoms)
        }
        return result
    }
}
