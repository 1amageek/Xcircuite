import DesignFlowKernel
import CircuiteFoundation
import DRCEngine
import ElectricalSignoffCore
import Foundation
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import RTLVerificationCore
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeSpecRoundTripsCoreSpiceProducerOutputInput() throws {
        let input = XcircuiteFlowInputReference.stageArtifact(
            .init(
                stageID: "pex.extract",
                artifactID: "extracted-netlist",
                kind: .netlist,
                format: .spice
            )
        )
        let spec = XcircuiteFlowRuntimeSpec(executors: [
            .coreSpiceSimulation(.init(stageID: "simulate.post-layout", netlistInput: input)),
        ])

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .coreSpiceSimulation(let simulation) = try #require(decoded.executors.first) else {
            Issue.record("Expected CoreSpice simulation executor")
            return
        }
        #expect(decoded.schemaVersion == XcircuiteFlowRuntimeSpec.currentSchemaVersion)
        #expect(simulation.netlistInput == input)
    }

    @Test func nativeDesignRuntimeFixtureIsCLIReady() throws {
        guard let url = Bundle.module.url(
            forResource: "native-design-runtime.json",
            withExtension: nil,
            subdirectory: "Fixtures/FlowRuntime"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let spec = try XcircuiteFlowRuntimeSpec.load(from: url)

        try spec.validate()

        #expect(spec.executors.count == 7)
        #expect(spec.executors.map(\.stageID) == [
            "logic.elaborate",
            "logic.power-intent",
            "logic.lower",
            "logic.simulate",
            "physical.floorplan",
            "timing.sta",
            "timing.signal-integrity",
        ])
    }

    @Test func runtimeSpecPathErrorIdentifiesTheFailingStage() async throws {
        let stageID = "electrical-signoff.fixture"
        let executor = XcircuiteFlowStageExecutorSpec.electricalSignoff(
            .init(stageID: stageID, requestPath: "missing-request.json")
        )

        do {
            _ = try await XcircuiteFlowRuntimeSpec(executors: [executor]).makeRuntime(
                projectRoot: FileManager.default.temporaryDirectory
            )
            Issue.record("Expected the missing request to fail")
        } catch XcircuiteFlowRuntimeSpecError.invalidPath(let detail) {
            #expect(detail.contains(stageID))
            #expect(detail.contains("missing-request.json"))
            #expect(!detail.contains("(stageID)"))
        }
    }

    @Test func runtimeSpecRoundTripsRTLVerificationStageWithEvidenceInput() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .rtlVerification(
                    XcircuiteFlowStageExecutorSpec.RTLVerification(
                        analysis: .lint,
                        rtlInput: .path("rtl/top.sv"),
                        evidenceInput: .path("qualification/rtl-input.json"),
                        pdkInput: .path("pdk/manifest.json"),
                        topModuleName: "top"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .rtlVerification(let rtl) = try #require(decoded.executors.first) else {
            Issue.record("Expected RTL verification executor")
            return
        }
        #expect(rtl.stageID == "rtl.lint")
        #expect(rtl.analysis == .lint)
        #expect(rtl.topModuleName == "top")
        #expect(rtl.evidenceInput == .path("qualification/rtl-input.json"))
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-rtl-verification")
    }

    @Test func runtimeSpecRegistersAnUnqualifiedIndependentRTLVerificationOracle() async throws {
        let oracleToolID = "fixture-rtl-oracle"
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .rtlVerification(
                    XcircuiteFlowStageExecutorSpec.RTLVerification(
                        analysis: .lint,
                        rtlInput: .path("rtl/top.sv"),
                        pdkInput: .path("pdk/manifest.json"),
                        topModuleName: "top",
                        oracleTool: RTLVerificationOracleToolSpec(
                            toolID: oracleToolID,
                            executablePath: "tools/rtl-oracle",
                            version: "1.0.0",
                            tool: XcircuiteFlowToolSpec()
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()
        let runtime = try await decoded.makeRuntime(
            projectRoot: FileManager.default.temporaryDirectory
                .appending(path: "rtl-oracle-runtime-\(UUID().uuidString)")
        )

        guard case .rtlVerification(let rtl) = try #require(decoded.executors.first) else {
            Issue.record("Expected RTL verification executor")
            return
        }
        #expect(rtl.oracleTool?.toolID == oracleToolID)
        #expect(runtime.toolRegistry.descriptor(toolID: oracleToolID)?.version == "1.0.0")
        #expect(runtime.toolRegistry.descriptor(toolID: oracleToolID)?.trustProfile.level == .unknown)
        #expect(runtime.healthResults[oracleToolID]?.status == .notChecked)
    }

    @Test func runtimeSpecRoundTripsElectricalRepairRevisionStage() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalRepairRevision(
                    XcircuiteFlowStageExecutorSpec.ElectricalRepairRevision(
                        requestPath: ".xcircuite/runs/run-1/electrical-signoff/repair-revision-request.json",
                        tool: qualifiedToolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .electricalRepairRevision(let repair) = try #require(decoded.executors.first) else {
            Issue.record("Expected electrical repair revision executor")
            return
        }
        #expect(repair.stageID == "electrical-signoff.repair-revision")
        #expect(repair.requestPath == ".xcircuite/runs/run-1/electrical-signoff/repair-revision-request.json")
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-electrical-signoff-repair-revision")
    }

    @Test func runtimeSpecRoundTripsElectricalSignoffStages() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalStandardLayoutImport(
                    XcircuiteFlowStageExecutorSpec.ElectricalStandardLayoutImport(
                        layoutInput: try digestBoundInput(
                            "layout/top.def",
                            kind: .layout,
                            format: .def
                        ),
                        layoutFormat: .def,
                        technologyInput: try digestBoundInput(
                            "tech/process.lef",
                            kind: .technology,
                            format: .lef
                        ),
                        technologyLayerMappingInput: try digestBoundInput(
                            "tech/process-layer-map.json",
                            kind: .technology,
                            format: .json
                        ),
                        connectivityInput: try digestBoundInput(
                            "layout/top.def",
                            kind: .layout,
                            format: .def
                        ),
                        topCellName: "top"
                    )
                ),
                .electricalSignoff(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoff(
                        requestPath: "electrical/signoff-request.json",
                        axes: [.powerIntegrity, .erc]
                    )
                ),
                .electricalSignoffCorpus(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffCorpus(
                        specPath: "electrical/corpus-spec.json",
                        oraclePath: "electrical/oracle-observations.json"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .electricalStandardLayoutImport(let layout) = decoded.executors[0],
              case .electricalSignoff(let signoff) = decoded.executors[1],
              case .electricalSignoffCorpus(let corpus) = decoded.executors[2] else {
            Issue.record("Expected all electrical signoff runtime executors")
            return
        }
        #expect(layout.stageID == "electrical-signoff.standard-layout-import")
        #expect(signoff.axes == [.powerIntegrity, .erc])
        #expect(corpus.specPath == "electrical/corpus-spec.json")
        #expect(corpus.oraclePath == "electrical/oracle-observations.json")
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-electrical-standard-layout-import")
        #expect(decoded.executors[1].makeDescriptor().toolID == "native-electrical-signoff")
        #expect(decoded.executors[2].makeDescriptor().toolID == "native-electrical-signoff-corpus")
    }

    @Test func runtimeSpecRoundTripsElectricalCorpusStage() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalSignoffCorpus(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffCorpus(
                        specPath: "electrical/corpus.json"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .electricalSignoffCorpus(let corpus) = decoded.executors[0] else {
            Issue.record("Expected electrical corpus runtime executor")
            return
        }
        #expect(corpus.specPath == "electrical/corpus.json")
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-electrical-signoff-corpus")
    }

    @Test func runtimeSpecRejectsUnboundElectricalStandardLayoutInputs() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalStandardLayoutImport(
                    XcircuiteFlowStageExecutorSpec.ElectricalStandardLayoutImport(
                        layoutInput: .path("layout/top.def"),
                        layoutFormat: .def,
                        technologyInput: .path("tech/process.lef")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected digest-bound standard-layout input validation error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingExecutorInput(
                stageID: "electrical-signoff.standard-layout-import",
                field: "layoutInput must be a digest-bound artifact or stageArtifact reference"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRoundTripsLogicSynthesisAndEquivalenceStages() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .logicSynthesis(
                    XcircuiteFlowStageExecutorSpec.LogicSynthesis(
                        requestPath: ".xcircuite/runs/current/logic-synthesis-request.json"
                    )
                ),
                .logicEquivalence(
                    XcircuiteFlowStageExecutorSpec.LogicEquivalence(
                        requestPath: ".xcircuite/runs/current/logic-equivalence-request.json"
                    )
                ),
                .logicEvidenceValidation(
                    XcircuiteFlowStageExecutorSpec.LogicEvidenceValidation(
                        reportPath: "qualification/logic-report.json"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .logicSynthesis(let synthesis) = decoded.executors[0] else {
            Issue.record("Expected logic synthesis executor")
            return
        }
        guard case .logicEquivalence(let equivalence) = decoded.executors[1] else {
            Issue.record("Expected logic equivalence executor")
            return
        }
        #expect(synthesis.stageID == "logic.synthesize")
        #expect(equivalence.stageID == "logic.equivalence")
        guard case .logicEvidenceValidation(let qualification) = decoded.executors[2] else {
            Issue.record("Expected logic evidence validation executor")
            return
        }
        #expect(qualification.stageID == "logic.evidence-validation")
        #expect(decoded.executors[0].makeDescriptor().toolID == "logic-synthesis")
        #expect(decoded.executors[1].makeDescriptor().toolID == "native-rtl-verification")
        #expect(decoded.executors[2].makeDescriptor().toolID == "logic-evidence-validation")
    }

    @Test func runtimeSpecRoundTripsAgentOperableDesignAndTimingStages() throws {
        let producedDesign = XcircuiteFlowInputReference.stageArtifact(.init(
            stageID: "logic.lower",
            artifactID: "logic-execution-design",
            kind: .netlist,
            format: .json
        ))
        let producedParasitics = XcircuiteFlowInputReference.stageArtifact(.init(
            stageID: "signoff.pex",
            kind: .parasitics,
            format: .spef,
            pathSuffix: "tt.spef"
        ))
        let pdkDigest = String(repeating: "0", count: 64)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .logicElaboration(.init(
                    sourceInput: .path("rtl/top.sv"),
                    topDesignName: "top"
                )),
                .powerIntent(.init(
                    sourceInput: .path("power/top.upf"),
                    designInput: .stageArtifact(.init(
                        stageID: "logic.elaborate",
                        artifactID: "logic-design",
                        kind: .rtl,
                        format: .json
                    )),
                    pdkInput: .path("pdk/manifest.json"),
                    topDesignName: "top"
                )),
                .logicLowering(.init(
                    designInput: .stageArtifact(.init(
                        stageID: "logic.elaborate",
                        artifactID: "logic-design",
                        kind: .rtl,
                        format: .json
                    )),
                    topDesignName: "top"
                )),
                .logicSimulation(.init(
                    designInput: producedDesign,
                    pdkInput: .path("pdk/manifest.json"),
                    topDesignName: "top",
                    stimulusInput: .path("logic/stimulus.json"),
                    seed: 7
                )),
                .physicalDesign(.init(
                    stageID: "physical.floorplan",
                    requestInput: .path("requests/floorplan.json"),
                    allowedStages: [.floorplan]
                )),
                .timingSTA(.init(inputs: TimingSTAFlowInputs(
                    design: producedDesign,
                    libraries: [.path("timing/cells.lib")],
                    constraints: .path("timing/top.sdc"),
                    pdkManifest: .path("pdk/manifest.json"),
                    parasitics: producedParasitics,
                    topDesignName: "top",
                    processID: "fixture-process",
                    pdkVersion: "1",
                    pdkDigest: pdkDigest,
                    modeIDs: ["functional"],
                    cornerIDs: ["tt"],
                    requiresPostLayoutInputs: true
                ))),
                .timingSignalIntegrity(.init(inputs: TimingSIFlowInputs(
                    design: producedDesign,
                    constraints: .path("timing/top.sdc"),
                    pdkManifest: .path("pdk/manifest.json"),
                    parasitics: producedParasitics,
                    topDesignName: "top",
                    processID: "fixture-process",
                    pdkVersion: "1",
                    pdkDigest: pdkDigest,
                    modeIDs: ["functional"],
                    maxDeltaDelay: 0.5,
                    maxNoiseRatio: 0.1
                ))),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        #expect(decoded == spec)
        #expect(decoded.executors.map { $0.makeDescriptor().toolID } == [
            "logic-design.native",
            "logic-design.power-intent",
            "logic-lowering",
            "logic-simulation",
            "physical-design",
            "native-sta",
            "native-signal-integrity",
        ])
    }

    @Test func runtimeSpecRejectsIncompleteTimingAndPhysicalDesignInputs() throws {
        let invalidPhysical = XcircuiteFlowRuntimeSpec(
            executors: [
                .physicalDesign(.init(
                    stageID: "physical.floorplan",
                    requestInput: .path("requests/floorplan.json"),
                    allowedStages: []
                )),
            ]
        )
        #expect(throws: XcircuiteFlowRuntimeSpecError.self) {
            try invalidPhysical.validate()
        }

        let invalidTiming = XcircuiteFlowRuntimeSpec(
            executors: [
                .timingSTA(.init(inputs: TimingSTAFlowInputs(
                    design: .path("design.json"),
                    libraries: [],
                    constraints: .path("constraints.sdc"),
                    pdkManifest: .path("pdk.json"),
                    topDesignName: "top",
                    processID: "fixture-process",
                    pdkVersion: "1",
                    pdkDigest: String(repeating: "0", count: 64)
                ))),
            ]
        )
        #expect(throws: XcircuiteFlowRuntimeSpecError.self) {
            try invalidTiming.validate()
        }
    }

    @Test func runtimeSpecRoundTripsLayoutCommandStandardExportsAndLVSInputs() async throws {
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
                        ]
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
                        schematicNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        technologyInput: .path("tech/process.json"),
                        extractionProfileInput: .path("tech/layout-extraction-profile.json"),
                        extractionDeckInput: .path("tech/extraction.deck"),
                        processProfileID: "fixture.generated-mos.v1",
                        terminalEquivalenceInput: .path("tech/lvs-terminal-equivalence.json")
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .layoutCommand(let layoutCommand) = decoded.executors[0] else {
            Issue.record("Expected layout command executor")
            return
        }
        guard case .nativeLVS(let lvs) = decoded.executors[1] else {
            Issue.record("Expected LVS executor")
            return
        }
        let standardExport = try #require(layoutCommand.standardLayoutExports.first)
        #expect(standardExport.artifactID == "layout-gds")
        #expect(standardExport.format == .gds)
        guard case .stageArtifact(let layoutArtifact) = try #require(lvs.layoutGDSInput) else {
            Issue.record("Expected LVS stage artifact layout input")
            return
        }
        #expect(layoutArtifact.stageID == "006-layout")
        #expect(layoutArtifact.artifactID == "layout-gds")
        guard case .path(let schematicPath) = try #require(lvs.schematicNetlistInput) else {
            Issue.record("Expected schematic path input")
            return
        }
        #expect(schematicPath == "circuits/top.spice")
        guard case .path(let technologyPath) = try #require(lvs.technologyInput) else {
            Issue.record("Expected technology path input")
            return
        }
        #expect(technologyPath == "tech/process.json")
        #expect(lvs.extractionProfileInput == .path("tech/layout-extraction-profile.json"))
        #expect(lvs.extractionDeckInput == .path("tech/extraction.deck"))
        #expect(lvs.processProfileID == "fixture.generated-mos.v1")
        guard case .path(let terminalEquivalencePath) = try #require(lvs.terminalEquivalenceInput) else {
            Issue.record("Expected terminal equivalence path input")
            return
        }
        #expect(terminalEquivalencePath == "tech/lvs-terminal-equivalence.json")
    }

    @Test func runtimeSpecRoundTripsPEXStageArtifactInputs() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
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
                        technology: .input(.path("tech/pex.json")),
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .pex(let pex) = try #require(decoded.executors.first) else {
            Issue.record("Expected PEX executor")
            return
        }
        guard case .stageArtifact(let layoutArtifact) = try #require(pex.layoutInput) else {
            Issue.record("Expected PEX layout stage artifact input")
            return
        }
        #expect(layoutArtifact.stageID == "006-layout")
        #expect(layoutArtifact.artifactID == "layout-gds")
        guard case .path(let netlistPath) = try #require(pex.sourceNetlistInput) else {
            Issue.record("Expected PEX source netlist path input")
            return
        }
        #expect(netlistPath == "circuits/top.spice")
        let technology = try #require(pex.technology)
        guard case .input(let technologyInput) = technology else {
            Issue.record("Expected PEX technology input reference")
            return
        }
        guard case .path(let technologyPath) = technologyInput else {
            Issue.record("Expected PEX technology path")
            return
        }
        #expect(technologyPath == "tech/pex.json")
    }

    @Test func runtimeSpecRoundTripsPEXBackendExecutor() async throws {
        let root = try makeTemporaryRoot("runtime-pex-backend-executor")
        defer { removeTemporaryRoot(root) }
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
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
                        processProfile: PEXProcessProfileReference(
                            primaryDeckPath: "tech/tt.rc",
                            cornerDeckPaths: ["tt": "tech/tt.rc"]
                        ),
                        backendSelection: PEXBackendSelection(backendID: "magic"),
                        tool: qualifiedToolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()
        let runtime = try await QualifiedToolFixtures.runtime(spec: decoded, projectRoot: root)
        let descriptor = try #require(runtime.toolRegistry.descriptor(toolID: "pex-magic"))

        #expect(descriptor.kind == .pex)
        #expect(descriptor.trustProfile.level == .smokeChecked)
        #expect(descriptor.capabilities.contains { $0.operationID == "run-pex" })
        #expect(runtime.healthResults["pex-magic"]?.status == .passed)
    }

    @Test func runtimeSpecRoundTripsPEXCornerTechnologyOverrides() async throws {
        let baseTechnology = makePEXTechnology()
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt"), PEXCorner(id: "ss")],
                        technology: .inline(baseTechnology),
                        technologyByCorner: ["ss": .inline(baseTechnology)],
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        let decoded = try JSONDecoder().decode(
            XcircuiteFlowRuntimeSpec.self,
            from: try JSONEncoder().encode(spec)
        )
        try decoded.validate()
        guard case .pex(let pex) = decoded.executors[0] else {
            Issue.record("Expected PEX executor")
            return
        }
        #expect(pex.technologyByCorner.keys.sorted() == ["ss"])
        #expect(pex.technologyByCorner["ss"] == .inline(baseTechnology))
    }

    @Test func runtimeSpecRejectsPEXCornerTechnologyForUndeclaredCorner() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        technologyByCorner: ["ss": .inline(makePEXTechnology())],
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected undeclared corner technology to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            guard case .missingExecutorInput(let stageID, let field) = error else {
                Issue.record("Expected a missing executor input diagnostic")
                return
            }
            #expect(stageID == "009-pex")
            #expect(field.contains("technologyByCorner[ss]"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecAcceptsProductionPEXBackend() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        try spec.validate()
    }

    @Test func runtimeSpecRejectsLVSWithoutLayoutInput() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        schematicNetlistInput: .path("circuits/top.spice"),
                        topCell: "top"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing LVS layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            guard case .missingExecutorInput(let stageID, let field) = error else {
                Issue.record("Expected a missing executor input diagnostic")
                return
            }
            #expect(stageID == "008-lvs")
            #expect(field.contains("layoutNetlistInput"))
            #expect(field.contains("layoutGDSInput"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsStandardLayoutLVSWithoutExtractionIdentity() async throws {
        let cases: [(
            profile: XcircuiteFlowInputReference?,
            deck: XcircuiteFlowInputReference?,
            processProfileID: String?,
            expectedField: String
        )] = [
            (nil, .path("tech/extraction.deck"), "fixture.generated-mos.v1", "extractionProfile"),
            (.path("tech/layout-extraction-profile.json"), nil, "fixture.generated-mos.v1", "extractionDeck"),
            (.path("tech/layout-extraction-profile.json"), .path("tech/extraction.deck"), nil, "processProfileID"),
        ]

        for item in cases {
            let spec = XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeLVS(
                        XcircuiteFlowStageExecutorSpec.NativeLVS(
                            stageID: "008-lvs",
                            layoutGDSInput: .path("layout/top.gds"),
                            layoutFormat: .gds,
                            schematicNetlistInput: .path("circuits/top.spice"),
                            topCell: "top",
                            extractionProfileInput: item.profile,
                            extractionDeckInput: item.deck,
                            processProfileID: item.processProfileID
                        )
                    ),
                ]
            )

            do {
                try spec.validate()
                Issue.record("Expected standard-layout LVS extraction identity to be required")
            } catch let error as XcircuiteFlowRuntimeSpecError {
                guard case .missingExecutorInput(let stageID, let field) = error else {
                    Issue.record("Expected a missing executor input diagnostic")
                    continue
                }
                #expect(stageID == "008-lvs")
                #expect(field.contains(item.expectedField))
            } catch {
                throw error
            }
        }
    }

    @Test func runtimeSpecRejectsConflictingLVSExtractionProfileInputs() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        schematicNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        extractionProfilePath: "tech/layout-extraction-profile.json",
                        extractionProfileInput: .path("tech/other-layout-extraction-profile.json"),
                        extractionDeckInput: .path("tech/extraction.deck"),
                        processProfileID: "fixture.generated-mos.v1"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected conflicting LVS extraction profile inputs to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            guard case .conflictingExecutorInputs(let stageID, let fields) = error else {
                Issue.record("Expected a conflicting executor input diagnostic")
                return
            }
            #expect(stageID == "008-lvs")
            #expect(fields == ["extractionProfilePath", "extractionProfileInput"])
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsPEXWithoutLayoutInput() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutFormat: .gds,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing PEX layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            guard case .missingExecutorInput(let stageID, let field) = error else {
                Issue.record("Expected a missing executor input diagnostic")
                return
            }
            #expect(stageID == "009-pex")
            #expect(field.contains("layoutInput"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsPEXWithoutTechnologyOrToolchainProfile() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        backendSelection: PEXBackendSelection(backendID: "magic")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing PEX technology input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingExecutorInput(
                stageID: "009-pex",
                field: "technology or toolchainProfile.pexTechnology"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRoundTripsStageArtifactInputReference() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
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
                        topCell: "top"
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .nativeDRC(let drc) = try #require(decoded.executors.first) else {
            Issue.record("Expected DRC executor")
            return
        }
        guard case .stageArtifact(let artifact) = try #require(drc.layoutInput) else {
            Issue.record("Expected stage artifact reference")
            return
        }
        #expect(artifact.stageID == "006-layout")
        #expect(artifact.artifactID == "drc-layout")
        #expect(artifact.kind == .layout)
        #expect(artifact.format == .json)
        #expect(artifact.pathSuffix == nil)
    }

    @Test func stageArtifactInputReferenceRejectsDigestMismatch() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-digest")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutRawPath = ".xcircuite/runs/run-1/stages/006-layout/raw"
        try await workspaceStore.ensureWorkspaceDirectory(at: layoutRawPath)
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutData = Data("tampered".utf8)
        try await workspaceStore.write(layoutData, to: layoutPath)
        try await persistTestStageResult(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try fixtureArtifactReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: String(repeating: "0", count: 64),
                        byteCount: Int64(layoutData.count),
                    ),
                ]
            ),
            runID: "run-1",
            store: workspaceStore
        )
        let executor = DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(
                XcircuiteFlowInputReference.StageArtifact(
                    stageID: "006-layout",
                    artifactID: "drc-layout",
                    kind: .layout,
                    format: .json
                )
            ),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR" && $0.message.contains("digest mismatch")
        })
    }

    @Test func stageArtifactInputReferenceRejectsAnUnretainedResultFile() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-unretained-result")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutData = Data("{}".utf8)
        try await workspaceStore.write(layoutData, to: layoutPath)
        try await workspaceStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try fixtureArtifactReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: try fixtureSHA256(data: layoutData),
                        byteCount: Int64(layoutData.count)
                    ),
                ]
            ),
            to: ".xcircuite/runs/run-1/stages/006-layout/result.json"
        )
        let result = try await DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(.init(
                stageID: "006-layout",
                artifactID: "drc-layout",
                kind: .layout,
                format: .json
            )),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        ).execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR"
                && $0.message.contains("not uniquely retained")
        })
    }

    @Test func stageArtifactInputReferenceRejectsARetainedFailedResult() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-failed-result")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        _ = try await persistTestStageResult(
            FlowStageResult(stageID: "006-layout", status: .failed),
            runID: "run-1",
            store: workspaceStore
        )
        let result = try await DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(.init(
                stageID: "006-layout",
                artifactID: "drc-layout",
                kind: .layout,
                format: .json
            )),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        ).execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR"
                && $0.message.contains("must be a succeeded result")
        })
    }

    @Test func stageArtifactInputReferenceRejectsByteCountMismatch() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-byte-count")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutRawPath = ".xcircuite/runs/run-1/stages/006-layout/raw"
        try await workspaceStore.ensureWorkspaceDirectory(at: layoutRawPath)
        let layoutData = Data("{}".utf8)
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        try await workspaceStore.write(layoutData, to: layoutPath)
        try await persistTestStageResult(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try fixtureArtifactReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: try fixtureSHA256(data: layoutData),
                        byteCount: 1,
                    ),
                ]
            ),
            runID: "run-1",
            store: workspaceStore
        )
        let executor = DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(
                XcircuiteFlowInputReference.StageArtifact(
                    stageID: "006-layout",
                    artifactID: "drc-layout",
                    kind: .layout,
                    format: .json
                )
            ),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR" && $0.message.contains("byte count mismatch")
        })
    }

    @Test func stageRawArtifactInputReferenceRejectsSymlinkEscape() async throws {
        let root = try makeTemporaryRoot("runtime-stage-raw-symlink")
        let outsideRoot = try makeTemporaryRoot("runtime-stage-raw-symlink-outside")
        defer {
            removeTemporaryRoot(root)
            removeTemporaryRoot(outsideRoot)
        }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        let runDirectory = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutRawPath = ".xcircuite/runs/run-1/stages/006-layout/raw"
        try await workspaceStore.ensureWorkspaceDirectory(at: layoutRawPath)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        let outsideLayoutURL = outsideRoot.appending(path: "escaped-layout.json")
        try Data("{}".utf8).write(to: outsideLayoutURL, options: [.atomic])
        try FileManager.default.createSymbolicLink(
            at: layoutRawDirectory.appending(path: "escaped-layout.json"),
            withDestinationURL: outsideLayoutURL
        )
        let executor = DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageRawArtifact(
                XcircuiteFlowInputReference.StageRawArtifact(
                    stageID: "006-layout",
                    relativePath: "escaped-layout.json"
                )
            ),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR"
                && $0.message.contains("Invalid flow input reference")
                && $0.message.contains("escaped-layout.json")
        })
    }

    @Test func stageArtifactInputReferenceRejectsSymlinkedResultEscape() async throws {
        let root = try makeTemporaryRoot("runtime-stage-result-symlink")
        let outsideRoot = try makeTemporaryRoot("runtime-stage-result-symlink-outside")
        defer {
            removeTemporaryRoot(root)
            removeTemporaryRoot(outsideRoot)
        }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        let runDirectory = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutRawPath = ".xcircuite/runs/run-1/stages/006-layout/raw"
        try await workspaceStore.ensureWorkspaceDirectory(at: layoutRawPath)
        let layoutData = Data("{}".utf8)
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        try await workspaceStore.write(layoutData, to: layoutPath)
        try await writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try fixtureArtifactReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: try fixtureSHA256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                    ),
                ]
            ),
            to: outsideRoot.appending(path: "result.json")
        )
        try FileManager.default.createSymbolicLink(
            at: runDirectory
                .appending(path: "stages")
                .appending(path: "006-layout")
                .appending(path: "result.json"),
            withDestinationURL: outsideRoot.appending(path: "result.json")
        )
        let executor = DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(
                XcircuiteFlowInputReference.StageArtifact(
                    stageID: "006-layout",
                    artifactID: "drc-layout",
                    kind: .layout,
                    format: .json
                )
            ),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR"
                && $0.message.contains("Invalid flow input reference")
                && $0.message.contains("stage result 006-layout")
        })
    }

    @Test func stageArtifactInputReferenceMatchesPathSuffixByComponent() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-component-suffix")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        _ = try await prepareTestRun(runID: "run-1", store: workspaceStore)
        let layoutRawPath = ".xcircuite/runs/run-1/stages/006-layout/raw"
        try await workspaceStore.ensureWorkspaceDirectory(at: layoutRawPath)
        let layoutData = Data("{}".utf8)
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/notdrc-layout.json"
        try await workspaceStore.write(layoutData, to: layoutPath)
        try await persistTestStageResult(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try fixtureArtifactReference(
                        artifactID: "not-drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: try fixtureSHA256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                    ),
                ]
            ),
            runID: "run-1",
            store: workspaceStore
        )
        let executor = DRCFlowStageExecutor(
            stageID: "007-drc",
            toolID: "native-drc",
            layoutInput: .stageArtifact(
                XcircuiteFlowInputReference.StageArtifact(
                    stageID: "006-layout",
                    kind: .layout,
                    format: .json,
                    pathSuffix: "drc-layout.json"
                )
            ),
            topCell: "top",
            backendSelection: DRCBackendSelection(backendID: "native"),
            engine: NoopDRCEngine()
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
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
            $0.code == "DRC_EXECUTION_ERROR"
                && $0.message.contains("did not match any artifact")
        })
    }

    @Test func runtimeSpecValidationRejectsDRCWithoutLayoutInput() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        topCell: "top"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing DRC layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            guard case .missingExecutorInput(let stageID, let field) = error else {
                Issue.record("Expected a missing executor input diagnostic")
                return
            }
            #expect(stageID == "007-drc")
            #expect(field.contains("layoutInput"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRoundTripsStandardSignoffInputs() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .path("layout/top.oas"),
                        layoutFormat: .oasis,
                        topCell: "TOP",
                        technologyInput: .path("tech/process.json"),
                        tool: XcircuiteFlowToolSpec()
                    )
                ),
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        schematicNetlistInput: .path("circuits/top.spice"),
                        topCell: "TOP",
                        technologyInput: .path("tech/process.json"),
                        extractionProfileInput: .path("tech/layout-extraction-profile.json"),
                        extractionDeckInput: .path("tech/extraction.deck"),
                        processProfileID: "fixture.generated-mos.v1",
                        tool: XcircuiteFlowToolSpec()
                    )
                ),
                .postLayoutComparison(
                    XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
                        stageID: "030-compare",
                        preLayoutWaveformInput: .path(".xcircuite/runs/pre.csv"),
                        postLayoutWaveformInput: .path(".xcircuite/runs/post.csv"),
                        options: PostLayoutComparisonOptions(
                            requiredPostVariables: ["V(n1_pex)"],
                            oscillationLimits: [
                                PostLayoutOscillationLimit(
                                    variableName: "V(n1)",
                                    minimumPostAmplitude: 0.5
                                ),
                            ]
                        ),
                        tool: XcircuiteFlowToolSpec()
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .nativeDRC(let drc) = decoded.executors[0] else {
            Issue.record("Expected DRC executor")
            return
        }
        guard case .nativeLVS(let lvs) = decoded.executors[1] else {
            Issue.record("Expected LVS executor")
            return
        }
        guard case .postLayoutComparison(let comparison) = decoded.executors[2] else {
            Issue.record("Expected comparison executor")
            return
        }
        #expect(drc.layoutFormat == .oasis)
        #expect(drc.technologyInput == .path("tech/process.json"))
        #expect(lvs.layoutGDSInput == .path("layout/top.gds"))
        #expect(lvs.layoutFormat == .gds)
        #expect(lvs.technologyInput == .path("tech/process.json"))
        #expect(lvs.extractionProfileInput == .path("tech/layout-extraction-profile.json"))
        #expect(lvs.extractionDeckInput == .path("tech/extraction.deck"))
        #expect(lvs.processProfileID == "fixture.generated-mos.v1")
        #expect(comparison.options.requiredPostVariables == ["V(n1_pex)"])
    }

    @Test func runtimeSpecRoundTripsPostLayoutStageArtifactInputs() async throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .postLayoutComparison(
                    XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
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
                        options: PostLayoutComparisonOptions(requiredPostVariables: ["V(out_pex)"])
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .postLayoutComparison(let comparison) = decoded.executors[0] else {
            Issue.record("Expected comparison executor")
            return
        }
        guard case .stageArtifact(let preArtifact) = try #require(comparison.preLayoutWaveformInput) else {
            Issue.record("Expected pre-layout stage artifact input")
            return
        }
        guard case .stageArtifact(let postArtifact) = try #require(comparison.postLayoutWaveformInput) else {
            Issue.record("Expected post-layout stage artifact input")
            return
        }
        #expect(preArtifact.stageID == "010-pre-sim")
        #expect(preArtifact.artifactID == "pre-layout-waveform")
        #expect(postArtifact.stageID == "020-post-sim")
        #expect(postArtifact.artifactID == "post-layout-waveform")
    }

    @Test func runtimeSpecUsesDedicatedPostLayoutComparisonToolDescriptor() async throws {
        let root = try makeTemporaryRoot("runtime-post-layout-comparison-tool")
        defer { removeTemporaryRoot(root) }
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .postLayoutComparison(
                    XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
                        stageID: "030-compare",
                        preLayoutWaveformInput: .path(".xcircuite/runs/pre.csv"),
                        postLayoutWaveformInput: .path(".xcircuite/runs/post.csv"),
                        tool: qualifiedToolSpec(level: .corpusChecked)
                    )
                ),
            ]
        )

        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)
        let descriptor = try #require(runtime.toolRegistry.descriptor(toolID: "post-layout-comparison"))

        #expect(descriptor.toolID == "post-layout-comparison")
        #expect(descriptor.kind == .simulation)
        #expect(descriptor.trustProfile.level == .corpusChecked)
        #expect(descriptor.capabilities.contains { $0.operationID == "compare-waveforms" })
        #expect(runtime.toolRegistry.descriptor(toolID: "corespice") == nil)
        #expect(runtime.healthResults["post-layout-comparison"]?.status == .passed)
        #expect(runtime.healthResults["corespice"] == nil)
    }

    @Test func runtimeSpecAllowsRepeatedToolIDWithIdenticalToolDeclaration() async throws {
        let root = try makeTemporaryRoot("runtime-repeated-tool")
        defer { removeTemporaryRoot(root) }
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-a",
                        layoutInput: .path("layout-a.json"),
                        topCell: "TOP"
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-b",
                        layoutInput: .path("layout-b.json"),
                        topCell: "TOP"
                    )
                ),
            ]
        )

        try spec.validate()
        let runtime = try await spec.makeRuntime(projectRoot: root)

        #expect(runtime.toolRegistry.descriptors.count == 1)
        #expect(runtime.toolRegistry.descriptor(toolID: "native-drc")?.trustProfile.level == .unknown)
        #expect(runtime.healthResults["native-drc"]?.status == .notChecked)
    }

    private func qualifiedToolSpec(level: ToolQualificationLevel) -> XcircuiteFlowToolSpec {
        QualifiedToolFixtures.toolSpec(level: level)
    }

    private func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }

    private func digestBoundInput(
        _ path: String,
        kind: ArtifactKind = .report,
        format: ArtifactFormat = .json
    ) throws -> XcircuiteFlowInputReference {
        .artifact(ArtifactReference(
            id: try ArtifactID(rawValue: "input-\(path.replacingOccurrences(of: "/", with: "-"))"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: String(repeating: "a", count: 64)),
            byteCount: 0
        ))
    }

}
