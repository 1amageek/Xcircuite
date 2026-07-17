import Foundation

/// Xcircuite CLI commands reachable from DesignFlowKernel semantic actions.
public enum XcircuiteFlowActionCommand: String, Sendable, Hashable, Codable {
    case summarizeLoop = "summarize-loop"
    case inspectRun = "inspect-run"
    case reviewRun = "review-run"
    case evaluateRunGuard = "evaluate-run-guard"
    case validatePlanningProblem = "validate-planning-problem"
    case auditProblemTranslation = "audit-problem-translation"
    case generateCandidatePlan = "generate-candidate-plan"
    case executeCandidatePlan = "execute-candidate-plan"
    case verifyCandidatePlan = "verify-candidate-plan"
    case generateParameterCandidates = "generate-parameter-candidates"
    case synthesizeParameterCandidatePlan = "synthesize-parameter-candidate-plan"
    case runNumericRepairLoop = "run-numeric-repair-loop"
    case buildStageArtifactLadder = "build-stage-artifact-ladder"
    case validateDecisionPacket = "validate-decision-packet"
    case buildReleaseEnvelope = "build-release-envelope"
}
