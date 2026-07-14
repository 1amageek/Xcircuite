import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteCandidatePlanExecutionStepResult: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var stepID: String
    public var order: Int
    public var actionID: String
    public var domainID: String
    public var operationID: String
    public var status: String
    public var artifactReferences: [ArtifactReference]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var nextActions: [String]

    public init(
        stepID: String,
        order: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        status: String,
        artifactReferences: [ArtifactReference] = [],
        diagnostics: [XcircuitePlanVerificationDiagnostic] = [],
        nextActions: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.stepID = stepID
        self.order = order
        self.actionID = actionID
        self.domainID = domainID
        self.operationID = operationID
        self.status = status
        self.artifactReferences = artifactReferences
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case stepID
        case order
        case actionID
        case domainID
        case operationID
        case status
        case artifactReferences
        case diagnostics
        case nextActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected candidate plan execution step schema version \(Self.currentSchemaVersion)."
            )
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.stepID = try container.decode(String.self, forKey: .stepID)
        self.order = try container.decode(Int.self, forKey: .order)
        self.actionID = try container.decode(String.self, forKey: .actionID)
        self.domainID = try container.decode(String.self, forKey: .domainID)
        self.operationID = try container.decode(String.self, forKey: .operationID)
        self.status = try container.decode(String.self, forKey: .status)
        self.artifactReferences = try container.decode(
            [ArtifactReference].self,
            forKey: .artifactReferences
        )
        self.diagnostics = try container.decode(
            [XcircuitePlanVerificationDiagnostic].self,
            forKey: .diagnostics
        )
        self.nextActions = try container.decode([String].self, forKey: .nextActions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(stepID, forKey: .stepID)
        try container.encode(order, forKey: .order)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(domainID, forKey: .domainID)
        try container.encode(operationID, forKey: .operationID)
        try container.encode(status, forKey: .status)
        try container.encode(artifactReferences, forKey: .artifactReferences)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(nextActions, forKey: .nextActions)
    }

}
