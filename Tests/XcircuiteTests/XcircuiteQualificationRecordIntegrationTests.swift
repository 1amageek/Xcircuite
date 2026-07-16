import CircuiteFoundation
import Foundation
import Testing
import ToolQualification

@testable import Xcircuite

@Suite("Xcircuite qualification record integration")
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
}
