import Foundation

public struct XcircuiteImprovementLoopResult: Codable, Sendable, Hashable {
    public struct Iteration: Codable, Sendable, Hashable {
        public var iterationIndex: Int
        public var status: String
        public var selectedCandidateID: String?
        public var accepted: Bool
        public var producedArtifactIDs: [String]
        public var failedGateIDs: [String]

        public init(
            iterationIndex: Int,
            status: String,
            selectedCandidateID: String? = nil,
            accepted: Bool,
            producedArtifactIDs: [String] = [],
            failedGateIDs: [String] = []
        ) {
            self.iterationIndex = iterationIndex
            self.status = status
            self.selectedCandidateID = selectedCandidateID
            self.accepted = accepted
            self.producedArtifactIDs = producedArtifactIDs
            self.failedGateIDs = failedGateIDs
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var problemID: String?
    public var loopID: String
    public var status: String
    public var thresholdProfileArtifactID: String?
    public var costCalibrationArtifactID: String?
    public var paretoCandidateArtifactID: String?
    public var iterationCount: Int
    public var acceptedCandidateID: String?
    public var iterations: [Iteration]
    public var diagnostics: [String]
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String? = nil,
        loopID: String,
        status: String,
        thresholdProfileArtifactID: String? = nil,
        costCalibrationArtifactID: String? = nil,
        paretoCandidateArtifactID: String? = nil,
        iterationCount: Int,
        acceptedCandidateID: String? = nil,
        iterations: [Iteration],
        diagnostics: [String] = [],
        nextActions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.loopID = loopID
        self.status = status
        self.thresholdProfileArtifactID = thresholdProfileArtifactID
        self.costCalibrationArtifactID = costCalibrationArtifactID
        self.paretoCandidateArtifactID = paretoCandidateArtifactID
        self.iterationCount = iterationCount
        self.acceptedCandidateID = acceptedCandidateID
        self.iterations = iterations
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
