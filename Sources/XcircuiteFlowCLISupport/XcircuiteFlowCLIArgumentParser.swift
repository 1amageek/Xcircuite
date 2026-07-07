import Foundation

struct XcircuiteFlowCLIArgumentParser {
    private let arguments: [String]
    private var index: Int

    init(arguments: [String]) {
        self.arguments = arguments
        self.index = 0
    }

    mutating func next() -> String? {
        guard index < arguments.count else {
            return nil
        }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func requiredValue(after option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--") else {
            throw XcircuiteFlowCLIError.missingValue(option)
        }
        return value
    }

    mutating func requiredInt(after option: String) throws -> Int {
        let value = try requiredValue(after: option)
        guard let intValue = Int(value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return intValue
    }

    mutating func requiredDouble(after option: String) throws -> Double {
        let value = try requiredValue(after: option)
        guard let doubleValue = Double(value), doubleValue.isFinite else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return doubleValue
    }
}
