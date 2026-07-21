import Foundation
import Testing
import CircuiteFoundation
import DesignFlowKernel
import ReleaseCore
import TapeoutEngine
@testable import Xcircuite

@Suite("XcircuiteWorkspaceStore")
struct XcircuiteWorkspaceStoreTests {
    @Test
    func persistsReleaseArtifactsThroughTheWorkspaceStoreContract() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.createWorkspace()
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "release/top.gds"),
            role: .output,
            kind: .layout,
            format: .gdsii
        )
        let producer = try ProducerIdentity(
            kind: .tool,
            identifier: "release-stream-encoder",
            version: "1.0.0"
        )
        let request = ReleaseArtifactPersistenceRequest(
            locator: locator,
            bytes: Data("gds-stream".utf8),
            producer: producer
        )

        let reference = try await store.persist(request, relativeTo: root)
        #expect(reference.producer == producer)
        #expect(try await store.load(reference, relativeTo: root) == request.bytes)

        await #expect(throws: XcircuiteWorkspaceStoreError.artifactAlreadyExists("release/top.gds")) {
            _ = try await store.persist(request, relativeTo: root)
        }
    }

    @Test
    func releaseArtifactPersistenceRejectsSymlinkEscape() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        defer {
            remove(root)
            remove(outside)
        }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.createWorkspace()
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "release"),
            withDestinationURL: outside
        )
        let request = ReleaseArtifactPersistenceRequest(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/top.gds"),
                role: .output,
                kind: .layout,
                format: .gdsii
            ),
            bytes: Data("gds-stream".utf8),
            producer: try ProducerIdentity(
                kind: .tool,
                identifier: "release-stream-encoder",
                version: "1.0.0"
            )
        )

        await #expect(throws: XcircuiteWorkspaceStoreError.unsafeProjectPath("release/top.gds")) {
            _ = try await store.persist(request, relativeTo: root)
        }
    }

    @Test
    func writesAndReadsProjectLocalArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.write(Data("artifact".utf8), to: ".xcircuite/runs/run-1/report.json")
        #expect(try await store.read(from: ".xcircuite/runs/run-1/report.json") == Data("artifact".utf8))
    }

    @Test
    func writesAndReadsJSONWithIdiomaticLabels() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let value = ["count": 3]
        try await store.writeJSON(value, to: ".xcircuite/runs/run-1/summary.json")
        let decoded = try await store.readJSON([String: Int].self, from: ".xcircuite/runs/run-1/summary.json")

        #expect(decoded == value)
    }

    @Test
    func rejectsTraversalAndAbsolutePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidArtifactLocation("../outside")) {
            try await store.write(Data(), to: "../outside")
        }
        await #expect(throws: XcircuiteWorkspaceStoreError.invalidArtifactLocation("/tmp/outside")) {
            try await store.write(Data(), to: "/tmp/outside")
        }
    }

    @Test
    func rejectsSymlinkEscape() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            remove(root)
            remove(outside)
        }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        let link = root.appending(path: ".xcircuite/escape", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: XcircuiteWorkspaceStoreError.pathOutsideWorkspace(".xcircuite/escape/file")) {
            try await store.write(Data(), to: ".xcircuite/escape/file")
        }
    }

    @Test
    func rejectsSymbolicWorkspaceRoot() async throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        defer {
            remove(root)
            remove(outside)
        }

        let workspace = root.appending(path: ".xcircuite", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: workspace, withDestinationURL: outside)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)

        await #expect(throws: XcircuiteWorkspaceStoreError.symbolicWorkspaceRoot(workspace.path())) {
            try await store.write(Data("artifact".utf8), to: ".xcircuite/runs/run-1/report.json")
        }
    }

    @Test
    func immutableArtifactRejectsReplacement() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        try await store.writeImmutable(Data("original".utf8), to: path)
        try await store.writeImmutable(Data("original".utf8), to: path)

        await #expect(throws: XcircuiteWorkspaceStoreError.immutableArtifactConflict(path)) {
            try await store.writeImmutable(Data("replacement".utf8), to: path)
        }
        #expect(try await store.read(from: path) == Data("original".utf8))
    }

    @Test
    func createOnlyArtifactRejectsAnIdenticalSecondWrite() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-create-only"
        let path = ".xcircuite/runs/\(runID)/archive.json"
        let content = Data("archive".utf8)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        try await prepareTestRun(runID: runID, store: store)
        _ = try await store.persistArtifact(
            content: content,
            id: try ArtifactID(rawValue: "archive"),
            locator: locator,
            runID: runID,
            mode: .createOnly
        )

        await #expect(throws: XcircuiteWorkspaceStoreError.artifactAlreadyExists(path)) {
            _ = try await store.persistArtifact(
                content: content,
                id: try ArtifactID(rawValue: "archive"),
                locator: locator,
                runID: runID,
                mode: .createOnly
            )
        }
        #expect(try await store.read(from: path) == content)
    }

    @Test
    func terminalRunAcceptsNewAuditArtifactButRejectsReplacement() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-terminal-audit"
        try await prepareTestRun(runID: runID, store: store)
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        let terminalStageID = "audit-ready"
        _ = try await coordinator.finalize(
            runID: runID,
            status: .succeeded,
            stages: [FlowStageResult(stageID: terminalStageID, status: .succeeded)],
            toolchain: FlowToolchainManifest(
                runID: runID,
                stages: [
                    FlowToolchainStageRecord(
                        stageID: terminalStageID,
                        executorToolID: "workspace-store-test"
                    ),
                ]
            ),
            evidence: EvidenceManifest(
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(
                        kind: .engine,
                        identifier: "workspace-store-test",
                        version: "1"
                    ),
                    inputs: [],
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    completedAt: Date(timeIntervalSince1970: 1_700_000_001)
                ),
                artifacts: []
            ),
            artifacts: []
        )

        let path = ".xcircuite/runs/\(runID)/review/audit.json"
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .evidence,
            format: .json
        )
        let original = Data("audit".utf8)
        let reference = try await store.persistArtifact(
            content: original,
            id: try ArtifactID(rawValue: "terminal-audit"),
            locator: locator,
            runID: runID,
            mode: .replaceable
        )

        #expect(try await store.loadArtifactContent(for: reference) == original)
        #expect(try await store.loadRunLedger(runID: runID).artifacts.contains(reference))
        await #expect(throws: XcircuiteWorkspaceStoreError.terminalRunArtifactMutation(
            runID: runID,
            path: path
        )) {
            _ = try await store.persistArtifact(
                content: Data("replacement".utf8),
                id: try ArtifactID(rawValue: "terminal-audit"),
                locator: locator,
                runID: runID,
                mode: .replaceable
            )
        }
    }

    @Test
    func terminalRunAllowsOnlyPrefixPreservingAuditAppend() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-terminal-append"
        try await prepareTestRun(runID: runID, store: store)
        let coordinator = FlowRunLedgerCoordinator(persistence: store)
        _ = try await coordinator.transition(runID: runID, to: .running)
        let stageID = "append-ready"
        _ = try await coordinator.finalize(
            runID: runID,
            status: .succeeded,
            stages: [FlowStageResult(stageID: stageID, status: .succeeded)],
            toolchain: FlowToolchainManifest(
                runID: runID,
                stages: [FlowToolchainStageRecord(stageID: stageID, executorToolID: "workspace-store-test")]
            ),
            evidence: EvidenceManifest(
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(kind: .engine, identifier: "workspace-store-test", version: "1"),
                    inputs: [],
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    completedAt: Date(timeIntervalSince1970: 1_700_000_001)
                ),
                artifacts: []
            ),
            artifacts: []
        )

        let path = ".xcircuite/runs/\(runID)/planning/rejected-plans.jsonl"
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .other,
            format: .text
        )
        let first = Data("{\"id\":1}\n".utf8)
        let second = Data("{\"id\":1}\n{\"id\":2}\n".utf8)
        _ = try await store.persistArtifact(
            content: first,
            id: try ArtifactID(rawValue: "append-only-audit"),
            locator: locator,
            runID: runID,
            mode: .appendOnly
        )
        let appended = try await store.persistArtifact(
            content: second,
            id: try ArtifactID(rawValue: "append-only-audit"),
            locator: locator,
            runID: runID,
            mode: .appendOnly
        )

        #expect(try await store.loadArtifactContent(for: appended) == second)
        await #expect(throws: XcircuiteWorkspaceStoreError.appendOnlyArtifactConflict(path)) {
            _ = try await store.persistArtifact(
                content: Data("{\"id\":0}\n{\"id\":2}\n".utf8),
                id: try ArtifactID(rawValue: "append-only-audit"),
                locator: locator,
                runID: runID,
                mode: .appendOnly
            )
        }
        #expect(try await store.read(from: path) == second)
    }

    @Test
    func persistsArtifactProducerInLedgerAndRunManifest() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-producer-lineage"
        try await prepareTestRun(runID: runID, store: store)
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "logic-simulation",
            version: "2.1.0"
        )
        let reference = try await store.persistArtifact(
            content: Data("measured-result".utf8),
            id: try ArtifactID(rawValue: "measured-result"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(runID)/stages/logic.simulate/raw/result.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: runID,
            producer: producer,
            mode: .immutable
        )

        let ledger = try await store.loadRunLedger(runID: runID)
        let manifest = try await store.loadRunManifest(runID: runID)
        #expect(reference.producer == producer)
        #expect(ledger.artifacts.first { $0.id == reference.id }?.producer == producer)
        #expect(manifest.artifacts.first { $0.id == reference.id }?.producer == producer)
    }

    @Test
    func recoversInterruptedRunArtifactRegistration() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-artifact-recovery", store: store)
        let interruptedStore = try XcircuiteWorkspaceStore(
            projectRoot: root,
            transactionFault: .afterOperation(0)
        )
        let path = ".xcircuite/runs/run-artifact-recovery/recovered.json"
        let content = Data("recovered-run-artifact".utf8)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )

        await #expect(throws: XcircuiteWorkspaceTransactionError.injectedFailure(.afterOperation(0))) {
            _ = try await interruptedStore.persistArtifact(
                content: content,
                id: try ArtifactID(rawValue: "recovered-run-artifact"),
                locator: locator,
                runID: "run-artifact-recovery",
                mode: .replaceable
            )
        }

        let ledger = try await store.loadRunLedger(runID: "run-artifact-recovery")
        let reference = try #require(ledger.artifacts.first {
            $0.id.rawValue == "recovered-run-artifact"
        })
        #expect(reference.path == path)
        #expect(try await store.loadArtifactContent(for: reference) == content)
    }

    @Test
    func independentStoresSerializeConcurrentWrites() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/ledger.json"

        async let firstWrite: Void = first.write(Data(repeating: 0x41, count: 65_536), to: path)
        async let secondWrite: Void = second.write(Data(repeating: 0x42, count: 65_536), to: path)
        _ = try await (firstWrite, secondWrite)

        let retained = try await first.read(from: path)
        #expect(
            retained == Data(repeating: 0x41, count: 65_536)
                || retained == Data(repeating: 0x42, count: 65_536)
        )
    }

    @Test
    func concurrentProjectArtifactRegistrationRetainsEveryManifestEntry() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)
        try await first.createWorkspace()
        let firstLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "reports/first.json"),
            role: .output,
            kind: .report,
            format: .json
        )
        let secondLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "reports/second.json"),
            role: .output,
            kind: .report,
            format: .json
        )

        async let firstReference = first.persistProjectArtifact(
            content: Data("first".utf8),
            id: try ArtifactID(rawValue: "first-report"),
            locator: firstLocator
        )
        async let secondReference = second.persistProjectArtifact(
            content: Data("second".utf8),
            id: try ArtifactID(rawValue: "second-report"),
            locator: secondLocator
        )
        _ = try await (firstReference, secondReference)

        let manifest = try await first.loadManifest()
        #expect(manifest.files.map(\.path) == ["reports/first.json", "reports/second.json"])
    }

    @Test
    func recoversInterruptedProjectArtifactRegistration() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.createWorkspace()
        let interruptedStore = try XcircuiteWorkspaceStore(
            projectRoot: root,
            transactionFault: .afterOperation(0)
        )
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "reports/recovered.json"),
            role: .output,
            kind: .report,
            format: .json
        )

        await #expect(throws: XcircuiteWorkspaceTransactionError.injectedFailure(.afterOperation(0))) {
            _ = try await interruptedStore.persistProjectArtifact(
                content: Data("recovered".utf8),
                id: try ArtifactID(rawValue: "recovered-report"),
                locator: locator
            )
        }

        let manifest = try await store.loadManifest()
        #expect(manifest.files.map(\.path) == ["reports/recovered.json"])
        #expect(try Data(contentsOf: root.appending(path: "reports/recovered.json")) == Data("recovered".utf8))
    }

    @Test
    func rejectsBlankCancellationRequesterAndReason() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-cancel", store: store)

        await #expect(throws: FlowRunCancellationRequestError.emptyRequestedBy) {
            _ = try await store.persistCancellationRequest(
                FlowRunCancellationRequest(
                    runID: "run-cancel",
                    requestedBy: "  ",
                    reason: "Stop the run."
                )
            )
        }
        await #expect(throws: FlowRunCancellationRequestError.emptyReason) {
            _ = try await store.persistCancellationRequest(
                FlowRunCancellationRequest(
                    runID: "run-cancel",
                    requestedBy: "operator",
                    reason: "\n"
                )
            )
        }
    }

    @Test
    func verifiesArtifactDigestAndByteCount() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        let data = Data("artifact".utf8)
        try await store.write(data, to: path)
        let reference = try await makeReference(for: path, store: store)

        let integrity = try await store.verify(reference)
        #expect(integrity.isVerified)
        #expect(integrity.issues.isEmpty)
    }

    @Test
    func rejectsArtifactDigestMismatch() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        try await store.write(Data("artifact".utf8), to: path)
        let reference = try await makeReference(for: path, store: store)
        try await store.write(Data("tampered".utf8), to: path)

        do {
            _ = try await store.verify(reference)
            Issue.record("Expected digest verification to fail.")
        } catch let error as XcircuiteWorkspaceStoreError {
            guard case .artifactIntegrityFailed(_, let issues) = error else {
                Issue.record("Unexpected workspace error: \(error.localizedDescription)")
                return
            }
            #expect(issues.contains { $0.code == .digestMismatch })
        }
    }

    @Test
    func rejectsArtifactByteCountMismatch() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        let data = Data("artifact".utf8)
        try await store.write(data, to: path)
        let reference = try await makeReference(for: path, store: store)
        try await store.write(Data("changed-byte-count".utf8), to: path)

        do {
            _ = try await store.verify(reference)
            Issue.record("Expected byte-count verification to fail.")
        } catch let error as XcircuiteWorkspaceStoreError {
            guard case .artifactIntegrityFailed(_, let issues) = error else {
                Issue.record("Unexpected workspace error: \(error.localizedDescription)")
                return
            }
            #expect(issues.contains { $0.code == .byteCountMismatch })
        }
    }

    @Test
    func rejectsMissingArtifact() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/missing.json"
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "0", count: 64)
        )
        let reference = ArtifactReference(
            locator: locator,
            digest: digest,
            byteCount: 0
        )

        await #expect(throws: XcircuiteWorkspaceStoreError.missingArtifact(path)) {
            _ = try await store.verify(reference)
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeReference(
        for path: String,
        store: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference {
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        return try LocalArtifactReferencer().reference(
            locator,
            relativeTo: store.projectRoot
        )
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to clean up temporary workspace: \(error.localizedDescription)")
        }
    }
}
