import DesignFlowKernel
import Foundation

public struct XcircuiteFlowRunSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case intent
        case stages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected flow run schema version \(Self.currentSchemaVersion)."
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        intent = try container.decode(String.self, forKey: .intent)
        stages = try container.decode([FlowStageDefinition].self, forKey: .stages)
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

    public func makeRequest(workspaceID: FlowWorkspaceID) throws -> FlowOperationRequest {
        try validate()
        return FlowOperationRequest(
            workspaceID: workspaceID,
            runID: runID,
            intent: intent,
            stages: stages
        )
    }
}
