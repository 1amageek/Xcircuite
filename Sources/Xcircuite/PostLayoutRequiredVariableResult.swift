public struct PostLayoutRequiredVariableResult: Sendable, Hashable, Codable {
    public var variableName: String
    public var present: Bool

    public init(variableName: String, present: Bool) {
        self.variableName = variableName
        self.present = present
    }
}
