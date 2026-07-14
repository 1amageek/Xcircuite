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
import DesignFlowKernel

extension XcircuiteFlowRuntimeTests {
    @Test func runtimeSpecRoundTripsRTLVerificationStageWithQualificationInput() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .rtlVerification(
                    XcircuiteFlowStageExecutorSpec.RTLVerification(
                        analysis: .lint,
                        rtlInput: .path("rtl/top.sv"),
                        qualificationInput: .path("qualification/rtl-input.json"),
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
        #expect(rtl.qualificationInput == .path("qualification/rtl-input.json"))
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-rtl-verification")
    }

    @Test func runtimeSpecRegistersAnIndependentRTLVerificationOracle() throws {
        let oracleToolID = "fixture-rtl-oracle"
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .rtlVerification(
                    XcircuiteFlowStageExecutorSpec.RTLVerification(
                        analysis: .lint,
                        rtlInput: .path("rtl/top.sv"),
                        topModuleName: "top",
                        oracleTool: RTLVerificationOracleToolSpec(
                            toolID: oracleToolID,
                            executablePath: "tools/rtl-oracle",
                            version: "1.0.0",
                            tool: QualifiedToolFixtures.toolSpec(level: .oracleChecked)
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()
        let runtime = try decoded.makeRuntime(
            projectRoot: FileManager.default.temporaryDirectory
                .appending(path: "rtl-oracle-runtime-\(UUID().uuidString)")
        )

        guard case .rtlVerification(let rtl) = try #require(decoded.executors.first) else {
            Issue.record("Expected RTL verification executor")
            return
        }
        #expect(rtl.oracleTool?.toolID == oracleToolID)
        #expect(runtime.toolRegistry.descriptor(toolID: oracleToolID)?.version == "1.0.0")
        #expect(runtime.healthResults[oracleToolID]?.status == .passed)
    }

    @Test func runtimeSpecRoundTripsElectricalRepairRevisionStage() throws {
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

    @Test func runtimeSpecRoundTripsElectricalSignoffStages() throws {
        let qualificationScope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: String(repeating: "b", count: 64)
        )
        let releaseRequestInput = try digestBoundInput("electrical/signoff-request.json")
        let releasePolicyInput = try digestBoundInput("electrical/release-policy.json")
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
                .electricalSignoffQualification(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffQualification(
                        specPath: "electrical/qualification-spec.json",
                        oraclePath: "electrical/oracle.json",
                        qualificationScope: qualificationScope
                    )
                ),
                .electricalSignoffReleaseGate(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffReleaseGate(
                        requestInput: releaseRequestInput,
                        runResultInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "electrical-signoff",
                                artifactID: "electrical-signoff-run-result",
                                kind: .report,
                                format: .json
                            )
                        ),
                        qualificationSpecInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "electrical-signoff.qualification",
                                artifactID: "electrical-signoff-qualification-spec",
                                kind: .report,
                                format: .json
                            )
                        ),
                        qualificationReportInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "electrical-signoff.qualification",
                                artifactID: "electrical-signoff-qualification-report",
                                kind: .report,
                                format: .json
                            )
                        ),
                        policyInput: releasePolicyInput,
                        processQualificationEvidenceInput: try digestBoundInput(
                            "electrical/process-qualification.json"
                        )
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .electricalStandardLayoutImport(let layout) = decoded.executors[0],
              case .electricalSignoff(let signoff) = decoded.executors[1],
              case .electricalSignoffQualification(let qualification) = decoded.executors[2],
              case .electricalSignoffReleaseGate(let releaseGate) = decoded.executors[3] else {
            Issue.record("Expected all electrical signoff runtime executors")
            return
        }
        #expect(layout.stageID == "electrical-signoff.standard-layout-import")
        #expect(signoff.axes == [.powerIntegrity, .erc])
        #expect(qualification.specPath == "electrical/qualification-spec.json")
        #expect(qualification.oraclePath == "electrical/oracle.json")
        #expect(releaseGate.requestInput == releaseRequestInput)
        #expect(releaseGate.policyInput == releasePolicyInput)
        #expect(releaseGate.processQualificationEvidenceInput == (try digestBoundInput("electrical/process-qualification.json")))
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-electrical-standard-layout-import")
        #expect(decoded.executors[1].makeDescriptor().toolID == "native-electrical-signoff")
        #expect(decoded.executors[2].makeDescriptor().toolID == "native-electrical-signoff-qualification")
        #expect(decoded.executors[3].makeDescriptor().toolID == "native-electrical-signoff-release-gate")
    }

    @Test func runtimeSpecRoundTripsElectricalProcessQualificationStage() throws {
        let requestInput = try digestBoundInput(
            "electrical/process-qualification-request.json",
            kind: .request,
            format: .json
        )
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalSignoffProcessQualification(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffProcessQualification(
                        requestInput: requestInput
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)
        try decoded.validate()

        guard case .electricalSignoffProcessQualification(let qualification) = decoded.executors[0] else {
            Issue.record("Expected electrical process qualification runtime executor")
            return
        }
        #expect(qualification.requestInput == requestInput)
        #expect(decoded.executors[0].makeDescriptor().toolID == "native-electrical-signoff-process-qualification")
    }

    @Test func runtimeCoverageRequiresHumanApprovalForElectricalProcessQualification() throws {
        let runtimeSpec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalSignoffProcessQualification(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffProcessQualification(
                        requestInput: try digestBoundInput(
                            "electrical/process-qualification-request.json",
                            kind: .request,
                            format: .json
                        )
                    )
                ),
            ]
        )
        let runSpec = XcircuiteFlowRunSpec(
            runID: "electrical-process-qualification-run",
            intent: "Validate process qualification approval governance.",
            stages: [FlowStageDefinition(
                stageID: "electrical-signoff.process-qualification",
                displayName: "Electrical process qualification",
                requiresApproval: false
            )]
        )

        do {
            try runtimeSpec.validateCoverage(for: runSpec)
            Issue.record("Expected human approval gate validation error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .electricalProcessQualificationRequiresApproval(
                "electrical-signoff.process-qualification"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsUnboundElectricalReleaseGateInputs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .electricalSignoffReleaseGate(
                    XcircuiteFlowStageExecutorSpec.ElectricalSignoffReleaseGate(
                        requestInput: .path("request.json"),
                        runResultInput: .path("run-result.json"),
                        qualificationSpecInput: .path("qualification-spec.json"),
                        qualificationReportInput: .path("qualification-report.json"),
                        policyInput: .path("policy.json")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected digest-bound release gate input validation error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingExecutorInput(
                stageID: "electrical-signoff.release-gate",
                field: "requestInput must be a digest-bound artifact or stageArtifact reference"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsUnboundElectricalStandardLayoutInputs() throws {
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

    @Test func runtimeSpecRoundTripsLogicSynthesisAndEquivalenceStages() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .logicSynthesis(
                    XcircuiteFlowStageExecutorSpec.LogicSynthesis(
                        requestPath: "runs/current/logic-synthesis-request.json"
                    )
                ),
                .logicEquivalence(
                    XcircuiteFlowStageExecutorSpec.LogicEquivalence(
                        requestPath: "runs/current/logic-equivalence-request.json"
                    )
                ),
                .logicQualification(
                    XcircuiteFlowStageExecutorSpec.LogicQualification(
                        reportPath: "qualification/logic-report.json",
                        processEvidencePath: "qualification/process-evidence.json",
                        releaseApprovalPath: "qualification/release-approval.json"
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
        guard case .logicQualification(let qualification) = decoded.executors[2] else {
            Issue.record("Expected logic qualification executor")
            return
        }
        #expect(qualification.stageID == "logic.qualification")
        #expect(decoded.executors[0].makeDescriptor().toolID == "logic-synthesis")
        #expect(decoded.executors[1].makeDescriptor().toolID == "native-rtl-verification")
        #expect(decoded.executors[2].makeDescriptor().toolID == "logic-qualification")
    }

    @Test func runtimeSpecRoundTripsLayoutCommandStandardExportsAndLVSInputs() throws {
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
        guard case .path(let terminalEquivalencePath) = try #require(lvs.terminalEquivalenceInput) else {
            Issue.record("Expected terminal equivalence path input")
            return
        }
        #expect(terminalEquivalencePath == "tech/lvs-terminal-equivalence.json")
    }

    @Test func runtimeSpecRoundTripsPEXStageArtifactInputs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
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
                        sourceNetlistInput: .path("circuits/top.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .input(.path("tech/pex.json"))
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: data)

        guard case .mockPEX(let pex) = try #require(decoded.executors.first) else {
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

    @Test func runtimeSpecRoundTripsPEXBackendExecutor() throws {
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
        let runtime = try decoded.makeRuntime(projectRoot: root)
        let descriptor = try #require(runtime.toolRegistry.descriptor(toolID: "pex-magic"))

        #expect(descriptor.kind == .pex)
        #expect(descriptor.trustProfile.level == .smokeChecked)
        #expect(descriptor.capabilities.contains { $0.operationID == "run-pex" })
        #expect(runtime.healthResults["pex-magic"]?.status == .passed)
    }

    @Test func runtimeSpecRoundTripsPEXCornerTechnologyOverrides() throws {
        let baseTechnology = makePEXTechnology()
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
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

    @Test func runtimeSpecRejectsPEXCornerTechnologyForUndeclaredCorner() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
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

    @Test func runtimeSpecRejectsQualifiedMockPEXExecutor() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        tool: qualifiedToolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected qualified mock PEX executor to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .mockExecutorCannotDeclareQualifiedTool(
                stageID: "009-pex",
                level: ToolQualificationLevel.smokeChecked.rawValue
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsPEXBackendExecutorWithMockBackend() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(backendID: "mock")
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected mock backend to be rejected by production PEX executor")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .mockPEXBackendNotAllowed(stageID: "009-pex", backendID: "mock"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsLVSWithoutLayoutInput() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        schematicNetlistPath: "circuits/top.spice",
                        topCell: "top"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing LVS layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingExecutorInput(
                stageID: "008-lvs",
                field: "layoutNetlistPath/layoutNetlistInput or layoutGDSPath/layoutGDSInput"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsConflictingLVSLayoutInputs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutNetlistPath: "layout/top.spice",
                        layoutGDSInput: .path("layout/top.gds"),
                        layoutFormat: .gds,
                        schematicNetlistPath: "circuits/top.spice",
                        topCell: "top"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected conflicting LVS layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .conflictingExecutorInputs(
                stageID: "008-lvs",
                fields: ["layoutNetlistPath", "layoutGDSInput"]
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsPEXWithoutLayoutInput() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology())
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing PEX layout input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingExecutorInput(stageID: "009-pex", field: "layoutPath or layoutInput"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsConflictingPEXSourceNetlistInputs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        sourceNetlistInput: .path("circuits/top.cdl"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology())
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected conflicting PEX source netlist input error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .conflictingExecutorInputs(
                stageID: "009-pex",
                fields: ["sourceNetlistPath", "sourceNetlistInput"]
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsPEXWithoutTechnologyOrToolchainProfile() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutPath: "layout/top.gds",
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/top.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")]
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

    @Test func runtimeSpecRoundTripsStageArtifactInputReference() throws {
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
        #expect(drc.layoutPath == nil)
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

    @Test func runtimeSpecRejectsRemovedSignoffKinds() throws {
        let removedKindJSON = """
        {
          "schemaVersion" : 1,
          "executors" : [
            {
              "kind" : "pureSwiftDRC",
              "value" : {
                "layoutPath" : "layout.json",
                "stageID" : "007-drc",
                "topCell" : "top",
                "tool" : {
                  "evidence" : [],
                  "healthStatus" : "passed",
                  "qualificationLevel" : "smokeChecked"
                }
              }
            },
            {
              "kind" : "pureSwiftLVS",
              "value" : {
                "layoutGDSPath" : "layout.gds",
                "schematicNetlistPath" : "top.spice",
                "stageID" : "008-lvs",
                "topCell" : "top",
                "tool" : {
                  "evidence" : [],
                  "healthStatus" : "passed",
                  "qualificationLevel" : "smokeChecked"
                }
              }
            }
          ]
        }
        """

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: Data(removedKindJSON.utf8))
        }
    }

    @Test func stageArtifactInputReferenceRejectsDigestMismatch() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-digest")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runDirectory = try workspaceStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        try Data("tampered".utf8).write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try workspaceStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try foundationReference(XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: String(repeating: "0", count: 64),
                        byteCount: Int64(Data("tampered".utf8).count),
                        producedByRunID: "run-1"
                    )),
                ]
            ),
            to: layoutStageDirectory.appending(path: "result.json"),
            forProjectAt: root
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                storage: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "DRC_EXECUTION_ERROR" && $0.message.contains("digest mismatch")
        })
    }

    @Test func stageArtifactInputReferenceRejectsByteCountMismatch() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-byte-count")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runDirectory = try workspaceStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try workspaceStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try foundationReference(XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: 1,
                        producedByRunID: "run-1"
                    )),
                ]
            ),
            to: layoutStageDirectory.appending(path: "result.json"),
            forProjectAt: root
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                storage: workspaceStore,
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
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runDirectory = try workspaceStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: layoutRawDirectory)
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                storage: workspaceStore,
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
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runDirectory = try workspaceStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        try writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try foundationReference(XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                        producedByRunID: "run-1"
                    )),
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                storage: workspaceStore,
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
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runDirectory = try workspaceStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "notdrc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/notdrc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try workspaceStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    try foundationReference(XcircuiteFileReference(
                        artifactID: "not-drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                        producedByRunID: "run-1"
                    )),
                ]
            ),
            to: layoutStageDirectory.appending(path: "result.json"),
            forProjectAt: root
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                storage: workspaceStore,
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

    @Test func runtimeSpecValidationRejectsDRCWithoutLayoutInput() throws {
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
            #expect(error == .missingExecutorInput(stageID: "007-drc", field: "layoutPath or layoutInput"))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRoundTripsStandardSignoffInputs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout/top.oas",
                        layoutFormat: .oasis,
                        topCell: "TOP",
                        technologyPath: "tech/process.json",
                        tool: XcircuiteFlowToolSpec(qualificationLevel: .productionEligible)
                    )
                ),
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSPath: "layout/top.gds",
                        layoutFormat: .gds,
                        schematicNetlistPath: "circuits/top.spice",
                        topCell: "TOP",
                        technologyPath: "tech/process.json",
                        tool: XcircuiteFlowToolSpec(qualificationLevel: .productionEligible)
                    )
                ),
                .postLayoutComparison(
                    XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
                        stageID: "030-compare",
                        preLayoutWaveformPath: "runs/pre.csv",
                        postLayoutWaveformPath: "runs/post.csv",
                        options: PostLayoutComparisonOptions(
                            requiredPostVariables: ["V(n1_pex)"],
                            oscillationLimits: [
                                PostLayoutOscillationLimit(
                                    variableName: "V(n1)",
                                    minimumPostAmplitude: 0.5
                                ),
                            ]
                        ),
                        tool: XcircuiteFlowToolSpec(qualificationLevel: .smokeChecked)
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
        #expect(drc.technologyPath == "tech/process.json")
        #expect(lvs.layoutGDSPath == "layout/top.gds")
        #expect(lvs.layoutFormat == .gds)
        #expect(lvs.technologyPath == "tech/process.json")
        #expect(comparison.options.requiredPostVariables == ["V(n1_pex)"])
    }

    @Test func runtimeSpecRoundTripsPostLayoutStageArtifactInputs() throws {
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
        #expect(comparison.preLayoutWaveformPath == nil)
        #expect(comparison.postLayoutWaveformPath == nil)
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

    @Test func runtimeSpecUsesDedicatedPostLayoutComparisonToolDescriptor() throws {
        let root = try makeTemporaryRoot("runtime-post-layout-comparison-tool")
        defer { removeTemporaryRoot(root) }
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .postLayoutComparison(
                    XcircuiteFlowStageExecutorSpec.PostLayoutComparison(
                        stageID: "030-compare",
                        preLayoutWaveformPath: "runs/pre.csv",
                        postLayoutWaveformPath: "runs/post.csv",
                        tool: qualifiedToolSpec(level: .productionEligible)
                    )
                ),
            ]
        )

        let runtime = try spec.makeRuntime(projectRoot: root)
        let descriptor = try #require(runtime.toolRegistry.descriptor(toolID: "post-layout-comparison"))

        #expect(descriptor.toolID == "post-layout-comparison")
        #expect(descriptor.kind == .simulation)
        #expect(descriptor.trustProfile.level == .productionEligible)
        #expect(descriptor.capabilities.contains { $0.operationID == "compare-waveforms" })
        #expect(runtime.toolRegistry.descriptor(toolID: "corespice") == nil)
        #expect(runtime.healthResults["post-layout-comparison"]?.status == .passed)
        #expect(runtime.healthResults["corespice"] == nil)
    }

    @Test func runtimeSpecRejectsSmokeQualificationWithoutEvidence() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout.json",
                        topCell: "TOP",
                        tool: XcircuiteFlowToolSpec(
                            qualificationLevel: .smokeChecked,
                            healthStatus: .passed
                        )
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected missing smoke evidence error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingToolQualificationEvidence(
                stageID: "007-drc",
                kind: "smoke",
                level: "smokeChecked"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsConflictingDescriptorForRepeatedToolID() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-a",
                        layoutPath: "layout-a.json",
                        topCell: "TOP"
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-b",
                        layoutPath: "layout-b.json",
                        topCell: "TOP",
                        tool: qualifiedToolSpec(level: .smokeChecked)
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected conflicting runtime tool descriptor error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .conflictingRuntimeToolDescriptor(
                toolID: "native-drc",
                stageIDs: ["007-drc-a", "007-drc-b"]
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecRejectsConflictingHealthForRepeatedToolID() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-a",
                        layoutPath: "layout-a.json",
                        topCell: "TOP"
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-b",
                        layoutPath: "layout-b.json",
                        topCell: "TOP",
                        tool: XcircuiteFlowToolSpec(
                            qualificationLevel: .unknown,
                            healthStatus: .failed
                        )
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected conflicting runtime tool health error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .conflictingRuntimeToolHealth(
                toolID: "native-drc",
                stageIDs: ["007-drc-a", "007-drc-b"]
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecAllowsRepeatedToolIDWithIdenticalToolDeclaration() throws {
        let root = try makeTemporaryRoot("runtime-repeated-tool")
        defer { removeTemporaryRoot(root) }
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-a",
                        layoutPath: "layout-a.json",
                        topCell: "TOP"
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc-b",
                        layoutPath: "layout-b.json",
                        topCell: "TOP"
                    )
                ),
            ]
        )

        try spec.validate()
        let runtime = try spec.makeRuntime(projectRoot: root)

        #expect(runtime.toolRegistry.descriptors.count == 1)
        #expect(runtime.toolRegistry.descriptor(toolID: "native-drc")?.trustProfile.level == .unknown)
        #expect(runtime.healthResults["native-drc"]?.status == .notChecked)
    }

    private func qualifiedToolSpec(level: ToolQualificationLevel) -> XcircuiteFlowToolSpec {
        XcircuiteFlowToolSpec(
            qualificationLevel: level,
            healthStatus: .passed,
            evidence: evidenceSupporting(level: level)
        )
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

    private func evidenceSupporting(level: ToolQualificationLevel) -> [ToolEvidence] {
        switch level {
        case .unknown:
            []
        case .smokeChecked:
            [qualifiedEvidence("smoke-1", kind: .smoke)]
        case .corpusChecked:
            [qualifiedEvidence("corpus-1", kind: .corpus)]
        case .oracleChecked:
            [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
            ]
        case .productionEligible:
            [
                qualifiedEvidence("corpus-1", kind: .corpus),
                qualifiedEvidence("oracle-1", kind: .oracle),
                qualifiedEvidence("production-approval-1", kind: .productionApproval),
            ]
        }
    }

    private func qualifiedEvidence(_ evidenceID: String, kind: ToolEvidenceKind) -> ToolEvidence {
        ToolEvidence(
            evidenceID: evidenceID,
            kind: kind,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: "unit-test-policy",
                observedMetrics: ["passRate": 1],
                observedCounts: ["caseCount": 1]
            )
        )
    }

}
