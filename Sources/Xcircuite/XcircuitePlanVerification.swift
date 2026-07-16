import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuitePlanVerification: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var problemID: String
    public var planID: String
    public var runID: String
    public var verificationMode: String
    public var candidatePlanRef: ArtifactReference
    public var stepResults: [XcircuitePlanVerificationStepResult]
    public var gateResults: [XcircuitePlanVerificationGateResult]
    public var correctnessGateResults: [XcircuitePlanningCorrectnessGateResult]
    public var riskReviews: [XcircuitePlanRiskReview]
    public var artifactRefs: [ArtifactReference]
    public var initialSymbolicState: [String]
    public var finalSymbolicState: [String]
    public var goalCoverageStatus: String
    public var goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage]
    public var missingGoalAtoms: [String]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var accepted: Bool
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        problemID: String,
        planID: String,
        runID: String,
        verificationMode: String,
        candidatePlanRef: ArtifactReference,
        stepResults: [XcircuitePlanVerificationStepResult],
        gateResults: [XcircuitePlanVerificationGateResult],
        correctnessGateResults: [XcircuitePlanningCorrectnessGateResult] = [],
        riskReviews: [XcircuitePlanRiskReview] = [],
        artifactRefs: [ArtifactReference],
        initialSymbolicState: [String] = [],
        finalSymbolicState: [String] = [],
        goalCoverageStatus: String = "not-evaluated",
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage] = [],
        missingGoalAtoms: [String] = [],
        diagnostics: [XcircuitePlanVerificationDiagnostic],
        accepted: Bool,
        nextActions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.problemID = problemID
        self.planID = planID
        self.runID = runID
        self.verificationMode = verificationMode
        self.candidatePlanRef = candidatePlanRef
        self.stepResults = stepResults
        self.gateResults = gateResults
        self.correctnessGateResults = correctnessGateResults
        self.riskReviews = riskReviews
        self.artifactRefs = artifactRefs
        self.initialSymbolicState = initialSymbolicState
        self.finalSymbolicState = finalSymbolicState
        self.goalCoverageStatus = goalCoverageStatus
        self.goalCoverage = goalCoverage
        self.missingGoalAtoms = missingGoalAtoms
        self.diagnostics = diagnostics
        self.accepted = accepted
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case problemID
        case planID
        case runID
        case verificationMode
        case candidatePlanRef
        case stepResults
        case gateResults
        case correctnessGateResults
        case riskReviews
        case artifactRefs
        case initialSymbolicState
        case finalSymbolicState
        case goalCoverageStatus
        case goalCoverage
        case missingGoalAtoms
        case diagnostics
        case accepted
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported plan verification schema version: \(schemaVersion)."
            )
        }
        self.problemID = try container.decode(String.self, forKey: .problemID)
        self.planID = try container.decode(String.self, forKey: .planID)
        self.runID = try container.decode(String.self, forKey: .runID)
        self.verificationMode = try container.decode(String.self, forKey: .verificationMode)
        self.candidatePlanRef = try container.decode(ArtifactReference.self, forKey: .candidatePlanRef)
        self.stepResults = try container.decode([XcircuitePlanVerificationStepResult].self, forKey: .stepResults)
        self.gateResults = try container.decode([XcircuitePlanVerificationGateResult].self, forKey: .gateResults)
        self.correctnessGateResults = try container.decode(
            [XcircuitePlanningCorrectnessGateResult].self,
            forKey: .correctnessGateResults
        )
        self.riskReviews = try container.decode(
            [XcircuitePlanRiskReview].self,
            forKey: .riskReviews
        )
        self.artifactRefs = try container.decode([ArtifactReference].self, forKey: .artifactRefs)
        self.initialSymbolicState = try container.decode([String].self, forKey: .initialSymbolicState)
        self.finalSymbolicState = try container.decode([String].self, forKey: .finalSymbolicState)
        self.goalCoverageStatus = try container.decode(String.self, forKey: .goalCoverageStatus)
        self.goalCoverage = try container.decode(
            [XcircuiteSymbolicPlannerGoalCoverage].self,
            forKey: .goalCoverage
        )
        self.missingGoalAtoms = try container.decode([String].self, forKey: .missingGoalAtoms)
        self.diagnostics = try container.decode([XcircuitePlanVerificationDiagnostic].self, forKey: .diagnostics)
        self.accepted = try container.decode(Bool.self, forKey: .accepted)
        self.nextActions = try container.decode([String].self, forKey: .nextActions)
    }
}
