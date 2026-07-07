import Foundation

struct XcircuiteCandidatePlanReviewProjection: Sendable {
    func assumptions(
        from problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningAssumption] {
        problem.assumptions
    }

    func riskClassifications(
        from problem: XcircuiteCircuitPlanningProblem,
        steps: [XcircuiteCandidatePlanStep]
    ) -> [XcircuitePlanningRiskClassification] {
        let selectedActionIDs = Set(steps.map(\.actionID))
        let selectedObjectiveIDs = Set(steps.flatMap(\.sourceObjectiveIDs))
        return problem.riskClassifications.filter { risk in
            isGlobal(risk)
                || intersects(risk.affectedActionIDs, selectedActionIDs)
                || intersects(risk.affectedObjectiveIDs, selectedObjectiveIDs)
        }
    }

    private func isGlobal(_ risk: XcircuitePlanningRiskClassification) -> Bool {
        risk.affectedActionIDs.isEmpty && risk.affectedObjectiveIDs.isEmpty
    }

    private func intersects(_ values: [String], _ selected: Set<String>) -> Bool {
        values.contains { selected.contains($0) }
    }
}
