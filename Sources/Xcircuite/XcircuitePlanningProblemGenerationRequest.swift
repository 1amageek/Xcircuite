import Foundation

public struct XcircuitePlanningProblemGenerationRequest: Sendable, Hashable {
    public var runID: String
    public var source: XcircuitePlanningProblemSource
    public var summaryArtifactID: String?
    public var summaryPath: String?
    public var layoutArtifactID: String?
    public var layoutPath: String?
    public var layoutNetlistPath: String?
    public var schematicNetlistPath: String?
    public var sourceNetlistPath: String?
    public var technologyArtifactID: String?
    public var technologyPath: String?
    public var metricReportPath: String?
    public var repairHintArtifactID: String?
    public var repairHintPath: String?
    public var actionDomainArtifactID: String?
    public var actionDomainPath: String?

    public init(
        runID: String,
        source: XcircuitePlanningProblemSource,
        summaryArtifactID: String? = nil,
        summaryPath: String? = nil,
        layoutArtifactID: String? = nil,
        layoutPath: String? = nil,
        layoutNetlistPath: String? = nil,
        schematicNetlistPath: String? = nil,
        sourceNetlistPath: String? = nil,
        technologyArtifactID: String? = nil,
        technologyPath: String? = nil,
        metricReportPath: String? = nil,
        repairHintArtifactID: String? = nil,
        repairHintPath: String? = nil,
        actionDomainArtifactID: String? = nil,
        actionDomainPath: String? = nil
    ) {
        self.runID = runID
        self.source = source
        self.summaryArtifactID = summaryArtifactID
        self.summaryPath = summaryPath
        self.layoutArtifactID = layoutArtifactID
        self.layoutPath = layoutPath
        self.layoutNetlistPath = layoutNetlistPath
        self.schematicNetlistPath = schematicNetlistPath
        self.sourceNetlistPath = sourceNetlistPath
        self.technologyArtifactID = technologyArtifactID
        self.technologyPath = technologyPath
        self.metricReportPath = metricReportPath
        self.repairHintArtifactID = repairHintArtifactID
        self.repairHintPath = repairHintPath
        self.actionDomainArtifactID = actionDomainArtifactID
        self.actionDomainPath = actionDomainPath
    }
}
