public struct XcircuiteProblemTranslationAuditRequest: Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
    }
}
