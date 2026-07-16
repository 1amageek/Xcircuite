import Foundation
import ToolQualification

public extension XcircuiteFlowStageExecutorSpec {
    struct ReleaseAuthorization: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.authorization",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

    struct ReleaseSignoff: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.signoff",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

    struct ReleaseTapeout: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestPath: String
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.tapeout",
            requestPath: String,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestPath = requestPath
            self.tool = tool
        }
    }

}
