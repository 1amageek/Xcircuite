public struct SimulationGoldenCorpusArtifactReference: Codable, Sendable, Hashable {
    public var artifactID: String
    public var path: String
    public var kind: String
    public var format: String
    public var sha256: String
    public var byteCount: Int64

    public init(
        artifactID: String,
        path: String,
        kind: String,
        format: String,
        sha256: String,
        byteCount: Int64
    ) {
        self.artifactID = artifactID
        self.path = path
        self.kind = kind
        self.format = format
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}
