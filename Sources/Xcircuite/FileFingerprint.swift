import CircuiteFoundation
import Foundation

public struct FileFingerprint: Sendable, Hashable {
    public let digest: ContentDigest
    public let byteCount: UInt64

    public init(digest: ContentDigest, byteCount: UInt64) {
        self.digest = digest
        self.byteCount = byteCount
    }
}
