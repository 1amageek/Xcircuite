import Foundation

public struct XcircuiteSymbolicPlannerGoalCoverage: Codable, Sendable, Hashable {
    public var objectiveID: String
    public var goalAtoms: [String]
    public var satisfiedGoalAtoms: [String]
    public var missingGoalAtoms: [String]
    public var status: String

    public init(
        objectiveID: String,
        goalAtoms: [String],
        satisfiedGoalAtoms: [String],
        missingGoalAtoms: [String],
        status: String
    ) {
        self.objectiveID = objectiveID
        self.goalAtoms = goalAtoms
        self.satisfiedGoalAtoms = satisfiedGoalAtoms
        self.missingGoalAtoms = missingGoalAtoms
        self.status = status
    }
}
