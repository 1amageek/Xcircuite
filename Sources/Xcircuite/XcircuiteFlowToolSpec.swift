import CircuiteFoundation
import Foundation
import ToolQualification

public struct XcircuiteFlowToolSpec: Sendable, Hashable, Codable {
    public var qualificationRecord: ArtifactReference?

    public init(
        qualificationRecord: ArtifactReference? = nil
    ) {
        self.qualificationRecord = qualificationRecord
    }
}
