import Foundation
import DesignFlowKernel

struct XcircuiteCandidatePlanRiskReviewer: Sendable {
    func riskReviews(
        for plan: XcircuiteCandidatePlan,
        approvals: [XcircuiteApprovalRecord] = []
    ) -> [XcircuitePlanRiskReview] {
        let approvalsByID = Dictionary(uniqueKeysWithValues: approvals.map { ($0.stageID, $0) })
        return plan.riskClassifications.map { risk in
            let approvalReviews = risk.requiredApprovals.map { approvalReview(for: $0, approvalsByID: approvalsByID) }
            return XcircuitePlanRiskReview(
                riskID: risk.riskID,
                category: risk.category,
                severity: risk.severity,
                scope: risk.scope,
                status: status(for: risk, approvalReviews: approvalReviews),
                description: risk.description,
                affectedObjectiveIDs: risk.affectedObjectiveIDs,
                affectedActionIDs: risk.affectedActionIDs,
                affectedStepIDs: affectedStepIDs(for: risk, plan: plan),
                requiredApprovals: risk.requiredApprovals,
                approvalReviews: approvalReviews,
                mitigationActions: risk.mitigationActions
            )
        }
    }

    func blockingDiagnostics(
        from riskReviews: [XcircuitePlanRiskReview]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        riskReviews.compactMap { review in
            switch review.status {
            case "approval-required":
                let missingApprovals = review.approvalReviews
                    .filter { $0.status == "missing" }
                    .map(\.approvalID)
                return XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "risk-approval-required",
                    message: "Risk \(review.riskID) requires approvals: \(missingApprovals.joined(separator: ","))",
                    gateID: "approval-gate"
                )
            case "approval-rejected":
                let rejectedApprovals = review.approvalReviews
                    .filter { $0.status == "rejected" }
                    .map(\.approvalID)
                return XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "risk-approval-rejected",
                    message: "Risk \(review.riskID) has rejected approvals: \(rejectedApprovals.joined(separator: ","))",
                    gateID: "approval-gate"
                )
            case "blocked":
                return XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "high-risk-approval-missing",
                    message: "Risk \(review.riskID) is \(review.severity) and must declare required approvals before plan acceptance."
                )
            default:
                return nil
            }
        }
    }

    func requiresApprovalGate(_ riskReviews: [XcircuitePlanRiskReview]) -> Bool {
        riskReviews.contains { !$0.requiredApprovals.isEmpty }
    }

    func blocksExecution(_ riskReviews: [XcircuitePlanRiskReview]) -> Bool {
        riskReviews.contains {
            $0.status == "approval-required" || $0.status == "approval-rejected" || $0.status == "blocked"
        }
    }

    func nextActions(from riskReviews: [XcircuitePlanRiskReview]) -> [String] {
        unique(riskReviews.flatMap { review -> [String] in
            switch review.status {
            case "approval-required":
                return review.approvalReviews
                    .filter { $0.status == "missing" }
                    .map { "request-human-approval:\($0.approvalID)" }
            case "approval-rejected":
                return review.approvalReviews
                    .filter { $0.status == "rejected" }
                    .map { "revise-plan-after-approval-rejection:\($0.approvalID)" }
            case "blocked":
                return ["add-required-approval:\(review.riskID)"]
            default:
                return []
            }
        })
    }

    func blockingStepIDs(
        from riskReviews: [XcircuitePlanRiskReview],
        plan: XcircuiteCandidatePlan
    ) -> [String] {
        let stepIDs = riskReviews
            .filter {
                $0.status == "approval-required" || $0.status == "approval-rejected" || $0.status == "blocked"
            }
            .flatMap(\.affectedStepIDs)
        if stepIDs.isEmpty {
            return plan.steps.map(\.stepID)
        }
        return unique(stepIDs)
    }

    private func status(
        for risk: XcircuitePlanningRiskClassification,
        approvalReviews: [XcircuitePlanApprovalReview]
    ) -> String {
        if risk.requiredApprovals.isEmpty && ["high", "critical"].contains(risk.severity) {
            return "blocked"
        }
        if approvalReviews.contains(where: { $0.status == "rejected" }) {
            return "approval-rejected"
        }
        if approvalReviews.contains(where: { $0.status == "missing" }) {
            return "approval-required"
        }
        if !approvalReviews.isEmpty {
            return "approved"
        }
        if !risk.mitigationActions.isEmpty {
            return "mitigation-required"
        }
        return "tracked"
    }

    private func approvalReview(
        for approvalID: String,
        approvalsByID: [String: XcircuiteApprovalRecord]
    ) -> XcircuitePlanApprovalReview {
        guard let approval = approvalsByID[approvalID] else {
            return XcircuitePlanApprovalReview(
                approvalID: approvalID,
                status: "missing"
            )
        }
        return XcircuitePlanApprovalReview(
            approvalID: approvalID,
            status: approval.verdict.rawValue,
            reviewer: approval.reviewer,
            note: approval.note.isEmpty ? nil : approval.note,
            decidedAt: approval.createdAt
        )
    }

    private func affectedStepIDs(
        for risk: XcircuitePlanningRiskClassification,
        plan: XcircuiteCandidatePlan
    ) -> [String] {
        let affectedActionIDs = Set(risk.affectedActionIDs)
        let affectedObjectiveIDs = Set(risk.affectedObjectiveIDs)
        if affectedActionIDs.isEmpty && affectedObjectiveIDs.isEmpty {
            return plan.steps.map(\.stepID)
        }
        return plan.steps.compactMap { step in
            if affectedActionIDs.contains(step.actionID) {
                return step.stepID
            }
            if step.sourceObjectiveIDs.contains(where: { affectedObjectiveIDs.contains($0) }) {
                return step.stepID
            }
            return nil
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }
}
