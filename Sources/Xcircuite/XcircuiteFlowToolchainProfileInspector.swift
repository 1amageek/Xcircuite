import Foundation

public struct XcircuiteFlowToolchainProfileInspector: XcircuiteFlowToolchainProfileInspecting {
    public init() {}

    public func inspect(
        request: XcircuiteFlowToolchainProfileInspectionRequest
    ) throws -> XcircuiteFlowToolchainProfileInspection {
        guard let profile = request.runtimeSpec.toolchainProfile else {
            return XcircuiteFlowToolchainProfileInspection(
                status: .notPresent,
                profilePresent: false,
                runtimeConfigPath: request.runtimeConfigURL?.path(percentEncoded: false),
                projectRootPath: request.projectRoot?.path(percentEncoded: false)
            )
        }

        let report = XcircuiteFlowToolchainProfileReadinessValidator().report(
            for: profile,
            projectRoot: request.projectRoot
        )
        return XcircuiteFlowToolchainProfileInspection(
            status: report.status == .passed ? .passed : .failed,
            profilePresent: true,
            runtimeConfigPath: request.runtimeConfigURL?.path(percentEncoded: false),
            projectRootPath: request.projectRoot?.path(percentEncoded: false),
            readinessReport: report
        )
    }
}
