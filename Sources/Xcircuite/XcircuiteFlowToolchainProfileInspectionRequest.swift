import Foundation

public struct XcircuiteFlowToolchainProfileInspectionRequest: Sendable, Hashable {
    public var runtimeSpec: XcircuiteFlowRuntimeSpec
    public var runtimeConfigURL: URL?
    public var projectRoot: URL?

    public init(
        runtimeSpec: XcircuiteFlowRuntimeSpec,
        runtimeConfigURL: URL? = nil,
        projectRoot: URL? = nil
    ) {
        self.runtimeSpec = runtimeSpec
        self.runtimeConfigURL = runtimeConfigURL
        self.projectRoot = projectRoot
    }
}
