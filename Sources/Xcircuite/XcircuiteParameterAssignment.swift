import Foundation

public struct XcircuiteParameterAssignment: Codable, Sendable, Hashable {
    public var name: String
    public var value: Double
    public var unit: String?

    public init(
        name: String,
        value: Double,
        unit: String? = nil
    ) {
        self.name = name
        self.value = value
        self.unit = unit
    }
}
