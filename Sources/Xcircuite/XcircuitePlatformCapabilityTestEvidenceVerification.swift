import CircuiteFoundation
import Foundation

/// An in-process receipt produced only after the platform test runner observes
/// the external process completion and persists its raw transcript.
///
/// The receipt is intentionally not Codable. Persisted JSON declarations and
/// result records remain auditable inputs, but cannot independently promote
/// their own status to passed.
public struct XcircuitePlatformCapabilityTestEvidenceVerification: Sendable, Hashable {
    public let evidenceID: String
    public let resultArtifactID: ArtifactID
    public let resultDigest: ContentDigest
    public let evidenceDigest: ContentDigest
    public let exitStatus: Int32

    init(
        evidenceID: String,
        resultArtifactID: ArtifactID,
        resultDigest: ContentDigest,
        evidenceDigest: ContentDigest,
        exitStatus: Int32
    ) {
        self.evidenceID = evidenceID
        self.resultArtifactID = resultArtifactID
        self.resultDigest = resultDigest
        self.evidenceDigest = evidenceDigest
        self.exitStatus = exitStatus
    }
}
