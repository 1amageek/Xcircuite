import Foundation

public struct ElectricalSignoffOracleProcessConfiguration: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String?
    public var timeoutSeconds: Double

    public init(
        executablePath: String,
        arguments: [String],
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
            throw ElectricalSignoffOracleProcessConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffOracleProcessConfigurationError.emptyExecutablePath
        }
        guard executablePath.hasPrefix("/") else {
            throw ElectricalSignoffOracleProcessConfigurationError.executablePathMustBeAbsolute(executablePath)
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw ElectricalSignoffOracleProcessConfigurationError.invalidTimeout(timeoutSeconds)
        }
        guard arguments.contains(where: { $0.contains("{{specPath}}") }) else {
            throw ElectricalSignoffOracleProcessConfigurationError.missingArgumentPlaceholder("{{specPath}}")
        }
        guard arguments.contains(where: { $0.contains("{{outputPath}}") }) else {
            throw ElectricalSignoffOracleProcessConfigurationError.missingArgumentPlaceholder("{{outputPath}}")
        }
        if let workingDirectoryPath {
            guard !workingDirectoryPath.isEmpty else {
                throw ElectricalSignoffOracleProcessConfigurationError.emptyWorkingDirectoryPath
            }
            if !workingDirectoryPath.hasPrefix("/") {
                let components = workingDirectoryPath.split(separator: "/", omittingEmptySubsequences: false)
                guard !components.contains("..") else {
                    throw ElectricalSignoffOracleProcessConfigurationError.unsafeWorkingDirectoryPath(
                        workingDirectoryPath
                    )
                }
            }
        }
    }

    public func resolvedWorkingDirectory(projectRoot: URL) -> URL {
        guard let workingDirectoryPath else { return projectRoot }
        if workingDirectoryPath.hasPrefix("/") {
            return URL(filePath: workingDirectoryPath).standardizedFileURL
        }
        return projectRoot.appending(path: workingDirectoryPath).standardizedFileURL
    }

    public func expandedArguments(
        specPath: String,
        outputPath: String,
        projectRoot: URL,
        runID: String
    ) -> [String] {
        arguments.map { argument in
            argument
                .replacingOccurrences(of: "{{specPath}}", with: specPath)
                .replacingOccurrences(of: "{{outputPath}}", with: outputPath)
                .replacingOccurrences(of: "{{projectRoot}}", with: projectRoot.path(percentEncoded: false))
                .replacingOccurrences(of: "{{runID}}", with: runID)
        }
    }
}
