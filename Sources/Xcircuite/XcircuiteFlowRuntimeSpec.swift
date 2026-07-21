import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

public struct XcircuiteFlowRuntimeSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 7

    public var schemaVersion: Int
    public var toolchainProfile: XcircuiteFlowToolchainProfile?
    public var executors: [XcircuiteFlowStageExecutorSpec]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
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

    public func makeRuntime(projectRoot: URL) async throws -> XcircuiteFlowRuntime {
        try validate(projectRoot: projectRoot)

        let executors = try executors.map {
            try $0.makeExecutor(projectRoot: projectRoot, toolchainProfile: toolchainProfile)
        }
        let toolBindings = try await makeToolBindings(projectRoot: projectRoot)

        return try XcircuiteFlowRuntime(
            toolRegistry: try ToolRegistry(descriptors: toolBindings.descriptors),
            healthResults: toolBindings.healthResults,
            executors: executors,
            workspaceStore: try XcircuiteWorkspaceStore(projectRoot: projectRoot),
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

    func makeUnqualifiedToolBindings() throws -> XcircuiteFlowRuntimeToolBindings {
        var descriptors: [String: (descriptor: ToolDescriptor, stageIDs: [String])] = [:]
        var healthResults: [String: (health: ToolHealthCheckResult, stageIDs: [String])] = [:]

        for spec in executors {
            let stageID = spec.stageID
            for descriptor in [spec.makeDescriptor()] + spec.additionalToolDescriptors() {
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
            }

            for health in [spec.makeUnqualifiedHealthResult()] + spec.additionalToolHealthResults() {
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

    func makeToolBindings(projectRoot: URL) async throws -> XcircuiteFlowRuntimeToolBindings {
        let unqualified = try makeUnqualifiedToolBindings()
        let references = try qualificationRecordReferences()
        guard !references.isEmpty else {
            return unqualified
        }

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let validator = ToolQualificationRecordValidator()
        var descriptors: [ToolDescriptor] = []
        var healthResults: [String: ToolHealthCheckResult] = [:]

        for baseDescriptor in unqualified.descriptors {
            guard let reference = references[baseDescriptor.toolID] else {
                descriptors.append(baseDescriptor)
                if let health = unqualified.healthResults[baseDescriptor.toolID] {
                    healthResults[baseDescriptor.toolID] = health
                }
                continue
            }
            let record: ToolQualificationRecord
            do {
                record = try await validator.validatedRecord(
                    referencedBy: reference,
                    expectedToolID: baseDescriptor.toolID,
                    reading: workspaceStore
                )
            } catch {
                throw XcircuiteFlowRuntimeSpecError.invalidQualificationRecord(
                    toolID: baseDescriptor.toolID,
                    reason: error.localizedDescription
                )
            }
            guard executionIdentityMatches(record.descriptor, baseDescriptor) else {
                throw XcircuiteFlowRuntimeSpecError.qualificationRecordExecutionIdentityMismatch(
                    toolID: baseDescriptor.toolID
                )
            }
            descriptors.append(record.descriptor)
            healthResults[record.descriptor.toolID] = record.health
        }
        return XcircuiteFlowRuntimeToolBindings(
            descriptors: descriptors.sorted { $0.toolID < $1.toolID },
            healthResults: healthResults
        )
    }

    private func qualificationRecordReferences() throws -> [String: ArtifactReference] {
        var references: [String: ArtifactReference] = [:]
        for spec in executors {
            for (toolID, reference) in spec.qualificationRecordReferences() {
                if let existing = references[toolID], existing != reference {
                    throw XcircuiteFlowRuntimeSpecError.conflictingQualificationRecord(toolID: toolID)
                }
                references[toolID] = reference
            }
        }
        return references
    }

    private func executionIdentityMatches(
        _ qualified: ToolDescriptor,
        _ base: ToolDescriptor
    ) -> Bool {
        qualified.toolID == base.toolID
            && qualified.displayName == base.displayName
            && qualified.kind == base.kind
            && qualified.version == base.version
            && qualified.capabilities == base.capabilities
            && qualified.environment == base.environment
    }
}

struct XcircuiteFlowRuntimeToolBindings: Sendable, Hashable {
    var descriptors: [ToolDescriptor]
    var healthResults: [String: ToolHealthCheckResult]
}
