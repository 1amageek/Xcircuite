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
            currentValue: .number(0),
            requiredValue: .number(0),
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
        var evidence: [String: XcircuiteJSONValue] = [
            "activeCount": .number(Double(bucket.activeCount)),
            "waivedCount": .number(Double(bucket.waivedCount)),
            "problemSourceOperation": .string("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .string("drc.run-native"),
            "symbolicGoalAtoms": .array(drcGoalAtoms(for: bucket).map { .string($0) }),
            "relatedShapeIDs": .array(bucket.relatedShapeIDs.map { .string($0) }),
            "relatedNetIDs": .array(bucket.relatedNetIDs.map { .string($0) }),
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
            currentValue: .number(Double(bucket.activeCount)),
            requiredValue: .number(0),
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
        var evidence: [String: XcircuiteJSONValue] = [
            "activeCount": .number(1),
            "problemSourceOperation": .string("xcircuite.generate-planning-problem"),
            "sourceEngineOperation": .string("drc.export-repair-hints"),
            "sourceRepairHintID": .string(hint.hintID),
            "sourceDiagnosticIndex": .number(Double(hint.sourceDiagnosticIndex)),
            "repairHintConfidence": .string(hint.confidence),
            "repairHintOperationID": .string(hint.operationID),
            "symbolicGoalAtoms": .array(drcGoalAtoms(forOperationID: hint.operationID).map { .string($0) }),
            "relatedShapeIDs": .array(hint.targetShapeIDs.map { .string($0) }),
            "relatedViaIDs": .array(hint.relatedViaIDs.map { .string($0) }),
            "relatedNetIDs": .array(hint.relatedNetIDs.map { .string($0) }),
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
            currentValue: .number(1),
            requiredValue: .number(0),
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
        to hints: [String: XcircuiteJSONValue]
    ) -> [String: XcircuiteJSONValue] {
        var result = hints
        if !atoms.isEmpty {
            result["symbolicEffects"] = .array(atoms.map { .string($0) })
        }
        return result
    }
}
