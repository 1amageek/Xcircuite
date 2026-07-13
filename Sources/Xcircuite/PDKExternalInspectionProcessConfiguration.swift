import Foundation

public struct PDKExternalInspectionProcessConfiguration: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String?
    public var timeoutSeconds: Double

    public init(
        executablePath: String,
        arguments: [String] = [],
        workingDirectoryPath: String? = nil,
        timeoutSeconds: Double = 300
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.executablePath = executablePath
        self.arguments = arguments
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
}
