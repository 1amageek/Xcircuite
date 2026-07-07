import Foundation
import PEXEngine

public protocol PEXExecuting: Sendable {
    func run(_ request: PEXRunRequest) async throws -> PEXRunResult

    func run(
        _ request: PEXRunRequest,
        cancellationCheck: PEXExecutionContext.CancellationCheck?
    ) async throws -> PEXRunResult
}

public extension PEXExecuting {
    func run(
        _ request: PEXRunRequest,
        cancellationCheck: PEXExecutionContext.CancellationCheck?
    ) async throws -> PEXRunResult {
        try await run(request)
    }
}

extension DefaultPEXEngine: PEXExecuting {}
