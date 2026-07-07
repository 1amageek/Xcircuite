import Foundation
import XcircuitePackage

public struct XcircuiteParameterCandidateGenerationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var strategy: String
    public var candidateCount: Int
    public var problemPath: String
    public var parameterCandidatesArtifact: XcircuiteFileReference?
    public var searchTrace: XcircuiteParameterCandidateSearchTrace?
    public var searchTraceArtifact: XcircuiteFileReference?
    public var diagnostics: [XcircuiteParameterCandidateDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        strategy: String,
        candidateCount: Int,
        problemPath: String,
        parameterCandidatesArtifact: XcircuiteFileReference?,
        searchTrace: XcircuiteParameterCandidateSearchTrace? = nil,
        searchTraceArtifact: XcircuiteFileReference? = nil,
        diagnostics: [XcircuiteParameterCandidateDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.strategy = strategy
        self.candidateCount = candidateCount
        self.problemPath = problemPath
        self.parameterCandidatesArtifact = parameterCandidatesArtifact
        self.searchTrace = searchTrace
        self.searchTraceArtifact = searchTraceArtifact
        self.diagnostics = diagnostics
    }
}
