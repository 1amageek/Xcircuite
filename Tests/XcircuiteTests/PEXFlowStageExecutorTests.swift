import DesignFlowKernel
import Foundation
import PEXEngine
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("PEX flow stage executor")
struct PEXFlowStageExecutorTests {
    @Test func fixturePEXBackendRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("pex-pass")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)
        _ = try writeText("tt-deck", name: "deck-tt.rc", root: root)
        _ = try writeText("ss-deck", name: "deck-ss.rc", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: ToolTrustRequirement(
                            kind: .pex,
                            operationID: "run-pex",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.gdsii, .spice],
                            requiredOutputFormats: [.spef, .json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [
                QualifiedToolFixtures.descriptor(
                    SignoffToolDescriptors.pexBackend(backendID: "test-fixture"),
                    qualifiedAt: .smokeChecked
                ),
            ]),
            healthResults: [
                "pex-test-fixture": QualifiedToolFixtures.health(
                    toolID: "pex-test-fixture",
                    level: .smokeChecked
                ),
            ],
            executors: [
                fixturePEXExecutor(
                    stageID: "009-pex",
                    layoutURL: layoutURL,
                    layoutFormat: .gds,
                    sourceNetlistURL: netlistURL,
                    topCell: "TESTCELL",
                    corners: [
                        PEXCorner(id: PEXCornerID("tt"), name: "tt", temperature: 25),
                        PEXCorner(id: PEXCornerID("ss"), name: "ss", temperature: 125),
                    ],
                    technology: .inline(makeTestTech()),
                    technologyByCorner: ["ss": .inline(makeTestTech())],
                    processProfile: PEXProcessProfileReference(
                        cornerDeckPaths: [
                            "tt": root.appending(path: "deck-tt.rc").path(percentEncoded: false),
                            "ss": root.appending(path: "deck-ss.rc").path(percentEncoded: false),
                        ]
                    )
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "pex" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "pex-flow-artifacts" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.stages[0].diagnostics.contains { $0.code == "PEX_WARNING" })
        #expect(artifacts.contains { $0.path.hasSuffix("manifest.json") })
        let summaryArtifact = try #require(artifacts.first { $0.artifactID == "pex-summary" })
        #expect(summaryArtifact.kind == .report)
        #expect(summaryArtifact.format == .json)
        let summaryURL = root.appending(path: summaryArtifact.path)
        let summary = try JSONDecoder().decode(
            PEXRunSummaryReport.self,
            from: Data(contentsOf: summaryURL)
        )
        #expect(summary.summary.corners.count == 2)
        #expect(summary.summary.corners.contains { $0.cornerID == "tt" && !$0.topNets.isEmpty })
        #expect(summary.summary.multiCorner.cornerCount == 2)
        #expect(summary.summary.multiCorner.successfulCornerCount == 2)
        #expect(summary.summary.multiCorner.failedCornerCount == 0)
        #expect(summary.summary.multiCorner.worstCapacitanceCornerID == "ss")
        #expect(summary.summary.multiCorner.worstResistanceCornerID == "ss")
        #expect(summary.summary.multiCorner.totalCapacitance.spread > 0)
        #expect(summary.summary.multiCorner.totalResistance.spread > 0)
        #expect(summary.summary.multiCorner.topNetSpreads.isEmpty == false)
        let envelopeArtifact = try #require(artifacts.first {
            $0.path.hasSuffix("evidence/pex-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(envelope.artifactID == "pex-summary")
        #expect(evaluation.status == .accepted)
        let totalNetCount = summary.summary.corners.reduce(0) { $0 + $1.netCount }
        let totalCapacitanceF = summary.summary.corners.reduce(0) { $0 + $1.totalCapacitanceF }
        #expect(channelValue("pex-corner-count", in: observations) == .scalar(2))
        #expect(channelValue("pex-failed-corner-count", in: observations) == .scalar(0))
        #expect(channelValue("pex-total-net-count", in: observations) == .scalar(Double(totalNetCount)))
        #expect(channelValue("pex-total-capacitance-f", in: observations) == .scalar(totalCapacitanceF))
        #expect(channelValue("pex-multi-corner-successful-corner-count", in: observations) == .scalar(2))
        #expect(channelValue("pex-multi-corner-comparison-basis", in: observations) == .text("perCornerTechnology"))
        #expect(channelValue("pex-multi-corner-failed-corner-count", in: observations) == .scalar(0))
        #expect(channelValue("pex-multi-corner-worst-capacitance-corner-id", in: observations) == .text("ss"))
        #expect(channelValue("pex-multi-corner-worst-resistance-corner-id", in: observations) == .text("ss"))
        #expect(channelValue("pex-multi-corner-total-capacitance-spread-f", in: observations) == .scalar(summary.summary.multiCorner.totalCapacitance.spread))
        #expect(channelValue("pex-multi-corner-total-resistance-spread-ohm", in: observations) == .scalar(summary.summary.multiCorner.totalResistance.spread))
        let ttStatusChannel = try #require(observations.channels.first {
            $0.channelID.hasPrefix("pex-corner-") && $0.channelID.hasSuffix("-tt-status")
        })
        let ttIRChannel = try #require(observations.channels.first {
            $0.channelID.hasPrefix("pex-corner-") && $0.channelID.hasSuffix("-tt-parasitic-ir-present")
        })
        #expect(ttStatusChannel.value == .text(PEXRunStatus.success.rawValue))
        #expect(ttIRChannel.value == .boolean(true))
        #expect(channelResult("pex-failed-corner-count", in: evaluation)?.status == .accepted)
        #expect(channelResult("pex-multi-corner-comparison-basis", in: evaluation)?.status == .rejected)
        #expect(channelResult("pex-multi-corner-failed-corner-count", in: evaluation)?.status == .accepted)
        #expect(channelResult("pex-multi-corner-error-diagnostic-count", in: evaluation)?.status == .accepted)
        #expect(channelResult(ttIRChannel.channelID, in: evaluation)?.status == .accepted)
        #expect(channelValue("pex-tool-evidence-count", in: observations) == .scalar(1))
        #expect(observations.missingChannelIDs.isEmpty)
        #expect(observations.uncalibratedChannelIDs == ["pex-qualified-calibration"])
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
        #expect(evaluation.feedbackSignals.contains {
            $0.channelID?.contains("top-net") == true
                && $0.suggestedActions.contains("compare-post-layout-metrics")
        })
        #expect(evaluation.feedbackSignals.contains {
            $0.channelID == "pex-multi-corner-total-capacitance-spread-f"
                && $0.suggestedActions.contains("compare-post-layout-metrics")
        })
        #expect(evaluation.feedbackSignals.contains {
            $0.channelID == "pex-multi-corner-comparison-basis"
                && $0.severity == .warning
        })
        #expect(artifacts.contains { $0.format == .spef })
        #expect(artifacts.contains { $0.kind == .technology && $0.path.contains("process-profile-decks") })
        #expect(artifacts.contains(where: { (artifact: ArtifactReference) in artifact.kind == .parasitics && artifact.format == .json }))
        #expect(artifacts.contains(where: { (artifact: ArtifactReference) in artifact.kind == .parasitics && artifact.format == .spice }))
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
        #expect(artifacts.filter { !$0.path.contains("/evidence/") }.allSatisfy {
            $0.path.contains(".xcircuite/runs/run-pex/stages/009-pex/raw")
        })
    }

    @Test func pexReviewBundleLinksMultiCornerSummaryAndPostLayoutComparison() async throws {
        let root = try makeTemporaryRoot("pex-postlayout-review")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)
        let preWaveform = try writeText(
            """
            time,V(out)
            0,0
            1e-9,1
            2e-9,0
            3e-9,1
            """,
            name: "pre.csv",
            root: root
        )
        let postWaveform = try writeText(
            """
            time,V(out),V(out_pex)
            0,0,0
            1e-9,0.98,0.97
            2e-9,0.02,0.03
            3e-9,1.01,1
            """,
            name: "post.csv",
            root: root
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex-postlayout-review",
                intent: "Run PEX and compare post-layout waveform",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                    FlowStageDefinition(stageID: "010-post-layout-comparison", displayName: "Post-layout comparison"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                fixturePEXExecutor(
                    stageID: "009-pex",
                    layoutURL: layoutURL,
                    layoutFormat: .gds,
                    sourceNetlistURL: netlistURL,
                    topCell: "TESTCELL",
                    corners: [
                        PEXCorner(id: PEXCornerID("tt"), name: "tt", temperature: 25),
                        PEXCorner(id: PEXCornerID("ss"), name: "ss", temperature: 125),
                    ],
                    technology: .inline(makeTestTech())
                ),
                PostLayoutComparisonFlowStageExecutor(
                    stageID: "010-post-layout-comparison",
                    preLayoutWaveformURL: preWaveform,
                    postLayoutWaveformURL: postWaveform,
                    options: PostLayoutComparisonOptions(
                        maxAbsoluteDelta: 0.05,
                        requiredPostVariables: ["V(out_pex)"]
                    )
                ),
            ]
        )

        #expect(result.status == .succeeded)
        let pexStage = try #require(result.stages.first { $0.stageID == "009-pex" })
        let comparisonStage = try #require(result.stages.first { $0.stageID == "010-post-layout-comparison" })
        let pexSummary = try #require(pexStage.artifacts.first { $0.artifactID == "pex-summary" })
        let comparison = try #require(comparisonStage.artifacts.first { $0.artifactID == "post-layout-comparison" })
        let envelopeArtifact = try #require(pexStage.artifacts.first {
            $0.path.hasSuffix("evidence/pex-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(channelValue("pex-multi-corner-comparison-basis", in: observations) == .text("sharedTechnology"))
        #expect(channelResult("pex-multi-corner-comparison-basis", in: evaluation)?.status == .accepted)
        #expect(channelValue("pex-multi-corner-worst-capacitance-corner-id", in: observations) == .text("ss"))
        #expect(channelValue("pex-multi-corner-total-capacitance-spread-f", in: observations) != nil)
        #expect(observations.channels.contains {
            $0.channelID.contains("pex-multi-corner-net-")
                && $0.channelID.hasSuffix("-total-capacitance-spread-f")
        })
        #expect(envelope.dependencies.contains {
            $0.path.hasSuffix(".spef")
        })
        #expect(envelope.dependencies.contains {
            $0.path.contains("/ir/") && $0.path.hasSuffix(".json")
        })

        let bundleStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let bundle = try await DefaultFlowRunReviewBundler(
            loader: bundleStore,
            persistence: bundleStore
        ).makeReviewBundle(
            runID: "run-pex-postlayout-review",
            workspaceID: try await workspaceID(projectRoot: root)
        )
        #expect(bundle.artifacts.first(where: {
            $0.stageID == "009-pex"
                && $0.reference.artifactID == "pex-summary"
                && $0.reference.path == pexSummary.path
        }) != nil)
        #expect(bundle.artifacts.first(where: {
            $0.stageID == "010-post-layout-comparison"
                && $0.reference.artifactID == "post-layout-comparison"
                && $0.purpose == .postLayoutComparison
                && $0.reference.path == comparison.path
        }) != nil)
        #expect(bundle.coverageRefs?.contains {
            $0.domain == "pex"
                && $0.stageID == "009-pex"
                && $0.artifactID == "pex-summary"
                && $0.path == pexSummary.path
        } == true)
        #expect(bundle.coverageRefs?.contains {
            $0.domain == "pex"
                && $0.stageID == "010-post-layout-comparison"
                && $0.artifactID == "post-layout-comparison"
                && $0.path == comparison.path
        } == true)
    }

    @Test func pexManifestCoverageGateRejectsDigestAndByteCountMismatch() async throws {
        let root = try makeTemporaryRoot("pex-manifest-mismatch")
        defer { removeTemporaryRoot(root) }

        let rawDirectory = root.appending(path: ".xcircuite/runs/run-pex/stages/009-pex/raw")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let manifestURL = rawDirectory.appending(path: "manifest.json")
        let now = Date()
        let cornerID = PEXCornerID("tt")
        let irRecord = PEXArtifactRecord(
            payload: .available(
                ArtifactReference(
                    id: try ArtifactID(rawValue: "ir-tt"),
                    locator: ArtifactLocator(
                        location: try ArtifactLocation(workspaceRelativePath: "ir/tt.json"),
                        role: .output,
                        kind: try ArtifactKind(rawValue: PEXArtifactKind.parasiticIR.foundationRawValue),
                        format: .json
                    ),
                    digest: try ContentDigest(
                        algorithm: .sha256,
                        hexadecimalValue: String(repeating: "b", count: 64)
                    ),
                    byteCount: 128
                )
            ),
            stage: .persistence,
            cornerID: cornerID,
            createdAt: now
        )
        let rawRecord = PEXArtifactRecord(
            payload: .available(
                ArtifactReference(
                    id: try ArtifactID(rawValue: "raw-tt"),
                    locator: ArtifactLocator(
                        location: try ArtifactLocation(workspaceRelativePath: "raw/tt.spef"),
                        role: .output,
                        kind: try ArtifactKind(rawValue: PEXArtifactKind.rawOutput.foundationRawValue),
                        format: .spef
                    ),
                    digest: try ContentDigest(
                        algorithm: .sha256,
                        hexadecimalValue: String(repeating: "c", count: 64)
                    ),
                    byteCount: 64
                )
            ),
            stage: .backendExecution,
            cornerID: cornerID,
            createdAt: now
        )
        let manifest = PEXArtifactManifest(
            runID: PEXRunID(),
            requestHash: PEXRequestHash("manifest-mismatch"),
            backendID: "mock",
            status: .success,
            startedAt: now,
            finishedAt: now,
            corners: [
                PEXArtifactCorner(cornerID: cornerID, status: .success, artifactIDs: [irRecord.id, rawRecord.id]),
            ],
            artifacts: [irRecord, rawRecord],
            warnings: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        let gate = StageArtifactManifestCoverageGateBuilder().pexGate(
            manifestURL: manifestURL,
            artifacts: [
                try fixtureArtifactReference(
                    artifactID: "ir-tt",
                    path: ".xcircuite/runs/run-pex/stages/009-pex/raw/ir/tt.json",
                    kind: .parasitics,
                    format: .json,
                    sha256: String(repeating: "b", count: 64),
                    byteCount: 1
                ),
                try fixtureArtifactReference(
                    artifactID: "raw-tt",
                    path: ".xcircuite/runs/run-pex/stages/009-pex/raw/raw/tt.spef",
                    kind: .parasitics,
                    format: .spef,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 64
                ),
            ],
            projectRoot: root
        )

        #expect(gate.gateID == "pex-flow-artifacts")
        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_BYTE_COUNT_MISMATCH" })
        #expect(gate.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_SHA256_MISMATCH" })
    }

    @Test func pexExecutorRetriesTransientFailureAndPersistsAttempts() async throws {
        let root = try makeTemporaryRoot("pex-retry")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)
        let engineState = FlakyPEXEngineState()

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex-retry",
                intent: "Retry transient PEX executor failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["PEX_BACKEND_EXECUTION_FAILED"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: FlakyPEXEngine(state: engineState)
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(await engineState.executionCount() == 2)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 2)
        #expect(stage.attempts[0].diagnosticCodes.contains("PEX_BACKEND_EXECUTION_FAILED"))
        #expect(stage.attempts[0].retryDecision.reason == .retryableDiagnosticMatched)
        #expect(stage.attempts[1].retryDecision.reason == .stageDidNotFail)
        #expect(stage.artifacts.contains { $0.artifactID == "009-pex-attempts" })

        let attemptsURL = root.appending(path: ".xcircuite/runs/run-pex-retry/stages/009-pex/attempts.json")
        let attempts = try JSONDecoder().decode(
            [FlowStageAttemptRecord].self,
            from: Data(contentsOf: attemptsURL)
        )
        #expect(attempts.map(\.attemptIndex) == [1, 2])
        #expect(attempts[0].retryDecision.matchedDiagnosticCodes == ["PEX_BACKEND_EXECUTION_FAILED"])

        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root).loadRunLedger(runID: "run-pex-retry")
        #expect(ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.stages.first?.attemptCount == 2)
        #expect(summary.stages.first?.retryCount == 1)

        let bundleStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let bundle = try await DefaultFlowRunReviewBundler(
            loader: bundleStore,
            persistence: bundleStore
        ).makeReviewBundle(
            runID: "run-pex-retry",
            workspaceID: try await workspaceID(projectRoot: root)
        )
        #expect(bundle.artifacts.first(where: { $0.purpose == .stageAttempts }) != nil)
    }

    @Test func pexExecutorForcesFlowManagedWorkingDirectory() async throws {
        let root = try makeTemporaryRoot("pex-forced-workdir")
        defer { removeTemporaryRoot(root) }
        let externalDirectory = try makeTemporaryRoot("external-pex-workdir")
        defer { removeTemporaryRoot(externalDirectory) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default,
                        workingDirectory: externalDirectory
                    ),
                    engine: makeFixturePEXEngine()
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].artifacts.filter { !$0.path.contains("/evidence/") }.allSatisfy {
            $0.path.contains(".xcircuite/runs/run-pex/stages/009-pex/raw")
        })
        #expect(result.stages[0].artifacts.contains {
            $0.path.hasSuffix("evidence/pex-summary-envelope.json")
        })
        #expect(directoryIsEmpty(externalDirectory))
    }

    @Test func pexExecutorCooperativelyCancelsAfterEngineCheckpoint() async throws {
        let root = try makeTemporaryRoot("pex-cooperative-cancel")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex-cancel",
                intent: "Run cancellable PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: CancellingPEXEngine(projectRoot: root, runID: "run-pex-cancel")
                ),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .cancelled)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let ledger = try await XcircuiteWorkspaceStore(projectRoot: root).loadRunLedger(runID: "run-pex-cancel")
        #expect(ledger.cancellationRequest?.requestedBy == "pex-test-fixture")
        #expect(ledger.progressEvents.contains { $0.kind == .cancellationObserved })
    }

    @Test func pexExecutorReportsArtifactCompletenessDiagnostics() async throws {
        let root = try makeTemporaryRoot("pex-artifact-completeness")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: IncompleteArtifactPEXEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "pex-artifacts" && $0.status == .incomplete })
        #expect(stage.gates.contains { $0.gateID == "pex-flow-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "PEX_ARTIFACT_missingArtifact" })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED" })
        #expect(!stage.diagnostics.contains { $0.code == "PEX_EXECUTION_ERROR" })
        #expect(stage.artifacts.contains { $0.path.hasSuffix("manifest.json") })
        #expect(!stage.artifacts.contains { $0.path.hasSuffix("tt.spef") })
        let envelopeArtifact = try #require(stage.artifacts.first {
            $0.path.hasSuffix("evidence/pex-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(evaluation.status == .inconclusive)
        #expect(channelValue("pex-artifact-completeness-status", in: observations) == .text(PEXArtifactCompletenessStatus.incomplete.rawValue))
        #expect(channelValue("pex-corner-0-tt-parasitic-ir-present", in: observations) == .boolean(false))
        #expect(observations.missingChannelIDs.contains("pex-corner-0-tt-parasitic-ir-present"))
        #expect(channelResult("pex-artifact-completeness-status", in: evaluation)?.status == .inconclusive)
        #expect(channelResult("pex-corner-0-tt-parasitic-ir-present", in: evaluation)?.status == .rejected)
        #expect(evaluation.feedbackSignals.contains {
            $0.channelID == "pex-artifact-completeness-status"
                && $0.suggestedActions.contains("repair-pex-artifact-production")
        })
    }

    @Test func pexExecutorFailsFlowArtifactGateWhenManifestOutputIsNotIndexed() async throws {
        let root = try makeTemporaryRoot("pex-flow-artifact-coverage")
        defer { removeTemporaryRoot(root) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: DivergentManifestPEXEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "pex" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "pex-artifacts" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "pex-flow-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED" })
    }

    @Test func pexExecutorRejectsEscapingArtifactBeforeEnvelopeCreation() async throws {
        let root = try makeTemporaryRoot("pex-escaping-artifact")
        defer { removeTemporaryRoot(root) }
        let externalRoot = try makeTemporaryRoot("pex-escaping-artifact-target")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)
        let externalArtifactURL = try writeText(
            "*SPEF \"IEEE 1481-1998\"\n",
            name: "outside.spef",
            root: externalRoot
        )

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: EscapingArtifactPEXEngine(externalArtifactURL: externalArtifactURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "pex-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "PEX_ARTIFACT_pathEscapesRunDirectory" })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_INTEGRITY_INVALID_PATH" })
        #expect(stage.artifacts.contains { $0.path.hasSuffix("tt.spef") })
        #expect(!stage.artifacts.contains { $0.path.hasSuffix("evidence/pex-summary-envelope.json") })
    }

    @Test func pexExecutorRejectsExternalManifestBeforeReadingSummarySource() async throws {
        let root = try makeTemporaryRoot("pex-external-manifest")
        defer { removeTemporaryRoot(root) }
        let externalRoot = try makeTemporaryRoot("pex-external-manifest-target")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let netlistURL = try writeText(".subckt TESTCELL\n.ends\n", name: "source.cir", root: root)
        let externalManifestURL = externalRoot.appending(path: "manifest.json")

        let result = try await makeOrchestrator(root: root).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-pex",
                intent: "Run PEX",
                stages: [
                    FlowStageDefinition(stageID: "009-pex", displayName: "PEX"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PEXFlowStageExecutor(
                    stageID: "009-pex",
                    toolID: "pex-test-fixture",
                    request: PEXRunRequest(
                        layoutURL: layoutURL,
                        layoutFormat: .gds,
                        sourceNetlistURL: netlistURL,
                        sourceNetlistFormat: .spice,
                        topCell: "TESTCELL",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makeTestTech()),
                        backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                        options: .default
                    ),
                    engine: ExternalManifestPEXEngine(externalManifestURL: externalManifestURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "pex" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "PEX_ARTIFACT_OUTPUT_OUTSIDE_PROJECT" })
        #expect(!FileManager.default.fileExists(atPath: externalRoot.appending(path: "pex-summary.json").path(percentEncoded: false)))
    }

    private func makeTestTech() -> TechnologyIR {
        TechnologyIR(
            processName: "test_process",
            stack: [
                TechnologyLayer(
                    name: "M1",
                    order: 0,
                    thickness: 0.1,
                    material: "copper",
                    resistivity: 1.7e-8
                ),
            ],
            logicalToPhysicalLayerMap: [:],
            vias: [],
            defaultExtractionRules: .default,
            backendHints: [:]
        )
    }

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func fixturePEXExecutor(
        stageID: String,
        layoutURL: URL,
        layoutFormat: LayoutFormat,
        sourceNetlistURL: URL,
        topCell: String,
        corners: [PEXCorner],
        technology: XcircuitePEXTechnologySpec,
        technologyByCorner: [String: XcircuitePEXTechnologySpec] = [:],
        processProfile: PEXProcessProfileReference? = nil
    ) -> PEXFlowStageExecutor {
        PEXFlowStageExecutor(
            stageID: stageID,
            toolID: SignoffToolDescriptors.pexToolID(backendID: "test-fixture"),
            layoutInput: .path(layoutURL.path(percentEncoded: false)),
            layoutFormat: layoutFormat,
            sourceNetlistInput: .path(sourceNetlistURL.path(percentEncoded: false)),
            topCell: topCell,
            corners: corners,
            technology: technology,
            technologyByCorner: technologyByCorner,
            processProfile: processProfile,
            backendSelection: PEXBackendSelection(backendID: "test-fixture"),
            engine: makeFixturePEXEngine()
        )
    }

    private func makeOrchestrator(root: URL) throws -> DefaultFlowOrchestrator {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        return DefaultFlowOrchestrator(
            infrastructure: store,
            ledgerPersistence: store,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "XcircuiteTests",
                version: "1.0.0"
            ),
            progressStore: FlowRunProgressStore(persistence: store)
        )
    }

    private func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PEXFlowStageExecutorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func decodeArtifactEnvelope(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> FlowArtifactEnvelope {
        try JSONDecoder().decode(
            FlowArtifactEnvelope.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func directoryIsEmpty(_ directory: URL) -> Bool {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        } catch {
            Issue.record("Failed to inspect temporary root: \(error)")
            return false
        }
    }

    private func channelValue(
        _ channelID: String,
        in observations: FlowObservationSet
    ) -> FlowMetricValue? {
        observations.channels.first { $0.channelID == channelID }?.value
    }

    private func channelResult(
        _ channelID: String,
        in evaluation: FlowEvaluationResult
    ) -> FlowEvaluationChannelResult? {
        evaluation.channelResults.first { $0.channelID == channelID }
    }

    private struct IncompleteArtifactPEXEngine: PEXEngine.PEXRunning {
        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            guard let workingDirectory = request.workingDirectory else {
                throw PEXError.invalidInput("Expected working directory")
            }
            let runID = PEXRunID()
            let cornerID = PEXCornerID("tt")
            let now = Date()
            let manifestURL = workingDirectory.appending(path: "manifest.json")
            let rawRecord = PEXArtifactRecord(
                payload: .available(
                    ArtifactReference(
                        id: try ArtifactID(rawValue: "raw-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "raw/tt/tt.spef"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.rawOutput.foundationRawValue),
                            format: .spef
                        ),
                        digest: try ContentDigest(
                            algorithm: .sha256,
                            hexadecimalValue: String(repeating: "0", count: 64)
                        ),
                        byteCount: 1
                    )
                ),
                stage: .backendExecution,
                cornerID: cornerID,
                createdAt: now
            )
            let omittedIRRecord = PEXArtifactRecord(
                payload: .omitted(
                    PEXArtifactDeclaration(
                        id: try ArtifactID(rawValue: "ir-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "ir/tt.json"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.parasiticIR.foundationRawValue),
                            format: .json
                        )
                    )
                ),
                stage: .persistence,
                cornerID: cornerID,
                createdAt: now
            )
            let manifest = PEXArtifactManifest(
                runID: runID,
                requestHash: PEXRequestHash("incomplete-artifacts"),
                backendID: "test-fixture",
                status: .success,
                startedAt: now,
                finishedAt: now,
                corners: [
                    PEXArtifactCorner(
                        cornerID: cornerID,
                        status: .success,
                        artifactIDs: [rawRecord.id, omittedIRRecord.id]
                    ),
                ],
                artifacts: [rawRecord, omittedIRRecord],
                warnings: []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            return try PEXRunResult(
                runID: runID,
                requestHash: PEXRequestHash("incomplete-artifacts"),
                status: .success,
                startedAt: now,
                finishedAt: now,
                cornerResults: [
                    PEXCornerResult(
                        cornerID: cornerID,
                        status: .success,
                        metrics: PEXCornerMetrics(
                            durationSeconds: 0,
                            netCount: 0,
                            elementCount: 0
                        )
                    ),
                ],
                warnings: [],
                artifactManifest: manifest,
                manifestURL: manifestURL,
                metrics: PEXRunMetrics(
                    totalDurationSeconds: 0,
                    cornerCount: 1,
                    successCount: 1,
                    failureCount: 0
                )
            )
        }
    }

    private struct CancellingPEXEngine: PEXEngine.PEXRunning {
        let projectRoot: URL
        let runID: String

        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
            try await store.createWorkspace()
            let manifest = try await store.loadManifest()
            _ = try await DefaultFlowRunCancellationRecorder(
                progressStore: FlowRunProgressStore(persistence: store)
            ).requestCancellation(
                workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
                runID: runID,
                requestedBy: "pex-test-fixture",
                reason: "cooperative PEX cancellation checkpoint"
            )
            return try await IncompleteArtifactPEXEngine().run(request)
        }
    }

    private struct FlakyPEXEngine: PEXEngine.PEXRunning {
        let state: FlakyPEXEngineState

        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            try await state.run(request)
        }
    }

    private actor FlakyPEXEngineState {
        private var runCount = 0

        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            runCount += 1
            if runCount == 1 {
                throw PEXError(
                    kind: .backendExecutionFailed,
                    stage: .backendExecution,
                    cornerID: PEXCornerID("tt"),
                    backendID: "test-fixture",
                    message: "transient PEX backend failure"
                )
            }
            return try await makeFixturePEXEngine().run(request)
        }

        func executionCount() -> Int {
            runCount
        }
    }

    private struct DivergentManifestPEXEngine: PEXEngine.PEXRunning {
        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            guard let workingDirectory = request.workingDirectory else {
                throw PEXError.invalidInput("Expected working directory")
            }
            let runID = PEXRunID()
            let cornerID = PEXCornerID("tt")
            let now = Date()
            let manifestURL = workingDirectory.appending(path: "manifest.json")
            let rawURL = workingDirectory.appending(path: "raw/tt/tt.spef")
            let extraURL = workingDirectory.appending(path: "reports/extra.json")
            try FileManager.default.createDirectory(
                at: rawURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: extraURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let rawData = Data("*SPEF \"IEEE 1481-1998\"\n".utf8)
            let extraData = Data("{\"extra\":true}\n".utf8)
            try rawData.write(to: rawURL, options: .atomic)
            try extraData.write(to: extraURL, options: .atomic)

            let rawRecord = PEXArtifactRecord(
                payload: .available(
                    ArtifactReference(
                        id: try ArtifactID(rawValue: "raw-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "raw/tt/tt.spef"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.rawOutput.foundationRawValue),
                            format: .spef
                        ),
                        digest: try ContentDigest(
                            algorithm: .sha256,
                            hexadecimalValue: PEXArtifactResolver.sha256(data: rawData)
                        ),
                        byteCount: UInt64(rawData.count)
                    )
                ),
                stage: .backendExecution,
                cornerID: cornerID,
                createdAt: now
            )
            let omittedIRRecord = PEXArtifactRecord(
                payload: .omitted(
                    PEXArtifactDeclaration(
                        id: try ArtifactID(rawValue: "ir-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "ir/tt.json"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.parasiticIR.foundationRawValue),
                            format: .json
                        )
                    )
                ),
                stage: .persistence,
                cornerID: cornerID,
                createdAt: now
            )
            let extraRecord = PEXArtifactRecord(
                payload: .available(
                    ArtifactReference(
                        id: try ArtifactID(rawValue: "extra-report"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "reports/extra.json"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.report.foundationRawValue),
                            format: .json
                        ),
                        digest: try ContentDigest(
                            algorithm: .sha256,
                            hexadecimalValue: PEXArtifactResolver.sha256(data: extraData)
                        ),
                        byteCount: UInt64(extraData.count)
                    )
                ),
                stage: .reporting,
                createdAt: now
            )
            let returnedManifest = PEXArtifactManifest(
                runID: runID,
                requestHash: PEXRequestHash("divergent-manifest"),
                backendID: "test-fixture",
                status: .success,
                startedAt: now,
                finishedAt: now,
                corners: [
                    PEXArtifactCorner(
                        cornerID: cornerID,
                        status: .success,
                        artifactIDs: [rawRecord.id, omittedIRRecord.id]
                    ),
                ],
                artifacts: [rawRecord, omittedIRRecord],
                warnings: []
            )
            let persistedManifest = PEXArtifactManifest(
                runID: runID,
                requestHash: PEXRequestHash("divergent-manifest"),
                backendID: "test-fixture",
                status: .success,
                startedAt: now,
                finishedAt: now,
                corners: returnedManifest.corners,
                artifacts: [rawRecord, omittedIRRecord, extraRecord],
                warnings: []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(persistedManifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            return try PEXRunResult(
                runID: runID,
                requestHash: PEXRequestHash("divergent-manifest"),
                status: .success,
                startedAt: now,
                finishedAt: now,
                cornerResults: [
                    PEXCornerResult(
                        cornerID: cornerID,
                        status: .success,
                        metrics: PEXCornerMetrics(
                            durationSeconds: 0,
                            netCount: 0,
                            elementCount: 0
                        )
                    ),
                ],
                warnings: [],
                artifactManifest: returnedManifest,
                manifestURL: manifestURL,
                metrics: PEXRunMetrics(
                    totalDurationSeconds: 0,
                    cornerCount: 1,
                    successCount: 1,
                    failureCount: 0
                )
            )
        }
    }

    private struct EscapingArtifactPEXEngine: PEXEngine.PEXRunning {
        let externalArtifactURL: URL

        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            guard let workingDirectory = request.workingDirectory else {
                throw PEXError.invalidInput("Expected working directory")
            }
            let runID = PEXRunID()
            let cornerID = PEXCornerID("tt")
            let now = Date()
            let manifestURL = workingDirectory.appending(path: "manifest.json")
            let rawURL = workingDirectory.appending(path: "raw/tt/tt.spef")
            try FileManager.default.createDirectory(
                at: rawURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: rawURL,
                withDestinationURL: externalArtifactURL
            )
            let rawData = try Data(contentsOf: externalArtifactURL)
            let rawRecord = PEXArtifactRecord(
                payload: .available(
                    ArtifactReference(
                        id: try ArtifactID(rawValue: "raw-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "raw/tt/tt.spef"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.rawOutput.foundationRawValue),
                            format: .spef
                        ),
                        digest: try ContentDigest(
                            algorithm: .sha256,
                            hexadecimalValue: PEXArtifactResolver.sha256(data: rawData)
                        ),
                        byteCount: UInt64(rawData.count)
                    )
                ),
                stage: .backendExecution,
                cornerID: cornerID,
                createdAt: now
            )
            let omittedIRRecord = PEXArtifactRecord(
                payload: .omitted(
                    PEXArtifactDeclaration(
                        id: try ArtifactID(rawValue: "ir-tt"),
                        locator: ArtifactLocator(
                            location: try ArtifactLocation(workspaceRelativePath: "ir/tt.json"),
                            role: .output,
                            kind: try ArtifactKind(rawValue: PEXArtifactKind.parasiticIR.foundationRawValue),
                            format: .json
                        )
                    )
                ),
                stage: .persistence,
                cornerID: cornerID,
                createdAt: now
            )
            let manifest = PEXArtifactManifest(
                runID: runID,
                requestHash: PEXRequestHash("escaping-artifact"),
                backendID: "test-fixture",
                status: .success,
                startedAt: now,
                finishedAt: now,
                corners: [
                    PEXArtifactCorner(
                        cornerID: cornerID,
                        status: .success,
                        artifactIDs: [rawRecord.id, omittedIRRecord.id]
                    ),
                ],
                artifacts: [rawRecord, omittedIRRecord],
                warnings: []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            return try PEXRunResult(
                runID: runID,
                requestHash: PEXRequestHash("escaping-artifact"),
                status: .success,
                startedAt: now,
                finishedAt: now,
                cornerResults: [
                    PEXCornerResult(
                        cornerID: cornerID,
                        status: .success,
                        metrics: PEXCornerMetrics(
                            durationSeconds: 0,
                            netCount: 0,
                            elementCount: 0
                        )
                    ),
                ],
                warnings: [],
                artifactManifest: manifest,
                manifestURL: manifestURL,
                metrics: PEXRunMetrics(
                    totalDurationSeconds: 0,
                    cornerCount: 1,
                    successCount: 1,
                    failureCount: 0
                )
            )
        }
    }

    private struct ExternalManifestPEXEngine: PEXEngine.PEXRunning {
        let externalManifestURL: URL

        func run(_ request: PEXRunRequest) async throws -> PEXRunResult {
            let runID = PEXRunID()
            let now = Date()
            let manifest = PEXArtifactManifest(
                runID: runID,
                requestHash: PEXRequestHash("external-manifest"),
                backendID: "test-fixture",
                status: .success,
                startedAt: now,
                finishedAt: now,
                corners: [],
                artifacts: [],
                warnings: []
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: externalManifestURL, options: .atomic)
            return try PEXRunResult(
                runID: runID,
                requestHash: PEXRequestHash("external-manifest"),
                status: .success,
                startedAt: now,
                finishedAt: now,
                cornerResults: [],
                warnings: [],
                artifactManifest: manifest,
                manifestURL: externalManifestURL,
                metrics: PEXRunMetrics(
                    totalDurationSeconds: 0,
                    cornerCount: 0,
                    successCount: 0,
                    failureCount: 0
                )
            )
        }
    }
}
import CircuiteFoundation
