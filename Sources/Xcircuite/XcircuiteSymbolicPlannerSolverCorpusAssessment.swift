import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverCorpusAssessment: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var status: String
    public var toolID: String
    public var policyID: String
    public var caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult]
    public var passedCaseCount: Int
    public var failedCaseCount: Int
    public var requiredCoverageTags: [String]
    public var coveredCoverageTags: [String]
    public var missingRequiredCoverageTags: [String]
    public var coverageTagCounts: [String: Int]
    public var failureCodes: [String]
    public var suiteSpecArtifact: ArtifactReference?
    public var corpusArtifact: ArtifactReference?

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        status: String,
        toolID: String,
        policyID: String,
        caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult],
        passedCaseCount: Int,
        failedCaseCount: Int,
        requiredCoverageTags: [String] = [],
        coveredCoverageTags: [String] = [],
        missingRequiredCoverageTags: [String] = [],
        coverageTagCounts: [String: Int] = [:],
        failureCodes: [String],
        suiteSpecArtifact: ArtifactReference? = nil,
        corpusArtifact: ArtifactReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.toolID = toolID
        self.policyID = policyID
        self.caseResults = caseResults
        self.passedCaseCount = passedCaseCount
        self.failedCaseCount = failedCaseCount
        self.requiredCoverageTags = requiredCoverageTags
        self.coveredCoverageTags = coveredCoverageTags
        self.missingRequiredCoverageTags = missingRequiredCoverageTags
        self.coverageTagCounts = coverageTagCounts
        self.failureCodes = failureCodes
        self.suiteSpecArtifact = suiteSpecArtifact
        self.corpusArtifact = corpusArtifact
    }
}
import CircuiteFoundation
