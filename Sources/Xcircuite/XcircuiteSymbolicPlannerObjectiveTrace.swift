import Foundation

public struct XcircuiteSymbolicPlannerObjectiveTrace: Codable, Sendable, Hashable {
    public var objectiveID: String
    public var selectedActionID: String?
    public var unresolvedReason: String?
    public var candidateActions: [XcircuiteSymbolicPlannerActionTrace]

    public init(
        objectiveID: String,
        selectedActionID: String? = nil,
        unresolvedReason: String? = nil,
        candidateActions: [XcircuiteSymbolicPlannerActionTrace]
    ) {
        self.objectiveID = objectiveID
        self.selectedActionID = selectedActionID
        self.unresolvedReason = unresolvedReason
        self.candidateActions = candidateActions
    }
}
