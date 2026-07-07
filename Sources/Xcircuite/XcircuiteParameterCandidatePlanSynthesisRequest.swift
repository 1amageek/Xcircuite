import Foundation

public struct XcircuiteParameterCandidatePlanSynthesisRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var parameterCandidatesArtifactID: String?
    public var parameterCandidatesPath: String?
    public var rejectedPlansArtifactID: String?
    public var rejectedPlansPath: String?
    public var candidateID: String?
    public var rank: Int?
    public var strategy: String
    public var includeRejectedCandidates: Bool

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        parameterCandidatesArtifactID: String? = nil,
        parameterCandidatesPath: String? = nil,
        rejectedPlansArtifactID: String? = nil,
        rejectedPlansPath: String? = nil,
        candidateID: String? = nil,
        rank: Int? = nil,
        strategy: String = "parameter-candidate-to-netlist-edit",
        includeRejectedCandidates: Bool = false
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.parameterCandidatesArtifactID = parameterCandidatesArtifactID
        self.parameterCandidatesPath = parameterCandidatesPath
        self.rejectedPlansArtifactID = rejectedPlansArtifactID
        self.rejectedPlansPath = rejectedPlansPath
        self.candidateID = candidateID
        self.rank = rank
        self.strategy = strategy
        self.includeRejectedCandidates = includeRejectedCandidates
    }
}
