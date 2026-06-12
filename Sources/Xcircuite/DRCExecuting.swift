import DRCEngine
import Foundation

public protocol DRCExecuting: Sendable {
    func run(_ request: DRCRequest) async throws -> DRCExecutionResult
}

extension DefaultDRCEngine: DRCExecuting {}
