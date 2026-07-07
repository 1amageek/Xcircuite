import DesignFlowKernel
import Foundation

public struct XcircuiteFlowRunSpec: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var intent: String
    public var stages: [FlowStageDefinition]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        intent: String,
        stages: [FlowStageDefinition]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.intent = intent
        self.stages = stages
    }

    public static func load(from url: URL) throws -> XcircuiteFlowRunSpec {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(url.path(percentEncoded: false))
        }
        let spec = try JSONDecoder().decode(XcircuiteFlowRunSpec.self, from: data)
        try spec.validate()
        return spec
    }

    public func makeRequest(projectRoot: URL) throws -> FlowOperationRequest {
        try validate()
        return FlowOperationRequest(
            projectRoot: projectRoot,
            runID: runID,
            intent: intent,
            stages: stages
        )
    }
}
