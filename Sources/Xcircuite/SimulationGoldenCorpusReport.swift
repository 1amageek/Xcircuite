import CircuiteFoundation

public struct SimulationGoldenCorpusReport: Codable, Sendable, Hashable {
    public struct Summary: Codable, Sendable, Hashable {
        public var caseCount: Int
        public var passedCaseCount: Int
        public var failedCaseCount: Int
        public var coverageTagCount: Int

        public init(
            caseCount: Int,
            passedCaseCount: Int,
            failedCaseCount: Int,
            coverageTagCount: Int
        ) {
            self.caseCount = caseCount
            self.passedCaseCount = passedCaseCount
            self.failedCaseCount = failedCaseCount
            self.coverageTagCount = coverageTagCount
        }
    }

    public struct CaseResult: Codable, Sendable, Hashable {
        public var caseID: String
        public var status: String
        public var expectedGateStatus: String
        public var observedGateStatus: String?
        public var analysisLabel: String?
        public var coverageTags: [String]
        public var comparison: SimulationGoldenComparisonReport?
        public var candidateWaveformArtifact: ArtifactReference?
        public var comparisonArtifact: ArtifactReference?
        public var diagnostics: [String]

        public init(
            caseID: String,
            status: String,
            expectedGateStatus: String,
            observedGateStatus: String?,
            analysisLabel: String?,
            coverageTags: [String],
            comparison: SimulationGoldenComparisonReport?,
            candidateWaveformArtifact: ArtifactReference?,
            comparisonArtifact: ArtifactReference?,
            diagnostics: [String]
        ) {
            self.caseID = caseID
            self.status = status
            self.expectedGateStatus = expectedGateStatus
            self.observedGateStatus = observedGateStatus
            self.analysisLabel = analysisLabel
            self.coverageTags = coverageTags
            self.comparison = comparison
            self.candidateWaveformArtifact = candidateWaveformArtifact
            self.comparisonArtifact = comparisonArtifact
            self.diagnostics = diagnostics
        }
    }

    public var schemaVersion: Int
    public var suiteID: String
    public var status: String
    public var summary: Summary
    public var coverageTags: [String]
    public var cases: [CaseResult]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 2,
        suiteID: String,
        status: String,
        summary: Summary,
        coverageTags: [String],
        cases: [CaseResult],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.coverageTags = coverageTags
        self.cases = cases
        self.diagnostics = diagnostics
    }
}
