import Foundation

public struct XcircuiteCostCalibrationReport: Codable, Sendable, Hashable {
    public struct Term: Codable, Sendable, Hashable {
        public var termID: String
        public var gateID: String?
        public var baseWeight: Double
        public var calibratedWeight: Double
        public var evidenceCount: Int
        public var rationale: String

        public init(
            termID: String,
            gateID: String? = nil,
            baseWeight: Double,
            calibratedWeight: Double,
            evidenceCount: Int,
            rationale: String
        ) {
            self.termID = termID
            self.gateID = gateID
            self.baseWeight = baseWeight
            self.calibratedWeight = calibratedWeight
            self.evidenceCount = evidenceCount
            self.rationale = rationale
        }
    }

    public struct Observation: Codable, Sendable, Hashable {
        public var candidateID: String
        public var accepted: Bool
        public var selectedTotalScore: Double?
        public var failedGateIDs: [String]
        public var sourceArtifactIDs: [String]

        public init(
            candidateID: String,
            accepted: Bool,
            selectedTotalScore: Double? = nil,
            failedGateIDs: [String] = [],
            sourceArtifactIDs: [String] = []
        ) {
            self.candidateID = candidateID
            self.accepted = accepted
            self.selectedTotalScore = selectedTotalScore
            self.failedGateIDs = failedGateIDs
            self.sourceArtifactIDs = sourceArtifactIDs
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var problemID: String?
    public var calibrationID: String
    public var generatedAt: String
    public var thresholdProfileArtifactID: String?
    public var inputArtifactIDs: [String]
    public var calibratedTerms: [Term]
    public var observations: [Observation]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String? = nil,
        calibrationID: String,
        generatedAt: String,
        thresholdProfileArtifactID: String? = nil,
        inputArtifactIDs: [String] = [],
        calibratedTerms: [Term],
        observations: [Observation] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.calibrationID = calibrationID
        self.generatedAt = generatedAt
        self.thresholdProfileArtifactID = thresholdProfileArtifactID
        self.inputArtifactIDs = inputArtifactIDs
        self.calibratedTerms = calibratedTerms
        self.observations = observations
        self.diagnostics = diagnostics
    }
}
