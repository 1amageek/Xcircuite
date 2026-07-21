import Foundation

public struct PDKExternalInspectionProcessConfiguration: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var executablePath: String
    public var arguments: [String]
    public var redactedArgumentIndexes: [Int]
    public var workingDirectoryPath: String?
    public var timeoutSeconds: Double

    public init(
        executablePath: String,
        arguments: [String] = [],
        redactedArgumentIndexes: [Int] = [],
        workingDirectoryPath: String? = nil,
        timeoutSeconds: Double = 300
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.executablePath = executablePath
        self.arguments = arguments
        self.redactedArgumentIndexes = redactedArgumentIndexes
        self.workingDirectoryPath = workingDirectoryPath
        self.timeoutSeconds = timeoutSeconds
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PDKExternalInspectionProcessConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDKExternalInspectionProcessConfigurationError.emptyExecutablePath
        }
        guard executablePath.hasPrefix("/") else {
            throw PDKExternalInspectionProcessConfigurationError.executablePathMustBeAbsolute(executablePath)
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw PDKExternalInspectionProcessConfigurationError.invalidTimeout(timeoutSeconds)
        }
        guard redactedArgumentIndexes == Array(Set(redactedArgumentIndexes)).sorted(),
              redactedArgumentIndexes.allSatisfy(arguments.indices.contains) else {
            throw PDKExternalInspectionProcessConfigurationError.invalidRedactedArgumentIndexes(
                redactedArgumentIndexes
            )
        }
        if let workingDirectoryPath {
            guard !workingDirectoryPath.isEmpty else {
                throw PDKExternalInspectionProcessConfigurationError.emptyWorkingDirectoryPath
            }
            if !workingDirectoryPath.hasPrefix("/") {
                let components = workingDirectoryPath.split(separator: "/", omittingEmptySubsequences: false)
                guard !components.contains("..") else {
                    throw PDKExternalInspectionProcessConfigurationError.unsafeWorkingDirectoryPath(
                        workingDirectoryPath
                    )
                }
            }
        }
    }

    func recordedArguments(from expandedArguments: [String]) throws -> [String] {
        try validate()
        guard expandedArguments.count == arguments.count else {
            throw PDKExternalInspectionProcessConfigurationError.argumentCountMismatch(
                expected: arguments.count,
                actual: expandedArguments.count
            )
        }
        let redactedIndexes = Set(redactedArgumentIndexes)
        return expandedArguments.enumerated().map { index, argument in
            redactedIndexes.contains(index) ? "<redacted>" : argument
        }
    }
}
