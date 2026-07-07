import DRCEngine
import Foundation

public protocol DRCExecuting: Sendable {
    func run(_ request: DRCRequest) async throws -> DRCExecutionResult

    func run(
        _ request: DRCRequest,
        cancellationCheck: DRCExecutionCancellationCheck?
    ) async throws -> DRCExecutionResult
}

public extension DRCExecuting {
    func run(
        _ request: DRCRequest,
        cancellationCheck: DRCExecutionCancellationCheck?
    ) async throws -> DRCExecutionResult {
        try await run(request)
    }
}

extension DefaultDRCEngine: DRCExecuting {}
