import CircuiteFoundation
import Foundation

public struct LocalFileFingerprinter: FileFingerprinting {
    private let digester: any ContentDigesting

    public init(digester: any ContentDigesting = SHA256ContentDigester()) {
        self.digester = digester
    }

    public func fingerprint(fileAt url: URL) throws -> FileFingerprint {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(fileURL: url),
            role: .output,
            kind: .other,
            format: .unknown
        )
        let reference = try LocalArtifactReferencer(digester: digester).reference(locator)
        return FileFingerprint(digest: reference.digest, byteCount: reference.byteCount)
    }
}
