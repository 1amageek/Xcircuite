import Foundation
import XcircuitePackage

public struct XcircuiteCandidatePlanExecution: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var planID: String
    public var status: String
    public var candidatePlanRef: XcircuiteFileReference
    public var stepResults: [XcircuiteCandidatePlanExecutionStepResult]
    public var artifactRefs: [XcircuiteFileReference]
    public var executionCoverage: XcircuiteCandidatePlanExecutionCoverage
    public var designDiffRef: XcircuiteFileReference?
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        planID: String,
        status: String,
        candidatePlanRef: XcircuiteFileReference,
        stepResults: [XcircuiteCandidatePlanExecutionStepResult],
        artifactRefs: [XcircuiteFileReference],
        executionCoverage: XcircuiteCandidatePlanExecutionCoverage = XcircuiteCandidatePlanExecutionCoverage(
            status: "not-evaluated",
            requiredFamilyIDs: [],
            coveredFamilyIDs: [],
            missingFamilyIDs: [],
            familyCoverage: [],
            producedArtifactIDs: []
        ),
        designDiffRef: XcircuiteFileReference? = nil,
        diagnostics: [XcircuitePlanVerificationDiagnostic],
        nextActions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.status = status
        self.candidatePlanRef = candidatePlanRef
        self.stepResults = stepResults
        self.artifactRefs = artifactRefs
        self.executionCoverage = executionCoverage
        self.designDiffRef = designDiffRef
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case problemID
        case planID
        case status
        case candidatePlanRef
        case stepResults
        case artifactRefs
        case executionCoverage
        case designDiffRef
        case diagnostics
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.runID = try container.decode(String.self, forKey: .runID)
        self.problemID = try container.decode(String.self, forKey: .problemID)
        self.planID = try container.decode(String.self, forKey: .planID)
        self.status = try container.decode(String.self, forKey: .status)
        self.candidatePlanRef = try container.decode(XcircuiteFileReference.self, forKey: .candidatePlanRef)
        self.stepResults = try container.decode(
            [XcircuiteCandidatePlanExecutionStepResult].self,
            forKey: .stepResults
        )
        self.artifactRefs = try container.decode([XcircuiteFileReference].self, forKey: .artifactRefs)
        self.executionCoverage = try container.decodeIfPresent(
            XcircuiteCandidatePlanExecutionCoverage.self,
            forKey: .executionCoverage
        ) ?? XcircuiteCandidatePlanExecutionCoverage(
            status: "not-evaluated",
            requiredFamilyIDs: [],
            coveredFamilyIDs: [],
            missingFamilyIDs: [],
            familyCoverage: [],
            producedArtifactIDs: []
        )
        self.designDiffRef = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .designDiffRef)
        self.diagnostics = try container.decode([XcircuitePlanVerificationDiagnostic].self, forKey: .diagnostics)
        self.nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(runID, forKey: .runID)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(planID, forKey: .planID)
        try container.encode(status, forKey: .status)
        try container.encode(candidatePlanRef, forKey: .candidatePlanRef)
        try container.encode(stepResults, forKey: .stepResults)
        try container.encode(artifactRefs, forKey: .artifactRefs)
        try container.encode(executionCoverage, forKey: .executionCoverage)
        try container.encodeIfPresent(designDiffRef, forKey: .designDiffRef)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
