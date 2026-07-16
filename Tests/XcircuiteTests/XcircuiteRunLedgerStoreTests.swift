import Foundation
import DesignFlowKernel
import CircuiteFoundation
import Testing
@testable import Xcircuite

@Suite("Xcircuite run-ledger persistence")
struct XcircuiteRunLedgerPersistenceTests {
    @Test
    func rejectsUnsafeRunIDsBeforeTouchingDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { remove(root) }

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        await #expect(throws: FlowIdentifierValidationError.invalidIdentifier(
            kind: FlowIdentifierKind.runID.rawValue,
            value: "../escape"
        )) {
            _ = try await store.loadRunLedger(runID: "../escape")
        }
    }

    @Test
    func persistsLifecycleThroughKernelCoordinator() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-1"))

        let transitioned = try await FlowRunLedgerCoordinator(persistence: store).transition(
            runID: "run-1",
            to: .running
        )
        #expect(transitioned.runManifest.status == .running)
        #expect(transitioned.runManifest.revision == 1)

        let reloaded = try await store.loadRunLedger(runID: "run-1")
        #expect(reloaded == transitioned)

        let projectManifest = try await store.loadManifest()
        #expect(projectManifest.runs == [
            FlowRunReference(
                runID: "run-1",
                manifestPath: ".xcircuite/runs/run-1/manifest.json"
            )
        ])
    }

    @Test
    func concurrentRunCreationRetainsEveryProjectManifestReference() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)

        async let firstSave: Void = first.saveRunLedger(try makeLedger(runID: "run-a"))
        async let secondSave: Void = second.saveRunLedger(try makeLedger(runID: "run-b"))
        _ = try await (firstSave, secondSave)

        let projectManifest = try await first.loadManifest()
        #expect(projectManifest.runs.map(\.runID) == ["run-a", "run-b"])
    }

    @Test
    func persistingDesignDiffUpdatesCanonicalLedgerField() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-diff"))
        let diff = DesignDiff(
            runID: "run-diff",
            title: "Layout repair",
            actor: "test",
            changes: [
                DesignDiffChange(
                    changeID: "change-1",
                    domain: .layout,
                    operation: .replace,
                    path: "layout/top.gds",
                    summary: "Replace repaired layout"
                )
            ]
        )

        let reference = try await store.persistDesignDiff(diff)
        let ledger = try await store.loadRunLedger(runID: "run-diff")

        #expect(ledger.designDiff == diff)
        #expect(ledger.artifacts.contains(reference))
        #expect(ledger.runManifest.revision == 1)
    }

    @Test
    func isolatesLedgersByBoundProjectRoot() async throws {
        let root = try makeTemporaryRoot()
        let otherRoot = try makeTemporaryRoot()
        defer {
            remove(root)
            remove(otherRoot)
        }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let otherStore = try XcircuiteWorkspaceStore(projectRoot: otherRoot)
        try await store.saveRunLedger(try makeLedger(runID: "run-1"))

        await #expect(throws: FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: "run-1")) {
            _ = try await otherStore.loadRunLedger(runID: "run-1")
        }

        #expect(try await store.loadRunLedger(runID: "run-1").runID == "run-1")
    }

    @Test
    func rejectsStaleConcurrentWriter() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)
        let initial = try makeLedger(runID: "run-1")
        try await first.saveRunLedger(initial)

        _ = try await FlowRunLedgerCoordinator(persistence: first).transition(
            runID: "run-1",
            to: .running
        )
        var stale = try makeLedger(runID: "run-1", revision: 1)
        stale.progressEvents.append(
            FlowRunProgressEvent(
                runID: "run-1",
                sequence: 1,
                kind: .runStarted,
                runStatus: .running,
                message: "stale"
            )
        )

        await #expect(throws: FlowRunLedgerPersistenceError.concurrentUpdate(
            runID: "run-1",
            expectedRevision: 2,
            actualRevision: 1
        )) {
            try await second.saveRunLedger(stale)
        }
    }

    @Test
    func atomicRevisionCheckAllowsExactlyOneConcurrentWriter() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)
        try await first.saveRunLedger(try makeLedger(runID: "run-cas"))

        var firstProposal = try makeLedger(runID: "run-cas", revision: 1)
        firstProposal.progressEvents.append(progressEvent(runID: "run-cas", sequence: 1))
        var secondProposal = try makeLedger(runID: "run-cas", revision: 1)
        secondProposal.progressEvents.append(progressEvent(runID: "run-cas", sequence: 2))
        let firstLedger = firstProposal
        let secondLedger = secondProposal

        async let firstResult = capture {
            try await first.saveRunLedger(firstLedger)
        }
        async let secondResult = capture {
            try await second.saveRunLedger(secondLedger)
        }
        let results = await [firstResult, secondResult]
        #expect(results.filter(\.isSuccess).count == 1)
        #expect(results.filter(\.isConcurrentUpdate).count == 1)
    }

    @Test
    func concurrentProgressAppendsPersistEveryEventWithUniqueSequence() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let firstStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let secondStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await firstStore.saveRunLedger(try makeLedger(runID: "run-progress"))
        let firstProgress = FlowRunProgressStore(persistence: firstStore)
        let secondProgress = FlowRunProgressStore(persistence: secondStore)

        async let first = firstProgress.appendEvent(
            runID: "run-progress",
            kind: .runStarted,
            runStatus: .running,
            message: "first writer"
        )
        async let second = secondProgress.appendEvent(
            runID: "run-progress",
            kind: .runStarted,
            runStatus: .running,
            message: "second writer"
        )
        let events = try await [first, second]

        #expect(Set(events.map(\.sequence)) == [1, 2])
        let persistedEvents = try await firstProgress.loadProgressEvents(runID: "run-progress")
        #expect(persistedEvents.count == 2)
        #expect(persistedEvents.map(\.sequence) == [1, 2])
        #expect(Set(persistedEvents.map(\.message)) == ["first writer", "second writer"])
        let ledger = try await firstStore.loadRunLedger(runID: "run-progress")
        #expect(ledger.progressEvents == persistedEvents)
    }

    @Test
    func revalidatesRetainedArtifactsOnLoad() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let workspace = try XcircuiteWorkspaceStore(projectRoot: root)
        let path = ".xcircuite/runs/run-1/report.json"
        try await workspace.writeImmutable(Data("qualified".utf8), to: path)
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .output,
            kind: .report,
            format: .json
        )
        let reference = try LocalArtifactReferencer().reference(
            locator,
            relativeTo: await workspace.projectRoot
        )
        var ledger = try makeLedger(runID: "run-1")
        ledger.artifacts = [reference]
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(ledger)

        try await workspace.write(Data("tampered".utf8), to: path)
        do {
            _ = try await store.loadAttestedRunLedger(runID: "run-1")
            Issue.record("Expected retained artifact integrity failure.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let failedPath, _) = error else {
                Issue.record("Unexpected ledger error: \(error.localizedDescription)")
                return
            }
            #expect(failedPath == path)
        }
    }

    @Test
    func recoversInterruptedRunLedgerGenerationBeforeReading() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-recovery"))
        let interruptedStore = try XcircuiteWorkspaceStore(
            projectRoot: root,
            transactionFault: .afterOperation(0)
        )
        let proposal = try makeLedger(runID: "run-recovery", revision: 1)

        await #expect(throws: XcircuiteWorkspaceTransactionError.injectedFailure(.afterOperation(0))) {
            try await interruptedStore.saveRunLedger(proposal)
        }

        let recovered = try await store.loadRunLedger(runID: "run-recovery")
        #expect(recovered == proposal)
        let transactionDirectory = root.appending(path: ".xcircuite/transactions")
        let remaining = try FileManager.default.contentsOfDirectory(
            at: transactionDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        #expect(remaining.isEmpty)
    }

    @Test
    func rejectsDifferentEmbeddedRunIdentifier() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-identity"))
        var corrupted = try await store.loadRunLedger(runID: "run-identity")
        corrupted.runManifest = try FlowRunManifest(
            runID: "different-run",
            status: .created,
            revision: 0,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try writeRawLedger(corrupted, root: root)

        await #expect(throws: FlowRunLedgerPersistenceError.runIdentifierMismatch(
            requested: "run-identity",
            stored: "different-run"
        )) {
            _ = try await store.loadRunLedger(runID: "run-identity")
        }
    }

    @Test
    func rejectsDifferentCanonicalAndEmbeddedManifests() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-manifest"))
        let differentManifest = try FlowRunManifest(
            runID: "run-manifest",
            status: .running,
            revision: 1,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let manifestURL = root.appending(path: ".xcircuite/runs/run-manifest/manifest.json")
        try sortedEncoder().encode(differentManifest).write(to: manifestURL, options: .atomic)

        do {
            _ = try await store.loadRunLedger(runID: "run-manifest")
            Issue.record("Expected canonical manifest mismatch.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .decodingFailed(let message) = error else {
                Issue.record("Unexpected ledger error: \(error.localizedDescription)")
                return
            }
            #expect(message.contains("Canonical and embedded run manifests differ"))
        }
    }

    @Test
    func rejectsDifferentLedgerAndManifestArtifactSets() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-artifacts"))
        let artifactPath = ".xcircuite/runs/run-artifacts/report.json"
        let artifactData = Data("retained".utf8)
        try artifactData.write(to: root.appending(path: artifactPath), options: .atomic)
        let reference = try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: artifactPath),
                role: .output,
                kind: .report,
                format: .json
            ),
            relativeTo: root
        )
        var corrupted = try await store.loadRunLedger(runID: "run-artifacts")
        corrupted.artifacts = [reference]
        try writeRawLedger(corrupted, root: root)

        do {
            _ = try await store.loadRunLedger(runID: "run-artifacts")
            Issue.record("Expected artifact-set mismatch.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .decodingFailed(let message) = error else {
                Issue.record("Unexpected ledger error: \(error.localizedDescription)")
                return
            }
            #expect(message.contains("different artifact sets"))
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

    private func makeLedger(
        runID: String,
        revision: Int = 0
    ) throws -> FlowRunLedger {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = try FlowRunManifest(
            runID: runID,
            status: revision == 0 ? .created : .running,
            revision: revision,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            createdAt: now,
            updatedAt: now,
            startedAt: revision == 0 ? nil : now
        )
        return FlowRunLedger(
            runID: runID,
            runManifest: manifest,
            stages: []
        )
    }

    private func progressEvent(runID: String, sequence: Int) -> FlowRunProgressEvent {
        FlowRunProgressEvent(
            runID: runID,
            sequence: sequence,
            kind: .runStarted,
            runStatus: .running,
            message: "writer-\(sequence)"
        )
    }

    private func writeRawLedger(_ ledger: FlowRunLedger, root: URL) throws {
        let url = root.appending(path: ".xcircuite/runs/\(ledger.runID)/ledger.json")
        try sortedEncoder().encode(ledger).write(to: url, options: .atomic)
    }

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func capture(
        _ operation: @Sendable () async throws -> Void
    ) async -> Result<Void, Error> {
        do {
            try await operation()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to clean up temporary workspace: \(error.localizedDescription)")
        }
    }
}

private extension Result where Success == Void, Failure == Error {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isConcurrentUpdate: Bool {
        guard case .failure(let error) = self,
              let persistenceError = error as? FlowRunLedgerPersistenceError,
              case .concurrentUpdate = persistenceError else {
            return false
        }
        return true
    }
}
