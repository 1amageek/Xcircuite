import DesignFlowKernel
import Foundation
import ToolQualification

public struct XcircuiteFlowRuntimeSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var toolchainProfile: XcircuiteFlowToolchainProfile?
    public var executors: [XcircuiteFlowStageExecutorSpec]

    public init(
        schemaVersion: Int = 1,
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil,
        executors: [XcircuiteFlowStageExecutorSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.toolchainProfile = toolchainProfile
        self.executors = executors
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case toolchainProfile
        case executors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Expected flow runtime schema version \(Self.currentSchemaVersion)."
            )
        }
        toolchainProfile = try container.decodeIfPresent(
            XcircuiteFlowToolchainProfile.self,
            forKey: .toolchainProfile
        )
        executors = try container.decode([XcircuiteFlowStageExecutorSpec].self, forKey: .executors)
    }

    public static func load(from url: URL) throws -> XcircuiteFlowRuntimeSpec {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(url.path(percentEncoded: false))
        }
        return try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
    }

    public func makeRuntime(projectRoot: URL) throws -> XcircuiteFlowRuntime {
        try validate(projectRoot: projectRoot, requireCompleteToolEvidence: false)

        let executors = try executors.map {
            try $0.makeExecutor(projectRoot: projectRoot, toolchainProfile: toolchainProfile)
        }
        let toolBindings = try makeToolBindings()

        return XcircuiteFlowRuntime(
            toolRegistry: try ToolRegistry(validating: toolBindings.descriptors),
            healthResults: toolBindings.healthResults,
            executors: executors,
            toolchainProfile: toolchainProfile
        )
    }

    static func resolvePath(_ rawPath: String, projectRoot: URL) throws -> URL {
        guard !rawPath.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(rawPath)
        }
        if rawPath.hasPrefix("/") {
            return URL(filePath: rawPath)
        }
        if rawPath.hasPrefix("~") {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(rawPath)
        }
        if rawPath.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
            throw XcircuiteFlowRuntimeSpecError.invalidPath(rawPath)
        }
        return projectRoot.appending(path: rawPath)
    }

    func makeToolBindings() throws -> XcircuiteFlowRuntimeToolBindings {
        var descriptors: [String: (descriptor: ToolDescriptor, stageIDs: [String])] = [:]
        var healthResults: [String: (health: ToolHealthCheckResult, stageIDs: [String])] = [:]

        for spec in executors {
            let stageID = spec.stageID
            let descriptor = spec.makeDescriptor()
            if var existing = descriptors[descriptor.toolID] {
                guard existing.descriptor == descriptor else {
                    throw XcircuiteFlowRuntimeSpecError.conflictingRuntimeToolDescriptor(
                        toolID: descriptor.toolID,
                        stageIDs: (existing.stageIDs + [stageID]).sorted()
                    )
                }
                existing.stageIDs.append(stageID)
                descriptors[descriptor.toolID] = existing
            } else {
                descriptors[descriptor.toolID] = (descriptor: descriptor, stageIDs: [stageID])
            }

            let health = spec.makeHealthResult()
            if var existing = healthResults[health.toolID] {
                guard existing.health == health else {
                    throw XcircuiteFlowRuntimeSpecError.conflictingRuntimeToolHealth(
                        toolID: health.toolID,
                        stageIDs: (existing.stageIDs + [stageID]).sorted()
                    )
                }
                existing.stageIDs.append(stageID)
                healthResults[health.toolID] = existing
            } else {
                healthResults[health.toolID] = (health: health, stageIDs: [stageID])
            }
        }

        let orderedDescriptors = descriptors.values
            .map(\.descriptor)
            .sorted { $0.toolID < $1.toolID }
        let orderedHealthResults = Dictionary(
            uniqueKeysWithValues: healthResults.values.map { ($0.health.toolID, $0.health) }
        )
        return XcircuiteFlowRuntimeToolBindings(
            descriptors: orderedDescriptors,
            healthResults: orderedHealthResults
        )
    }
}

struct XcircuiteFlowRuntimeToolBindings: Sendable, Hashable {
    var descriptors: [ToolDescriptor]
    var healthResults: [String: ToolHealthCheckResult]
}
