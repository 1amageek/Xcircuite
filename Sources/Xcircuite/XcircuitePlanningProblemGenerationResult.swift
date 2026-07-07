import Foundation
import XcircuitePackage

public struct XcircuitePlanningProblemGenerationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var source: XcircuitePlanningProblemSource
    public var problemID: String
    public var summaryPath: String
    public var layoutPath: String?
    public var layoutNetlistPath: String?
    public var schematicNetlistPath: String?
    public var sourceNetlistPath: String?
    public var technologyPath: String?
    public var metricReportPath: String?
    public var repairHintPath: String?
    public var actionDomainPath: String?
    public var problemArtifact: XcircuiteFileReference

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        source: XcircuitePlanningProblemSource,
        problemID: String,
        summaryPath: String,
        layoutPath: String?,
        layoutNetlistPath: String? = nil,
        schematicNetlistPath: String?,
        sourceNetlistPath: String?,
        technologyPath: String?,
        metricReportPath: String?,
        repairHintPath: String? = nil,
        actionDomainPath: String?,
        problemArtifact: XcircuiteFileReference
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.source = source
        self.problemID = problemID
        self.summaryPath = summaryPath
        self.layoutPath = layoutPath
        self.layoutNetlistPath = layoutNetlistPath
        self.schematicNetlistPath = schematicNetlistPath
        self.sourceNetlistPath = sourceNetlistPath
        self.technologyPath = technologyPath
        self.metricReportPath = metricReportPath
        self.repairHintPath = repairHintPath
        self.actionDomainPath = actionDomainPath
        self.problemArtifact = problemArtifact
    }
}
