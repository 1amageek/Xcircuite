import Foundation
import CircuiteFoundation
import ToolQualification

public extension XcircuiteFlowStageExecutorSpec {
    struct ReleaseEvidenceAssembly: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.evidence-assembly",
            requestInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestInput = requestInput
            self.tool = tool
        }
    }

    struct ReleaseAuthorization: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.authorization",
            requestInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestInput = requestInput
            self.tool = tool
        }
    }

    struct ReleaseSignoff: Sendable, Hashable, Codable {
        public var stageID: String
        public var requestInput: XcircuiteFlowInputReference
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.signoff",
            requestInput: XcircuiteFlowInputReference,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestInput = requestInput
            self.tool = tool
        }
    }

    struct ReleaseTapeout: Sendable, Hashable, Codable {
        public struct GeometricXOR: Sendable, Hashable, Codable {
            public var qualificationInput: XcircuiteFlowInputReference
            public var reportOutput: ArtifactLocator
            public var arguments: [String]
            public var environment: [String: String]
            public var timeoutSeconds: Double

            public init(
                qualificationInput: XcircuiteFlowInputReference,
                reportOutput: ArtifactLocator,
                arguments: [String] = [],
                environment: [String: String] = [
                    "LANG": "C",
                    "LC_ALL": "C",
                    "TZ": "UTC",
                ],
                timeoutSeconds: Double = 300
            ) {
                self.qualificationInput = qualificationInput
                self.reportOutput = reportOutput
                self.arguments = arguments
                self.environment = environment
                self.timeoutSeconds = timeoutSeconds
            }
        }

        public var stageID: String
        public var requestInput: XcircuiteFlowInputReference
        public var geometricXOR: GeometricXOR?
        public var tool: XcircuiteFlowToolSpec

        public init(
            stageID: String = "release.tapeout",
            requestInput: XcircuiteFlowInputReference,
            geometricXOR: GeometricXOR? = nil,
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec()
        ) {
            self.stageID = stageID
            self.requestInput = requestInput
            self.geometricXOR = geometricXOR
            self.tool = tool
        }
    }

}
