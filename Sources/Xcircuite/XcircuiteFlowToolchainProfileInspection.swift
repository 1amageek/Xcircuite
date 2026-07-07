import Foundation

public struct XcircuiteFlowToolchainProfileInspection: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var status: XcircuiteFlowToolchainProfileInspectionStatus
    public var profilePresent: Bool
    public var runtimeConfigPath: String?
    public var projectRootPath: String?
    public var readinessReport: XcircuiteFlowToolchainProfileReadinessReport?

    public init(
        schemaVersion: Int = 1,
        status: XcircuiteFlowToolchainProfileInspectionStatus,
        profilePresent: Bool,
        runtimeConfigPath: String? = nil,
        projectRootPath: String? = nil,
        readinessReport: XcircuiteFlowToolchainProfileReadinessReport? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.profilePresent = profilePresent
        self.runtimeConfigPath = runtimeConfigPath
        self.projectRootPath = projectRootPath
        self.readinessReport = readinessReport
    }
}
