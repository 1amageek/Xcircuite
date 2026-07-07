import Foundation

public struct XcircuiteParameterCandidateSearchTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var strategy: String
    public var maxCandidates: Int
    public var problemPath: String?
    public var generatedCandidateCount: Int
    public var generatedCandidateIDs: [String]
    public var actionTraces: [XcircuiteParameterCandidateSearchActionTrace]
    public var feedbackTrace: XcircuiteParameterCandidateSearchFeedbackTrace?
    public var calibrationTrace: XcircuiteParameterCandidateCalibrationTrace?
    public var diagnostics: [XcircuiteParameterCandidateDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        strategy: String,
        maxCandidates: Int,
        problemPath: String? = nil,
        generatedCandidateCount: Int,
        generatedCandidateIDs: [String],
        actionTraces: [XcircuiteParameterCandidateSearchActionTrace],
        feedbackTrace: XcircuiteParameterCandidateSearchFeedbackTrace? = nil,
        calibrationTrace: XcircuiteParameterCandidateCalibrationTrace? = nil,
        diagnostics: [XcircuiteParameterCandidateDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.strategy = strategy
        self.maxCandidates = maxCandidates
        self.problemPath = problemPath
        self.generatedCandidateCount = generatedCandidateCount
        self.generatedCandidateIDs = generatedCandidateIDs
        self.actionTraces = actionTraces
        self.feedbackTrace = feedbackTrace
        self.calibrationTrace = calibrationTrace
        self.diagnostics = diagnostics
    }
}
