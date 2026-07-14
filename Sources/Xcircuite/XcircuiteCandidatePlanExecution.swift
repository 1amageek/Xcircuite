import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanExecution: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var planID: String
    public var status: String
    public var candidatePlanRef: XcircuiteFileReference
    public var stepResults: [XcircuiteCandidatePlanExecutionStepResult]
    public var artifactReferences: [ArtifactReference]
    public var executionCoverage: XcircuiteCandidatePlanExecutionCoverage
    public var designDiffRef: XcircuiteFileReference?
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var nextActions: [String]

    public init(
        runID: String,
        problemID: String,
        planID: String,
        status: String,
        candidatePlanRef: XcircuiteFileReference,
        stepResults: [XcircuiteCandidatePlanExecutionStepResult],
        artifactReferences: [ArtifactReference],
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
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.status = status
        self.candidatePlanRef = candidatePlanRef
        self.stepResults = stepResults
        self.artifactReferences = artifactReferences
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
        case artifactReferences
        case artifactRefs
        case executionCoverage
        case designDiffRef
        case diagnostics
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == 1 || decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected candidate plan execution schema version 1 or \(Self.currentSchemaVersion)."
            )
        }
        // Normalize legacy records so the next persistence writes the current schema.
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = try container.decode(String.self, forKey: .runID)
        self.problemID = try container.decode(String.self, forKey: .problemID)
        self.planID = try container.decode(String.self, forKey: .planID)
        self.status = try container.decode(String.self, forKey: .status)
        self.candidatePlanRef = try container.decode(XcircuiteFileReference.self, forKey: .candidatePlanRef)
        self.stepResults = try container.decode(
            [XcircuiteCandidatePlanExecutionStepResult].self,
            forKey: .stepResults
        )
        if container.contains(.artifactReferences) {
            self.artifactReferences = try container.decode(
                [ArtifactReference].self,
                forKey: .artifactReferences
            )
        } else {
            let legacyReferences = try container.decode(
                [XcircuiteFileReference].self,
                forKey: .artifactRefs
            )
            self.artifactReferences = try legacyReferences.enumerated().map { index, reference in
                guard let artifact = foundationArtifactReference(reference) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .artifactRefs,
                        in: container,
                        debugDescription: "Legacy artifact reference at index \(index) cannot be represented as a Foundation artifact."
                    )
                }
                return artifact
            }
        }
        self.executionCoverage = try container.decode(
            XcircuiteCandidatePlanExecutionCoverage.self,
            forKey: .executionCoverage
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
        try container.encode(artifactReferences, forKey: .artifactReferences)
        try container.encode(executionCoverage, forKey: .executionCoverage)
        try container.encodeIfPresent(designDiffRef, forKey: .designDiffRef)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(nextActions, forKey: .nextActions)
    }

    /// Legacy read-only projection retained while stored execution records migrate.
    @available(*, deprecated, message: "Use artifactReferences.")
    public var artifactRefs: [XcircuiteFileReference] {
        artifactReferences.map {
            legacyArtifactReferenceWithProvenance($0, producedByRunID: runID)
        }
    }

    /// Legacy initializer retained for callers that still construct execution records at the storage edge.
    @available(*, deprecated, message: "Use artifactReferences: [ArtifactReference].")
    public init(
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
    ) throws {
        let artifactReferences = try artifactRefs.enumerated().map { index, reference in
            guard let artifact = foundationArtifactReference(reference) else {
                throw XcircuiteCandidatePlanExecutionError.invalidArtifactReference(
                    path: reference.path,
                    reason: "Legacy artifact reference at index \(index) cannot be represented as a Foundation artifact."
                )
            }
            return artifact
        }
        self.init(
            runID: runID,
            problemID: problemID,
            planID: planID,
            status: status,
            candidatePlanRef: candidatePlanRef,
            stepResults: stepResults,
            artifactReferences: artifactReferences,
            executionCoverage: executionCoverage,
            designDiffRef: designDiffRef,
            diagnostics: diagnostics,
            nextActions: nextActions
        )
    }
}
