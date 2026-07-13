import Foundation

public struct PDKExternalInspectionExecutionRecord: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var stageID: String
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String
    public var timeoutSeconds: Double
    public var requestPath: String
    public var resultPath: String
    public var standardOutputPath: String
    public var standardErrorPath: String
    public var exitCode: Int32?
    public var status: String
    public var startedAt: Date
    public var completedAt: Date
    public var diagnostics: [String]

    public init(
        runID: String,
        stageID: String,
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String,
        timeoutSeconds: Double,
        requestPath: String,
        resultPath: String,
        standardOutputPath: String,
        standardErrorPath: String,
        exitCode: Int32?,
        status: String,
        startedAt: Date,
        completedAt: Date,
        diagnostics: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.stageID = stageID
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.timeoutSeconds = timeoutSeconds
        self.requestPath = requestPath
        self.resultPath = resultPath
        self.standardOutputPath = standardOutputPath
        self.standardErrorPath = standardErrorPath
        self.exitCode = exitCode
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.diagnostics = diagnostics
    }
}
