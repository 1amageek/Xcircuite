import ToolQualification
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverCorpusQualificationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var status: String
    public var toolID: String
    public var policyID: String
    public var caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult]
    public var qualifiedCaseCount: Int
    public var failedCaseCount: Int
    public var requiredCoverageTags: [String]
    public var coveredCoverageTags: [String]
    public var missingRequiredCoverageTags: [String]
    public var coverageTagCounts: [String: Int]
    public var failureCodes: [String]
    public var suiteSpecArtifact: XcircuiteFileReference?
    public var corpusArtifact: XcircuiteFileReference?
    public var toolHealth: ToolHealthCheckResult

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        status: String,
        toolID: String,
        policyID: String,
        caseResults: [XcircuiteSymbolicPlannerSolverCorpusCaseResult],
        qualifiedCaseCount: Int,
        failedCaseCount: Int,
        requiredCoverageTags: [String] = [],
        coveredCoverageTags: [String] = [],
        missingRequiredCoverageTags: [String] = [],
        coverageTagCounts: [String: Int] = [:],
        failureCodes: [String],
        suiteSpecArtifact: XcircuiteFileReference? = nil,
        corpusArtifact: XcircuiteFileReference? = nil,
        toolHealth: ToolHealthCheckResult
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.toolID = toolID
        self.policyID = policyID
        self.caseResults = caseResults
        self.qualifiedCaseCount = qualifiedCaseCount
        self.failedCaseCount = failedCaseCount
        self.requiredCoverageTags = requiredCoverageTags
        self.coveredCoverageTags = coveredCoverageTags
        self.missingRequiredCoverageTags = missingRequiredCoverageTags
        self.coverageTagCounts = coverageTagCounts
        self.failureCodes = failureCodes
        self.suiteSpecArtifact = suiteSpecArtifact
        self.corpusArtifact = corpusArtifact
        self.toolHealth = toolHealth
    }
}
