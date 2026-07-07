import Foundation

public struct XcircuiteParameterCandidateSearchActionTrace: Codable, Sendable, Hashable {
    public var actionID: String
    public var operationID: String
    public var sourceObjectiveIDs: [String]
    public var parameterTraces: [XcircuiteParameterCandidateSearchParameterTrace]

    public init(
        actionID: String,
        operationID: String,
        sourceObjectiveIDs: [String],
        parameterTraces: [XcircuiteParameterCandidateSearchParameterTrace]
    ) {
        self.actionID = actionID
        self.operationID = operationID
        self.sourceObjectiveIDs = sourceObjectiveIDs
        self.parameterTraces = parameterTraces
    }
}
