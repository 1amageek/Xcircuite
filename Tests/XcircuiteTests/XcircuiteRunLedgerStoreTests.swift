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
        #expect(transitioned.runResult.status == .running)
        #expect(transitioned.runManifest.revision == 1)

        let reloaded = try await store.loadRunLedger(runID: "run-1")
        #expect(reloaded == transitioned)
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
