import Foundation
import XcircuitePackage

public struct XcircuitePlanningProblemValidation: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String
    public var problemPath: String
    public var problemTranslationAuditArtifactID: String?
    public var problemTranslationAuditPath: String?
    public var actionDomainSnapshotArtifactID: String?
    public var actionDomainSnapshotPath: String?
    public var sourceRefCount: Int
    public var initialStateRefCount: Int
    public var assumptionCount: Int
    public var riskClassificationCount: Int
    public var objectiveCount: Int
    public var candidateActionCount: Int
    public var verificationGateCount: Int
    public var diagnostics: [XcircuitePlanningProblemValidationDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String,
        problemPath: String,
        problemTranslationAuditArtifactID: String? = nil,
        problemTranslationAuditPath: String? = nil,
        actionDomainSnapshotArtifactID: String? = nil,
        actionDomainSnapshotPath: String? = nil,
        sourceRefCount: Int,
        initialStateRefCount: Int,
        assumptionCount: Int = 0,
        riskClassificationCount: Int = 0,
        objectiveCount: Int,
        candidateActionCount: Int,
        verificationGateCount: Int,
        diagnostics: [XcircuitePlanningProblemValidationDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.problemPath = problemPath
        self.problemTranslationAuditArtifactID = problemTranslationAuditArtifactID
        self.problemTranslationAuditPath = problemTranslationAuditPath
        self.actionDomainSnapshotArtifactID = actionDomainSnapshotArtifactID
        self.actionDomainSnapshotPath = actionDomainSnapshotPath
        self.sourceRefCount = sourceRefCount
        self.initialStateRefCount = initialStateRefCount
        self.assumptionCount = assumptionCount
        self.riskClassificationCount = riskClassificationCount
        self.objectiveCount = objectiveCount
        self.candidateActionCount = candidateActionCount
        self.verificationGateCount = verificationGateCount
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case runID
        case problemID
        case problemPath
        case problemTranslationAuditArtifactID
        case problemTranslationAuditPath
        case actionDomainSnapshotArtifactID
        case actionDomainSnapshotPath
        case sourceRefCount
        case initialStateRefCount
        case assumptionCount
        case riskClassificationCount
        case objectiveCount
        case candidateActionCount
        case verificationGateCount
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        status = try container.decode(String.self, forKey: .status)
        runID = try container.decode(String.self, forKey: .runID)
        problemID = try container.decode(String.self, forKey: .problemID)
        problemPath = try container.decode(String.self, forKey: .problemPath)
        problemTranslationAuditArtifactID = try container.decodeIfPresent(
            String.self,
            forKey: .problemTranslationAuditArtifactID
        )
        problemTranslationAuditPath = try container.decodeIfPresent(
            String.self,
            forKey: .problemTranslationAuditPath
        )
        actionDomainSnapshotArtifactID = try container.decodeIfPresent(
            String.self,
            forKey: .actionDomainSnapshotArtifactID
        )
        actionDomainSnapshotPath = try container.decodeIfPresent(String.self, forKey: .actionDomainSnapshotPath)
        sourceRefCount = try container.decode(Int.self, forKey: .sourceRefCount)
        initialStateRefCount = try container.decode(Int.self, forKey: .initialStateRefCount)
        assumptionCount = try container.decodeIfPresent(Int.self, forKey: .assumptionCount) ?? 0
        riskClassificationCount = try container.decodeIfPresent(Int.self, forKey: .riskClassificationCount) ?? 0
        objectiveCount = try container.decode(Int.self, forKey: .objectiveCount)
        candidateActionCount = try container.decode(Int.self, forKey: .candidateActionCount)
        verificationGateCount = try container.decode(Int.self, forKey: .verificationGateCount)
        diagnostics = try container.decode([XcircuitePlanningProblemValidationDiagnostic].self, forKey: .diagnostics)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encode(runID, forKey: .runID)
        try container.encode(problemID, forKey: .problemID)
        try container.encode(problemPath, forKey: .problemPath)
        try container.encodeIfPresent(
            problemTranslationAuditArtifactID,
            forKey: .problemTranslationAuditArtifactID
        )
        try container.encodeIfPresent(problemTranslationAuditPath, forKey: .problemTranslationAuditPath)
        try container.encodeIfPresent(actionDomainSnapshotArtifactID, forKey: .actionDomainSnapshotArtifactID)
        try container.encodeIfPresent(actionDomainSnapshotPath, forKey: .actionDomainSnapshotPath)
        try container.encode(sourceRefCount, forKey: .sourceRefCount)
        try container.encode(initialStateRefCount, forKey: .initialStateRefCount)
        try container.encode(assumptionCount, forKey: .assumptionCount)
        try container.encode(riskClassificationCount, forKey: .riskClassificationCount)
        try container.encode(objectiveCount, forKey: .objectiveCount)
        try container.encode(candidateActionCount, forKey: .candidateActionCount)
        try container.encode(verificationGateCount, forKey: .verificationGateCount)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}
