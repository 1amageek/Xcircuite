import Foundation

public struct ElectricalSignoffOracleProcessExecution: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String
    public var specPath: String
    public var outputPath: String
    public var standardOutputPath: String
    public var standardErrorPath: String
    public var status: String
    public var exitCode: Int32?
    public var startedAt: Date
    public var completedAt: Date
    public var message: String?

    public init(
        runID: String,
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String,
        specPath: String,
        outputPath: String,
        standardOutputPath: String,
        standardErrorPath: String,
        status: String,
        exitCode: Int32?,
        startedAt: Date,
        completedAt: Date,
        message: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.specPath = specPath
        self.outputPath = outputPath
        self.standardOutputPath = standardOutputPath
        self.standardErrorPath = standardErrorPath
        self.status = status
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.message = message
    }
}
