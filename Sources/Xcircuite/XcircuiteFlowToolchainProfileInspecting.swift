import Foundation

public protocol XcircuiteFlowToolchainProfileInspecting: Sendable {
    func inspect(
        request: XcircuiteFlowToolchainProfileInspectionRequest
    ) throws -> XcircuiteFlowToolchainProfileInspection
}
