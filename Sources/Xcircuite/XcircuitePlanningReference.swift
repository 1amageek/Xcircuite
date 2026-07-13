import Foundation
import DesignFlowKernel

public struct XcircuitePlanningReference: Codable, Sendable, Hashable {
    public var refID: String
    public var kind: String
    public var path: String?
    public var artifactID: String?
    public var metadata: [String: XcircuiteJSONValue]

    public init(
        refID: String,
        kind: String,
        path: String? = nil,
        artifactID: String? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) {
        self.refID = refID
        self.kind = kind
        self.path = path
        self.artifactID = artifactID
        self.metadata = metadata
    }
}
