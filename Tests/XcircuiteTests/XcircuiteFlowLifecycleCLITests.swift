import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("xcircuite-flow run lifecycle", .timeLimit(.minutes(2)))
struct XcircuiteFlowLifecycleCLITests {
    @Test func reviewAndReleaseCommandsOperateOnOnePersistedRun() async throws {
        let root = try makeTemporaryRoot("review-release")
        defer { removeTemporaryRoot(root) }
        let runID = "run-lifecycle-review"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await createRunFixture(
            runID: runID,
            status: .succeeded,
            stageStatus: .succeeded,
            requiresApproval: false,
            store: store
        )
        let baselineLedger = try await store.loadRunLedger(runID: runID)

        let summary: FlowRunLedgerSummary = try await runCLI(
            "inspect-run",
            root: root,
            runID: runID
        )
        #expect(summary.runID == runID)
        #expect(summary.status == .succeeded)
        #expect(summary.stages.map(\.stageID) == ["001-analysis"])

        let review: FlowRunReviewBundle = try await runCLI(
            "review-run",
            root: root,
            runID: runID
        )
        #expect(review.runID == runID)
        #expect(review.artifacts.first(where: {
            $0.reference.artifactID == "analysis-summary"
        }) != nil)

        let ladder: FlowRunStageArtifactLadderBuildResult = try await runCLI(
            "build-stage-artifact-ladder",
            root: root,
            runID: runID
        )
        #expect(ladder.ladder.runID == runID)
        #expect(ladder.artifact.artifactID == DefaultFlowRunStageArtifactLadderBuilder.artifactID)
        #expect(ladder.artifact.path.contains("/review/stage-artifact-ladder-sha256-"))
        #expect(ladder.artifact.path.hasSuffix(".json"))

        let actionCountAfterFirstLadder = try await store.loadRunLedger(runID: runID).actions.count
        let repeatedLadder: FlowRunStageArtifactLadderBuildResult = try await runCLI(
            "build-stage-artifact-ladder",
            root: root,
            runID: runID
        )
        #expect(repeatedLadder.artifact == ladder.artifact)
        #expect(try await store.loadRunLedger(runID: runID).actions.count == actionCountAfterFirstLadder)

        let loopSummary: FlowRunLoopSummaryResult = try await runCLI(
            "summarize-loop",
            root: root,
            runID: runID
        )
        #expect(loopSummary.runID == runID)
        #expect(loopSummary.iterations.count == 1)
        #expect(loopSummary.artifactReferences.count == 2)

        let packet: FlowRunDecisionPacketBuildResult = try await runCLI(
            "build-decision-packet",
            root: root,
            runID: runID
        )
        #expect(packet.packet.runID == runID)
        #expect(packet.artifact.artifactID == DefaultFlowRunDecisionPacketBuilder.artifactID)
        #expect(packet.artifact.path.contains("/review/decision-packet-sha256-"))

        let validation: FlowRunDecisionPacketValidationResult = try await runCLI(
            "validate-decision-packet",
            root: root,
            runID: runID
        )
        #expect(validation.runID == runID)
        #expect(validation.packetArtifactIntegrity?.status == .verified)
        #expect(validation.packetPath == packet.artifact.path)

        let envelope: FlowRunReleaseEnvelopeBuildResult = try await runCLI(
            "build-release-envelope",
            root: root,
            runID: runID,
            additionalArguments: ["--max-evidence-age-days", "30"]
        )
        #expect(envelope.envelope.runID == runID)
        #expect(envelope.artifact.artifactID == DefaultFlowRunReleaseEnvelopeBuilder.artifactID)
        #expect(envelope.artifact.path.contains("/qualification/release-envelope-sha256-"))

        let ledger = try await store.loadRunLedger(runID: runID)
        let artifactIDs = Set(ledger.actions.flatMap(\.outputs).map(\.artifactID))
        #expect(artifactIDs.contains(DefaultFlowRunStageArtifactLadderBuilder.artifactID))
        #expect(artifactIDs.contains(DefaultFlowRunDecisionPacketBuilder.artifactID))
        #expect(artifactIDs.contains(DefaultFlowRunReleaseEnvelopeBuilder.artifactID))
        #expect(ledger.artifacts == baselineLedger.artifacts)
        #expect(ledger.runManifest.artifacts == baselineLedger.runManifest.artifacts)
        #expect(ledger.evidence == baselineLedger.evidence)
    }

    @Test func releaseEvidenceAndRetentionCommandsPersistVerifiableArtifacts() async throws {
        let root = try makeTemporaryRoot("release-retention")
        defer { removeTemporaryRoot(root) }
        let runID = "run-lifecycle-retention"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await createRunFixture(
            runID: runID,
            status: .succeeded,
            stageStatus: .succeeded,
            requiresApproval: false,
            store: store
        )
        let recordedAt = Date()
        let timestamp = ISO8601DateFormatter().string(from: recordedAt)
        let dashboardPath = ".xcircuite/runs/\(runID)/inputs/signoff-dashboard.json"
        let contractPath = ".xcircuite/runs/\(runID)/inputs/contract-report.json"
        let historyPath = ".xcircuite/runs/\(runID)/inputs/release-history.jsonl"
        try await store.writeWorkspaceText(
            """
            {
              "schemaVersion": 1,
              "runID": "\(runID)",
              "status": "passed",
              "history": {
                "status": "passed",
                "previousEntryCount": 0,
                "maxTotalDurationRegression": 0,
                "appended": true,
                "domains": [],
                "promotion": {"status": "passed", "failures": []},
                "failures": [],
                "entry": {"recordedAt": "\(timestamp)"}
              },
              "retainedSignoffSuite": {"status": "passed"}
            }
            """,
            to: dashboardPath
        )
        try await store.writeWorkspaceText(
            """
            {
              "schemaVersion": 1,
              "status": "passed",
              "contractCount": 1,
              "failedContractCount": 0,
              "contracts": [{
                "id": "artifact-schema",
                "owner": "CircuiteFoundation",
                "status": "passed",
                "expectedVersion": 1,
                "observedVersion": 1,
                "requiredPathCount": 1,
                "failures": []
              }]
            }
            """,
            to: contractPath
        )

        let evidence: FlowRunReleaseEvidenceCollectionResult = try await runCLI(
            "collect-release-evidence",
            root: root,
            runID: runID,
            additionalArguments: [
                "--signoff-dashboard", try await store.url(for: dashboardPath).path(percentEncoded: false),
                "--contract-report", try await store.url(for: contractPath).path(percentEncoded: false),
            ]
        )
        #expect(evidence.runID == runID)
        #expect(evidence.artifacts.count == 3)
        #expect(evidence.diagnostics.isEmpty)

        var historyEntry = FlowRunReleaseHistoryEntry(
            sequence: 1,
            entryID: "entry-1",
            runID: runID,
            recordedAt: timestamp,
            qualificationDigest: String(repeating: "c", count: 64),
            previousEntrySHA256: nil,
            entrySHA256: String(repeating: "0", count: 64)
        )
        historyEntry.entrySHA256 = try historyEntry.computedSHA256()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var historyData = try encoder.encode(historyEntry)
        historyData.append(Data("\n".utf8))
        try await store.write(historyData, to: historyPath)

        let retentionBuild: FlowRunReleaseRetentionIndexBuildResult = try await runCLI(
            "build-retention-index",
            root: root,
            runID: runID,
            additionalArguments: [
                "--workflow-run-id", "workflow-1",
                "--source-dashboard", try await store.url(for: dashboardPath).path(percentEncoded: false),
                "--history", try await store.url(for: historyPath).path(percentEncoded: false),
                "--previous-entry-count", "0",
                "--retention-days", "30",
                "--minimum-retention-days", "30",
                "--recorded-at", timestamp,
            ]
        )
        #expect(retentionBuild.index.status == .passed)
        #expect(retentionBuild.index.appendOnly)
        #expect(retentionBuild.artifact.artifactID == "qualification-retention-index")
        #expect(retentionBuild.artifact.path.contains("/qualification/retention-index-sha256-"))

        let actionCountAfterRetentionBuild = try await store.loadRunLedger(runID: runID).actions.count
        let repeatedRetentionBuild: FlowRunReleaseRetentionIndexBuildResult = try await runCLI(
            "build-retention-index",
            root: root,
            runID: runID,
            additionalArguments: [
                "--workflow-run-id", "workflow-1",
                "--source-dashboard", try await store.url(for: dashboardPath).path(percentEncoded: false),
                "--history", try await store.url(for: historyPath).path(percentEncoded: false),
                "--previous-entry-count", "0",
                "--retention-days", "30",
                "--minimum-retention-days", "30",
                "--recorded-at", timestamp,
            ]
        )
        #expect(repeatedRetentionBuild.artifact == retentionBuild.artifact)
        #expect(try await store.loadRunLedger(runID: runID).actions.count == actionCountAfterRetentionBuild)

        let laterTimestamp = ISO8601DateFormatter().string(from: recordedAt.addingTimeInterval(1))
        let changedRetentionBuild: FlowRunReleaseRetentionIndexBuildResult = try await runCLI(
            "build-retention-index",
            root: root,
            runID: runID,
            additionalArguments: [
                "--workflow-run-id", "workflow-2",
                "--source-dashboard", try await store.url(for: dashboardPath).path(percentEncoded: false),
                "--history", try await store.url(for: historyPath).path(percentEncoded: false),
                "--previous-entry-count", "0",
                "--retention-days", "30",
                "--minimum-retention-days", "30",
                "--recorded-at", laterTimestamp,
            ]
        )
        #expect(changedRetentionBuild.artifact != retentionBuild.artifact)
        #expect(changedRetentionBuild.artifact.path != retentionBuild.artifact.path)
        #expect(try await store.artifactExists(at: retentionBuild.artifact.locator))
        #expect(try await store.artifactExists(at: changedRetentionBuild.artifact.locator))

        let retentionValidation: FlowRunReleaseRetentionValidationResult = try await runCLI(
            "validate-retention-index",
            root: root,
            runID: runID,
            additionalArguments: ["--max-evidence-age-days", "30"]
        )
        #expect(retentionValidation.status == .passed)
        #expect(retentionValidation.diagnostics.isEmpty)

        let _: FlowRunDecisionPacketBuildResult = try await runCLI(
            "build-decision-packet",
            root: root,
            runID: runID
        )
        let envelope: FlowRunReleaseEnvelopeBuildResult = try await runCLI(
            "build-release-envelope",
            root: root,
            runID: runID,
            additionalArguments: ["--max-evidence-age-days", "30"]
        )
        let requirements = Dictionary(
            uniqueKeysWithValues: envelope.envelope.requirements.map { ($0.requirementID, $0) }
        )
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: evidence.artifacts.map { ($0.artifactID, $0) }
        )
        #expect(requirements["retained-corpus-history"]?.artifactPaths == [
            try #require(evidenceByID["qualification-corpus-history"]).path,
        ])
        #expect(requirements["performance-envelope"]?.artifactPaths == [
            try #require(evidenceByID["qualification-performance-envelope"]).path,
        ])
        #expect(requirements["contract-audit"]?.artifactPaths == [
            try #require(evidenceByID["qualification-contract-audit"]).path,
        ])
        #expect(requirements["retention-index"]?.artifactPaths == [changedRetentionBuild.artifact.path])
    }

    @Test func approvalCommandBindsPersistedPlanAndStageEvidence() async throws {
        let root = try makeTemporaryRoot("approval")
        defer { removeTemporaryRoot(root) }
        let runID = "run-lifecycle-approval"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await createRunFixture(
            runID: runID,
            status: .blocked,
            stageStatus: .blocked,
            requiresApproval: true,
            store: store
        )

        let result: FlowGateApprovalResult = try await runCLI(
            "approve-gate",
            root: root,
            runID: runID,
            additionalArguments: [
                "--stage-id", "001-analysis",
                "--verdict", "approved",
                "--reviewer", "integration-reviewer",
                "--reviewer-kind", "agent",
                "--note", "Stage evidence reviewed.",
            ]
        )
        #expect(result.approval.verdict == .approved)
        #expect(result.approval.reviewerKind == .agent)
        #expect(result.approval.evidence.plan.artifactID == "run-plan")
        #expect(result.approval.evidence.stageResult.artifactID == "approval-review-001-analysis")

        let ledger = try await store.loadRunLedger(runID: runID)
        #expect(ledger.approvals == [result.approval])
        #expect(ledger.actions.contains {
            $0.actionKind == FlowRunReviewDecisionKind.approval.rawValue
                && $0.actor.kind == .agent
        })
    }

    @Test func cancellationAndProgressCommandsShareTheRunControlLedger() async throws {
        let root = try makeTemporaryRoot("cancellation-progress")
        defer { removeTemporaryRoot(root) }
        let runID = "run-lifecycle-cancel"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await createRunFixture(
            runID: runID,
            status: .running,
            stageStatus: .running,
            requiresApproval: false,
            store: store
        )

        let cancellation: FlowRunCancellationResult = try await runCLI(
            "request-cancel",
            root: root,
            runID: runID,
            additionalArguments: [
                "--requested-by", "integration-operator",
                "--reason", "Stop after review.",
            ]
        )
        #expect(cancellation.status == "recorded")
        #expect(cancellation.request.runID == runID)

        let progress: FlowRunProgressSnapshot = try await runCLI(
            "progress-run",
            root: root,
            runID: runID,
            additionalArguments: ["--since-sequence", "0"]
        )
        #expect(progress.events.contains { $0.kind == .cancellationRequested })
        #expect(progress.latestSequence == 1)

        let ledger = try await store.loadRunLedger(runID: runID)
        #expect(ledger.cancellationRequest == cancellation.request)
        #expect(ledger.progressEvents == progress.events)
    }

    @Test func cancellationCommandDoesNotMutateATerminalRun() async throws {
        let root = try makeTemporaryRoot("terminal-cancellation")
        defer { removeTemporaryRoot(root) }
        let runID = "run-terminal-cancel"
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await createRunFixture(
            runID: runID,
            status: .succeeded,
            stageStatus: .succeeded,
            requiresApproval: false,
            store: store
        )
        let before = try await store.loadRunLedger(runID: runID)

        await #expect(throws: XcircuiteWorkspaceStoreError.terminalRunArtifactMutation(
            runID: runID,
            path: ".xcircuite/runs/\(runID)/cancellation.json"
        )) {
            let _: FlowRunCancellationResult = try await runCLI(
                "request-cancel",
                root: root,
                runID: runID,
                additionalArguments: [
                    "--requested-by", "integration-operator",
                    "--reason", "This terminal run must remain immutable.",
                ]
            )
        }

        let after = try await store.loadRunLedger(runID: runID)
        #expect(after == before)
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: ".xcircuite/runs/\(runID)/cancellation.json").path
        ))
    }

    private func createRunFixture(
        runID: String,
        status: FlowRunStatus,
        stageStatus: FlowStageStatus,
        requiresApproval: Bool,
        store: XcircuiteWorkspaceStore
    ) async throws {
        let stageID = "001-analysis"
        let plan = FlowRunPlan(
            runID: runID,
            intent: "Exercise the developer and agent run lifecycle.",
            stages: [
                FlowStageDefinition(
                    stageID: stageID,
                    displayName: "Analysis",
                    requiresApproval: requiresApproval
                ),
            ]
        )
        let summaryReference = try await writeArtifact(
            Data(#"{"status":"passed"}"#.utf8),
            artifactID: "analysis-summary",
            path: ".xcircuite/runs/\(runID)/stages/\(stageID)/raw/summary.json",
            role: .output,
            kind: .report,
            store: store
        )
        let stage = FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            gates: requiresApproval
                ? [FlowGateResult(gateID: "approval", status: .incomplete)]
                : [FlowGateResult(gateID: "execution", status: .passed)],
            artifacts: [summaryReference]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let planReference = try await writeArtifact(
            encoder.encode(plan),
            artifactID: "run-plan",
            path: ".xcircuite/runs/\(runID)/plan.json",
            role: .input,
            kind: .other,
            store: store
        )
        let stageResultReference = try await writeArtifact(
            encoder.encode(stage),
            artifactID: "\(stageID)-result",
            path: ".xcircuite/runs/\(runID)/stages/\(stageID)/result.json",
            role: .output,
            kind: .other,
            store: store
        )
        let references = [planReference, stageResultReference, summaryReference]
        let now = Date()
        let startedAt: Date? = status == .created ? nil : now
        let finishedAt: Date? = switch status {
        case .created, .running: nil
        case .succeeded, .failed, .cancelled, .blocked, .partial: now
        }
        let manifest = try FlowRunManifest(
            runID: runID,
            status: status,
            actor: FlowRunActor(kind: .system, identifier: "integration-test"),
            intent: plan.intent,
            createdAt: now,
            updatedAt: now,
            startedAt: startedAt,
            finishedAt: finishedAt,
            artifacts: references
        )
        let actionStatus: FlowRunActionStatus = stageStatus == .succeeded ? .succeeded : .running
        let action = FlowRunActionRecord(
            actionID: "action-1",
            runID: runID,
            stageID: stageID,
            actor: FlowRunActor(kind: .agent, identifier: "integration-agent"),
            actionKind: "analysis.execute",
            status: actionStatus,
            inputs: [planReference],
            outputs: [summaryReference]
        )
        let toolchain: FlowToolchainManifest? = status.isTerminal
            ? FlowToolchainManifest(
                runID: runID,
                stages: [
                    FlowToolchainStageRecord(
                        stageID: stageID,
                        executorToolID: "integration-analysis"
                    ),
                ]
            )
            : nil
        let evidence: EvidenceManifest? = if status.isTerminal {
            EvidenceManifest(
                provenance: try ExecutionProvenance(
                    producer: ProducerIdentity(
                        kind: .engine,
                        identifier: "integration-analysis",
                        version: "1"
                    ),
                    inputs: [planReference],
                    startedAt: now,
                    completedAt: now
                ),
                artifacts: references
            )
        } else {
            nil
        }
        try await store.saveRunLedger(
            FlowRunLedger(
                runID: runID,
                runManifest: manifest,
                plan: plan,
                stages: [stage],
                toolchain: toolchain,
                evidence: evidence,
                artifacts: references,
                actions: [action]
            )
        )
    }

    private func writeArtifact(
        _ data: Data,
        artifactID: String,
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        store: XcircuiteWorkspaceStore
    ) async throws -> ArtifactReference {
        try await store.write(data, to: path)
        return try await store.makeArtifactReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            role: role,
            kind: kind,
            format: .json
        )
    }

    private func runCLI<Value: Decodable>(
        _ command: String,
        root: URL,
        runID: String,
        additionalArguments: [String] = []
    ) async throws -> Value {
        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            command,
            "--project-root", root.path(percentEncoded: false),
            "--run-id", runID,
        ] + additionalArguments + ["--pretty"])
        return try JSONDecoder().decode(
            Value.self,
            from: try #require(output.data(using: .utf8))
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteFlowLifecycleCLITests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
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
