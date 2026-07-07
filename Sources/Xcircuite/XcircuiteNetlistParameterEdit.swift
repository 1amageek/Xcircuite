import Foundation

public struct XcircuiteNetlistParameterEdit: Codable, Sendable, Hashable {
    public var assignmentName: String
    public var targetKind: String
    public var targetName: String
    public var parameterName: String
    public var value: Double
    public var unit: String?

    public init(
        assignmentName: String,
        targetKind: String,
        targetName: String,
        parameterName: String,
        value: Double,
        unit: String? = nil
    ) {
        self.assignmentName = assignmentName
        self.targetKind = targetKind
        self.targetName = targetName
        self.parameterName = parameterName
        self.value = value
        self.unit = unit
    }
}
