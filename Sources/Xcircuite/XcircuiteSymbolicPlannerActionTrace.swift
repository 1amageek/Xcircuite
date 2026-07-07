import Foundation

public struct XcircuiteSymbolicPlannerActionTrace: Codable, Sendable, Hashable {
    public var rank: Int
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var maturity: String
    public var score: Int
    public var scoreBeforeRejectedFeedback: Int
    public var rejectedFeedbackScoreDelta: Int
    public var rankBeforeRejectedFeedback: Int
    public var rejectedFeedbackRankDelta: Int
    public var scoreComponents: [XcircuiteSymbolicPlannerScoreComponent]
    public var requiredInputRefs: [String]
    public var missingInputRefs: [String]
    public var verificationGates: [String]
    public var actionDomainSupported: Bool
    public var operationSupported: Bool
    public var operationMaturity: String?
    public var operationReversible: Bool?
    public var operationPreconditions: [String]
    public var operationEffects: [String]
    public var operationProducedArtifacts: [String]
    public var operationVerificationGates: [String]
    public var objectiveGoalAtoms: [String]
    public var candidateEffectAtoms: [String]
    public var matchedObjectiveGoalAtoms: [String]
    public var missingObjectiveGoalAtoms: [String]
    public var symbolicStateBefore: [String]
    public var symbolicStateAfter: [String]
    public var satisfiedPreconditionAtoms: [String]
    public var unsatisfiedPreconditionAtoms: [String]
    public var selected: Bool
    public var blockedReasons: [String]
    public var reason: String

    public init(
        rank: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        maturity: String,
        score: Int,
        scoreBeforeRejectedFeedback: Int? = nil,
        rejectedFeedbackScoreDelta: Int = 0,
        rankBeforeRejectedFeedback: Int? = nil,
        rejectedFeedbackRankDelta: Int = 0,
        scoreComponents: [XcircuiteSymbolicPlannerScoreComponent],
        requiredInputRefs: [String],
        missingInputRefs: [String],
        verificationGates: [String],
        actionDomainSupported: Bool,
        operationSupported: Bool,
        operationMaturity: String? = nil,
        operationReversible: Bool? = nil,
        operationPreconditions: [String] = [],
        operationEffects: [String] = [],
        operationProducedArtifacts: [String] = [],
        operationVerificationGates: [String] = [],
        objectiveGoalAtoms: [String] = [],
        candidateEffectAtoms: [String] = [],
        matchedObjectiveGoalAtoms: [String] = [],
        missingObjectiveGoalAtoms: [String] = [],
        symbolicStateBefore: [String] = [],
        symbolicStateAfter: [String] = [],
        satisfiedPreconditionAtoms: [String] = [],
        unsatisfiedPreconditionAtoms: [String] = [],
        selected: Bool,
        blockedReasons: [String],
        reason: String
    ) {
        self.rank = rank
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.maturity = maturity
        self.score = score
        self.scoreBeforeRejectedFeedback = scoreBeforeRejectedFeedback ?? score
        self.rejectedFeedbackScoreDelta = rejectedFeedbackScoreDelta
        self.rankBeforeRejectedFeedback = rankBeforeRejectedFeedback ?? rank
        self.rejectedFeedbackRankDelta = rejectedFeedbackRankDelta
        self.scoreComponents = scoreComponents
        self.requiredInputRefs = requiredInputRefs
        self.missingInputRefs = missingInputRefs
        self.verificationGates = verificationGates
        self.actionDomainSupported = actionDomainSupported
        self.operationSupported = operationSupported
        self.operationMaturity = operationMaturity
        self.operationReversible = operationReversible
        self.operationPreconditions = operationPreconditions
        self.operationEffects = operationEffects
        self.operationProducedArtifacts = operationProducedArtifacts
        self.operationVerificationGates = operationVerificationGates
        self.objectiveGoalAtoms = objectiveGoalAtoms
        self.candidateEffectAtoms = candidateEffectAtoms
        self.matchedObjectiveGoalAtoms = matchedObjectiveGoalAtoms
        self.missingObjectiveGoalAtoms = missingObjectiveGoalAtoms
        self.symbolicStateBefore = symbolicStateBefore
        self.symbolicStateAfter = symbolicStateAfter
        self.satisfiedPreconditionAtoms = satisfiedPreconditionAtoms
        self.unsatisfiedPreconditionAtoms = unsatisfiedPreconditionAtoms
        self.selected = selected
        self.blockedReasons = blockedReasons
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case rank
        case actionID
        case domainID
        case operationID
        case maturity
        case score
        case scoreBeforeRejectedFeedback
        case rejectedFeedbackScoreDelta
        case rankBeforeRejectedFeedback
        case rejectedFeedbackRankDelta
        case scoreComponents
        case requiredInputRefs
        case missingInputRefs
        case verificationGates
        case actionDomainSupported
        case operationSupported
        case operationMaturity
        case operationReversible
        case operationPreconditions
        case operationEffects
        case operationProducedArtifacts
        case operationVerificationGates
        case objectiveGoalAtoms
        case candidateEffectAtoms
        case matchedObjectiveGoalAtoms
        case missingObjectiveGoalAtoms
        case symbolicStateBefore
        case symbolicStateAfter
        case satisfiedPreconditionAtoms
        case unsatisfiedPreconditionAtoms
        case selected
        case blockedReasons
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rank = try container.decode(Int.self, forKey: .rank)
        self.actionID = try container.decode(String.self, forKey: .actionID)
        self.domainID = try container.decode(String.self, forKey: .domainID)
        self.operationID = try container.decode(String.self, forKey: .operationID)
        self.maturity = try container.decode(String.self, forKey: .maturity)
        self.score = try container.decode(Int.self, forKey: .score)
        self.scoreBeforeRejectedFeedback = try container.decodeIfPresent(
            Int.self,
            forKey: .scoreBeforeRejectedFeedback
        ) ?? self.score
        self.rejectedFeedbackScoreDelta = try container.decodeIfPresent(
            Int.self,
            forKey: .rejectedFeedbackScoreDelta
        ) ?? 0
        self.rankBeforeRejectedFeedback = try container.decodeIfPresent(
            Int.self,
            forKey: .rankBeforeRejectedFeedback
        ) ?? self.rank
        self.rejectedFeedbackRankDelta = try container.decodeIfPresent(
            Int.self,
            forKey: .rejectedFeedbackRankDelta
        ) ?? 0
        self.scoreComponents = try container.decode([XcircuiteSymbolicPlannerScoreComponent].self, forKey: .scoreComponents)
        self.requiredInputRefs = try container.decode([String].self, forKey: .requiredInputRefs)
        self.missingInputRefs = try container.decode([String].self, forKey: .missingInputRefs)
        self.verificationGates = try container.decode([String].self, forKey: .verificationGates)
        self.actionDomainSupported = try container.decode(Bool.self, forKey: .actionDomainSupported)
        self.operationSupported = try container.decode(Bool.self, forKey: .operationSupported)
        self.operationMaturity = try container.decodeIfPresent(String.self, forKey: .operationMaturity)
        self.operationReversible = try container.decodeIfPresent(Bool.self, forKey: .operationReversible)
        self.operationPreconditions = try container.decodeIfPresent([String].self, forKey: .operationPreconditions) ?? []
        self.operationEffects = try container.decodeIfPresent([String].self, forKey: .operationEffects) ?? []
        self.operationProducedArtifacts = try container.decodeIfPresent([String].self, forKey: .operationProducedArtifacts) ?? []
        self.operationVerificationGates = try container.decodeIfPresent([String].self, forKey: .operationVerificationGates) ?? []
        self.objectiveGoalAtoms = try container.decodeIfPresent([String].self, forKey: .objectiveGoalAtoms) ?? []
        self.candidateEffectAtoms = try container.decodeIfPresent([String].self, forKey: .candidateEffectAtoms) ?? []
        self.matchedObjectiveGoalAtoms = try container.decodeIfPresent([String].self, forKey: .matchedObjectiveGoalAtoms) ?? []
        self.missingObjectiveGoalAtoms = try container.decodeIfPresent([String].self, forKey: .missingObjectiveGoalAtoms) ?? []
        self.symbolicStateBefore = try container.decodeIfPresent([String].self, forKey: .symbolicStateBefore) ?? []
        self.symbolicStateAfter = try container.decodeIfPresent([String].self, forKey: .symbolicStateAfter) ?? []
        self.satisfiedPreconditionAtoms = try container.decodeIfPresent([String].self, forKey: .satisfiedPreconditionAtoms) ?? []
        self.unsatisfiedPreconditionAtoms = try container.decodeIfPresent([String].self, forKey: .unsatisfiedPreconditionAtoms) ?? []
        self.selected = try container.decode(Bool.self, forKey: .selected)
        self.blockedReasons = try container.decode([String].self, forKey: .blockedReasons)
        self.reason = try container.decode(String.self, forKey: .reason)
    }
}
