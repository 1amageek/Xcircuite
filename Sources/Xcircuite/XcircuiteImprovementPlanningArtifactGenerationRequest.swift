import Foundation

public struct XcircuiteImprovementPlanningArtifactGenerationRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var numericRepairLoopArtifactID: String?
    public var numericRepairLoopPath: String?
    public var generatedAt: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        numericRepairLoopArtifactID: String? = nil,
        numericRepairLoopPath: String? = nil,
        generatedAt: String? = nil
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.numericRepairLoopArtifactID = numericRepairLoopArtifactID
        self.numericRepairLoopPath = numericRepairLoopPath
        self.generatedAt = generatedAt
    }
}
