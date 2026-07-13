import Foundation
import SignoffToolSupport

public protocol PDKExternalInspectionProcessRunning: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: Double,
        cancellationCheck: @escaping @Sendable () async throws -> Bool
    ) async throws -> TimedProcessResult
}
