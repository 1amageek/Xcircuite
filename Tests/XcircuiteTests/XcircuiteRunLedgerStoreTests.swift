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
    func canonicalizesPersistedEvidenceArtifactOrder() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let references = try ["z-report.json", "a-report.json"].map {
            try makeArtifactReference(path: $0, root: root)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var ledger = try makeLedger(runID: "run-evidence-order")
        ledger.artifacts = references
        ledger.runManifest = try FlowRunManifest(
            runID: ledger.runID,
            status: .created,
            actor: ledger.runManifest.actor,
            createdAt: now,
            updatedAt: now,
            artifacts: references
        )
        let provenance = try ExecutionProvenance(
            producer: ProducerIdentity(kind: .engine, identifier: "test-engine", version: "1"),
            inputs: references,
            startedAt: now,
            completedAt: now
        )
        ledger.evidence = EvidenceManifest(provenance: provenance, artifacts: references)

        try await store.saveRunLedger(ledger)
        let persisted = try await store.loadRunLedger(runID: ledger.runID)

        #expect(persisted.artifacts.map(\.path) == references.map(\.path).sorted())
        #expect(persisted.evidence?.artifacts == persisted.artifacts)
        #expect(persisted.evidence?.provenance.inputs == persisted.artifacts)
    }

    @Test
    func rejectsNonProjectionEvidenceInventoryChanges() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let references = try ["first.json", "unattested.json"].map {
            try makeArtifactReference(path: $0, root: root)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var ledger = try makeLedger(runID: "run-evidence-mismatch")
        ledger.artifacts = references
        ledger.runManifest = try FlowRunManifest(
            runID: ledger.runID,
            status: .created,
            actor: ledger.runManifest.actor,
            createdAt: now,
            updatedAt: now,
            artifacts: references
        )
        let provenance = try ExecutionProvenance(
            producer: ProducerIdentity(kind: .engine, identifier: "test-engine", version: "1"),
            inputs: [references[0]],
            startedAt: now,
            completedAt: now
        )
        ledger.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: [references[0]]
        )

        await #expect(throws: FlowRunLedgerPersistenceError.invalidEvidenceProjection(
            runID: ledger.runID,
            issue: .evidenceArtifactInventoryMismatch
        )) {
            try await store.saveRunLedger(ledger)
        }
    }

    @Test
    func concurrentRunCreationRetainsEveryProjectManifestReference() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let first = try XcircuiteWorkspaceStore(projectRoot: root)
        let second = try XcircuiteWorkspaceStore(projectRoot: root)

        async let firstSave: FlowRunLedger = first.saveRunLedger(try makeLedger(runID: "run-a"))
        async let secondSave: FlowRunLedger = second.saveRunLedger(try makeLedger(runID: "run-b"))
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
    func directLedgerSaveRejectsRetainedArtifactProducerMutation() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-artifact-lineage"
        let unbound = try makeArtifactReference(path: "retained-result.json", root: root)
        let originalProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "timing-sta",
            version: "1.0.0"
        )
        let retained = ArtifactReference(
            id: unbound.id,
            locator: unbound.locator,
            digest: unbound.digest,
            byteCount: unbound.byteCount,
            producer: originalProducer
        )
        var initial = try makeLedger(runID: runID)
        initial.artifacts = [retained]
        initial.runManifest = try manifest(from: initial.runManifest, artifacts: [retained])
        _ = try await store.saveRunLedger(initial)

        let replacement = ArtifactReference(
            id: retained.id,
            locator: retained.locator,
            digest: retained.digest,
            byteCount: retained.byteCount,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "different-engine",
                version: "9.0.0"
            )
        )
        var proposal = try await store.loadRunLedger(runID: runID)
        proposal.artifacts = [replacement]
        proposal.runManifest = try manifest(
            from: proposal.runManifest,
            artifacts: [replacement],
            revision: proposal.runManifest.revision + 1
        )

        await #expect(throws: FlowRunLedgerPersistenceError.artifactReferenceMutation(
            runID: runID,
            path: replacement.path
        )) {
            _ = try await store.saveRunLedger(proposal)
        }
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
            relativeTo: workspace.projectRoot
        )
        var ledger = try makeLedger(runID: "run-1")
        ledger.artifacts = [reference]
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(ledger)

        try await workspace.write(Data("tampered".utf8), to: path)
        let reviewLedger = try await store.loadRunLedgerForReview(runID: "run-1")
        #expect(reviewLedger.artifacts == [reference])
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

    @Test
    func appendsActionArtifactWithoutMutatingAnalysisEvidenceInventory() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-action"))
        let content = Data("retained review".utf8)
        let reference = try makeActionArtifactReference(
            runID: "run-action",
            name: "review/retained.json",
            content: content
        )
        let action = makeAction(
            actionID: "retain-review",
            runID: "run-action",
            output: reference
        )

        let updated = try await store.appendActionArtifact(
            content: content,
            reference: reference,
            action: action
        )

        #expect(updated.actions == [action])
        #expect(updated.artifacts.isEmpty)
        #expect(updated.runManifest.artifacts.isEmpty)
        #expect(updated.runManifest.revision == 1)
        #expect(try await store.loadArtifactContent(for: reference) == content)
        #expect(
            try await store.read(from: ".xcircuite/runs/run-action/actions.jsonl")
                == sortedEncoder().encode(action) + Data([0x0A])
        )
    }

    @Test
    func appendsMultipleActionArtifactsAndProjectEditAtomically() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-batch-action"
        try await store.saveRunLedger(try makeLedger(runID: runID))
        let originalDesign = Data("{\"enabled\":true}".utf8)
        let updatedDesign = Data("{\"enabled\":false}".utf8)
        let designPath = "design/waivers.json"
        try FileManager.default.createDirectory(
            at: root.appending(path: "design"),
            withIntermediateDirectories: true
        )
        try originalDesign.write(to: root.appending(path: designPath), options: .atomic)

        let beforeContent = Data("before".utf8)
        let afterContent = Data("after".utf8)
        let beforeReference = try makeActionArtifactReference(
            runID: runID,
            name: "review/edit/before.json",
            content: beforeContent
        )
        let afterReference = try makeActionArtifactReference(
            runID: runID,
            name: "review/edit/after.json",
            content: afterContent
        )
        let action = FlowRunActionRecord(
            actionID: "apply-edit",
            runID: runID,
            actor: FlowRunActor(kind: .human, identifier: "reviewer"),
            actionKind: "review.applyEdit",
            status: .succeeded,
            outputs: [beforeReference, afterReference],
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )

        let updated = try await store.appendActionArtifacts(
            [
                XcircuitePreparedArtifact(
                    reference: beforeReference,
                    content: beforeContent
                ),
                XcircuitePreparedArtifact(
                    reference: afterReference,
                    content: afterContent
                ),
            ],
            action: action,
            replacingProjectArtifactAt: designPath,
            expectedContent: originalDesign,
            replacementContent: updatedDesign
        )

        #expect(updated.actions == [action])
        #expect(updated.artifacts.isEmpty)
        #expect(try Data(contentsOf: root.appending(path: designPath)) == updatedDesign)
        #expect(try await store.loadArtifactContent(for: beforeReference) == beforeContent)
        #expect(try await store.loadArtifactContent(for: afterReference) == afterContent)
    }

    @Test
    func identicalActionAppendIsIdempotentAndConflictingDuplicateIsRejected() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-duplicate"))
        let content = Data("first".utf8)
        let reference = try makeActionArtifactReference(
            runID: "run-duplicate",
            name: "review/decision.json",
            content: content
        )
        let action = makeAction(
            actionID: "decision-1",
            runID: "run-duplicate",
            output: reference
        )
        let first = try await store.appendActionArtifact(
            content: content,
            reference: reference,
            action: action
        )
        let repeated = try await store.appendActionArtifact(
            content: content,
            reference: reference,
            action: action
        )
        #expect(repeated == first)

        let conflictingContent = Data("second".utf8)
        let conflictingReference = try makeActionArtifactReference(
            runID: "run-duplicate",
            name: "review/second-decision.json",
            content: conflictingContent
        )
        let conflictingAction = makeAction(
            actionID: action.actionID,
            runID: "run-duplicate",
            output: conflictingReference
        )
        await #expect(throws: FlowRunLedgerPersistenceError.duplicateActionID(
            runID: "run-duplicate",
            actionID: action.actionID
        )) {
            _ = try await store.appendActionArtifact(
                content: conflictingContent,
                reference: conflictingReference,
                action: conflictingAction
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: conflictingReference.path).path(percentEncoded: false)
        ))
    }

    @Test
    func directLedgerSaveRejectsRetainedActionMutation() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-action-ledger-mutation"))
        let content = Data("trusted action".utf8)
        let reference = try makeActionArtifactReference(
            runID: "run-action-ledger-mutation",
            name: "review/action.json",
            content: content
        )
        _ = try await store.appendActionArtifact(
            content: content,
            reference: reference,
            action: makeAction(
                actionID: "trusted-action",
                runID: "run-action-ledger-mutation",
                output: reference
            )
        )

        var proposed = try await store.loadRunLedger(runID: "run-action-ledger-mutation")
        proposed.actions = [
            FlowRunActionRecord(
                actionID: "trusted-action",
                runID: proposed.runID,
                actor: FlowRunActor(kind: .system, identifier: "test"),
                actionKind: "review.mutated",
                status: .succeeded,
                outputs: [reference],
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
        ]
        proposed.runManifest = try FlowRunManifest(
            runID: proposed.runManifest.runID,
            status: proposed.runManifest.status,
            revision: proposed.runManifest.revision + 1,
            actor: proposed.runManifest.actor,
            intent: proposed.runManifest.intent,
            parentRunID: proposed.runManifest.parentRunID,
            createdAt: proposed.runManifest.createdAt,
            updatedAt: proposed.runManifest.updatedAt.addingTimeInterval(1),
            startedAt: proposed.runManifest.startedAt,
            finishedAt: proposed.runManifest.finishedAt,
            artifacts: proposed.runManifest.artifacts
        )

        await #expect(throws: FlowRunLedgerPersistenceError.protectedProjectionMutation(
            runID: proposed.runID,
            field: "actions"
        )) {
            _ = try await store.saveRunLedger(proposed)
        }
    }

    @Test
    func directLedgerSaveRejectsUnretainedActionOutputWithoutPoisoningTheRun() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-unretained-action-output"
        let missingContent = Data("missing".utf8)
        let missingReference = try makeActionArtifactReference(
            runID: runID,
            name: "review/missing.json",
            content: missingContent
        )
        var poisoned = try makeLedger(runID: runID)
        poisoned.actions = [makeAction(
            actionID: "bind-missing-output",
            runID: runID,
            output: missingReference
        )]

        do {
            _ = try await store.saveRunLedger(poisoned)
            Issue.record("Expected an unretained action output to fail before ledger persistence.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, _) = error else {
                Issue.record("Expected artifactIntegrityFailure, got \(error).")
                return
            }
            #expect(path == missingReference.path)
        }

        await #expect(throws: FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)) {
            _ = try await store.loadRunLedger(runID: runID)
        }
    }

    @Test
    func approvalAppendRejectsNoncanonicalPayloadWithoutChangingLedger() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let inputs = try ["plan.json", "verification.json"].map {
            try makeArtifactReference(path: $0, root: root)
        }
        var initial = try makeLedger(runID: "run-approval")
        initial.artifacts = inputs
        initial.runManifest = try manifest(
            from: initial.runManifest,
            artifacts: inputs
        )
        try await store.saveRunLedger(initial)
        let approval = FlowApprovalRecord(
            runID: "run-approval",
            stageID: "risk-approval",
            verdict: .approved,
            reviewer: "reviewer",
            createdAt: Date(timeIntervalSince1970: 1_700_000_001),
            evidence: FlowApprovalEvidenceBinding(plan: inputs[0], stageResult: inputs[1])
        )
        let invalidContent = Data("not the encoded approval".utf8)
        let reference = try makeApprovalArtifactReference(
            approval: approval,
            content: invalidContent
        )
        let action = FlowRunActionRecord(
            actionID: "approve-risk",
            runID: approval.runID,
            stageID: approval.stageID,
            actor: FlowRunActor(kind: .human, identifier: "reviewer"),
            actionKind: "review.approve",
            status: .succeeded,
            inputs: inputs,
            outputs: [reference],
            createdAt: approval.createdAt
        )

        await #expect(throws: FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
            runID: approval.runID,
            path: reference.path
        )) {
            _ = try await store.appendApprovalArtifact(
                content: invalidContent,
                reference: reference,
                approval: approval,
                action: action
            )
        }

        let unchanged = try await store.loadRunLedger(runID: approval.runID)
        #expect(unchanged.runManifest.revision == 0)
        #expect(unchanged.actions.isEmpty)
        #expect(unchanged.approvals.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: reference.path).path(percentEncoded: false)
        ))
    }

    @Test
    func interruptedActionAppendRollsForwardAsOneLedgerGeneration() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-recover-action"))
        let interruptedStore = try XcircuiteWorkspaceStore(
            projectRoot: root,
            transactionFault: .afterOperation(0)
        )
        let content = Data("recoverable action".utf8)
        let reference = try makeActionArtifactReference(
            runID: "run-recover-action",
            name: "review/recoverable.json",
            content: content
        )
        let action = makeAction(
            actionID: "recover-action",
            runID: "run-recover-action",
            output: reference
        )

        await #expect(throws: XcircuiteWorkspaceTransactionError.injectedFailure(.afterOperation(0))) {
            _ = try await interruptedStore.appendActionArtifact(
                content: content,
                reference: reference,
                action: action
            )
        }

        let recovered = try await store.loadRunLedger(runID: "run-recover-action")
        #expect(recovered.actions == [action])
        #expect(recovered.runManifest.revision == 1)
        #expect(try await store.loadArtifactContent(for: reference) == content)
        #expect(try await store.read(from: ".xcircuite/runs/run-recover-action/actions.jsonl").isEmpty == false)
    }

    @Test
    func actionAppendRejectsTamperedRetainedActionArtifactBeforeCommit() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.saveRunLedger(try makeLedger(runID: "run-action-tamper"))
        let firstContent = Data("trusted".utf8)
        let firstReference = try makeActionArtifactReference(
            runID: "run-action-tamper",
            name: "review/first.json",
            content: firstContent
        )
        _ = try await store.appendActionArtifact(
            content: firstContent,
            reference: firstReference,
            action: makeAction(
                actionID: "first-action",
                runID: "run-action-tamper",
                output: firstReference
            )
        )
        try Data("tampered".utf8).write(
            to: root.appending(path: firstReference.path),
            options: .atomic
        )
        let secondContent = Data("must not commit".utf8)
        let secondReference = try makeActionArtifactReference(
            runID: "run-action-tamper",
            name: "review/second.json",
            content: secondContent
        )

        do {
            _ = try await store.appendActionArtifact(
                content: secondContent,
                reference: secondReference,
                action: makeAction(
                    actionID: "second-action",
                    runID: "run-action-tamper",
                    output: secondReference
                )
            )
            Issue.record("Expected retained action artifact integrity failure.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, _) = error else {
                Issue.record("Unexpected persistence error: \(error.localizedDescription)")
                return
            }
            #expect(path == firstReference.path)
        }
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: secondReference.path).path(percentEncoded: false)
        ))
    }

    @Test
    func atomicActionAppendDoesNotCreateDirectoryForMissingRun() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "missing-run"

        await #expect(throws: FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)) {
            try await store.appendRunAction(
                FlowRunActionRecord(
                    actionID: "missing-run-action",
                    runID: runID,
                    actor: FlowRunActor(kind: .system, identifier: "test"),
                    actionKind: "review.inspect",
                    status: .succeeded
                )
            )
        }

        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: ".xcircuite/runs/\(runID)").path(percentEncoded: false)
        ))
    }

    @Test
    func auditedProjectArtifactMutationCommitsSourceAndActionTogether() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "audited-project-mutation"
        try await store.saveRunLedger(try makeLedger(runID: runID))
        let before = Data("before".utf8)
        let after = Data("after".utf8)
        try FileManager.default.createDirectory(
            at: root.appending(path: "design"),
            withIntermediateDirectories: true
        )
        try before.write(to: root.appending(path: "design/config.json"), options: .atomic)
        let action = FlowRunActionRecord(
            actionID: "replace-config",
            runID: runID,
            actor: FlowRunActor(kind: .human, identifier: "reviewer"),
            actionKind: "review.replaceProjectArtifact",
            status: .succeeded
        )

        let updated = try await store.appendRunAction(
            action,
            replacingProjectArtifactAt: "design/config.json",
            expectedContent: before,
            replacementContent: after
        )

        #expect(try Data(contentsOf: root.appending(path: "design/config.json")) == after)
        #expect(updated.actions == [action])
        #expect(try await store.loadRunLedger(runID: runID).actions == [action])
    }

    @Test
    func auditedProjectArtifactMutationRejectsStaleExpectedContentWithoutAppending() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "stale-project-mutation"
        try await store.saveRunLedger(try makeLedger(runID: runID))
        let current = Data("current".utf8)
        try FileManager.default.createDirectory(
            at: root.appending(path: "design"),
            withIntermediateDirectories: true
        )
        try current.write(to: root.appending(path: "design/config.json"), options: .atomic)

        await #expect(throws: XcircuiteWorkspaceStoreError.projectArtifactChanged("design/config.json")) {
            _ = try await store.appendRunAction(
                FlowRunActionRecord(
                    actionID: "stale-replace",
                    runID: runID,
                    actor: FlowRunActor(kind: .human, identifier: "reviewer"),
                    actionKind: "review.replaceProjectArtifact",
                    status: .succeeded
                ),
                replacingProjectArtifactAt: "design/config.json",
                expectedContent: Data("stale".utf8),
                replacementContent: Data("replacement".utf8)
            )
        }
        #expect(try Data(contentsOf: root.appending(path: "design/config.json")) == current)
        #expect(try await store.loadRunLedger(runID: runID).actions.isEmpty)
    }

    @Test
    func atomicActionAppendRejectsTamperedActionProjection() async throws {
        let root = try makeTemporaryRoot()
        defer { remove(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "run-tampered-action-projection"
        try await store.saveRunLedger(try makeLedger(runID: runID))
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "first-action",
                runID: runID,
                actor: FlowRunActor(kind: .system, identifier: "test"),
                actionKind: "review.inspect",
                status: .succeeded,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        )
        let projectionPath = ".xcircuite/runs/\(runID)/actions.jsonl"
        try Data("tampered\n".utf8).write(
            to: root.appending(path: projectionPath),
            options: .atomic
        )

        do {
            try await store.appendRunAction(
                FlowRunActionRecord(
                    actionID: "second-action",
                    runID: runID,
                    actor: FlowRunActor(kind: .system, identifier: "test"),
                    actionKind: "review.inspect",
                    status: .succeeded,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_002)
                )
            )
            Issue.record("Expected the tampered action projection to block append.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, let reason) = error else {
                Issue.record("Unexpected persistence error: \(error.localizedDescription)")
                return
            }
            #expect(path == projectionPath)
            #expect(reason == "decision-projection-mismatch")
        }
        let ledger = try await store.loadRunLedgerForReview(runID: runID)
        #expect(ledger.actions.map(\.actionID) == ["first-action"])
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

    private func makeArtifactReference(path: String, root: URL) throws -> ArtifactReference {
        let data = Data(path.utf8)
        try data.write(to: root.appending(path: path), options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: .report,
                format: .json
            ),
            relativeTo: root
        )
    }

    private func makeActionArtifactReference(
        runID: String,
        name: String,
        content: Data
    ) throws -> ArtifactReference {
        let path = ".xcircuite/runs/\(runID)/\(name)"
        return ArtifactReference(
            id: try ArtifactID(rawValue: name.replacingOccurrences(of: "/", with: "-")),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: content, using: .sha256),
            byteCount: UInt64(content.count)
        )
    }

    private func makeApprovalArtifactReference(
        approval: FlowApprovalRecord,
        content: Data
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: "approval-\(approval.stageID)"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(approval.runID)/approvals/\(approval.stageID).json"
                ),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: content, using: .sha256),
            byteCount: UInt64(content.count)
        )
    }

    private func makeAction(
        actionID: String,
        runID: String,
        output: ArtifactReference
    ) -> FlowRunActionRecord {
        FlowRunActionRecord(
            actionID: actionID,
            runID: runID,
            actor: FlowRunActor(kind: .system, identifier: "test"),
            actionKind: "review.retain",
            status: .succeeded,
            outputs: [output],
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func manifest(
        from manifest: FlowRunManifest,
        artifacts: [ArtifactReference],
        revision: Int? = nil
    ) throws -> FlowRunManifest {
        try FlowRunManifest(
            runID: manifest.runID,
            status: manifest.status,
            revision: revision ?? manifest.revision,
            actor: manifest.actor,
            intent: manifest.intent,
            parentRunID: manifest.parentRunID,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            startedAt: manifest.startedAt,
            finishedAt: manifest.finishedAt,
            artifacts: artifacts
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
