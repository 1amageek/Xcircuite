import Foundation
import RTLVerificationCore
import ToolQualification

public struct RTLVerificationOracleToolSpec: Sendable, Hashable, Codable {
    public var toolID: String
    public var executablePath: String
    public var version: String
    public var tool: XcircuiteFlowToolSpec
    public var additionalArguments: [String]
    public var timeoutSeconds: TimeInterval

    public init(
        toolID: String,
        executablePath: String,
        version: String,
        tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec(),
        additionalArguments: [String] = [],
        timeoutSeconds: TimeInterval = 60
    ) {
        self.toolID = toolID
        self.executablePath = executablePath
        self.version = version
        self.tool = tool
        self.additionalArguments = additionalArguments
        self.timeoutSeconds = timeoutSeconds
    }

    public func makeDescriptor(
        analysis: RTLVerificationAnalysis,
        proofView: RTLVerificationProofView
    ) -> ToolDescriptor {
        RTLToolDescriptors.oracle(
            toolID: toolID,
            executablePath: executablePath,
            version: version,
            analysis: analysis,
            proofView: proofView
        )
    }

    public func resolvedExecutablePath(projectRoot: URL) throws -> String {
        try XcircuiteFlowRuntimeSpec.resolvePath(executablePath, projectRoot: projectRoot)
            .path(percentEncoded: false)
    }
}
