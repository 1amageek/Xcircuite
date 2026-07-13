import Foundation
import DesignFlowKernel

public struct XcircuitePlanningConstraint: Codable, Sendable, Hashable {
    public var constraintID: String
    public var kind: String
    public var severity: String
    public var description: String
    public var sourceRefIDs: [String]
    public var evidence: [String: XcircuiteJSONValue]

    public init(
        constraintID: String,
        kind: String,
        severity: String,
        description: String,
        sourceRefIDs: [String] = [],
        evidence: [String: XcircuiteJSONValue] = [:]
    ) {
        self.constraintID = constraintID
        self.kind = kind
        self.severity = severity
        self.description = description
        self.sourceRefIDs = sourceRefIDs
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case constraintID
        case kind
        case severity
        case description
        case sourceRefIDs
        case evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.constraintID = try container.decode(String.self, forKey: .constraintID)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.severity = try container.decode(String.self, forKey: .severity)
        self.description = try container.decode(String.self, forKey: .description)
        self.sourceRefIDs = try container.decode([String].self, forKey: .sourceRefIDs)
        self.evidence = try container.decode(
            [String: XcircuiteJSONValue].self,
            forKey: .evidence
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(constraintID, forKey: .constraintID)
        try container.encode(kind, forKey: .kind)
        try container.encode(severity, forKey: .severity)
        try container.encode(description, forKey: .description)
        try container.encode(sourceRefIDs, forKey: .sourceRefIDs)
        try container.encode(evidence, forKey: .evidence)
    }
}
