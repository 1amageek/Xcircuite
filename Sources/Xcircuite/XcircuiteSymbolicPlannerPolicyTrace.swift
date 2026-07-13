import Foundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPolicyTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var calibrationPolicy: String
    public var baseStrategy: String
    public var selectedStrategy: String
    public var usesCalibrationArtifacts: Bool
    public var metricThresholdProfileArtifact: XcircuiteFileReference?
    public var costCalibrationArtifact: XcircuiteFileReference?
    public var paretoCandidatesArtifact: XcircuiteFileReference?
    public var reasonCodes: [String]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        calibrationPolicy: String,
        baseStrategy: String,
        selectedStrategy: String,
        usesCalibrationArtifacts: Bool,
        metricThresholdProfileArtifact: XcircuiteFileReference? = nil,
        costCalibrationArtifact: XcircuiteFileReference? = nil,
        paretoCandidatesArtifact: XcircuiteFileReference? = nil,
        reasonCodes: [String] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.calibrationPolicy = calibrationPolicy
        self.baseStrategy = baseStrategy
        self.selectedStrategy = selectedStrategy
        self.usesCalibrationArtifacts = usesCalibrationArtifacts
        self.metricThresholdProfileArtifact = metricThresholdProfileArtifact
        self.costCalibrationArtifact = costCalibrationArtifact
        self.paretoCandidatesArtifact = paretoCandidatesArtifact
        self.reasonCodes = reasonCodes
        self.diagnostics = diagnostics
    }
}
