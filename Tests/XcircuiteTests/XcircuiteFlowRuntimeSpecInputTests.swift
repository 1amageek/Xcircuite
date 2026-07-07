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

    @Test func runtimeSpecDecodesDeprecatedSignoffKindsAndReencodesNativeKinds() throws {
        let legacyJSON = """
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

        let decoded = try JSONDecoder().decode(XcircuiteFlowRuntimeSpec.self, from: Data(legacyJSON.utf8))

        guard case .nativeDRC(let drc) = decoded.executors[0] else {
            Issue.record("Expected native DRC executor")
            return
        }
        guard case .nativeLVS(let lvs) = decoded.executors[1] else {
            Issue.record("Expected native LVS executor")
            return
        }
        #expect(drc.stageID == "007-drc")
        #expect(drc.layoutPath == "layout.json")
        #expect(lvs.stageID == "008-lvs")
        #expect(lvs.layoutGDSPath == "layout.gds")

        let encodedData = try JSONEncoder().encode(decoded)
        let encodedJSON = try #require(String(data: encodedData, encoding: .utf8))
        #expect(encodedJSON.contains("\"kind\":\"nativeDRC\""))
        #expect(encodedJSON.contains("\"kind\":\"nativeLVS\""))
        #expect(!encodedJSON.contains("pureSwift"))
    }

    @Test func stageArtifactInputReferenceRejectsDigestMismatch() async throws {
        let root = try makeTemporaryRoot("runtime-stage-artifact-digest")
        defer { removeTemporaryRoot(root) }
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        let runDirectory = try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try packageStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        try Data("tampered".utf8).write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try packageStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: String(repeating: "0", count: 64),
                        byteCount: Int64(Data("tampered".utf8).count),
                        producedByRunID: "run-1"
                    ),
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
                packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        let runDirectory = try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try packageStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try packageStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: 1,
                        producedByRunID: "run-1"
                    ),
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
                packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        let runDirectory = try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try packageStore.ensureDirectory(at: layoutRawDirectory)
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
                packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        let runDirectory = try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try packageStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "drc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/drc-layout.json"
        try writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                        producedByRunID: "run-1"
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
                projectRoot: root,
                runID: "run-1",
                runDirectory: runDirectory,
                packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        let runDirectory = try packageStore.createRunDirectory(for: "run-1", inProjectAt: root)
        let layoutRawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
            .appending(path: "raw")
        try packageStore.ensureDirectory(at: layoutRawDirectory)
        let layoutURL = layoutRawDirectory.appending(path: "notdrc-layout.json")
        let layoutData = Data("{}".utf8)
        try layoutData.write(to: layoutURL, options: [.atomic])
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/notdrc-layout.json"
        let layoutStageDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "006-layout")
        try packageStore.writeJSON(
            FlowStageResult(
                stageID: "006-layout",
                status: .succeeded,
                artifacts: [
                    XcircuiteFileReference(
                        artifactID: "not-drc-layout",
                        path: layoutPath,
                        kind: .layout,
                        format: .json,
                        sha256: XcircuiteHasher().sha256(data: layoutData),
                        byteCount: Int64(layoutData.count),
                        producedByRunID: "run-1"
                    ),
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
                packageStore: packageStore,
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
