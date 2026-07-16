import DesignFlowKernel
import DRCEngine
import Foundation
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite flow runtime")
struct XcircuiteFlowRuntimeTests {}

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeRunsInjectedExecutorThroughDesignFlowKernel() async throws {
        let root = try makeTemporaryRoot("runtime-run")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()]
        )

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        #expect(result.stages.first?.gates.contains {
            $0.gateID == "drc" && $0.status == .passed
        } == true)
    }

    @Test func runtimeFeedsSimulationWaveformArtifactsIntoPostLayoutComparisonStage() async throws {
        let root = try makeTemporaryRoot("runtime-post-layout-artifact-input")
        defer { removeTemporaryRoot(root) }
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                WaveformArtifactExecutor(
                    stageID: "010-pre-sim",
                    artifactID: "pre-layout-waveform",
                    fileName: "waveform.csv",
                    csv: """
                    time,V(out)
                    0,0
                    1e-9,1
                    2e-9,0
                    3e-9,1
                    """
                ),
                WaveformArtifactExecutor(
                    stageID: "020-post-sim",
                    artifactID: "post-layout-waveform",
                    fileName: "waveform.csv",
                    csv: """
                    time,V(out),V(out_pex)
                    0,0,0
                    1e-9,0.99,0.98
                    2e-9,0.01,0.02
                    3e-9,1.0,0.99
                    """
                ),
                PostLayoutComparisonFlowStageExecutor(
                    stageID: "030-compare",
                    preLayoutWaveformInput: .stageArtifact(
                        XcircuiteFlowInputReference.StageArtifact(
                            stageID: "010-pre-sim",
                            artifactID: "pre-layout-waveform",
                            kind: .waveform,
                            format: .csv
                        )
                    ),
                    postLayoutWaveformInput: .stageArtifact(
                        XcircuiteFlowInputReference.StageArtifact(
                            stageID: "020-post-sim",
                            artifactID: "post-layout-waveform",
                            kind: .waveform,
                            format: .csv
                        )
                    ),
                    options: PostLayoutComparisonOptions(
                        maxAbsoluteDelta: 0.05,
                        requiredPostVariables: ["V(out_pex)"]
                    )
                ),
            ],
            descriptors: [SignoffToolDescriptors.postLayoutComparison()],
            qualificationLevels: ["post-layout-comparison": .smokeChecked]
        )

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-post-layout-artifact-input",
                intent: "Compare stage-produced pre/post layout waveforms",
                stages: [
                    FlowStageDefinition(stageID: "010-pre-sim", displayName: "Pre-layout simulation"),
                    FlowStageDefinition(stageID: "020-post-sim", displayName: "Post-layout simulation"),
                    FlowStageDefinition(
                        stageID: "030-compare",
                        displayName: "Post-layout comparison",
                        requiredTool: comparisonRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        let comparisonStage = try #require(result.stages.first { $0.stageID == "030-compare" })
        #expect(comparisonStage.status == .succeeded)
        #expect(comparisonStage.gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(comparisonStage.gates.contains { $0.gateID == "comparison" && $0.status == .passed })
        #expect(comparisonStage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        let reportArtifact = try #require(comparisonStage.artifacts.first {
            $0.artifactID == "post-layout-comparison" && $0.kind == .report && $0.format == .json
        })
        #expect(reportArtifact.digest.hexadecimalValue.isEmpty == false)
        #expect(reportArtifact.byteCount > 0)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let report = try await store.readJSON(
            PostLayoutComparisonReport.self,
            from: reportArtifact.path
        )
        #expect(report.gateStatus == "passed")
        #expect(report.requiredPostVariables.contains { $0.variableName == "V(out_pex)" && $0.present })
    }

    @Test func runtimeRetriesTransientDRCExecutorFailureAndPersistsAttempts() async throws {
        let root = try makeTemporaryRoot("runtime-drc-retry")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let engineState = FlakyDRCEngineState()
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        backendSelection: DRCBackendSelection(backendID: "native")
                    ),
                    engine: FlakyDRCEngine(state: engineState)
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()]
        )

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-drc-retry",
                intent: "Retry transient DRC executor failure",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["DRC_EXECUTION_ERROR"]
                        )
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        #expect(await engineState.executionCount() == 2)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .succeeded)
        #expect(stage.attempts.count == 2)
        #expect(stage.attempts[0].diagnosticCodes.contains("DRC_EXECUTION_ERROR"))
        #expect(stage.attempts[0].retryDecision.shouldRetry)
        #expect(stage.attempts[0].retryDecision.reason == .retryableDiagnosticMatched)
        #expect(stage.attempts[1].retryDecision.shouldRetry == false)
        #expect(stage.attempts[1].retryDecision.reason == .stageDidNotFail)
        #expect(stage.artifacts.contains { $0.artifactID == "007-drc-attempts" })

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let attempts = try await store.readJSON(
            [FlowStageAttemptRecord].self,
            from: ".xcircuite/runs/run-drc-retry/stages/007-drc/attempts.json"
        )
        #expect(attempts.map(\.attemptIndex) == [1, 2])
        #expect(attempts[0].retryDecision.matchedDiagnosticCodes == ["DRC_EXECUTION_ERROR"])

        let ledger = try await store.loadRunLedger(runID: "run-drc-retry")
        #expect(ledger.progressEvents.map(\.kind).contains(.stageRetryScheduled))
        let summary = DefaultFlowRunLedgerSummarizer().summarize(ledger)
        #expect(summary.stages.first?.attemptCount == 2)
        #expect(summary.stages.first?.retryCount == 1)
        #expect(summary.nextActions.contains { $0.kind == "reviewRetryAttempts" })

        let manifest = ledger.runManifest
        #expect(manifest.artifacts.contains {
            $0.artifactID == "007-drc-attempts"
                && $0.path == ".xcircuite/runs/run-drc-retry/stages/007-drc/attempts.json"
        })

        let bundle = try await DefaultFlowRunReviewBundler(
            loader: store,
            persistence: store
        ).makeReviewBundle(
            runID: "run-drc-retry",
            workspaceID: try await workspaceID(projectRoot: root)
        )
        #expect(bundle.artifacts.first(where: { $0.purpose == .stageAttempts }) != nil)
    }

    @Test func runtimePersistsPlanningActionDomainSnapshot() async throws {
        let root = try makeTemporaryRoot("runtime-action-domain")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()]
        )

        _ = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Run DRC and persist planning capabilities",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let snapshotPath = ".xcircuite/runs/run-1/planning/action-domain-snapshot.json"
        let snapshot = try await store.readJSON(
            XcircuitePlanningActionDomainSnapshot.self,
            from: snapshotPath
        )
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.runID == "run-1")
        #expect(Set(snapshot.domains.map(\.domainID)) == Set([
            "drc-signoff",
            "layout-edit",
            "lvs-signoff",
            "pex-extraction",
            "simulation-analysis",
        ]))
        #expect(snapshot.domains.allSatisfy { $0.schemaVersion == 1 })
        #expect(snapshot.domains.allSatisfy { !$0.ownerPackages.isEmpty })
        #expect(snapshot.domains.allSatisfy { !$0.operations.isEmpty })

        for domain in snapshot.domains {
            let operationIDs = domain.operations.map(\.operationID)
            #expect(operationIDs.count == Set(operationIDs).count, "\(domain.domainID) must not duplicate operation IDs")
            for operation in domain.operations {
                #expect(!operation.maturity.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose maturity")
                #expect(!operation.inputRefs.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose input refs")
                #expect(!operation.preconditions.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose preconditions")
                #expect(!operation.effects.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose effects")
                #expect(!operation.producedArtifacts.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose produced artifacts")
                #expect(!operation.verificationGates.isEmpty, "\(domain.domainID)/\(operation.operationID) must expose verification gates")
                #expect(operation.inputRefs.count == Set(operation.inputRefs).count)
                #expect(operation.preconditions.count == Set(operation.preconditions).count)
                #expect(operation.effects.count == Set(operation.effects).count)
                #expect(operation.producedArtifacts.count == Set(operation.producedArtifacts).count)
                #expect(operation.verificationGates.count == Set(operation.verificationGates).count)
            }
        }

        let operationsByDomain = Dictionary(
            uniqueKeysWithValues: snapshot.domains.map { domain in
                (domain.domainID, Set(domain.operations.map(\.operationID)))
            }
        )
        #expect(operationsByDomain["layout-edit"]?.isSuperset(of: [
            "layout-command-replay",
            "layout.add-rect",
            "layout.add-via",
            "layout.flatten-instance",
        ]) == true)
        #expect(operationsByDomain["drc-signoff"]?.isSuperset(of: [
            "drc.run-native",
            "drc.export-repair-hints",
        ]) == true)
        #expect(operationsByDomain["lvs-signoff"]?.isSuperset(of: [
            "lvs.run-native",
            "lvs.export-repair-hints",
        ]) == true)
        #expect(snapshot.domains.flatMap(\.operations).contains {
            $0.operationID.contains("export-tool-evidence")
        } == false)
        #expect(operationsByDomain["pex-extraction"]?.isSuperset(of: [
            "pex.extract",
            "pex.summarize-run",
            "pex.metric-recovery-objective",
        ]) == true)
        let pexDomain = try #require(snapshot.domains.first { $0.domainID == "pex-extraction" })
        #expect(pexDomain.ownerPackages.contains("PEXEngine"))
        #expect(pexDomain.ownerPackages.contains("Xcircuite"))
        let pexRecovery = try #require(pexDomain.operations.first {
            $0.operationID == "pex.metric-recovery-objective"
        })
        #expect(pexRecovery.maturity == "implemented")
        #expect(pexRecovery.producedArtifacts.contains("planning-problem"))
        #expect(operationsByDomain["simulation-analysis"]?.isSuperset(of: [
            "simulation.import-spice",
            "simulation.load-netlist",
            "simulation.run-analysis",
            "simulation.run-tran",
            "simulation.export-metric-report",
            "simulation.summarize-run",
            "simulation.metric-improvement-objective",
            "simulation.compare-post-layout",
            "simulation.set-netlist-parameters",
        ]) == true)
        let simulationDomain = try #require(snapshot.domains.first { $0.domainID == "simulation-analysis" })
        let metricImprovement = try #require(simulationDomain.operations.first {
            $0.operationID == "simulation.metric-improvement-objective"
        })
        #expect(metricImprovement.maturity == "implemented")
        #expect(metricImprovement.producedArtifacts.contains("parameter-candidates"))
        #expect(metricImprovement.producedArtifacts.contains("numeric-repair-loop"))

        let manifest = try await store.loadRunLedger(runID: "run-1").runManifest
        let planningArtifact = try #require(manifest.artifacts.first {
            $0.artifactID == XcircuitePlanningArtifactStore.actionDomainArtifactID
        })
        #expect(planningArtifact.path == snapshotPath)
        #expect(planningArtifact.kind == .other)
        #expect(planningArtifact.format == .json)
        #expect(planningArtifact.digest.hexadecimalValue.isEmpty == false)
        #expect(planningArtifact.byteCount > 0)

        let bundle = try await DefaultFlowRunReviewBundler(
            loader: store,
            persistence: store
        ).makeReviewBundle(
            runID: "run-1",
            workspaceID: try await workspaceID(projectRoot: root)
        )
        #expect(bundle.artifacts.first(where: {
            $0.purpose == .planningActionDomain
                && $0.reference.path == snapshotPath
                && $0.integrity?.status == .verified
        }) != nil)
    }

    @Test func runtimeResumesPersistedPlanAfterApproval() async throws {
        let root = try makeTemporaryRoot("runtime-resume")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let toolchainProfile = XcircuiteFlowToolchainProfile(
            profileID: "resume-profile",
            pdkID: "test-pdk",
            technologyCatalogID: "test-catalog",
            metadata: [
                "source": "resume-test",
            ]
        )
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()],
            toolchainProfile: toolchainProfile
        )

        let initial = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Run DRC with approval",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        requiresApproval: true
                    ),
                ]
            )
        )
        #expect(initial.status == .blocked)

        let reviewBundler = DefaultFlowRunReviewBundler(loader: store, persistence: store)
        let inspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)
        _ = try await DefaultFlowGateApprovalRecorder(
            loader: store,
            inspector: inspector,
            ledgerPersistence: store
        ).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                stageID: "007-drc",
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )

        let resumed = try await runtime.resume(
            request: FlowRunResumeRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1"
            )
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.summary.status == .succeeded)
        #expect(resumed.summary.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .passed
        } == true)
        #expect(resumed.summary.toolchain?.profileID == "resume-profile")
        #expect(resumed.summary.toolchain?.profileArtifactPath == ".xcircuite/runs/run-1/toolchain-profile.json")
        #expect(resumed.summary.nextActions.map(\.kind) == ["archiveOrContinue"])

        let persistedProfile = try await store.readJSON(
            XcircuiteFlowToolchainProfile.self,
            from: ".xcircuite/runs/run-1/toolchain-profile.json"
        )
        #expect(persistedProfile.profileID == "resume-profile")
    }

    @Test func runtimeResumesPersistedPlanAfterWaiverWithAuditableDiagnostic() async throws {
        let root = try makeTemporaryRoot("runtime-waiver-resume")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()]
        )
        let initial = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-waiver",
                intent: "Run DRC with a reviewed waiver",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        requiresApproval: true
                    ),
                ]
            )
        )
        #expect(initial.status == .blocked)

        let reviewBundler = DefaultFlowRunReviewBundler(loader: store, persistence: store)
        let inspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)
        _ = try await DefaultFlowGateApprovalRecorder(
            loader: store,
            inspector: inspector,
            ledgerPersistence: store
        ).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-waiver",
                stageID: "007-drc",
                verdict: .waived,
                reviewer: "reviewer-1",
                note: "Reviewed exception accepted for this retained run."
            )
        )

        let resumed = try await runtime.resume(
            request: FlowRunResumeRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-waiver"
            )
        )

        #expect(resumed.result.status == .succeeded)
        let stage = try #require(resumed.result.stages.first { $0.stageID == "007-drc" })
        #expect(stage.gates.contains { $0.gateID == "approval" && $0.status == .waived })
        #expect(stage.diagnostics.contains { $0.code == "STAGE_WAIVED" })
        let persisted = try await store.loadRunLedger(runID: "run-waiver")
        #expect(persisted.approvals.contains {
            $0.stageID == "007-drc"
                && $0.verdict == .waived
                && $0.note == "Reviewed exception accepted for this retained run."
        })
    }

    @Test func runtimeResumeRejectsTamperingInAnyRetainedArtifact() async throws {
        let root = try makeTemporaryRoot("runtime-attested-resume")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let runtime = try await makeQualifiedRuntime(
            projectRoot: root,
            executors: [
                DRCFlowStageExecutor.native(
                    stageID: "007-drc",
                    layoutURL: layoutURL,
                    topCell: "TOP"
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC()]
        )
        _ = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-tampered",
                intent: "Retain and attest every resume artifact",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        requiresApproval: true
                    ),
                ]
            )
        )
        let reviewBundler = DefaultFlowRunReviewBundler(loader: store, persistence: store)
        let inspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)
        _ = try await DefaultFlowGateApprovalRecorder(
            loader: store,
            inspector: inspector,
            ledgerPersistence: store
        ).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-tampered",
                stageID: "007-drc",
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )
        let ledger = try await store.loadRunLedger(runID: "run-tampered")
        let retained = try #require(ledger.artifacts.first {
            $0.id.rawValue == "action-ledger"
        })
        try Data("tampered".utf8).write(
            to: root.appending(path: retained.path),
            options: .atomic
        )

        do {
            _ = try await runtime.resume(
                request: FlowRunResumeRequest(
                    workspaceID: try await workspaceID(projectRoot: root),
                    runID: "run-tampered"
                )
            )
            Issue.record("Expected retained artifact attestation failure.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, _) = error else {
                Issue.record("Unexpected ledger error: \(error.localizedDescription)")
                return
            }
            #expect(path == retained.path)
        }
    }

    @Test func runtimeSpecBuildsRuntimeForDRCExecutor() async throws {
        let root = try makeTemporaryRoot("runtime-spec")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout.json",
                        topCell: "TOP",
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked)
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Run DRC",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
    }

    @Test func runtimeSpecBuildsRuntimeForLayoutCommandExecutor() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        tool: QualifiedToolFixtures.toolSpec(
                            level: .smokeChecked,
                            toolID: "layout-command"
                        )
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Apply layout commands",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        let stage = try #require(result.stages.first)
        #expect(stage.gates.contains { $0.gateID == "layout-command" && $0.status == .passed })
        #expect(stage.artifacts.contains { $0.kind == .layout && $0.format == .json })
        #expect(stage.artifacts.contains { $0.kind == .report && $0.format == .json })
        #expect(stage.artifacts.contains { $0.kind == .other && $0.format == .json })

        let layoutArtifact = try #require(stage.artifacts.first { $0.kind == .layout })
        let layoutDigest = layoutArtifact.digest.hexadecimalValue
        #expect(!layoutDigest.isEmpty)
        let layoutURL = root.appending(path: layoutArtifact.path)
        let layoutData = try Data(contentsOf: layoutURL)
        let layoutObject = try #require(JSONSerialization.jsonObject(with: layoutData) as? [String: Any])
        let cells = try #require(layoutObject["cells"] as? [[String: Any]])
        #expect(cells.count == 1)
        let shapes = try #require(cells.first?["shapes"] as? [[String: Any]])
        #expect(shapes.count == 1)

        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let ledger = try await store.loadRunLedger(runID: "run-1")
        let toolchain = try #require(ledger.toolchain)
        let record = try #require(toolchain.stages.first)
        #expect(record.selectedToolID == "layout-command")
        #expect(record.selectedDecision?.status == .eligible)
    }

    private func makeQualifiedRuntime(
        projectRoot: URL,
        executors: [any FlowStageExecutor],
        descriptors: [ToolDescriptor],
        qualificationLevels: [String: ToolQualificationLevel] = [:],
        toolchainProfile: XcircuiteFlowToolchainProfile? = nil
    ) async throws -> XcircuiteFlowRuntime {
        try await QualifiedToolFixtures.runtime(
            executors: executors,
            descriptors: descriptors,
            projectRoot: projectRoot,
            qualificationLevels: qualificationLevels,
            toolchainProfile: toolchainProfile
        )
    }

    private func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

}
