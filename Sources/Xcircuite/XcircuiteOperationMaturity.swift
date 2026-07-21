import Foundation

public struct XcircuiteOperationMaturity: Codable, Sendable, Hashable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public static let implemented = Self(validatedLiteral: "implemented")
    public static let partial = Self(validatedLiteral: "partial")
    public static let planned = Self(validatedLiteral: "planned")
    public static let availableUnqualified = Self(validatedLiteral: "available-unqualified")

    public let rawValue: String

    public init(rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw XcircuiteOperationMaturityError.invalidToken(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        guard Self.isValid(value) else {
            preconditionFailure("Invalid operation maturity token literal: \(value)")
        }
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    private init(validatedLiteral value: String) {
        self.rawValue = value
    }

    private static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard value.unicodeScalars.allSatisfy(allowed.contains),
              value.first?.isLetter == true,
              value.last?.isLetter == true || value.last?.isNumber == true else {
            return false
        }
        return !value.contains("..")
            && !value.contains("--")
            && !value.contains(".-")
            && !value.contains("-.")
    }
}
