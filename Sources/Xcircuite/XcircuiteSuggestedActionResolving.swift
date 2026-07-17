import Foundation

public protocol XcircuiteSuggestedActionResolving: Sendable {
    func resolve(
        request: XcircuiteSelectedSuggestedActionResolutionRequest
    ) async throws -> XcircuiteResolvedSuggestedAction
}
