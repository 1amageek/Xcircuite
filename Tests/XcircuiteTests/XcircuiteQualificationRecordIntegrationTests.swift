import CircuiteFoundation
import Foundation
import Testing
import ToolQualification
import XcircuiteFlowCLISupport

@testable import Xcircuite

@Suite("Xcircuite qualification record integration", .timeLimit(.minutes(1)))
struct XcircuiteQualificationRecordIntegrationTests {
    @Test func attachmentStoresOnlyRecordReference() throws {
        let reference = try recordReference(id: "record-a", path: "qualification/a.json")
        let updated = try runtimeSpec().attachingQualificationRecord(reference, toStageID: "sim")

        guard case .coreSpiceSimulation(let executor) = updated.executors[0] else {
            Issue.record("Expected a simulation executor")
            return
        }
        #expect(executor.tool.qualificationRecord == reference)
    }

    @Test func attachmentRejectsUnknownStage() throws {
        let reference = try recordReference(id: "record-a", path: "qualification/a.json")

        #expect(throws: XcircuiteFlowRuntimeSpecError.missingRuntimeExecutorForRunStage("missing")) {
            _ = try runtimeSpec().attachingQualificationRecord(reference, toStageID: "missing")
        }
    }

    @Test func unqualifiedBindingCannotSelfDeclareTrust() throws {
        let bindings = try runtimeSpec().makeUnqualifiedToolBindings()
        let descriptor = try #require(bindings.descriptors.first)
        let health = try #require(bindings.healthResults[descriptor.toolID])

        #expect(descriptor.trustProfile.level == .unknown)
        #expect(descriptor.trustProfile.evidence.isEmpty)
        #expect(health.status == .notChecked)
    }

    @Test func conflictingRecordReferencesFailClosed() async throws {
        let first = try recordReference(id: "record-a", path: "qualification/a.json")
        let second = try recordReference(id: "record-b", path: "qualification/b.json")
        let spec = XcircuiteFlowRuntimeSpec(executors: [
            .coreSpiceSimulation(.init(
                stageID: "sim-a",
                netlistPath: "a.cir",
                tool: XcircuiteFlowToolSpec(qualificationRecord: first)
            )),
            .coreSpiceSimulation(.init(
                stageID: "sim-b",
                netlistPath: "b.cir",
                tool: XcircuiteFlowToolSpec(qualificationRecord: second)
            )),
        ])

        await #expect(throws: XcircuiteFlowRuntimeSpecError.conflictingQualificationRecord(
            toolID: "corespice"
        )) {
            _ = try await spec.makeToolBindings(projectRoot: URL(filePath: "/tmp/xcircuite-record-conflict"))
        }
    }

    @Test func recordReferenceRoundTripsThroughRuntimeJSON() throws {
        let reference = try recordReference(id: "record-a", path: "qualification/a.json")
        let spec = try runtimeSpec().attachingQualificationRecord(reference, toStageID: "sim")
        let decoded = try JSONDecoder().decode(
            XcircuiteFlowRuntimeSpec.self,
            from: JSONEncoder().encode(spec)
        )

        #expect(decoded == spec)
    }

    @Test func descriptorFactoryAlwaysStartsUnqualified() {
        let descriptor = SignoffToolDescriptors.coreSpiceSimulation()

        #expect(descriptor.trustProfile.level == .unknown)
        #expect(descriptor.trustProfile.evidence.isEmpty)
    }

    @Test func attachQualificationRecordCLIValidatesCanonicalRecordReference() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "XcircuiteQualificationRecordIntegrationTests-\(UUID().uuidString)"
        )
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let unqualifiedSpec = runtimeSpec()
        let descriptor = try #require(unqualifiedSpec.makeUnqualifiedToolBindings().descriptors.first)
        let reference = try await QualifiedToolFixtures.qualificationRecordReference(
            for: descriptor,
            level: .smokeChecked,
            projectRoot: root
        )
        let runtimeURL = root.appending(path: "runtime.json")
        let referenceURL = root.appending(path: "qualification-record-reference.json")
        let attachedRuntimeURL = root.appending(path: "runtime-qualified.json")
        try writeJSON(unqualifiedSpec, to: runtimeURL)
        try writeJSON(reference, to: referenceURL)

        _ = try await XcircuiteFlowCLICommand.run(arguments: [
            "attach-qualification-record",
            "--project-root", root.path(percentEncoded: false),
            "--runtime-config", runtimeURL.path(percentEncoded: false),
            "--stage-id", "sim",
            "--record-reference", referenceURL.path(percentEncoded: false),
            "--out", attachedRuntimeURL.path(percentEncoded: false),
        ])

        let attachedSpec = try XcircuiteFlowRuntimeSpec.load(from: attachedRuntimeURL)
        guard case .coreSpiceSimulation(let executor) = attachedSpec.executors[0] else {
            Issue.record("Expected a simulation executor")
            return
        }
        #expect(executor.tool.qualificationRecord == reference)
        _ = try await attachedSpec.makeRuntime(projectRoot: root)
    }

    @Test func qualifiedRunRequirementFixturesDecodeCurrentSchema() throws {
        for name in ["qualified-evidence-run.json", "qualified-signoff-run.json"] {
            let runSpec = try XcircuiteFlowRunSpec.load(from: fixtureURL(name))
            #expect(runSpec.schemaVersion == XcircuiteFlowRunSpec.currentSchemaVersion)
            #expect(runSpec.stages.allSatisfy {
                $0.requiredTool?.requiredQualifiedEvidenceKinds.isEmpty == false
            })
        }
    }

    private func runtimeSpec() -> XcircuiteFlowRuntimeSpec {
        XcircuiteFlowRuntimeSpec(executors: [
            .coreSpiceSimulation(.init(stageID: "sim", netlistPath: "input.cir")),
        ])
    }

    private func recordReference(id: String, path: String) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: id == "record-a" ? "a" : "b", count: 64)
            ),
            byteCount: 1,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "tool-qualification",
                version: "1"
            )
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Fixtures/FlowRuntime"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
