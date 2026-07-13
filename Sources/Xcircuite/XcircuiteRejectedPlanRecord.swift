import Foundation
import DesignFlowKernel

public struct XcircuiteRejectedPlanRecord: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var rejectionID: String
    public var runID: String
    public var problemID: String
    public var planID: String
    public var verificationMode: String
    public var status: String
    public var sourceParameterCandidateIDs: [String]
    public var failedStepIDs: [String]
    public var failedGateIDs: [String]
    public var candidatePlanRef: XcircuiteFileReference
    public var planVerificationRef: XcircuiteFileReference
    public var artifactRefs: [XcircuiteFileReference]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var diagnosticClassifications: [XcircuiteRejectedPlanDiagnosticClassification]
    public var nextActions: [String]

    public init(
        rejectionID: String,
        runID: String,
        problemID: String,
        planID: String,
        verificationMode: String,
        status: String,
        sourceParameterCandidateIDs: [String],
        failedStepIDs: [String],
        failedGateIDs: [String],
        candidatePlanRef: XcircuiteFileReference,
        planVerificationRef: XcircuiteFileReference,
        artifactRefs: [XcircuiteFileReference],
        diagnostics: [XcircuitePlanVerificationDiagnostic],
        diagnosticClassifications: [XcircuiteRejectedPlanDiagnosticClassification] = [],
        nextActions: [String]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.rejectionID = rejectionID
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.verificationMode = verificationMode
        self.status = status
        self.sourceParameterCandidateIDs = sourceParameterCandidateIDs
        self.failedStepIDs = failedStepIDs
        self.failedGateIDs = failedGateIDs
        self.candidatePlanRef = candidatePlanRef
        self.planVerificationRef = planVerificationRef
        self.artifactRefs = artifactRefs
        self.diagnostics = diagnostics
        self.diagnosticClassifications = diagnosticClassifications
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case rejectionID
        case runID
        case problemID
        case planID
        case verificationMode
        case status
        case sourceParameterCandidateIDs
        case failedStepIDs
        case failedGateIDs
        case candidatePlanRef
        case planVerificationRef
        case artifactRefs
        case diagnostics
        case diagnosticClassifications
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected rejected plan record schema version \(Self.currentSchemaVersion)."
            )
        }
        rejectionID = try container.decode(String.self, forKey: .rejectionID)
        runID = try container.decode(String.self, forKey: .runID)
        problemID = try container.decode(String.self, forKey: .problemID)
        planID = try container.decode(String.self, forKey: .planID)
        verificationMode = try container.decode(String.self, forKey: .verificationMode)
        status = try container.decode(String.self, forKey: .status)
        sourceParameterCandidateIDs = try container.decode([String].self, forKey: .sourceParameterCandidateIDs)
        failedStepIDs = try container.decode([String].self, forKey: .failedStepIDs)
        failedGateIDs = try container.decode([String].self, forKey: .failedGateIDs)
        candidatePlanRef = try container.decode(XcircuiteFileReference.self, forKey: .candidatePlanRef)
        planVerificationRef = try container.decode(XcircuiteFileReference.self, forKey: .planVerificationRef)
        artifactRefs = try container.decode([XcircuiteFileReference].self, forKey: .artifactRefs)
        diagnostics = try container.decode([XcircuitePlanVerificationDiagnostic].self, forKey: .diagnostics)
        diagnosticClassifications = try container.decode(
            [XcircuiteRejectedPlanDiagnosticClassification].self,
            forKey: .diagnosticClassifications
        )
        nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(rejectionID, forKey: .rejectionID)
        try container.encode(runID, forKey: .runID)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(planID, forKey: .planID)
        try container.encode(verificationMode, forKey: .verificationMode)
        try container.encode(status, forKey: .status)
        try container.encode(sourceParameterCandidateIDs, forKey: .sourceParameterCandidateIDs)
        try container.encode(failedStepIDs, forKey: .failedStepIDs)
        try container.encode(failedGateIDs, forKey: .failedGateIDs)
        try container.encode(candidatePlanRef, forKey: .candidatePlanRef)
        try container.encode(planVerificationRef, forKey: .planVerificationRef)
        try container.encode(artifactRefs, forKey: .artifactRefs)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(diagnosticClassifications, forKey: .diagnosticClassifications)
        try container.encode(nextActions, forKey: .nextActions)
    }
}
