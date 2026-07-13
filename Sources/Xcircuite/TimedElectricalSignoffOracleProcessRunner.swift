import Foundation
import SignoffToolSupport

public struct TimedElectricalSignoffOracleProcessRunner: ElectricalSignoffOracleProcessRunning {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: Double,
        cancellationCheck: @escaping @Sendable () async throws -> Bool
    ) async throws -> TimedProcessResult {
        let process = Process()
        process.executableURL = URL(filePath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        return try await TimedProcessRunner(timeoutSeconds: timeoutSeconds).run(
            process: process,
            cancellationCheck: cancellationCheck
        )
    }
}
