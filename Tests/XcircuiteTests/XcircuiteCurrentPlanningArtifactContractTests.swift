import Foundation
import Testing
import Xcircuite

@Suite("Xcircuite current planning artifact contracts")
struct XcircuiteCurrentPlanningArtifactContractTests {
    @Test func candidatePlanRejectsMissingAssumptionInventory() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "planID": "plan-1",
          "problemID": "problem-1",
          "runID": "run-1",
          "strategy": "deterministic",
          "executionReadiness": "ready",
          "sourceProblemRef": {
            "refID": "problem",
            "kind": "planning-problem",
            "metadata": {}
          },
          "riskClassifications": [],
          "steps": [],
          "verificationGates": [],
          "constraints": [],
          "unresolvedObjectives": [],
          "blockers": []
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(XcircuiteCandidatePlan.self, from: data)
        }
    }

    @Test func symbolicPlannerTraceRejectsMissingStateEvidence() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "runID": "run-1",
          "problemID": "problem-1",
          "strategy": "deterministic",
          "problemPath": ".xcircuite/runs/run-1/planning/problem.json",
          "rejectedPlanFeedbackRecordCount": 0,
          "globalRejectedPlanFeedbackCount": 0,
          "generatedPlanID": "plan-1",
          "selectedActionIDs": [],
          "unresolvedObjectiveIDs": [],
          "finalSymbolicState": [],
          "goalCoverageStatus": "covered",
          "goalCoverage": [],
          "missingGoalAtoms": [],
          "objectiveTraces": []
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(XcircuiteSymbolicPlannerTrace.self, from: data)
        }
    }

    @Test func planVerificationRejectsMissingCorrectnessGateEvidence() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "problemID": "problem-1",
          "planID": "plan-1",
          "runID": "run-1",
          "verificationMode": "post-execution",
          "candidatePlanRef": {
            "path": ".xcircuite/runs/run-1/planning/candidate-plan.json",
            "kind": "other",
            "format": "JSON"
          },
          "stepResults": [],
          "gateResults": [],
          "riskReviews": [],
          "artifactRefs": [],
          "initialSymbolicState": [],
          "finalSymbolicState": [],
          "goalCoverageStatus": "covered",
          "goalCoverage": [],
          "missingGoalAtoms": [],
          "diagnostics": [],
          "accepted": true,
          "nextActions": []
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(XcircuitePlanVerification.self, from: data)
        }
    }
}
