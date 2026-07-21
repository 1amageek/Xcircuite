import CircuiteFoundation
import Foundation

public struct ReleaseSignoffEvidenceAssemblyRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var runID: String
    public var designArtifact: ArtifactReference
    public var pdkArtifact: ArtifactReference
    public var sources: [ReleaseSignoffEvidenceSource]
    public var evaluatedAt: Date

    public init(
        runID: String,
        designArtifact: ArtifactReference,
        pdkArtifact: ArtifactReference,
        sources: [ReleaseSignoffEvidenceSource],
        evaluatedAt: Date
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.designArtifact = designArtifact
        self.pdkArtifact = pdkArtifact
        self.sources = sources
        self.evaluatedAt = evaluatedAt
    }
}
