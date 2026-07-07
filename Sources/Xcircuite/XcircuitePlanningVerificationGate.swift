import Foundation

public struct XcircuitePlanningVerificationGate: Codable, Sendable, Hashable {
    public var gateID: String
    public var required: Bool
    public var description: String

    public init(
        gateID: String,
        required: Bool,
        description: String
    ) {
        self.gateID = gateID
        self.required = required
        self.description = description
    }
}
