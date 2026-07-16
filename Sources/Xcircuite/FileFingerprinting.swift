import Foundation

public protocol FileFingerprinting: Sendable {
    func fingerprint(fileAt url: URL) throws -> FileFingerprint
}
