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
import XcircuitePackage

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeProgressFollowStreamsLayoutDRCLVSPEXStages() async throws {
        let root = try makeTemporaryRoot("runtime-progress-signoff-follow")
        defer { removeTemporaryRoot(root) }
        try writeLayoutCommandRequest(root: root)
        try writeStandardLayoutTechnology(root: root)
        _ = try writeNetlist(
            """
            .subckt top
            .ends top
            """,
            name: "circuits/top.spice",
            root: root
        )
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            rules: [
                                NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 0.5),
                            ]
                        ),
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "drc-layout",
                                kind: .layout,
                                format: .json
                            )
                        ),
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        schematicNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        technologyPath: "tech/process.json",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        tool: mockPEXContractToolSpec()
                    )
                ),
            ]
        )
        let runtime = try spec.makeRuntime(projectRoot: root)
        let sink = ProgressEventSink()

        async let followSnapshot = DefaultFlowRunProgressSubscriber().followProgress(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-signoff-follow",
                timeoutMilliseconds: 2_000,
                pollIntervalMilliseconds: 10
            )
        ) { event in
            await sink.append(event)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-signoff-follow",
                intent: "Follow runtime progress while layout, DRC, LVS, and PEX stages execute",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: lvsRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: mockPEXContractRequirement()
                    ),
                ]
            )
        )
        let snapshot = try await followSnapshot
        let events = await sink.events()

        #expect(result.status == .succeeded)
        #expect(result.stages.map(\.stageID) == ["006-layout", "007-drc", "008-lvs", "009-pex"])
        #expect(events.map(\.kind) == [
            .runStarted,
            .stageStarted,
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .runFinished,
        ])
        #expect(events.compactMap(\.stageID) == [
            "006-layout",
            "006-layout",
            "007-drc",
            "007-drc",
            "008-lvs",
            "008-lvs",
            "009-pex",
            "009-pex",
        ])
        #expect(events.map(\.sequence) == Array(1...10))
        #expect(snapshot.latestSequence == 10)
        #expect(snapshot.terminalStatus == .succeeded)
        #expect(snapshot.isTerminal)

        let recovered = try DefaultFlowRunProgressSubscriber().snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-signoff-follow",
                afterSequence: 4
            )
        )
        #expect(recovered.events.map(\.kind) == [
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .stageStarted,
            .stageFinished,
            .runFinished,
        ])
        #expect(recovered.events.first?.stageID == "007-drc")
        #expect(recovered.terminalStatus == .succeeded)

        let ledger = try FlowRunLedgerLoader().loadRunLedger(
            runID: "run-progress-signoff-follow",
            projectRoot: root
        )
        #expect(ledger.progressEvents.map(\.sequence) == Array(1...10))
        let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: "run-progress-signoff-follow",
            projectRoot: root
        )
        #expect(bundle.artifacts.contains {
            $0.role == "run-progress"
                && $0.path == ".xcircuite/runs/run-progress-signoff-follow/progress.jsonl"
        })
    }

    @Test func runtimeProgressFollowStreamsNativeDRCStressStagesWithoutSequenceGaps() async throws {
        let root = try makeTemporaryRoot("runtime-progress-drc-stress")
        defer { removeTemporaryRoot(root) }
        let layoutURL = try writeLayout(cleanLayout(), root: root)
        let stageIDs = (1...32).map { "stress-drc-\($0)" }
        let executors: [any FlowStageExecutor] = stageIDs.map { stageID in
            DRCFlowStageExecutor.native(
                stageID: stageID,
                layoutURL: layoutURL,
                topCell: "TOP"
            )
        }
        let runtime = QualifiedToolFixtures.runtime(
            executors: executors,
            descriptors: [SignoffToolDescriptors.nativeDRC(level: .productionEligible)]
        )
        let sink = ProgressEventSink()

        async let followSnapshot = DefaultFlowRunProgressSubscriber().followProgress(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-drc-stress",
                timeoutMilliseconds: 20_000,
                pollIntervalMilliseconds: 10
            )
        ) { event in
            await sink.append(event)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-drc-stress",
                intent: "Stress follow runtime progress over repeated native DRC stages",
                stages: stageIDs.map { stageID in
                    FlowStageDefinition(
                        stageID: stageID,
                        displayName: "Native DRC \(stageID)",
                        requiredTool: drcRequirement()
                    )
                }
            )
        )
        let snapshot = try await followSnapshot
        let events = await sink.events()
        var expectedKinds: [FlowRunProgressEventKind] = [.runStarted]
        for _ in stageIDs {
            expectedKinds.append(.stageStarted)
            expectedKinds.append(.stageFinished)
        }
        expectedKinds.append(.runFinished)
        let expectedSequences = Array(1...expectedKinds.count)
        let expectedStageEvents = stageIDs.flatMap { [$0, $0] }

        #expect(result.status == .succeeded)
        #expect(result.stages.count == stageIDs.count)
        #expect(result.stages.allSatisfy { $0.status == .succeeded })
        #expect(result.stages.allSatisfy { stage in
            stage.gates.contains { $0.gateID == "drc" && $0.status == .passed }
        })
        #expect(events.map(\.kind) == expectedKinds)
        #expect(events.compactMap(\.stageID) == expectedStageEvents)
        #expect(events.map(\.sequence) == expectedSequences)
        #expect(snapshot.latestSequence == expectedKinds.count)
        #expect(snapshot.terminalStatus == .succeeded)
        #expect(snapshot.isTerminal)

        let tailCursor = expectedKinds.count - 5
        let recovered = try DefaultFlowRunProgressSubscriber().snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-drc-stress",
                afterSequence: tailCursor
            )
        )
        #expect(recovered.events.map(\.sequence) == Array((tailCursor + 1)...expectedKinds.count))
        #expect(recovered.events.last?.kind == .runFinished)
        #expect(recovered.terminalStatus == .succeeded)

        let ledger = try FlowRunLedgerLoader().loadRunLedger(
            runID: "run-progress-drc-stress",
            projectRoot: root
        )
        #expect(ledger.progressEvents.map(\.sequence) == expectedSequences)
        let manifest = try XcircuitePackageStore().readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-progress-drc-stress/manifest.json")
        )
        let progressArtifact = try #require(manifest.artifacts.first { $0.artifactID == "run-progress" })
        #expect(progressArtifact.path == ".xcircuite/runs/run-progress-drc-stress/progress.jsonl")
        #expect((progressArtifact.byteCount ?? 0) > 0)
    }

    @Test func runtimeProgressFollowStreamsMultiFamilyStressStagesWithoutSequenceGaps() async throws {
        let root = try makeTemporaryRoot("runtime-progress-multifamily-stress")
        defer { removeTemporaryRoot(root) }
        try writeLayoutCommandRequest(root: root)
        try writeStandardLayoutTechnology(root: root)
        _ = try writeNetlist(
            """
            .subckt top
            .ends top
            """,
            name: "circuits/top.spice",
            root: root
        )
        _ = try writeNetlist(
            """
            * rc lowpass step
            V1 1 0 1
            R1 1 2 1k
            C1 2 0 1n
            .tran 0.1u 5u
            .measure tran vfinal FIND V(2) AT=5u
            .end
            """,
            name: "circuits/rc.cir",
            root: root
        )

        var executors: [XcircuiteFlowStageExecutorSpec] = []
        var stages: [FlowStageDefinition] = []
        for cycle in 1...4 {
            let suffix = String(format: "%02d", cycle)
            let layoutStageID = "stress-\(suffix)-layout"
            let drcStageID = "stress-\(suffix)-drc"
            let lvsStageID = "stress-\(suffix)-lvs"
            let pexStageID = "stress-\(suffix)-pex"
            let simulationStageID = "stress-\(suffix)-sim"

            executors.append(.layoutCommand(
                XcircuiteFlowStageExecutorSpec.LayoutCommand(
                    stageID: layoutStageID,
                    requestPath: "layout-command-request.json",
                    drcExport: LayoutCommandDRCExportSpec(
                        technologyID: "flow-test",
                        topCell: "top",
                        rules: [
                            NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 0.5),
                        ]
                    ),
                    standardLayoutExports: [
                        LayoutCommandStandardLayoutExportSpec(
                            artifactID: "layout-gds",
                            format: .gds,
                            technologyInput: .path("tech/process.json")
                        ),
                    ],
                    tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                )
            ))
            executors.append(.nativeDRC(
                XcircuiteFlowStageExecutorSpec.NativeDRC(
                    stageID: drcStageID,
                    layoutInput: .stageArtifact(
                        XcircuiteFlowInputReference.StageArtifact(
                            stageID: layoutStageID,
                            artifactID: "drc-layout",
                            kind: .layout,
                            format: .json
                        )
                    ),
                    topCell: "top",
                    tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                )
            ))
            executors.append(.nativeLVS(
                XcircuiteFlowStageExecutorSpec.NativeLVS(
                    stageID: lvsStageID,
                    layoutGDSInput: .stageArtifact(
                        XcircuiteFlowInputReference.StageArtifact(
                            stageID: layoutStageID,
                            artifactID: "layout-gds",
                            kind: .layout,
                            format: .gdsii
                        )
                    ),
                    layoutFormat: .gds,
                    schematicNetlistPath: "circuits/top.spice",
                    topCell: "top",
                    technologyPath: "tech/process.json",
                    tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                )
            ))
            executors.append(.mockPEX(
                XcircuiteFlowStageExecutorSpec.MockPEX(
                    stageID: pexStageID,
                    layoutInput: .stageArtifact(
                        XcircuiteFlowInputReference.StageArtifact(
                            stageID: layoutStageID,
                            artifactID: "layout-gds",
                            kind: .layout,
                            format: .gdsii
                        )
                    ),
                    layoutFormat: .gds,
                    sourceNetlistPath: "circuits/top.spice",
                    topCell: "top",
                    corners: [PEXCorner(id: "tt")],
                    technology: .inline(makePEXTechnology()),
                    tool: mockPEXContractToolSpec()
                )
            ))
            executors.append(.coreSpiceSimulation(
                XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                    stageID: simulationStageID,
                    netlistPath: "circuits/rc.cir",
                    expectations: [
                        SimulationMeasurementExpectation(name: "vfinal", target: 1.0, tolerance: 0.01),
                    ],
                    tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                )
            ))

            stages.append(FlowStageDefinition(
                stageID: layoutStageID,
                displayName: "Layout command \(suffix)",
                requiredTool: layoutCommandRequirement()
            ))
            stages.append(FlowStageDefinition(
                stageID: drcStageID,
                displayName: "DRC \(suffix)",
                requiredTool: drcRequirement()
            ))
            stages.append(FlowStageDefinition(
                stageID: lvsStageID,
                displayName: "LVS \(suffix)",
                requiredTool: lvsRequirement()
            ))
            stages.append(FlowStageDefinition(
                stageID: pexStageID,
                displayName: "PEX \(suffix)",
                requiredTool: mockPEXContractRequirement()
            ))
            stages.append(FlowStageDefinition(
                stageID: simulationStageID,
                displayName: "Simulation \(suffix)",
                requiredTool: simulationRequirement()
            ))
        }

        let runtime = try XcircuiteFlowRuntimeSpec(executors: executors).makeRuntime(projectRoot: root)
        let sink = ProgressEventSink()
        async let followSnapshot = DefaultFlowRunProgressSubscriber().followProgress(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-multifamily-stress",
                timeoutMilliseconds: 30_000,
                pollIntervalMilliseconds: 10
            )
        ) { event in
            await sink.append(event)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-progress-multifamily-stress",
                intent: "Stress follow runtime progress over layout, DRC, LVS, PEX, and simulation stages",
                stages: stages
            )
        )
        let snapshot = try await followSnapshot
        let events = await sink.events()
        var expectedKinds: [FlowRunProgressEventKind] = [.runStarted]
        for _ in stages {
            expectedKinds.append(.stageStarted)
            expectedKinds.append(.stageFinished)
        }
        expectedKinds.append(.runFinished)
        let expectedSequences = Array(1...expectedKinds.count)
        let expectedStageEvents = stages.flatMap { [$0.stageID, $0.stageID] }

        #expect(result.status == .succeeded)
        #expect(result.stages.count == stages.count)
        #expect(result.stages.allSatisfy { $0.status == .succeeded })
        #expect(result.stages.contains { stage in
            stage.gates.contains { $0.gateID == "layout-command" && $0.status == .passed }
        })
        #expect(result.stages.contains { stage in
            stage.gates.contains { $0.gateID == "drc" && $0.status == .passed }
        })
        #expect(result.stages.contains { stage in
            stage.gates.contains { $0.gateID == "lvs" && $0.status == .passed }
        })
        #expect(result.stages.contains { stage in
            stage.gates.contains { $0.gateID == "pex" && $0.status == .passed }
        })
        #expect(result.stages.contains { stage in
            stage.gates.contains { $0.gateID == "simulation" && $0.status == .passed }
        })
        #expect(events.map(\.kind) == expectedKinds)
        #expect(events.compactMap(\.stageID) == expectedStageEvents)
        #expect(events.map(\.sequence) == expectedSequences)
        #expect(snapshot.latestSequence == expectedKinds.count)
        #expect(snapshot.terminalStatus == .succeeded)
        #expect(snapshot.isTerminal)

        let tailCursor = expectedKinds.count - 7
        let recovered = try DefaultFlowRunProgressSubscriber().snapshot(
            request: FlowRunProgressSubscriptionRequest(
                projectRoot: root,
                runID: "run-progress-multifamily-stress",
                afterSequence: tailCursor
            )
        )
        #expect(recovered.events.map(\.sequence) == Array((tailCursor + 1)...expectedKinds.count))
        #expect(recovered.events.last?.kind == .runFinished)
        #expect(recovered.terminalStatus == .succeeded)

        let ledger = try FlowRunLedgerLoader().loadRunLedger(
            runID: "run-progress-multifamily-stress",
            projectRoot: root
        )
        #expect(ledger.progressEvents.map(\.sequence) == expectedSequences)
        let manifest = try XcircuitePackageStore().readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-progress-multifamily-stress/manifest.json")
        )
        let progressArtifact = try #require(manifest.artifacts.first { $0.artifactID == "run-progress" })
        #expect(progressArtifact.path == ".xcircuite/runs/run-progress-multifamily-stress/progress.jsonl")
        #expect((progressArtifact.byteCount ?? 0) > 0)
        try copyProgressStressArtifactIfRequested(root: root, runID: "run-progress-multifamily-stress")
    }

}
