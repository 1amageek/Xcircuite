import CircuiteFoundation
import Foundation

public struct XcircuitePreparedArtifact: Sendable, Hashable {
    public let reference: ArtifactReference
    public let content: Data

    public init(reference: ArtifactReference, content: Data) {
        self.reference = reference
        self.content = content
    }
}
