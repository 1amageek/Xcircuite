import Foundation
import LVSEngine

public protocol LVSExecuting: Sendable {
    func run(_ request: LVSRequest) async throws -> LVSExecutionResult
}

extension DefaultLVSEngine: LVSExecuting {}
