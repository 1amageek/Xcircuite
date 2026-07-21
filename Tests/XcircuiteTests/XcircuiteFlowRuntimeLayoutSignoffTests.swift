import DesignFlowKernel
import CircuiteFoundation
import DRCEngine
import Foundation
import LayoutCommands
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeFeedsLayoutCommandDRCExportIntoDRCStage() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-drc")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                intent: "Apply layout commands and run DRC",
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
                ]
            )
        )

        if result.status != .succeeded {
            let diagnosticMessages: [String] = result.stages
                .flatMap(\.diagnostics)
                .map { "\($0.code):\($0.message)" }
            Issue.record(Comment(rawValue: diagnosticMessages.joined(separator: " | ")))
        }
        #expect(result.status == .succeeded)
        let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
        let drcStage = try #require(result.stages.first { $0.stageID == "007-drc" })
        let drcInputArtifact = try #require(layoutStage.artifacts.first {
            $0.artifactID == "drc-layout"
        })
        #expect(drcInputArtifact.kind == .layout)
        #expect(drcInputArtifact.format == .json)
        #expect(drcInputArtifact.digest.hexadecimalValue.isEmpty == false)
        #expect(drcInputArtifact.producer?.identifier == "layout-command")
        #expect(drcInputArtifact.producer?.version == "2")
        #expect(drcInputArtifact.locator.location.storage == .workspaceRelative)
        let layoutResultArtifact = try #require(layoutStage.artifacts.first {
            $0.artifactID == "layout-command-result"
        })
        let layoutManifestArtifact = try #require(layoutStage.artifacts.first {
            $0.artifactID == "layout-command-manifest"
        })
        #expect(layoutResultArtifact.producer == drcInputArtifact.producer)
        #expect(layoutManifestArtifact.producer == drcInputArtifact.producer)
        #expect(layoutResultArtifact.locator.location.storage == .workspaceRelative)
        #expect(layoutManifestArtifact.locator.location.storage == .workspaceRelative)
        let persistedLedger = try await XcircuiteWorkspaceStore(projectRoot: root)
            .loadRunLedger(runID: "run-1")
        let persistedLayoutResult = try #require(persistedLedger.artifacts.first {
            $0.artifactID == "layout-command-result"
        })
        #expect(persistedLayoutResult == layoutResultArtifact)
        #expect(persistedLayoutResult.producer == drcInputArtifact.producer)
        #expect(drcStage.gates.contains { $0.gateID == "drc" && $0.status == .passed })

        let drcInputURL = root.appending(path: drcInputArtifact.path)
        let data = try Data(contentsOf: drcInputURL)
        let layout = try JSONDecoder().decode(NativeDRCLayout.self, from: data)
        #expect(layout.topCell == "top")
        #expect(layout.technologyID == "flow-test")
        #expect(layout.rectangles.count == 1)
        #expect(layout.rules.map(\.id) == ["M1.width"])
    }

    @Test func layoutCommandExecutorRejectsRunnerOutputOutsideProject() async throws {
        let root = try makeTemporaryRoot("layout-command-outside-run-directory")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let executor = LayoutCommandFlowStageExecutor(
            stageID: "006-layout",
            requestURL: root.appending(path: "layout-command-request.json"),
            runner: OutsideProjectLayoutCommandRunner()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "006-layout", displayName: "Layout command"),
            context: FlowExecutionContext(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_ARTIFACT_OUTPUT_OUTSIDE_PROJECT"
        })
    }

    @Test func layoutCommandExecutorRejectsRunnerResultPathMismatch() async throws {
        let root = try makeTemporaryRoot("layout-command-result-path-mismatch")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let executor = LayoutCommandFlowStageExecutor(
            stageID: "006-layout",
            requestURL: root.appending(path: "layout-command-request.json"),
            runner: InProjectMismatchedLayoutCommandRunner()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "006-layout", displayName: "Layout command"),
            context: FlowExecutionContext(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_RESULT_PATH_MISMATCH"
                && $0.message.contains("outputArtifact.path")
        })
    }

    @Test func layoutCommandExecutorRejectsRunnerOutputDigestMismatch() async throws {
        let root = try makeTemporaryRoot("layout-command-output-digest-mismatch")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let executor = LayoutCommandFlowStageExecutor(
            stageID: "006-layout",
            requestURL: root.appending(path: "layout-command-request.json"),
            runner: DigestMismatchLayoutCommandRunner()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "006-layout", displayName: "Layout command"),
            context: FlowExecutionContext(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_OUTPUT_SHA256_MISMATCH"
        })
    }

    @Test func layoutCommandExecutorRejectsUnpassedRunnerStatusWithValidArtifacts() async throws {
        let root = try makeTemporaryRoot("layout-command-unpassed-runner-status")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let executor = LayoutCommandFlowStageExecutor(
            stageID: "006-layout",
            requestURL: root.appending(path: "layout-command-request.json"),
            runner: UnpassedStatusLayoutCommandRunner()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "006-layout", displayName: "Layout command"),
            context: FlowExecutionContext(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.gates.contains { $0.gateID == "layout-command" && $0.status == .failed })
        #expect(result.artifacts.isEmpty)
        #expect(result.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_RESULT_STATUS_NOT_PASSED"
                && $0.message.contains("failed")
        })
    }

    @Test func layoutCommandExecutorRejectsProducerMismatchBetweenResultAndEvidence() async throws {
        let root = try makeTemporaryRoot("layout-command-producer-mismatch")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let executor = LayoutCommandFlowStageExecutor(
            stageID: "006-layout",
            requestURL: root.appending(path: "layout-command-request.json"),
            runner: ProducerMismatchLayoutCommandRunner()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "006-layout", displayName: "Layout command"),
            context: FlowExecutionContext(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                infrastructure: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.artifacts.isEmpty)
        #expect(result.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_PRODUCER_MISMATCH"
        })
    }

    @Test func runtimeExpandsLayoutCommandViasIntoDRCExport() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-via-drc")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequestWithVia(root: root)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            viaDefinitions: [
                                LayoutCommandDRCViaDefinition(
                                    id: "VIA1",
                                    cutLayer: "VIA1",
                                    bottomLayer: "M1",
                                    topLayer: "M2",
                                    cutWidth: 0.5,
                                    cutHeight: 0.5
                                ),
                            ],
                            rules: [
                                NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 0.5),
                                NativeDRCRule(id: "M2.width", kind: .minimumWidth, layer: "M2", value: 0.5),
                                NativeDRCRule(id: "VIA1.width", kind: .minimumWidth, layer: "VIA1", value: 0.2),
                                NativeDRCRule(
                                    id: "M1.encloses.VIA1",
                                    kind: .minimumEnclosure,
                                    layer: "M1",
                                    value: 0.1,
                                    enclosedLayer: "VIA1"
                                ),
                                NativeDRCRule(
                                    id: "M2.encloses.VIA1",
                                    kind: .minimumEnclosure,
                                    layer: "M2",
                                    value: 0.1,
                                    enclosedLayer: "VIA1"
                                ),
                            ]
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                intent: "Apply layout commands with a via and run DRC",
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
                ]
            )
        )

        #expect(result.status == .succeeded)
        let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
        let drcStage = try #require(result.stages.first { $0.stageID == "007-drc" })
        #expect(drcStage.gates.contains { $0.gateID == "drc" && $0.status == .passed })

        let drcInputArtifact = try #require(layoutStage.artifacts.first {
            $0.artifactID == "drc-layout"
        })
        let drcInputURL = root.appending(path: drcInputArtifact.path)
        let data = try Data(contentsOf: drcInputURL)
        let layout = try JSONDecoder().decode(NativeDRCLayout.self, from: data)
        #expect(layout.rectangles.count == 3)
        #expect(Set(layout.rectangles.map(\.layer)) == ["M1", "M2", "VIA1"])
        let viaRectangle = try #require(layout.rectangles.first { $0.layer == "VIA1" })
        #expect(viaRectangle.id == "20000000-0000-0000-0000-000000000005.cut")
        #expect(viaRectangle.xMin == 0.75)
        #expect(viaRectangle.yMin == 0.75)
        #expect(viaRectangle.xMax == 1.25)
        #expect(viaRectangle.yMax == 1.25)
        #expect(viaRectangle.netID == "20000000-0000-0000-0000-000000000002")
    }

    @Test func layoutCommandDRCExportRejectsViasWithoutDefinitions() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-via-missing-def")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequestWithVia(root: root)
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
                                NativeDRCRule(id: "VIA1.width", kind: .minimumWidth, layer: "VIA1", value: 0.2),
                            ]
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Reject DRC export without via definitions",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .failed)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .failed)
        #expect(stage.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_EXECUTION_ERROR"
                && $0.message.contains("definition VIA1 is missing")
        })
    }

    @Test func runtimeSpecRoundTripsLayoutCommandDRCViaDefinitions() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            viaDefinitions: [
                                LayoutCommandDRCViaDefinition(
                                    id: "VIA1",
                                    cutLayer: "VIA1",
                                    bottomLayer: "M1",
                                    topLayer: "M2",
                                    cutWidth: 0.5,
                                    cutHeight: 0.5
                                ),
                            ],
                            rules: [
                                NativeDRCRule(id: "VIA1.width", kind: .minimumWidth, layer: "VIA1", value: 0.2),
                            ]
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .layoutCommand(let layoutCommand) = try #require(decoded.executors.first) else {
            Issue.record("Expected layout command executor")
            return
        }
        let drcExport = try #require(layoutCommand.drcExport)
        let viaDefinition = try #require(drcExport.viaDefinitions.first)
        #expect(viaDefinition.id == "VIA1")
        #expect(viaDefinition.cutLayer == "VIA1")
        #expect(viaDefinition.bottomLayer == "M1")
        #expect(viaDefinition.topLayer == "M2")
        #expect(viaDefinition.cutWidth == 0.5)
        #expect(viaDefinition.cutHeight == 0.5)
        #expect(drcExport.rules.map(\.id) == ["VIA1.width"])
    }

    @Test func runtimeFeedsLayoutCommandStandardGDSExportIntoLVSStage() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-gds-lvs")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        try await writeStandardLayoutTechnology(root: root)
        let lvsExtraction = try writeStandardLVSExtractionArtifacts(to: root)
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
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                        extractionProfilePath: lvsExtraction.profilePath,
                        extractionDeckPath: lvsExtraction.deckPath,
                        processProfileID: lvsExtraction.processProfileID,
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked, toolID: "native-lvs")
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Export edited layout as GDS and verify it with LVS",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: lvsRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .succeeded)
        let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
        let lvsStage = try #require(result.stages.first { $0.stageID == "008-lvs" })
        let gdsArtifact = try #require(layoutStage.artifacts.first { $0.artifactID == "layout-gds" })
        #expect(gdsArtifact.kind == .layout)
        #expect(gdsArtifact.format == .gdsii)
        #expect(!gdsArtifact.digest.hexadecimalValue.isEmpty)
        #expect(lvsStage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
        #expect(lvsStage.artifacts.contains { $0.path.contains("lvs-report") })
    }

    @Test func runtimeFeedsLayoutCommandStandardMaskExportsIntoLVSStage() async throws {
        for layoutCase in standardMaskLVSCases() {
            let root = try makeTemporaryRoot("runtime-layout-command-\(layoutCase.name)-lvs")
            defer { removeTemporaryRoot(root) }
            let artifactFormat = try ArtifactFormat(rawValue: layoutCase.artifactFormat.rawValue.lowercased())
            try await writeLayoutCommandRequest(
                root: root,
                includeShapeProperties: false
            )
            try await writeStandardLayoutTechnology(root: root)
            let lvsExtraction = try writeStandardLVSExtractionArtifacts(to: root)
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
                            standardLayoutExports: [
                                LayoutCommandStandardLayoutExportSpec(
                                    artifactID: layoutCase.artifactID,
                                    format: layoutCase.exportFormat,
                                    technologyInput: .path("tech/process.json")
                                ),
                            ],
                            tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                        )
                    ),
                    .nativeLVS(
                        XcircuiteFlowStageExecutorSpec.NativeLVS(
                            stageID: "008-lvs",
                            layoutGDSInput: .stageArtifact(
                                XcircuiteFlowInputReference.StageArtifact(
                                    stageID: "006-layout",
                                    artifactID: layoutCase.artifactID,
                                    kind: .layout,
                                    format: artifactFormat
                                )
                            ),
                            layoutFormat: layoutCase.lvsFormat,
                            schematicNetlistPath: "circuits/top.spice",
                            topCell: "top",
                            technologyPath: "tech/process.json",
                            extractionProfilePath: lvsExtraction.profilePath,
                            extractionDeckPath: lvsExtraction.deckPath,
                            processProfileID: lvsExtraction.processProfileID,
                            tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked, toolID: "native-lvs")
                        )
                    ),
                ]
            )
            let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

            let result = try await runtime.run(
                request: FlowOperationRequest(
                    workspaceID: try await workspaceID(projectRoot: root),
                    runID: "run-1",
                    intent: "Export edited layout as \(layoutCase.displayName) and verify it with LVS",
                    stages: [
                        FlowStageDefinition(
                            stageID: "006-layout",
                            displayName: "Layout command",
                            requiredTool: layoutCommandRequirement(requiredStandardOutputFormat: artifactFormat)
                        ),
                        FlowStageDefinition(
                            stageID: "008-lvs",
                            displayName: "LVS",
                            requiredTool: lvsRequirement(requiredLayoutFormat: artifactFormat)
                        ),
                    ]
                )
            )

            let failureDetails = result.stages.flatMap { stage in
                stage.diagnostics.map { "\(stage.stageID):\($0.code):\($0.message)" }
            }.joined(separator: " | ")
            #expect(
                result.status == FlowRunStatus.succeeded,
                "\(layoutCase.displayName) LVS flow failed: \(failureDetails)"
            )
            let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
            let lvsStage = try #require(result.stages.first { $0.stageID == "008-lvs" })
            let layoutArtifact = try #require(layoutStage.artifacts.first { $0.artifactID == layoutCase.artifactID })
            #expect(layoutArtifact.kind == .layout)
            #expect(layoutArtifact.format.rawValue.lowercased() == artifactFormat.rawValue.lowercased())
            #expect(layoutArtifact.path.hasSuffix(layoutCase.fileSuffix))
            #expect(layoutArtifact.digest.hexadecimalValue.isEmpty == false)
            #expect(layoutArtifact.byteCount > 0)
            #expect(lvsStage.gates.contains { $0.gateID == "lvs" && $0.status == .passed })
            #expect(lvsStage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
            #expect(lvsStage.artifacts.contains { $0.artifactID == "lvs-summary" })
        }
    }

    @Test func layoutCommandStandardExportRejectsUnsupportedFormat() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-standard-export-unsupported")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        try await writeStandardLayoutTechnology(root: root)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-json",
                                format: .json,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Reject unsupported standard layout export format",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .failed)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .failed)
        #expect(stage.diagnostics.contains {
            $0.code == "LAYOUT_COMMAND_EXECUTION_ERROR"
                && $0.message.contains("does not support format json")
        })
    }

    @Test func runtimeBlocksProductionPEXWhenMagicIsUnavailableAfterGDSExport() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-gds-pex")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        try await writeStandardLayoutTechnology(root: root)
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
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                    )
                ),
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
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
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(
                            backendID: "magic",
                            executablePath: root.appending(path: "missing-magic").path(percentEncoded: false)
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Export edited layout as GDS and run PEX",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: pexRequirement()
                    ),
                ]
            )
        )

        #expect(result.status == .blocked)
        let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
        let pexStage = try #require(result.stages.first { $0.stageID == "009-pex" })
        let gdsArtifact = try #require(layoutStage.artifacts.first { $0.artifactID == "layout-gds" })
        #expect(!gdsArtifact.digest.hexadecimalValue.isEmpty)
        #expect(pexStage.gates.contains { $0.gateID == "pex" && $0.status == .blocked })
        #expect(pexStage.diagnostics.contains { $0.code == "PEX_BACKEND_UNAVAILABLE" })
        #expect(!pexStage.artifacts.contains { $0.artifactID == "pex-summary" })
    }

    @Test func runtimeBlocksProductionPEXWhenMagicIsUnavailableAfterOASISExport() async throws {
        let root = try makeTemporaryRoot("runtime-layout-command-oasis-pex")
        defer { removeTemporaryRoot(root) }
        try await writeLayoutCommandRequest(root: root)
        try await writeStandardLayoutTechnology(root: root)
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
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-oasis",
                                format: .oasis,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                    )
                ),
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-oasis",
                                kind: .layout,
                                format: .oasis
                            )
                        ),
                        layoutFormat: .oas,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(
                            backendID: "magic",
                            executablePath: root.appending(path: "missing-magic").path(percentEncoded: false)
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)

        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
                runID: "run-1",
                intent: "Export edited layout as OASIS and run PEX",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: pexRequirement(requiredLayoutFormat: .oasis)
                    ),
                ]
            )
        )

        #expect(result.status == .blocked)
        let layoutStage = try #require(result.stages.first { $0.stageID == "006-layout" })
        let pexStage = try #require(result.stages.first { $0.stageID == "009-pex" })
        let oasisArtifact = try #require(layoutStage.artifacts.first { $0.artifactID == "layout-oasis" })
        #expect(oasisArtifact.kind == .layout)
        #expect(oasisArtifact.format == .oasis)
        #expect(oasisArtifact.path.hasSuffix(".oas"))
        #expect(!oasisArtifact.digest.hexadecimalValue.isEmpty)
        #expect(oasisArtifact.byteCount > 0)
        #expect(pexStage.gates.contains { $0.gateID == "pex" && $0.status == .blocked })
        #expect(pexStage.diagnostics.contains { $0.code == "PEX_BACKEND_UNAVAILABLE" })
        #expect(!pexStage.artifacts.contains { $0.artifactID == "pex-summary" })
    }

    private struct OutsideProjectLayoutCommandRunner: LayoutCommandRunning {
        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            LayoutCommandResult(
                status: "passed",
                commandCount: request.commands.count,
                appliedCommands: [],
                outputArtifact: try XcircuiteFlowRuntimeTests.outputArtifact(
                    at: FileManager.default.temporaryDirectory
                        .appending(path: "external-layout-document.json"),
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 0
                ),
                cellCount: 0,
                shapeCount: 0,
                viaCount: 0,
                labelCount: 0,
                netCount: 0
            )
        }
    }

    private struct InProjectMismatchedLayoutCommandRunner: LayoutCommandRunning {
        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            LayoutCommandResult(
                status: "passed",
                commandCount: request.commands.count,
                appliedCommands: [],
                outputArtifact: try XcircuiteFlowRuntimeTests.outputArtifact(
                    at: baseURL.appending(path: "mismatched-layout-document.json"),
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 0
                ),
                cellCount: 0,
                shapeCount: 0,
                viaCount: 0,
                labelCount: 0,
                netCount: 0
            )
        }
    }

    private struct DigestMismatchLayoutCommandRunner: LayoutCommandRunning {
        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            let outputURL = URL(filePath: request.outputDocumentPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let outputData = Data("not-a-layout-document".utf8)
            try outputData.write(to: outputURL, options: [.atomic])
            return LayoutCommandResult(
                status: "passed",
                commandCount: request.commands.count,
                appliedCommands: [],
                outputArtifact: try XcircuiteFlowRuntimeTests.outputArtifact(
                    at: outputURL,
                    sha256: String(repeating: "0", count: 64),
                    byteCount: UInt64(outputData.count)
                ),
                cellCount: 0,
                shapeCount: 0,
                viaCount: 0,
                labelCount: 0,
                netCount: 0
            )
        }
    }

    private struct UnpassedStatusLayoutCommandRunner: LayoutCommandRunning {
        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            let result = try LayoutCommandRunner().run(request: request, baseURL: baseURL)
            return LayoutCommandResult(
                status: "failed",
                commandCount: result.commandCount,
                appliedCommands: result.appliedCommands,
                outputArtifact: result.outputArtifact,
                cellCount: result.cellCount,
                shapeCount: result.shapeCount,
                viaCount: result.viaCount,
                labelCount: result.labelCount,
                netCount: result.netCount
            )
        }
    }

    private struct ProducerMismatchLayoutCommandRunner: LayoutCommandRunning {
        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            let result = try LayoutCommandRunner().run(request: request, baseURL: baseURL)
            let mismatchedArtifact = ArtifactReference(
                id: result.outputArtifact.id,
                locator: result.outputArtifact.locator,
                digest: result.outputArtifact.digest,
                byteCount: result.outputArtifact.byteCount,
                producer: try ProducerIdentity(
                    kind: .tool,
                    identifier: "different-layout-command",
                    version: "2"
                )
            )
            return LayoutCommandResult(
                status: result.status,
                commandCount: result.commandCount,
                appliedCommands: result.appliedCommands,
                outputArtifact: mismatchedArtifact,
                cellCount: result.cellCount,
                shapeCount: result.shapeCount,
                viaCount: result.viaCount,
                labelCount: result.labelCount,
                netCount: result.netCount
            )
        }
    }

    private func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

    private static func outputArtifact(
        at url: URL,
        sha256: String,
        byteCount: UInt64
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: "layout-command-output"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(fileURL: url),
                role: try ArtifactRole(validatingRawValue: "output-layout-document"),
                kind: .layout,
                format: .json
            ),
            digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: sha256),
            byteCount: byteCount
        )
    }

}
