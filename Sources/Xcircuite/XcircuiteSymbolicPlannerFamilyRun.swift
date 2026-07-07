import Foundation
import XcircuitePackage

public struct XcircuiteSymbolicPlannerFamilyRun: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var familyRunID: String
    public var problemID: String
    public var problemPath: String
    public var selectionPolicy: String
    public var calibrationPolicy: String
    public var requestedStrategies: [String]
    public var selectedCandidateIndex: Int
    public var selectedStrategy: String
    public var selectedPlanID: String
    public var selectedCandidatePlanArtifact: XcircuiteFileReference
    public var selectedSymbolicPlannerTraceArtifact: XcircuiteFileReference
    public var promotedCandidatePlanArtifact: XcircuiteFileReference
    public var promotedSymbolicPlannerTraceArtifact: XcircuiteFileReference
    public var candidates: [XcircuiteSymbolicPlannerFamilyCandidateResult]
    public var diagnostics: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        familyRunID: String,
        problemID: String,
        problemPath: String,
        selectionPolicy: String,
        calibrationPolicy: String,
        requestedStrategies: [String],
        selectedCandidateIndex: Int,
        selectedStrategy: String,
        selectedPlanID: String,
        selectedCandidatePlanArtifact: XcircuiteFileReference,
        selectedSymbolicPlannerTraceArtifact: XcircuiteFileReference,
        promotedCandidatePlanArtifact: XcircuiteFileReference,
        promotedSymbolicPlannerTraceArtifact: XcircuiteFileReference,
        candidates: [XcircuiteSymbolicPlannerFamilyCandidateResult],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.familyRunID = familyRunID
        self.problemID = problemID
        self.problemPath = problemPath
        self.selectionPolicy = selectionPolicy
        self.calibrationPolicy = calibrationPolicy
        self.requestedStrategies = requestedStrategies
        self.selectedCandidateIndex = selectedCandidateIndex
        self.selectedStrategy = selectedStrategy
        self.selectedPlanID = selectedPlanID
        self.selectedCandidatePlanArtifact = selectedCandidatePlanArtifact
        self.selectedSymbolicPlannerTraceArtifact = selectedSymbolicPlannerTraceArtifact
        self.promotedCandidatePlanArtifact = promotedCandidatePlanArtifact
        self.promotedSymbolicPlannerTraceArtifact = promotedSymbolicPlannerTraceArtifact
        self.candidates = candidates
        self.diagnostics = diagnostics
    }
}
