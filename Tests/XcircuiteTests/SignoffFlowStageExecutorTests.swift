import CircuiteFoundation
import DesignFlowKernel
import DRCEngine
import Foundation
import LVSEngine
import Testing
import ToolQualification
import Xcircuite

@Suite("Signoff flow stage executors")
struct SignoffFlowStageExecutorTests {
    @Test func nativeDRCExecutorRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("drc-pass")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeLayout(
            NativeDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    NativeDRCRectangle(id: "m1_a", layer: "met1", xMin: 0, yMin: 0, xMax: 1, yMax: 1),
                    NativeDRCRectangle(id: "m1_b", layer: "met1", xMin: 2, yMin: 0, xMax: 3, yMax: 1),
                ],
                rules: [
                    NativeDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                    NativeDRCRule(id: "met1.space", kind: .minimumSpacing, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: ToolTrustRequirement(
                            kind: .drc,
                            operationID: "run-drc",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.json],
                            requiredOutputFormats: [.json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.nativeDRC(level: .smokeChecked)]),
            healthResults: [
                "native-drc": QualifiedToolFixtures.health(toolID: "native-drc", level: .smokeChecked),
            ],
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "drc" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "drc-artifacts" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.stages[0].artifacts.contains { $0.path.contains("drc-report") })
        #expect(result.stages[0].artifacts.contains { $0.path.contains("drc-artifact-manifest") })
        let summaryArtifact = try #require(result.stages[0].artifacts.first { $0.artifactID == "drc-summary" })
        let summary = try decodeDRCSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "passed")
        #expect(summary.summary.activeViolationCount == 0)
        let envelopeArtifact = try #require(result.stages[0].artifacts.first {
            $0.path.hasSuffix("evidence/drc-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(envelope.artifactID == "drc-summary")
        #expect(evaluation.status == .accepted)
        #expect(channelValue("drc-active-violation-count", in: observations) == .scalar(0))
        #expect(channelValue("drc-violation-bucket-count", in: observations) == .scalar(0))
        #expect(channelValue("drc-tool-evidence-count", in: observations) == .scalar(1))
        #expect(channelResult("drc-active-violation-count", in: evaluation)?.status == .accepted)
        #expect(observations.missingChannelIDs.isEmpty)
        #expect(observations.uncalibratedChannelIDs == ["drc-qualified-calibration"])
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
    }

    @Test func drcExecutorForcesFlowManagedWorkingDirectory() async throws {
        let root = try makeTemporaryRoot("drc-forced-workdir")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let externalDirectory = try makeTemporaryRoot("external-drc-workdir")
        defer { removeTemporaryRoot(externalDirectory) }

        let layoutURL = try writeLayout(
            NativeDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    NativeDRCRectangle(id: "m1_a", layer: "met1", xMin: 0, yMin: 0, xMax: 1, yMax: 1),
                ],
                rules: [
                    NativeDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        workingDirectory: externalDirectory,
                        backendSelection: DRCBackendSelection(backendID: "native")
                    ),
                    engine: DefaultDRCEngine(backend: nil)
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(artifacts.contains { $0.path.contains(".xcircuite/runs/run-drc/stages/007-drc/raw") })
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
        #expect(!directoryContainsReport(externalDirectory))
    }

    @Test func drcExecutorCooperativelyCancelsAfterEngineCheckpoint() async throws {
        let root = try makeTemporaryRoot("drc-cooperative-cancel")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.oas", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc-cancel",
                intent: "Run cancellable DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: CancellingDRCStubEngine(
                        cancellationRecorder: services.cancellationRecorder,
                        workspaceID: services.workspaceID,
                        runID: "run-drc-cancel"
                    )
                ),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .cancelled)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let ledger = try await services.store.loadRunLedger(runID: "run-drc-cancel")
        #expect(ledger.cancellationRequest?.requestedBy == "native-drc")
        #expect(ledger.progressEvents.contains { $0.kind == .cancellationObserved })
    }

    @Test func drcExecutorPreservesStandardInputRequestAndIndexesManifest() async throws {
        let root = try makeTemporaryRoot("drc-standard-input")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.oas", root: root)
        let technologyURL = try writeText("{}", name: "tech.json", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run standard DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        technologyURL: technologyURL,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: StandardDRCStubEngine(expectedTechnologyURL: technologyURL)
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(artifacts.contains { $0.path.contains("drc-report") })
        #expect(artifacts.contains { $0.path.contains("drc-artifact-manifest") })
        #expect(artifacts.contains { $0.artifactID == "drc-summary" })
        #expect(result.stages[0].gates.contains { $0.gateID == "drc-artifacts" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(artifacts.contains { $0.path.contains("drc.log") })
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
    }

    @Test func drcExecutorFailsManifestGateWhenOutputIsNotIndexed() async throws {
        let root = try makeTemporaryRoot("drc-manifest-coverage")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeText("layout", name: "layout.oas", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: UnindexedManifestOutputDRCStubEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "drc" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "drc-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED" })
    }

    @Test func drcExecutorFailsManifestGateWhenFlowArtifactsDuplicatePath() async throws {
        let root = try makeTemporaryRoot("drc-manifest-duplicate-path")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeText("layout", name: "layout.oas", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: DuplicateArtifactPathDRCStubEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "drc" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "drc-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_DUPLICATE_FLOW_ARTIFACT_PATH" })
    }

    @Test func drcExecutorFailsArtifactIntegrityGateWhenArtifactEscapesProject() async throws {
        let root = try makeTemporaryRoot("drc-artifact-integrity")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let externalRoot = try makeTemporaryRoot("drc-artifact-integrity-external")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.oas", root: root)
        let externalManifestURL = externalRoot.appending(path: "drc-artifact-manifest.json")

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: EscapingArtifactDRCStubEngine(externalManifestURL: externalManifestURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "drc" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "DRC_ARTIFACT_OUTPUT_OUTSIDE_PROJECT" })
        #expect(!stage.gates.contains { $0.gateID == "drc-artifacts" })
        #expect(!stage.gates.contains { $0.gateID == "artifact-integrity" })
        #expect(!stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_UNREADABLE" })
    }

    @Test func drcExecutorRejectsExternalManifestBeforeWritingSummaryArtifacts() async throws {
        let root = try makeTemporaryRoot("drc-external-manifest")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let externalRoot = try makeTemporaryRoot("drc-external-manifest-target")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.oas", root: root)
        let externalManifestURL = externalRoot.appending(path: "drc-artifact-manifest.json")

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        layoutFormat: .oasis,
                        backendSelection: DRCBackendSelection(backendID: "native-gds")
                    ),
                    engine: ExternalManifestDRCStubEngine(externalManifestURL: externalManifestURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "drc" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "DRC_ARTIFACT_OUTPUT_OUTSIDE_PROJECT" })
        #expect(!FileManager.default.fileExists(atPath: externalRoot.appending(path: "drc-summary.json").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: externalRoot.appending(path: "drc-repair-hints.json").path(percentEncoded: false)))
    }

    @Test func nativeDRCExecutorFailsGateOnViolation() async throws {
        let root = try makeTemporaryRoot("drc-fail")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeLayout(
            NativeDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    NativeDRCRectangle(id: "thin", layer: "met1", xMin: 0, yMin: 0, xMax: 0.1, yMax: 1),
                ],
                rules: [
                    NativeDRCRule(id: "met1.width", kind: .minimumWidth, layer: "met1", value: 0.5),
                ]
            ),
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .failed)
        #expect(result.stages[0].gates.first?.status == .failed)
        #expect(result.stages[0].diagnostics.contains { $0.code == "met1.width" })
        let summaryArtifact = try #require(result.stages[0].artifacts.first { $0.artifactID == "drc-summary" })
        let summary = try decodeDRCSummary(summaryArtifact, root: root)
        #expect(summary.summary.status == "failed")
        #expect(summary.summary.activeViolationCount == 1)
        #expect(summary.summary.violationBuckets.first?.ruleID == "met1.width")
        let envelopeArtifact = try #require(result.stages[0].artifacts.first {
            $0.path.hasSuffix("evidence/drc-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(evaluation.status == .rejected)
        #expect(evaluation.residual == 1)
        #expect(channelValue("drc-active-violation-count", in: observations) == .scalar(1))
        #expect(channelValue("drc-rule-0-met1-width-active-count", in: observations) == .scalar(1))
        #expect(channelResult("drc-active-violation-count", in: evaluation)?.status == .rejected)
        #expect(channelResult("drc-rule-0-met1-width-active-count", in: evaluation)?.status == .rejected)
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
        #expect(evaluation.feedbackSignals.first?.channelID == "drc-rule-0-met1-width-active-count")
        #expect(evaluation.feedbackSignals.first?.suggestedActions.contains("apply-drc-repair-hint") == true)
    }

    @Test func drcExecutorPersistsMinimumCutRepairHintsForFlowReview() async throws {
        let root = try makeTemporaryRoot("drc-minimum-cut-repair-hints")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeLayout(
            NativeDRCLayout(
                technologyID: "generic",
                topCell: "TOP",
                rectangles: [
                    NativeDRCRectangle(
                        id: "lower",
                        layer: "met1",
                        xMin: 0,
                        yMin: 0,
                        xMax: 2,
                        yMax: 2,
                        netID: "sig"
                    ),
                    NativeDRCRectangle(
                        id: "upper",
                        layer: "met2",
                        xMin: 0,
                        yMin: 0,
                        xMax: 2,
                        yMax: 2,
                        netID: "sig"
                    ),
                    NativeDRCRectangle(
                        id: "cut-a",
                        layer: "via1",
                        xMin: 0.5,
                        yMin: 0.5,
                        xMax: 1,
                        yMax: 1,
                        netID: "sig"
                    ),
                ],
                rules: [
                    NativeDRCRule(
                        id: "via1.minimumCut",
                        kind: .minimumCut,
                        layer: "via1",
                        value: 2,
                        lowerLayer: "met1",
                        upperLayer: "met2"
                    ),
                ]
            ),
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-drc-minimum-cut",
                intent: "Run minimum-cut DRC",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "drc" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "via1.minimumCut" })
        let repairHintsArtifact = try #require(stage.artifacts.first {
            $0.artifactID == "drc-repair-hints"
        })
        #expect(repairHintsArtifact.path.hasSuffix("raw/drc-repair-hints.json"))
        let repairHints = try decodeDRCRepairHints(repairHintsArtifact, root: root)
        #expect(repairHints.status == "ready")
        #expect(repairHints.activeDiagnosticCount == 1)
        #expect(repairHints.hintCount == 1)
        let hint = try #require(repairHints.hints.first)
        #expect(hint.hintID == "drc-repair-0-via1-minimumCut")
        #expect(hint.ruleID == "via1.minimumCut")
        #expect(hint.kind == "minimumCut")
        #expect(hint.layer == "via1")
        #expect(hint.operationID == "layout.add-via")
        #expect(hint.relatedViaIDs == ["cut-a"])
        #expect(hint.relatedNetIDs == ["sig"])
        #expect(hint.numericParameters["missingCutCount"] == 1)
        #expect(hint.stringParameters["viaDefinitionID"] == "VIA1")
        #expect(hint.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])

        let bundle = try await services.reviewBundler.makeReviewBundle(
            runID: "run-drc-minimum-cut",
            workspaceID: services.workspaceID
        )
        #expect(bundle.artifacts.first(where: {
            $0.stageID == "007-drc"
                && $0.reference.artifactID == "drc-repair-hints"
                && $0.reference.path == repairHintsArtifact.path
        }) != nil)
        #expect(bundle.coverageRefs?.contains {
            $0.domain == "drc"
                && $0.stageID == "007-drc"
                && $0.artifactID == "drc-repair-hints"
                && $0.path == repairHintsArtifact.path
        } == true)
    }

    @Test func nativeLVSExecutorRunsThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("lvs-pass")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let layoutURL = try writeNetlist(matchingNetlist(), name: "layout.spice", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: ToolTrustRequirement(
                            kind: .lvs,
                            operationID: "run-lvs",
                            minimumLevel: .smokeChecked,
                            requiredInputFormats: [.spice],
                            requiredOutputFormats: [.json]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [SignoffToolDescriptors.nativeLVS(level: .smokeChecked)]),
            healthResults: [
                "native-lvs": QualifiedToolFixtures.health(toolID: "native-lvs", level: .smokeChecked),
            ],
            executors: [
                LVSFlowStageExecutor.native(
                    stageID: "008-lvs",
                    layoutNetlistURL: layoutURL,
                    schematicNetlistURL: schematicURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(result.stages[0].gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "lvs-artifacts" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(result.stages[0].artifacts.contains { $0.path.contains("lvs-report") })
        #expect(result.stages[0].artifacts.contains { $0.path.contains("lvs-artifact-manifest") })
        let summaryArtifact = try #require(result.stages[0].artifacts.first { $0.artifactID == "lvs-summary" })
        let summary = try decodeLVSSummary(summaryArtifact, root: root)
        #expect(summary.summary.executionStatus == .completed)
        #expect(summary.summary.verdict == .match)
        #expect(summary.summary.readiness == .ready)
        #expect(summary.summary.activeMismatchCount == 0)
        let envelopeArtifact = try #require(result.stages[0].artifacts.first {
            $0.path.hasSuffix("evidence/lvs-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(envelope.artifactID == "lvs-summary")
        #expect(evaluation.status == .accepted)
        #expect(channelValue("lvs-active-mismatch-count", in: observations) == .scalar(0))
        #expect(channelValue("lvs-mismatch-bucket-count", in: observations) == .scalar(0))
        #expect(channelValue("lvs-tool-evidence-count", in: observations) == .scalar(1))
        #expect(channelResult("lvs-active-mismatch-count", in: evaluation)?.status == .accepted)
        #expect(!observations.missingChannelIDs.contains("lvs-tool-evidence-count"))
        #expect(observations.missingChannelIDs.contains("lvs-device-policy-present"))
        #expect(observations.uncalibratedChannelIDs == ["lvs-qualified-calibration"])
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
    }

    @Test func lvsExecutorPersistsDevicePolicyReportForFlowReview() async throws {
        let root = try makeTemporaryRoot("lvs-policy-report")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let layoutURL = try writeNetlist(matchingNetlist(), name: "layout.spice", root: root)
        let policyReport = LVSDevicePolicyApplicationReport(
            generatedAt: "2026-06-29T00:00:00Z",
            status: .partial,
            policyPath: "/tmp/lvs-device-policy.json",
            seedSourcePath: "/tmp/netgen_setup.tcl",
            knownDeviceCount: 2,
            observedKnownDeviceCount: 1,
            policyRuleCount: 3,
            appliedRuleCount: 1,
            ignoredRuleCount: 1,
            unobservedRuleCount: 1,
            policyRuleCountsByKind: ["permute": 1, "property": 1, "equatePins": 1],
            appliedRuleCountsByKind: ["permute": 1],
            ignoredRuleCountsByReason: ["unsupported-property-command": 1],
            unobservedRuleCountsByKind: ["equatePins": 1],
            deviceFamilyCounts: ["mos": 2],
            observedDeviceFamilyCounts: ["mos": 1],
            appliedRules: [
                LVSDevicePolicyAppliedRule(
                    kind: "permute",
                    model: "nmos",
                    family: "mos",
                    equivalentPinGroups: [[1, 3]],
                    sourceLineNumber: 10,
                    sourceLine: "permute nmos 1 3"
                ),
            ],
            ignoredRules: [
                LVSDevicePolicyIgnoredRule(
                    kind: "property",
                    reasonCode: "unsupported-property-command",
                    message: "Unsupported property command",
                    sourceLineNumber: 12,
                    sourceLine: "property nmos unsupported"
                ),
            ],
            unobservedRules: [
                LVSDevicePolicyUnobservedRule(
                    kind: "equatePins",
                    reasonCode: "selector-not-observed",
                    message: "No compared device matched this selector.",
                    targetModels: ["pmos"],
                    sourceLineNumber: 14,
                    sourceLine: "equate_pins pmos 1 3"
                ),
            ]
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs-policy-report",
                intent: "Run LVS with device policy evidence",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutNetlistURL: layoutURL,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native")
                    ),
                    engine: DevicePolicyReportLVSStubEngine(devicePolicyReport: policyReport)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "lvs-artifacts" && $0.status == .passed })
        let policyArtifact = try #require(stage.artifacts.first {
            $0.artifactID == "lvs-device-policy-application-report"
        })
        #expect(policyArtifact.path.hasSuffix("raw/lvs-device-policy-application-report.json"))
        let persistedPolicyReport = try decodeLVSDevicePolicyReport(policyArtifact, root: root)
        #expect(persistedPolicyReport.status == .partial)
        #expect(persistedPolicyReport.policyPath == "/tmp/lvs-device-policy.json")
        #expect(persistedPolicyReport.appliedRuleCount == 1)
        #expect(persistedPolicyReport.ignoredRuleCountsByReason["unsupported-property-command"] == 1)
        #expect(persistedPolicyReport.unobservedRuleCountsByKind["equatePins"] == 1)
        #expect(persistedPolicyReport.appliedRules.first?.model == "nmos")
        #expect(persistedPolicyReport.ignoredRules.first?.reasonCode == "unsupported-property-command")
        #expect(persistedPolicyReport.unobservedRules.first?.targetModels == ["pmos"])

        let summaryArtifact = try #require(stage.artifacts.first { $0.artifactID == "lvs-summary" })
        let summary = try decodeLVSSummary(summaryArtifact, root: root)
        #expect(summary.summary.devicePolicySummary?.status == .partial)
        #expect(summary.summary.devicePolicySummary?.policyRuleCount == 3)
        #expect(summary.summary.devicePolicySummary?.appliedRuleCount == 1)
        #expect(summary.summary.devicePolicySummary?.ignoredRuleCount == 1)
        #expect(summary.summary.devicePolicySummary?.unobservedRuleCount == 1)

        let envelopeArtifact = try #require(stage.artifacts.first {
            $0.path.hasSuffix("evidence/lvs-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        #expect(envelope.dependencies.contains {
            $0.artifactID == "lvs-device-policy-application-report"
                && $0.path == policyArtifact.path
        })
        let observations = try #require(envelope.observationSet)
        #expect(channelValue("lvs-device-policy-present", in: observations) == .boolean(true))
        #expect(channelValue("lvs-device-policy-status", in: observations) == .text("partial"))
        #expect(channelValue("lvs-device-policy-applied-rule-count", in: observations) == .scalar(1))
        #expect(channelValue("lvs-device-policy-ignored-rule-count", in: observations) == .scalar(1))
        #expect(channelValue("lvs-device-policy-unobserved-rule-count", in: observations) == .scalar(1))

        let bundle = try await services.reviewBundler.makeReviewBundle(
            runID: "run-lvs-policy-report",
            workspaceID: services.workspaceID
        )
        #expect(bundle.artifacts.first(where: {
            $0.stageID == "008-lvs"
                && $0.reference.artifactID == "lvs-device-policy-application-report"
                && $0.reference.path == policyArtifact.path
        }) != nil)
        #expect(bundle.coverageRefs?.contains {
            $0.domain == "lvs"
                && $0.stageID == "008-lvs"
                && $0.artifactID == "lvs-device-policy-application-report"
                && $0.path == policyArtifact.path
        } == true)
    }

    @Test func nativeLVSExecutorFailsGateOnModelMismatch() async throws {
        let root = try makeTemporaryRoot("lvs-fail")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let layoutURL = try writeNetlist(matchingNetlist(), name: "layout.spice", root: root)
        let schematicURL = try writeNetlist(
            """
            .subckt TOP in out vdd vss
            M1 out in vdd vdd pmos
            M2 out in vss vss nmos_mismatch
            .ends TOP
            """,
            name: "schematic.spice",
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor.native(
                    stageID: "008-lvs",
                    layoutNetlistURL: layoutURL,
                    schematicNetlistURL: schematicURL,
                    topCell: "TOP"
                ),
            ]
        )

        #expect(result.status == .failed)
        #expect(result.stages[0].gates.contains { $0.gateID == "lvs" && $0.status == .failed })
        #expect(result.stages[0].diagnostics.contains { $0.code == "LVS_MODEL_MISMATCH" })
        let summaryArtifact = try #require(result.stages[0].artifacts.first { $0.artifactID == "lvs-summary" })
        let summary = try decodeLVSSummary(summaryArtifact, root: root)
        #expect(summary.summary.executionStatus == .completed)
        #expect(summary.summary.verdict == .mismatch)
        #expect(summary.summary.readiness == .ready)
        #expect(summary.summary.activeMismatchCount == 1)
        #expect(summary.summary.mismatchBuckets.first?.ruleID == "LVS_MODEL_MISMATCH")
        let envelopeArtifact = try #require(result.stages[0].artifacts.first {
            $0.path.hasSuffix("evidence/lvs-summary-envelope.json")
        })
        let envelope = try decodeArtifactEnvelope(envelopeArtifact, root: root)
        let observations = try #require(envelope.observationSet)
        let evaluation = try #require(envelope.evaluationResult)
        #expect(evaluation.status == .rejected)
        #expect(evaluation.residual == 1)
        #expect(channelValue("lvs-active-mismatch-count", in: observations) == .scalar(1))
        #expect(channelValue("lvs-mismatch-0-lvs-model-mismatch-active-count", in: observations) == .scalar(1))
        #expect(channelResult("lvs-active-mismatch-count", in: evaluation)?.status == .rejected)
        #expect(channelResult("lvs-mismatch-0-lvs-model-mismatch-active-count", in: evaluation)?.status == .rejected)
        #expect(evaluation.feedbackSignals.first?.routingLevel == .localSurface)
        #expect(evaluation.feedbackSignals.first?.channelID == "lvs-mismatch-0-lvs-model-mismatch-active-count")
        #expect(evaluation.feedbackSignals.first?.suggestedActions.contains("repair-layout-or-schematic-mapping") == true)
    }

    @Test func lvsExecutorRetriesTransientFailureAndPersistsAttempts() async throws {
        let root = try makeTemporaryRoot("lvs-retry")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)

        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let layoutURL = try writeNetlist(matchingNetlist(), name: "layout.spice", root: root)
        let engineState = FlakyLVSStubEngineState()

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs-retry",
                intent: "Retry transient LVS executor failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["LVS_EXECUTION_ERROR"]
                        )
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutNetlistURL: layoutURL,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native")
                    ),
                    engine: FlakyLVSStubEngine(state: engineState)
                ),
            ]
        )

        #expect(result.status == .succeeded)
        #expect(await engineState.executionCount() == 2)
        let stage = try #require(result.stages.first)
        #expect(stage.attempts.count == 2)
        #expect(stage.attempts[0].diagnosticCodes.contains("LVS_EXECUTION_ERROR"))
        #expect(stage.attempts[0].retryDecision.reason == .retryableDiagnosticMatched)
        #expect(stage.attempts[1].retryDecision.reason == .stageDidNotFail)
        #expect(stage.artifacts.contains { $0.artifactID == "008-lvs-attempts" })

        let attemptsURL = root.appending(path: ".xcircuite/runs/run-lvs-retry/stages/008-lvs/attempts.json")
        let attempts = try JSONDecoder().decode(
            [FlowStageAttemptRecord].self,
            from: Data(contentsOf: attemptsURL)
        )
        #expect(attempts.map(\.attemptIndex) == [1, 2])
        #expect(attempts[0].retryDecision.matchedDiagnosticCodes == ["LVS_EXECUTION_ERROR"])

        let ledger = try await services.store.loadRunLedger(runID: "run-lvs-retry")
        #expect(ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
        let bundle = try await services.reviewBundler.makeReviewBundle(
            runID: "run-lvs-retry",
            workspaceID: services.workspaceID
        )
        let summary = bundle.summary
        #expect(summary.stages.first?.attemptCount == 2)
        #expect(summary.stages.first?.retryCount == 1)

        #expect(bundle.artifacts.first(where: { $0.purpose == .stageAttempts }) != nil)
    }

    @Test func lvsExecutorCooperativelyCancelsAfterEngineCheckpoint() async throws {
        let root = try makeTemporaryRoot("lvs-cooperative-cancel")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs-cancel",
                intent: "Run cancellable LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: CancellingLVSStubEngine(
                        cancellationRecorder: services.cancellationRecorder,
                        workspaceID: services.workspaceID,
                        runID: "run-lvs-cancel"
                    )
                ),
            ]
        )

        let stage = try #require(result.stages.first)
        #expect(result.status == .cancelled)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains { $0.gateID == "cancellation" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "RUN_CANCELLATION_REQUESTED" })

        let ledger = try await services.store.loadRunLedger(runID: "run-lvs-cancel")
        #expect(ledger.cancellationRequest?.requestedBy == "native-lvs")
        #expect(ledger.progressEvents.contains { $0.kind == .cancellationObserved })
    }

    @Test func lvsExecutorPreservesStandardInputRequestAndIndexesManifest() async throws {
        let root = try makeTemporaryRoot("lvs-standard-input")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let technologyURL = try writeText("{}", name: "tech.json", root: root)
        let terminalEquivalenceURL = try writeText(
            """
            {
              "schemaVersion" : 1,
              "rules" : []
            }
            """,
            name: "terminal-equivalence.json",
            root: root
        )

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run standard LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        technologyURL: technologyURL,
                        terminalEquivalenceURL: terminalEquivalenceURL,
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: StandardLVSStubEngine(
                        expectedTechnologyURL: technologyURL,
                        expectedTerminalEquivalenceURL: terminalEquivalenceURL
                    )
                ),
            ]
        )

        let artifacts = result.stages[0].artifacts
        #expect(result.status == .succeeded)
        #expect(artifacts.contains { $0.path.contains("lvs-report") })
        #expect(artifacts.contains { $0.path.contains("lvs-artifact-manifest") })
        #expect(artifacts.contains { $0.artifactID == "lvs-summary" })
        #expect(result.stages[0].gates.contains { $0.gateID == "lvs-artifacts" && $0.status == .passed })
        #expect(result.stages[0].gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(artifacts.contains { $0.path.contains("lvs.log") })
        #expect(artifacts.allSatisfy { !$0.path.hasPrefix("/") })
    }

    @Test func lvsExecutorFailsManifestGateWhenOutputIsNotIndexed() async throws {
        let root = try makeTemporaryRoot("lvs-manifest-coverage")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: UnindexedManifestOutputLVSStubEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "lvs-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_OUTPUT_NOT_INDEXED" })
    }

    @Test func lvsExecutorFailsManifestGateWhenFlowArtifactsDuplicatePath() async throws {
        let root = try makeTemporaryRoot("lvs-manifest-duplicate-path")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: DuplicateArtifactPathLVSStubEngine()
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "lvs-artifacts" && $0.status == .failed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_DUPLICATE_FLOW_ARTIFACT_PATH" })
    }

    @Test func lvsExecutorFailsArtifactIntegrityGateWhenArtifactEscapesProject() async throws {
        let root = try makeTemporaryRoot("lvs-artifact-integrity")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let externalRoot = try makeTemporaryRoot("lvs-artifact-integrity-external")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let externalManifestURL = externalRoot.appending(path: "lvs-artifact-manifest.json")

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: EscapingArtifactLVSStubEngine(externalManifestURL: externalManifestURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "lvs" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "LVS_ARTIFACT_OUTPUT_OUTSIDE_PROJECT" })
        #expect(!stage.gates.contains { $0.gateID == "lvs-artifacts" })
        #expect(!stage.gates.contains { $0.gateID == "artifact-integrity" })
        #expect(!stage.diagnostics.contains { $0.code == "ARTIFACT_MANIFEST_UNREADABLE" })
    }

    @Test func lvsExecutorRejectsExternalManifestBeforeWritingSummaryArtifacts() async throws {
        let root = try makeTemporaryRoot("lvs-external-manifest")
        defer { removeTemporaryRoot(root) }
        let services = try await makeFlowServices(root: root)
        let externalRoot = try makeTemporaryRoot("lvs-external-manifest-target")
        defer { removeTemporaryRoot(externalRoot) }

        let layoutURL = try writeText("layout", name: "layout.gds", root: root)
        let schematicURL = try writeNetlist(matchingNetlist(), name: "schematic.spice", root: root)
        let externalManifestURL = externalRoot.appending(path: "lvs-artifact-manifest.json")

        let result = try await services.orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: services.workspaceID,
                runID: "run-lvs",
                intent: "Run LVS",
                stages: [
                    FlowStageDefinition(stageID: "008-lvs", displayName: "LVS"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                LVSFlowStageExecutor(
                    stageID: "008-lvs",
                    toolID: "native-lvs",
                    request: LVSRequest(
                        layoutGDSURL: layoutURL,
                        layoutFormat: .gds,
                        schematicNetlistURL: schematicURL,
                        topCell: "TOP",
                        backendSelection: LVSBackendSelection(backendID: "native-gds")
                    ),
                    engine: ExternalManifestLVSStubEngine(externalManifestURL: externalManifestURL)
                ),
            ]
        )

        let stage = result.stages[0]
        #expect(result.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "lvs" && $0.status == .failed })
        #expect(stage.diagnostics.contains { $0.code == "LVS_ARTIFACT_OUTPUT_OUTSIDE_PROJECT" })
        #expect(!FileManager.default.fileExists(atPath: externalRoot.appending(path: "lvs-summary.json").path(percentEncoded: false)))
    }

    private struct FlowServices {
        let store: XcircuiteWorkspaceStore
        let workspaceID: FlowWorkspaceID
        let orchestrator: DefaultFlowOrchestrator
        let reviewBundler: DefaultFlowRunReviewBundler
        let cancellationRecorder: DefaultFlowRunCancellationRecorder
    }

    private func makeFlowServices(root: URL) async throws -> FlowServices {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        let workspaceID = try FlowWorkspaceID(rawValue: manifest.identity.projectID)
        let progressStore = FlowRunProgressStore(persistence: store)
        let orchestrator = DefaultFlowOrchestrator(
            infrastructure: store,
            ledgerPersistence: store,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "XcircuiteTests",
                version: "1.0.0"
            ),
            progressStore: progressStore
        )
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: store,
            persistence: store
        )
        return FlowServices(
            store: store,
            workspaceID: workspaceID,
            orchestrator: orchestrator,
            reviewBundler: reviewBundler,
            cancellationRecorder: DefaultFlowRunCancellationRecorder(progressStore: progressStore)
        )
    }

    private func matchingNetlist() -> String {
        """
        .subckt TOP in out vdd vss
        M1 out in vdd vdd pmos
        M2 out in vss vss nmos
        .ends TOP
        """
    }

    private func writeLayout(_ layout: NativeDRCLayout, root: URL) throws -> URL {
        let url = root.appending(path: "layout.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func writeNetlist(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func decodeDRCSummary(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> DRCRunSummaryReport {
        try JSONDecoder().decode(
            DRCRunSummaryReport.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func decodeDRCRepairHints(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> DRCRepairHintReport {
        try JSONDecoder().decode(
            DRCRepairHintReport.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func decodeLVSSummary(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> LVSRunSummaryReport {
        try JSONDecoder().decode(
            LVSRunSummaryReport.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
    }

    private func decodeLVSDevicePolicyReport(
        _ reference: ArtifactReference,
        root: URL
    ) throws -> LVSDevicePolicyApplicationReport {
        try JSONDecoder().decode(
            LVSDevicePolicyApplicationReport.self,
            from: Data(contentsOf: root.appending(path: reference.path))
        )
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

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffFlowStageExecutorTests-\(name)-\(UUID().uuidString)")
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

    private func directoryContainsReport(_ directory: URL) -> Bool {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            return contents.contains { $0.lastPathComponent.contains("drc-report") }
        } catch {
            Issue.record("Failed to inspect temporary root: \(error)")
            return false
        }
    }

    private struct StandardDRCStubEngine: DRCEngine.DRCExecuting {
        let expectedTechnologyURL: URL

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            guard request.layoutFormat == .oasis else {
                throw DRCError.invalidInput("Expected OASIS layout format")
            }
            guard request.technologyURL?.standardizedFileURL == expectedTechnologyURL.standardizedFileURL else {
                throw DRCError.invalidInput("Expected technology URL to be preserved")
            }
            guard request.backendSelection.backendID == "native-gds" else {
                throw DRCError.invalidInput("Expected native-gds backend selection")
            }
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "drc-report.json")
            let manifestURL = workingDirectory.appending(path: "drc-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            try writeManifest(
                reportURL: reportURL,
                manifestURL: manifestURL,
                logURL: logURL,
                extraOutputs: []
            )
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "StandardDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }

        private func writeManifest(
            reportURL: URL,
            manifestURL: URL,
            logURL: URL,
            extraOutputs: [DRCArtifactRecord]
        ) throws {
            var outputs = [
                DRCArtifactRecord(
                    id: "report",
                    kind: .report,
                    path: reportURL.lastPathComponent,
                    byteCount: nil,
                    sha256: nil
                ),
                DRCArtifactRecord(
                    id: "log",
                    kind: .log,
                    path: logURL.lastPathComponent,
                    byteCount: nil,
                    sha256: nil
                ),
                DRCArtifactRecord(
                    id: "manifest",
                    kind: .manifest,
                    path: manifestURL.lastPathComponent,
                    byteCount: nil,
                    sha256: nil
                ),
            ]
            outputs.append(contentsOf: extraOutputs)
            let manifest = DRCArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "StandardDRCStub",
                passed: true,
                completed: true,
                inputs: [],
                outputs: outputs,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        }
    }

    private struct CancellingDRCStubEngine: DRCEngine.DRCExecuting {
        let cancellationRecorder: DefaultFlowRunCancellationRecorder
        let workspaceID: FlowWorkspaceID
        let runID: String

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            _ = try await cancellationRecorder.requestCancellation(
                workspaceID: workspaceID,
                runID: runID,
                requestedBy: "native-drc",
                reason: "cooperative DRC cancellation checkpoint"
            )
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "drc-report.json")
            let manifestURL = workingDirectory.appending(path: "drc-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let manifest = DRCArtifactManifest(
                generatedAt: "2026-06-23T00:00:00Z",
                backendID: "native-gds",
                toolName: "CancellingDRCStub",
                passed: true,
                completed: true,
                inputs: [],
                outputs: [
                    DRCArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "CancellingDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct UnindexedManifestOutputDRCStubEngine: DRCEngine.DRCExecuting {
        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "drc-report.json")
            let manifestURL = workingDirectory.appending(path: "drc-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            let extraURL = workingDirectory.appending(path: "extra-report.json")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            try "extra".write(to: extraURL, atomically: true, encoding: .utf8)
            let manifest = DRCArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "UnindexedManifestOutputDRCStub",
                passed: true,
                completed: true,
                inputs: [],
                outputs: [
                    DRCArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "extra-report",
                        kind: .report,
                        path: extraURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "UnindexedManifestOutputDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct DuplicateArtifactPathDRCStubEngine: DRCEngine.DRCExecuting {
        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let manifestURL = workingDirectory.appending(path: "drc-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let manifest = DRCArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "DuplicateArtifactPathDRCStub",
                passed: true,
                completed: true,
                inputs: [],
                outputs: [
                    DRCArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    DRCArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "DuplicateArtifactPathDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: manifestURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct EscapingArtifactDRCStubEngine: DRCEngine.DRCExecuting {
        let externalManifestURL: URL

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "drc-report.json")
            let manifestURL = workingDirectory.appending(path: "drc-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "external-manifest".write(to: externalManifestURL, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: manifestURL,
                withDestinationURL: externalManifestURL
            )
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "EscapingArtifactDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct ExternalManifestDRCStubEngine: DRCEngine.DRCExecuting {
        let externalManifestURL: URL

        func run(_ request: DRCRequest) async throws -> DRCExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "drc-report.json")
            let logURL = workingDirectory.appending(path: "drc.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            try "{}".write(to: externalManifestURL, atomically: true, encoding: .utf8)
            return DRCExecutionResult(
                request: request,
                result: DRCResult(
                    backendID: "native-gds",
                    toolName: "ExternalManifestDRCStub",
                    success: true,
                    completed: true,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: externalManifestURL
            )
        }
    }

    private struct StandardLVSStubEngine: LVSEngine.LVSExecuting {
        let expectedTechnologyURL: URL
        let expectedTerminalEquivalenceURL: URL?

        init(
            expectedTechnologyURL: URL,
            expectedTerminalEquivalenceURL: URL? = nil
        ) {
            self.expectedTechnologyURL = expectedTechnologyURL
            self.expectedTerminalEquivalenceURL = expectedTerminalEquivalenceURL
        }

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            guard request.layoutGDSURL != nil else {
                throw LVSError.invalidInput("Expected layout GDS URL")
            }
            guard request.layoutFormat == .gds else {
                throw LVSError.invalidInput("Expected GDS layout format")
            }
            guard request.technologyURL?.standardizedFileURL == expectedTechnologyURL.standardizedFileURL else {
                throw LVSError.invalidInput("Expected technology URL to be preserved")
            }
            if let expectedTerminalEquivalenceURL {
                guard request.terminalEquivalenceURL?.standardizedFileURL == expectedTerminalEquivalenceURL.standardizedFileURL else {
                    throw LVSError.invalidInput("Expected terminal equivalence URL to be preserved")
                }
            }
            guard request.backendSelection.backendID == "native-gds" else {
                throw LVSError.invalidInput("Expected native-gds backend selection")
            }
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            let correspondenceURL = workingDirectory.appending(path: "lvs-correspondence.json")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let correspondenceJSON = """
            {
              "schemaVersion": 2,
              "deviceMappings": [],
              "netMappings": [],
              "portMappings": [],
              "unmatchedLayoutObjectIDs": [],
              "unmatchedSchematicObjectIDs": [],
              "ambiguousLayoutObjectIDs": [],
              "layoutSourceReferences": []
            }
            """
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try correspondenceJSON.write(to: correspondenceURL, atomically: true, encoding: .utf8)
            let hasher = SHA256ContentDigester()
            let manifest = LVSArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "StandardLVSStub",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                blockingReasons: [],
                inputs: [],
                outputs: [
                    LVSArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: try Data(contentsOf: reportURL).count,
                        sha256: try hasher.digest(fileAt: reportURL).hexadecimalValue
                    ),
                    LVSArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "lvs-correspondence",
                        kind: .correspondence,
                        path: correspondenceURL.lastPathComponent,
                        byteCount: try Data(contentsOf: correspondenceURL).count,
                        sha256: try hasher.digest(fileAt: correspondenceURL).hexadecimalValue
                    ),
                    LVSArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "StandardLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL,
                correspondenceURL: correspondenceURL
            )
        }
    }

    private struct DevicePolicyReportLVSStubEngine: LVSEngine.LVSExecuting {
        let devicePolicyReport: LVSDevicePolicyApplicationReport

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            let correspondenceURL = workingDirectory.appending(path: "lvs-correspondence.json")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let correspondenceJSON = """
            {
              "schemaVersion": 2,
              "deviceMappings": [],
              "netMappings": [],
              "portMappings": [],
              "unmatchedLayoutObjectIDs": [],
              "unmatchedSchematicObjectIDs": [],
              "ambiguousLayoutObjectIDs": [],
              "layoutSourceReferences": []
            }
            """
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try correspondenceJSON.write(to: correspondenceURL, atomically: true, encoding: .utf8)
            let hasher = SHA256ContentDigester()
            let manifest = LVSArtifactManifest(
                generatedAt: "2026-06-29T00:00:00Z",
                backendID: "native",
                toolName: "DevicePolicyReportLVSStub",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                blockingReasons: [],
                inputs: [],
                outputs: [
                    LVSArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: try Data(contentsOf: reportURL).count,
                        sha256: try hasher.digest(fileAt: reportURL).hexadecimalValue
                    ),
                    LVSArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "lvs-correspondence",
                        kind: .correspondence,
                        path: correspondenceURL.lastPathComponent,
                        byteCount: try Data(contentsOf: correspondenceURL).count,
                        sha256: try hasher.digest(fileAt: correspondenceURL).hexadecimalValue
                    ),
                    LVSArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0),
                devicePolicyReport: devicePolicyReport
            )
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native",
                    toolName: "DevicePolicyReportLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                devicePolicyReport: devicePolicyReport,
                reportURL: reportURL,
                artifactManifestURL: manifestURL,
                correspondenceURL: correspondenceURL
            )
        }
    }

    private struct CancellingLVSStubEngine: LVSEngine.LVSExecuting {
        let cancellationRecorder: DefaultFlowRunCancellationRecorder
        let workspaceID: FlowWorkspaceID
        let runID: String

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            _ = try await cancellationRecorder.requestCancellation(
                workspaceID: workspaceID,
                runID: runID,
                requestedBy: "native-lvs",
                reason: "cooperative LVS cancellation checkpoint"
            )
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let manifest = LVSArtifactManifest(
                generatedAt: "2026-06-23T00:00:00Z",
                backendID: "native-gds",
                toolName: "CancellingLVSStub",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                blockingReasons: [],
                inputs: [],
                outputs: [
                    LVSArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "CancellingLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct FlakyLVSStubEngine: LVSEngine.LVSExecuting {
        let state: FlakyLVSStubEngineState

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            try await state.run(request)
        }
    }

    private actor FlakyLVSStubEngineState {
        private var runCount = 0

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            runCount += 1
            if runCount == 1 {
                throw LVSError.backendUnavailable("Transient native LVS startup failure.")
            }
            return try await DefaultLVSEngine(backend: nil, layoutNetlistExtractor: nil).run(request)
        }

        func executionCount() -> Int {
            runCount
        }
    }

    private struct UnindexedManifestOutputLVSStubEngine: LVSEngine.LVSExecuting {
        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            let extraURL = workingDirectory.appending(path: "extra-lvs-report.json")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            try "extra".write(to: extraURL, atomically: true, encoding: .utf8)
            let manifest = LVSArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "UnindexedManifestOutputLVSStub",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                blockingReasons: [],
                inputs: [],
                outputs: [
                    LVSArtifactRecord(
                        id: "report",
                        kind: .report,
                        path: reportURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "extra-report",
                        kind: .report,
                        path: extraURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "UnindexedManifestOutputLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct DuplicateArtifactPathLVSStubEngine: LVSEngine.LVSExecuting {
        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            let manifest = LVSArtifactManifest(
                generatedAt: "2026-06-19T00:00:00Z",
                backendID: "native-gds",
                toolName: "DuplicateArtifactPathLVSStub",
                executionStatus: .completed,
                verdict: .match,
                readiness: .ready,
                blockingReasons: [],
                inputs: [],
                outputs: [
                    LVSArtifactRecord(
                        id: "manifest",
                        kind: .manifest,
                        path: manifestURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                    LVSArtifactRecord(
                        id: "log",
                        kind: .log,
                        path: logURL.lastPathComponent,
                        byteCount: nil,
                        sha256: nil
                    ),
                ],
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 0)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "DuplicateArtifactPathLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: manifestURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct EscapingArtifactLVSStubEngine: LVSEngine.LVSExecuting {
        let externalManifestURL: URL

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let manifestURL = workingDirectory.appending(path: "lvs-artifact-manifest.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "external-manifest".write(to: externalManifestURL, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: manifestURL,
                withDestinationURL: externalManifestURL
            )
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "EscapingArtifactLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: manifestURL
            )
        }
    }

    private struct ExternalManifestLVSStubEngine: LVSEngine.LVSExecuting {
        let externalManifestURL: URL

        func run(_ request: LVSRequest) async throws -> LVSExecutionResult {
            let workingDirectory = try #require(request.workingDirectory)
            let reportURL = workingDirectory.appending(path: "lvs-report.json")
            let logURL = workingDirectory.appending(path: "lvs.log")
            try "report".write(to: reportURL, atomically: true, encoding: .utf8)
            try "log".write(to: logURL, atomically: true, encoding: .utf8)
            try "{}".write(to: externalManifestURL, atomically: true, encoding: .utf8)
            return LVSExecutionResult(
                request: request,
                result: LVSResult(
                    backendID: "native-gds",
                    toolName: "ExternalManifestLVSStub",
                    executionStatus: .completed,
                    verdict: .match,
                    readiness: .ready,
                    logPath: logURL.path(percentEncoded: false)
                ),
                reportURL: reportURL,
                artifactManifestURL: externalManifestURL
            )
        }
    }
}
