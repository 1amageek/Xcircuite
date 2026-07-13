import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteNumericRepairLoopPolicyTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var iterationIndex: Int
    public var calibrationPolicy: String
    public var baseCandidateStrategy: String
    public var selectedCandidateStrategy: String
    public var usesCalibrationArtifacts: Bool
    public var sourceIterationIndexes: [Int]
    public var metricThresholdProfileArtifact: ArtifactReference?
    public var costCalibrationArtifact: ArtifactReference?
    public var paretoCandidatesArtifact: ArtifactReference?
    public var improvementLoopArtifact: ArtifactReference?
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
        metricThresholdProfileArtifact: ArtifactReference? = nil,
        costCalibrationArtifact: ArtifactReference? = nil,
        paretoCandidatesArtifact: ArtifactReference? = nil,
        improvementLoopArtifact: ArtifactReference? = nil,
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
