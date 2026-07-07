import Foundation
import LVSEngine

public protocol LVSExecuting: Sendable {
    func run(_ request: LVSRequest) async throws -> LVSExecutionResult

    func run(
        _ request: LVSRequest,
        cancellationCheck: LVSExecutionCancellationCheck?
    ) async throws -> LVSExecutionResult
}

public extension LVSExecuting {
    func run(
        _ request: LVSRequest,
        cancellationCheck: LVSExecutionCancellationCheck?
    ) async throws -> LVSExecutionResult {
        try await run(request)
    }
}

extension DefaultLVSEngine: LVSExecuting {}
