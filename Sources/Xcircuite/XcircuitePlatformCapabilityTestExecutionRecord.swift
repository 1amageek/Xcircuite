import CircuiteFoundation
import Foundation

public struct XcircuitePlatformCapabilityTestExecutionRecord: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var evidenceID: String
    public var testFilter: String
    public var command: [String]
    public var startedAt: Date
    public var completedAt: Date
    public var exitStatus: Int32
    public var transcriptArtifact: ArtifactReference

    public init(
        evidenceID: String,
        testFilter: String,
        command: [String],
        startedAt: Date,
        completedAt: Date,
        exitStatus: Int32,
        transcriptArtifact: ArtifactReference
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.evidenceID = evidenceID
        self.testFilter = testFilter
        self.command = command
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exitStatus = exitStatus
        self.transcriptArtifact = transcriptArtifact
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case evidenceID
        case testFilter
        case command
        case startedAt
        case completedAt
        case exitStatus
        case transcriptArtifact
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported platform capability test execution record schema."
            )
        }
        self.schemaVersion = schemaVersion
        self.evidenceID = try container.decode(String.self, forKey: .evidenceID)
        self.testFilter = try container.decode(String.self, forKey: .testFilter)
        self.command = try container.decode([String].self, forKey: .command)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.completedAt = try container.decode(Date.self, forKey: .completedAt)
        self.exitStatus = try container.decode(Int32.self, forKey: .exitStatus)
        self.transcriptArtifact = try container.decode(
            ArtifactReference.self,
            forKey: .transcriptArtifact
        )
        guard completedAt >= startedAt else {
            throw DecodingError.dataCorruptedError(
                forKey: .completedAt,
                in: container,
                debugDescription: "Test execution completion must not precede its start."
            )
        }
    }
}
