import CircuiteFoundation
import Foundation

func fixtureArtifactReference(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: UInt64? = nil,
    role: ArtifactRole = .input
) throws -> ArtifactReference {
    let location = if path.hasPrefix("/") {
        try ArtifactLocation(fileURL: URL(filePath: path))
    } else {
        try ArtifactLocation(workspaceRelativePath: path)
    }
    return ArtifactReference(
        id: try artifactID.map { try ArtifactID(rawValue: $0) },
        locator: ArtifactLocator(
            location: location,
            role: role,
            kind: kind,
            format: format
        ),
        digest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: sha256 ?? String(repeating: "0", count: 64)
        ),
        byteCount: byteCount ?? 0
    )
}

func fixtureArtifactReference(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: Int,
    role: ArtifactRole = .input
) throws -> ArtifactReference {
    try fixtureArtifactReference(
        artifactID: artifactID,
        path: path,
        kind: kind,
        format: format,
        sha256: sha256,
        byteCount: UInt64(max(byteCount, 0)),
        role: role
    )
}

func fixtureArtifactReference(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    sha256: String? = nil,
    byteCount: Int64,
    role: ArtifactRole = .input
) throws -> ArtifactReference {
    try fixtureArtifactReference(
        artifactID: artifactID,
        path: path,
        kind: kind,
        format: format,
        sha256: sha256,
        byteCount: UInt64(max(byteCount, 0)),
        role: role
    )
}

func fixtureSHA256(data: Data) throws -> String {
    try SHA256ContentDigester().digest(data: data).hexadecimalValue
}
