import Foundation
import PEXEngine

public protocol PEXExecuting: Sendable {
    func run(_ request: PEXRunRequest) async throws -> PEXRunResult
}

extension DefaultPEXEngine: PEXExecuting {}
