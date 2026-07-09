import Foundation

public struct OpAmpLayoutConstraintPlan: Sendable, Hashable, Codable {
    public enum ConstraintKind: String, Sendable, Hashable, Codable {
        case symmetry
        case matching
        case commonCentroid
        case interdigitated
        case guardRing
        case shielding
        case proximity
    }

    public struct Constraint: Sendable, Hashable, Codable {
        public var constraintID: String
        public var kind: ConstraintKind
        public var members: [String]
        public var pattern: [String]
        public var isHard: Bool
        public var rationale: String

        public init(
            constraintID: String,
            kind: ConstraintKind,
            members: [String],
            pattern: [String] = [],
            isHard: Bool = true,
            rationale: String
        ) {
            self.constraintID = constraintID
            self.kind = kind
            self.members = members
            self.pattern = pattern
            self.isHard = isHard
            self.rationale = rationale
        }
    }

    public var planID: String
    public var topologyID: String
    public var constraints: [Constraint]
    public var notes: [String]

    public init(
        planID: String,
        topologyID: String,
        constraints: [Constraint],
        notes: [String] = []
    ) {
        self.planID = planID
        self.topologyID = topologyID
        self.constraints = constraints
        self.notes = notes
    }
}
