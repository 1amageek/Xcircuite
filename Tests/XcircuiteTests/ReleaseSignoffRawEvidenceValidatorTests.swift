import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation
import LVSEngine
import Testing
import TimingCore
import ToolQualification
@testable import Xcircuite

@Suite("Release signoff raw evidence validation")
struct ReleaseSignoffRawEvidenceValidatorTests {
    @Test("timing accepts only the exact retained canonical result artifacts")
    func timingRequiresExactCanonicalArtifacts() async throws {
        let fixture = try fixture()
        defer { remove(fixture.root) }
        let runID = "raw-evidence-timing"
        let bytes = Data("{\"slack\":0.1}".utf8)
        let canonical = try await fixture.store.persistProjectArtifact(
            content: bytes,
            id: try ArtifactID(rawValue: "timing-report"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "evidence/\(runID)/timing/report.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            producer: fixture.producer,
            mode: .immutable
        )
        let sameBytesAtAnotherLocation = try await fixture.store.persistProjectArtifact(
            content: bytes,
            id: try ArtifactID(rawValue: "timing-report-copy"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "evidence/\(runID)/timing-copy/report.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            producer: fixture.producer,
            mode: .immutable
        )
        let executionProvenance = try provenance(fixture: fixture)

        try await ReleaseSignoffRawEvidenceValidator().validateTiming(
            provenance: executionProvenance,
            resultArtifacts: [canonical],
            qualificationScope: fixture.scope,
            rawEvidence: [canonical],
            reading: fixture.store
        )

        await #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try await ReleaseSignoffRawEvidenceValidator().validateTiming(
                provenance: executionProvenance,
                resultArtifacts: [canonical],
                qualificationScope: fixture.scope,
                rawEvidence: [sameBytesAtAnotherLocation],
                reading: fixture.store
            )
        }
    }

    @Test("DRC cannot pass release without retained raw artifacts")
    func drcRequiresRetainedRawArtifacts() async throws {
        let fixture = try fixture()
        defer { remove(fixture.root) }
        let request = DRCRequest(
            layoutURL: URL(filePath: "/fixture/layout.json"),
            topCell: "TOP",
            backendSelection: DRCBackendSelection(backendID: "native"),
            executionInputArtifacts: [fixture.input]
        )
        let execution = DRCExecutionResult(
            request: request,
            result: DRCResult(
                backendID: "native",
                toolName: "Native DRC",
                success: true,
                completed: true,
                logPath: ""
            ),
            artifactRunID: "raw-evidence-drc",
            provenance: try provenance(fixture: fixture)
        )

        await #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try await ReleaseSignoffRawEvidenceValidator().validateDRC(
                execution,
                qualificationScope: fixture.scope,
                manifestArtifact: nil,
                reportArtifact: nil,
                rawEvidence: [],
                reading: fixture.store
            )
        }
    }

    @Test("LVS cannot pass release without retained raw artifacts")
    func lvsRequiresRetainedRawArtifacts() async throws {
        let fixture = try fixture()
        defer { remove(fixture.root) }
        let request = LVSRequest(
            layoutNetlistURL: URL(filePath: "/fixture/layout.spice"),
            schematicNetlistURL: URL(filePath: "/fixture/schematic.spice"),
            topCell: "TOP",
            backendSelection: LVSBackendSelection(backendID: "native"),
            executionInputArtifacts: [fixture.input]
        )
        let execution = LVSExecutionResult(
            request: request,
            result: LVSResult(
                backendID: "native",
                toolName: "Native LVS",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                logPath: ""
            ),
            provenance: try provenance(fixture: fixture)
        )

        await #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try await ReleaseSignoffRawEvidenceValidator().validateLVS(
                execution,
                qualificationScope: fixture.scope,
                manifestArtifact: nil,
                reportArtifact: nil,
                rawEvidence: [],
                reading: fixture.store
            )
        }
    }

    @Test("DRC input coverage compares the complete artifact identity")
    func drcInputCoverageRejectsContentEquivalentSubstitution() throws {
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "b", count: 64)
        )
        let source = ArtifactReference(
            id: try ArtifactID(rawValue: "drc-source-layout"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/layout.gds"),
                role: .input,
                kind: .layout,
                format: .gdsii
            ),
            digest: digest,
            byteCount: 1
        )
        let substituted = ArtifactReference(
            id: try ArtifactID(rawValue: "drc-substituted-layout"),
            locator: source.locator,
            digest: digest,
            byteCount: 1
        )
        let record = DRCArtifactRecord(
            id: "input-layout",
            kind: .layout,
            path: "retained-artifacts/input-layout/layout.gds",
            byteCount: 1,
            sha256: digest.hexadecimalValue,
            sourceReference: substituted
        )

        #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try ReleaseSignoffRawEvidenceValidator().validateDRCInputCoverage(
                [record],
                provenanceInputs: [source]
            )
        }
    }

    @Test("LVS derived netlist retains its producer-bound output identity")
    func lvsInputCoverageValidatesDerivedIdentity() throws {
        let fixture = try fixture()
        defer { remove(fixture.root) }
        let sourceDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "b", count: 64)
        )
        let derivedDigest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "c", count: 64)
        )
        let source = ArtifactReference(
            id: try ArtifactID(rawValue: "lvs-source-schematic"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/schematic.spice"),
                role: .input,
                kind: .netlist,
                format: .spice
            ),
            digest: sourceDigest,
            byteCount: 1
        )
        let derived = ArtifactReference(
            id: try ArtifactID(rawValue: "lvs-derived-layout-netlist"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "runs/extracted-layout.spice"),
                role: .output,
                kind: .netlist,
                format: .spice
            ),
            digest: derivedDigest,
            byteCount: 2,
            producer: fixture.producer
        )
        let sourceRecord = LVSArtifactRecord(
            id: "input-schematic-netlist",
            kind: .schematicNetlist,
            path: "retained-artifacts/input-schematic-netlist/schematic.spice",
            byteCount: 1,
            sha256: sourceDigest.hexadecimalValue,
            sourceReference: source
        )
        let derivedRecord = LVSArtifactRecord(
            id: "input-layout-netlist",
            kind: .layoutNetlist,
            path: "retained-artifacts/input-layout-netlist/extracted-layout.spice",
            byteCount: 2,
            sha256: derivedDigest.hexadecimalValue,
            derivedReference: derived
        )
        let validator = ReleaseSignoffRawEvidenceValidator()

        try validator.validateLVSInputCoverage(
            [sourceRecord, derivedRecord],
            provenanceInputs: [source, derived],
            allowsDerivedLayoutNetlist: true
        )

        let substituted = ArtifactReference(
            id: try ArtifactID(rawValue: "lvs-substituted-layout-netlist"),
            locator: derived.locator,
            digest: derivedDigest,
            byteCount: 2,
            producer: fixture.producer
        )
        let substitutedRecord = LVSArtifactRecord(
            id: derivedRecord.id,
            kind: derivedRecord.kind,
            path: derivedRecord.path,
            byteCount: derivedRecord.byteCount,
            sha256: derivedRecord.sha256,
            derivedReference: substituted
        )
        #expect(throws: ReleaseSignoffEvidenceAssemblyError.self) {
            try validator.validateLVSInputCoverage(
                [sourceRecord, substitutedRecord],
                provenanceInputs: [source, derived],
                allowsDerivedLayoutNetlist: true
            )
        }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "xcircuite-raw-evidence-validator-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "fixture-engine",
            version: "1.0.0",
            build: String(repeating: "a", count: 64)
        )
        let input = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "inputs/design.json"),
                role: .input,
                kind: .input,
                format: .json
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "b", count: 64)
            ),
            byteCount: 1
        )
        return Fixture(
            root: root,
            store: try XcircuiteWorkspaceStore(projectRoot: root),
            producer: producer,
            input: input,
            scope: ToolQualificationScope(
                implementationID: producer.identifier,
                toolVersion: producer.version,
                binaryDigest: producer.build ?? "",
                algorithmVersion: "fixture-v1",
                processProfileID: "fixture-process",
                processProfileDigest: String(repeating: "c", count: 64),
                deckDigest: String(repeating: "d", count: 64)
            )
        )
    }

    private func provenance(fixture: Fixture) throws -> ExecutionProvenance {
        try ExecutionProvenance(
            producer: fixture.producer,
            inputs: [fixture.input],
            invocation: ExecutionInvocation.inProcess(entryPoint: "Fixture.execute"),
            environment: ExecutionEnvironmentFingerprint(
                platform: "test",
                architecture: "test",
                toolchain: "fixture",
                environmentDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "e", count: 64)
                )
            ),
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
    }

    private func remove(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove raw evidence fixture: \(error)")
        }
    }

    private struct Fixture {
        let root: URL
        let store: XcircuiteWorkspaceStore
        let producer: ProducerIdentity
        let input: ArtifactReference
        let scope: ToolQualificationScope
    }
}
