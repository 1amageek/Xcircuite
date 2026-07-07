import Foundation

public struct XcircuiteSymbolicPlannerPDDLExportRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var actionDomainArtifactID: String?
    public var actionDomainPath: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        actionDomainArtifactID: String? = nil,
        actionDomainPath: String? = nil
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.actionDomainArtifactID = actionDomainArtifactID
        self.actionDomainPath = actionDomainPath
    }
}
