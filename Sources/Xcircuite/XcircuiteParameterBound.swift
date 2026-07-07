import Foundation

public struct XcircuiteParameterBound: Codable, Sendable, Hashable {
    public var name: String
    public var lowerBound: Double
    public var upperBound: Double
    public var nominalValue: Double?
    public var step: Double?
    public var unit: String?
    public var preferredDirection: String?

    public init(
        name: String,
        lowerBound: Double,
        upperBound: Double,
        nominalValue: Double? = nil,
        step: Double? = nil,
        unit: String? = nil,
        preferredDirection: String? = nil
    ) {
        self.name = name
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.nominalValue = nominalValue
        self.step = step
        self.unit = unit
        self.preferredDirection = preferredDirection
    }
}
