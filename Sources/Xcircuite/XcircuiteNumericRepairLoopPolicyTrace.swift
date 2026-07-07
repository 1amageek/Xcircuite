import Foundation
import XcircuitePackage

public struct XcircuiteNumericRepairLoopPolicyTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var iterationIndex: Int
    public var calibrationPolicy: String
    public var baseCandidateStrategy: String
    public var selectedCandidateStrategy: String
    public var usesCalibrationArtifacts: Bool
    public var sourceIterationIndexes: [Int]
    public var metricThresholdProfileArtifact: XcircuiteFileReference?
    public var costCalibrationArtifact: XcircuiteFileReference?
    public var paretoCandidatesArtifact: XcircuiteFileReference?
    public var improvementLoopArtifact: XcircuiteFileReference?
    public var reasonCodes: [String]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        iterationIndex: Int,
        calibrationPolicy: String,
        baseCandidateStrategy: String,
        selectedCandidateStrategy: String,
        usesCalibrationArtifacts: Bool,
        sourceIterationIndexes: [Int] = [],
        metricThresholdProfileArtifact: XcircuiteFileReference? = nil,
        costCalibrationArtifact: XcircuiteFileReference? = nil,
        paretoCandidatesArtifact: XcircuiteFileReference? = nil,
        improvementLoopArtifact: XcircuiteFileReference? = nil,
        reasonCodes: [String] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.iterationIndex = iterationIndex
        self.calibrationPolicy = calibrationPolicy
        self.baseCandidateStrategy = baseCandidateStrategy
        self.selectedCandidateStrategy = selectedCandidateStrategy
        self.usesCalibrationArtifacts = usesCalibrationArtifacts
        self.sourceIterationIndexes = sourceIterationIndexes
        self.metricThresholdProfileArtifact = metricThresholdProfileArtifact
        self.costCalibrationArtifact = costCalibrationArtifact
        self.paretoCandidatesArtifact = paretoCandidatesArtifact
        self.improvementLoopArtifact = improvementLoopArtifact
        self.reasonCodes = reasonCodes
        self.diagnostics = diagnostics
    }
}
