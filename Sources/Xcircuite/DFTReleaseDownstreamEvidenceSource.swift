import DFTCore
import Foundation

public struct DFTReleaseDownstreamEvidenceSource: Sendable, Hashable, Codable {
    public var domain: DFTReleaseDownstreamEvidence.Domain
    public var role: String
    public var input: XcircuiteFlowInputReference

    public init(
        domain: DFTReleaseDownstreamEvidence.Domain,
        role: String,
        input: XcircuiteFlowInputReference
    ) {
        self.domain = domain
        self.role = role
        self.input = input
    }
}
