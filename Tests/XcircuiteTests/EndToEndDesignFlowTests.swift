import DesignFlowKernel
import CircuiteFoundation
import DRCEngine
import Foundation
import LVSEngine
import LayoutIO
import LayoutTech
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import PDKCore
import PEXEngine
import PhysicalDesignCore
import STAEngine
import Testing
import TimingCore
import ToolQualification
@testable import Xcircuite

@Suite("End-to-end design flow")
struct EndToEndDesignFlowTests {
    @Test("retains a multi-engine run through human review and same-run resume", .timeLimit(.minutes(2)))
    func retainedMultiEngineRunResumesAfterReview() async throws {
        let root = try makeRoot(name: "end-to-end-design-flow")
        defer { removeRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        let manifest = try await workspaceStore.loadManifest()
        let workspaceID = try FlowWorkspaceID(rawValue: manifest.identity.projectID)
        let progressStore = FlowRunProgressStore(persistence: workspaceStore)
        let orchestrator = DefaultFlowOrchestrator(
            infrastructure: workspaceStore,
            ledgerPersistence: workspaceStore,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "XcircuiteTests",
                version: "1.0.0"
            ),
            progressStore: progressStore
        )
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        let ledgerInspector = DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler)

        let runID = "end-to-end-design-flow"
        try await writeText(
            "module e2e_top(input logic a, input logic b, output logic y); assign y = a && b; endmodule",
            name: "e2e-top.sv",
            root: root
        )

        let logicDocument = LogicDesignDocument(
            topDesignName: "e2e_top",
            ports: [
                LogicPort(name: "a", direction: .input),
                LogicPort(name: "b", direction: .input),
                LogicPort(name: "y", direction: .output),
            ],
            signals: [
                LogicSignal(name: "a"),
                LogicSignal(name: "b"),
                LogicSignal(name: "y"),
            ],
            nodes: [LogicNode(id: "and0", kind: .and, inputs: ["a", "b"], outputs: ["y"])]
        )
        let logicDesignReference = try writeJSON(
            logicDocument,
            name: "logic-design.json",
            root: root,
            kind: .netlist
        )
        let stimulus = LogicStimulusDocument(
            events: [LogicStimulusEvent(
                time: 0,
                assignments: [
                    "a": try LogicVector(string: "1"),
                    "b": try LogicVector(string: "1"),
                ]
            )],
            assertions: [LogicAssertion(
                id: "y-is-high",
                time: 0,
                signal: "y",
                expected: try LogicVector(string: "1")
            )]
        )
        let stimulusReference = try writeJSON(
            stimulus,
            name: "stimulus.json",
            root: root,
            kind: .testPattern
        )
        try await writeSTAInputs(to: root)
        try await writeStandardLayoutTechnology(root: root)
        let lvsExtraction = try writeStandardLVSExtractionArtifacts(to: root)
        let pdkReference = try writeJSON(
            ["processID": "fixture-process", "version": "1"],
            name: "pdk.json",
            root: root,
            kind: .technology
        )
        let storedConstraintsReference = try await XcircuiteWorkspaceStore(projectRoot: root).makeArtifactReference(
            forProjectRelativePath: "constraints.sdc",
            artifactID: "e2e-constraints",
            kind: .constraint,
            format: .sdc,
        )
        let constraintsReference = storedConstraintsReference
        let physicalRequest = PhysicalDesignRequest(
            runID: runID,
            inputs: [logicDesignReference, constraintsReference, pdkReference],
            design: LogicIR.LogicDesignReference(
                artifact: logicDesignReference,
                topDesignName: "e2e_top",
                designDigest: logicDesignReference.digest.hexadecimalValue
            ),
            constraints: constraintsReference,
            requestedModeIDs: ["functional"],
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture-process",
                version: "1",
                digest: pdkReference.digest.hexadecimalValue
            ),
            stage: .floorplan,
            initialSnapshot: PhysicalDesignSnapshot(
                topCell: "e2e_top",
                cells: [PhysicalDesignSnapshot.Cell(id: "U1", master: "AND2_X1")]
            )
        )
        let physicalRequestPath = try writeJSON(
            physicalRequest,
            name: "physical-design-request.json",
            root: root,
            kind: .other
        ).locator.location.value

        try await writeText(layoutCommandRequest(), name: "layout-command-request.json", root: root)
        try await writeText(matchingNetlist(), name: "schematic.spice", root: root)

        let staInputs = TimingSTAFlowInputs(
            design: .path("sta-design.json"),
            libraries: [.path("library.lib")],
            constraints: .path("constraints.sdc"),
            pdkManifest: .path("pdk.json"),
            parasitics: .stageArtifact(.init(
                stageID: "signoff.pex",
                kind: .parasitics,
                format: .spef,
                pathSuffix: "tt.spef"
            )),
            topDesignName: "top",
            processID: "fixture-process",
            pdkVersion: "1",
            pdkDigest: pdkReference.digest.hexadecimalValue,
            modeIDs: ["functional"],
            cornerIDs: ["typical"],
            analysisKinds: [.setup],
            requiresPostLayoutInputs: true
        )
        let reviewManifestPath = "runs/\(runID)/physical-design/floorplan/run-manifest.json"
        let executors: [any FlowStageExecutor] = [
            LogicElaborationFlowStageExecutor(
                sourceInput: .path("e2e-top.sv"),
                topDesignName: "e2e_top"
            ),
            LogicLoweringFlowStageExecutor(
                designInput: .stageArtifact(.init(
                    stageID: "logic.elaborate",
                    artifactID: "logic-design",
                    kind: .rtl,
                    format: .json
                )),
                topDesignName: "e2e_top"
            ),
            LogicSimulationFlowStageExecutor(
                designInput: .stageArtifact(.init(
                    stageID: "logic.lower",
                    artifactID: "logic-execution-design",
                    kind: .netlist,
                    format: .json
                )),
                pdkInput: .artifact(pdkReference),
                topDesignName: "e2e_top",
                stimulusInput: .artifact(stimulusReference),
                seed: 7
            ),
            LayoutCommandFlowStageExecutor(
                stageID: "physical.layout",
                requestURL: root.appending(path: "layout-command-request.json"),
                drcExport: LayoutCommandDRCExportSpec(
                    technologyID: "e2e-technology",
                    topCell: "top",
                    rules: [
                        NativeDRCRule(
                            id: "M1.width",
                            kind: .minimumWidth,
                            layer: "M1",
                            value: 0.5
                        ),
                    ]
                ),
                standardLayoutExports: [
                    LayoutCommandStandardLayoutExportSpec(
                        artifactID: "layout-gds",
                        format: .gds,
                        technologyInput: .path("tech/process.json")
                    ),
                ]
            ),
            PhysicalDesignFlowStageExecutor.local(
                stageID: "physical.floorplan",
                requestInput: .path(physicalRequestPath),
                designInput: .stageArtifact(.init(
                    stageID: "logic.lower",
                    artifactID: "logic-execution-design",
                    kind: .netlist,
                    format: .json
                )),
                constraintsInput: .artifact(constraintsReference),
                pdkInput: .artifact(pdkReference)
            ),
            DRCFlowStageExecutor.native(
                stageID: "signoff.drc",
                layoutInput: .stageArtifact(.init(
                    stageID: "physical.layout",
                    artifactID: "drc-layout",
                    kind: .layout,
                    format: .json
                )),
                topCell: "top"
            ),
            LVSFlowStageExecutor.native(
                stageID: "signoff.lvs",
                layoutGDSInput: .stageArtifact(.init(
                    stageID: "physical.layout",
                    artifactID: "layout-gds",
                    kind: .layout,
                    format: .gdsii
                )),
                layoutFormat: .gds,
                schematicNetlistInput: .path("schematic.spice"),
                topCell: "top",
                technologyInput: .path("tech/process.json"),
                extractionProfileInput: .path(lvsExtraction.profilePath),
                extractionDeckInput: .path(lvsExtraction.deckPath),
                processProfileID: lvsExtraction.processProfileID
            ),
            PEXFlowStageExecutor(
                stageID: "signoff.pex",
                toolID: SignoffToolDescriptors.pexToolID(backendID: "test-fixture"),
                layoutInput: .stageArtifact(.init(
                    stageID: "physical.layout",
                    artifactID: "layout-gds",
                    kind: .layout,
                    format: .gdsii
                )),
                layoutFormat: .gds,
                sourceNetlistInput: .path("schematic.spice"),
                topCell: "top",
                corners: [
                    PEXCorner(id: PEXCornerID("tt"), name: "tt", temperature: 25),
                    PEXCorner(id: PEXCornerID("ss"), name: "ss", temperature: 125),
                ],
                technology: .inline(makeTestTechnology()),
                technologyByCorner: ["ss": .inline(makeTestTechnology())],
                backendSelection: PEXBackendSelection(backendID: "test-fixture"),
                engine: makeFixturePEXEngine()
            ),
            TimingSTAFlowStageExecutor(inputs: staInputs),
            PhysicalDesignReviewFlowStageExecutor(manifestInput: .path(reviewManifestPath)),
        ]
        let stages = [
            FlowStageDefinition(stageID: "logic.elaborate", displayName: "Logic elaboration"),
            FlowStageDefinition(stageID: "logic.lower", displayName: "Logic lowering"),
            FlowStageDefinition(stageID: "logic.simulate", displayName: "Logic simulation"),
            FlowStageDefinition(stageID: "physical.layout", displayName: "Physical layout materialization"),
            FlowStageDefinition(stageID: "physical.floorplan", displayName: "Physical floorplan"),
            FlowStageDefinition(stageID: "signoff.drc", displayName: "DRC"),
            FlowStageDefinition(stageID: "signoff.lvs", displayName: "LVS"),
            FlowStageDefinition(stageID: "signoff.pex", displayName: "PEX"),
            FlowStageDefinition(stageID: "timing.sta", displayName: "Post-layout timing STA"),
            FlowStageDefinition(
                stageID: "physical.review",
                displayName: "Physical design review",
                requiresApproval: true
            ),
        ]

        let initial = try await orchestrator.run(
            request: FlowOperationRequest(
                workspaceID: workspaceID,
                runID: runID,
                intent: "Execute a retained multi-engine design flow and request human review.",
                stages: stages
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        if initial.stages.count != stages.count {
            let stageSummaries: [String] = initial.stages.map { stage in
                let diagnostics = stage.diagnostics
                    .map { "\($0.code):\($0.message)" }
                    .joined(separator: ",")
                return "\(stage.stageID)[\(stage.status.rawValue)]:\(diagnostics)"
            }
            Issue.record(Comment(rawValue: stageSummaries.joined(separator: " | ")))
        }
        #expect(initial.status == .blocked, "Initial multi-engine stages: \(initial.stages)")
        #expect(initial.stages.count == stages.count)
        #expect(initial.stages.dropLast().allSatisfy { $0.status == .succeeded })
        #expect(initial.stages.last?.status == .blocked)
        #expect(initial.stages.last?.artifacts.contains { $0.artifactID == "physical-design-review-packet" } == true)
        #expect(initial.stages.last?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)

        let reviewBundle = try await reviewBundler.makeReviewBundle(
            runID: runID,
            workspaceID: workspaceID
        )
        let elaboratedDesign = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "logic.elaborate" && $0.reference.artifactID == "logic-design"
        }))
        let loweredDesign = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "logic.lower" && $0.reference.artifactID == "logic-execution-design"
        }))
        let loweringResultReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "logic.lower" && $0.reference.artifactID == "logic-lowering-result"
        })?.reference)
        let loweringResult = try JSONDecoder().decode(
            LogicLoweringResult.self,
            from: Data(contentsOf: root.appending(path: loweringResultReference.path))
        )
        #expect(loweringResult.provenance.inputs.contains(elaboratedDesign.reference))
        let simulationResultReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "logic.simulate" && $0.reference.artifactID == "logic-simulation-result"
        })?.reference)
        let simulationResult = try JSONDecoder().decode(
            LogicSimulationResult.self,
            from: Data(contentsOf: root.appending(path: simulationResultReference.path))
        )
        #expect(simulationResult.provenance.inputs.contains(loweredDesign.reference))
        #expect(reviewBundle.artifacts.first(where: { $0.stageID == "timing.sta" }) != nil)
        let producedDRCLayout = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "physical.layout" && $0.reference.artifactID == "drc-layout"
        }))
        let producedGDSLayout = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "physical.layout" && $0.reference.artifactID == "layout-gds"
        }))
        #expect(producedDRCLayout.integrity?.status == .verified)
        #expect(producedGDSLayout.integrity?.status == .verified)
        let physicalRequestReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "physical.floorplan"
                && $0.reference.artifactID == "physical.floorplan-request"
        })?.reference)
        let retainedPhysicalRequest = try JSONDecoder().decode(
            PhysicalDesignRequest.self,
            from: Data(contentsOf: root.appending(path: physicalRequestReference.path))
        )
        #expect(retainedPhysicalRequest.design.artifact == loweredDesign.reference)
        #expect(retainedPhysicalRequest.inputLayout == nil)
        #expect(retainedPhysicalRequest.initialSnapshot?.topCell == "e2e_top")
        #expect(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.drc" && $0.reference.artifactID == "drc-summary"
        }) != nil)
        let drcManifestReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.drc"
                && $0.reference.path.contains("drc-artifact-manifest-")
                && $0.reference.path.hasSuffix(".json")
        })?.reference)
        let drcManifest = try JSONDecoder().decode(
            DRCArtifactManifest.self,
            from: Data(contentsOf: root.appending(path: drcManifestReference.path))
        )
        #expect(drcManifest.inputs.contains {
            $0.kind == .layout
                && $0.sha256 == producedDRCLayout.reference.digest.hexadecimalValue
        })
        #expect(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.lvs" && $0.reference.artifactID == "lvs-summary"
        }) != nil)
        let lvsExecutionReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.lvs" && $0.reference.artifactID == "lvs-execution-result"
        })?.reference)
        let lvsExecution = try JSONDecoder().decode(
            LVSExecutionResult.self,
            from: Data(contentsOf: root.appending(path: lvsExecutionReference.path))
        )
        #expect(lvsExecution.provenance.inputs.contains(producedGDSLayout.reference))
        #expect(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.pex" && $0.reference.artifactID == "pex-summary"
        }) != nil)
        let pexExecutionReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "signoff.pex" && $0.reference.artifactID == "pex-run-result"
        })?.reference)
        let pexExecution = try JSONDecoder().decode(
            PEXRunResult.self,
            from: Data(contentsOf: root.appending(path: pexExecutionReference.path))
        )
        #expect(pexExecution.provenance.inputs.contains(producedGDSLayout.reference))
        let pexTimingArtifactCandidate = reviewBundle.artifacts.first { artifact in
            guard artifact.stageID == "signoff.pex" else { return false }
            guard artifact.reference.kind == .parasitics else { return false }
            guard artifact.reference.format == .spef else { return false }
            return artifact.reference.path.hasSuffix("tt.spef")
        }
        let pexTimingArtifact = try #require(pexTimingArtifactCandidate)
        let timingExecutionReference = try #require(reviewBundle.artifacts.first(where: {
            $0.stageID == "timing.sta" && $0.reference.artifactID == "timing-sta-result"
        })?.reference)
        let timingExecution = try JSONDecoder().decode(
            STAExecutionResult.self,
            from: Data(contentsOf: root.appending(path: timingExecutionReference.path))
        )
        #expect(timingExecution.evidence.provenance.inputs.contains(pexTimingArtifact.reference))
        #expect(reviewBundle.artifacts.first(where: {
            $0.stageID == "physical.review"
                && $0.reference.artifactID == "physical-design-review-packet"
                && $0.integrity?.status == .verified
        }) != nil)
        #expect((reviewBundle.coverageRefs ?? []).contains {
            $0.domain == "approval" && $0.stageID == "physical.review"
        } == false)

        _ = try await DefaultFlowGateApprovalRecorder(
            loader: workspaceStore,
            inspector: ledgerInspector,
            approvalPersistence: workspaceStore,
            artifactLocationValidator: DefaultFlowRunArtifactLocationValidator(storagePrefix: ".xcircuite")
        ).recordApproval(
            FlowGateApprovalRequest(
                workspaceID: workspaceID,
                runID: runID,
                stageID: "physical.review",
                verdict: .approved,
                reviewer: "e2e-human-reviewer",
                note: "Reviewed the multi-engine artifact bundle and physical revision."
            )
        )
        let resumed = try await DefaultFlowRunResumer(
            loader: workspaceStore,
            orchestrator: orchestrator,
            inspector: ledgerInspector,
            artifactPersistence: workspaceStore,
            artifactLocationValidator: DefaultFlowRunArtifactLocationValidator(storagePrefix: ".xcircuite")
        ).resumeRun(
            request: FlowRunResumeRequest(workspaceID: workspaceID, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.result.stages.allSatisfy { $0.status == .succeeded })
        #expect(resumed.summary.approvalCount == 1)
        #expect(Set(resumed.summary.stages.map(\.stageID)) == Set(stages.map(\.stageID)))
        #expect(resumed.summary.stages.allSatisfy { $0.artifactCount > 0 })

        let retainedBundle = try await reviewBundler.makeReviewBundle(
            runID: runID,
            workspaceID: workspaceID
        )
        #expect(retainedBundle.status == .succeeded)
        #expect(retainedBundle.approvals.count == 1)
        #expect(retainedBundle.decisionActions?.contains {
            $0.decisionKind == .approval
                && $0.stageID == "physical.review"
                && $0.status == .succeeded
        } == true)
        #expect(retainedBundle.coverageRefs?.contains {
            $0.domain == "approval"
                && $0.stageID == "physical.review"
                && $0.role == "approval-record"
        } == true)
        #expect(retainedBundle.artifacts.first(where: {
            $0.stageID == "physical.review"
                && $0.reference.artifactID == "physical-design-review-packet"
                && $0.integrity?.status == .verified
        }) != nil)
    }

    private func writeSTAInputs(to root: URL) async throws {
        try await writeText(
            """
            {"schemaVersion":1,"topDesignName":"top","ports":[{"name":"in","direction":"input"},{"name":"out","direction":"output"}],"instances":[{"name":"U1","cell":"INV","connections":{"A":"in","Y":"out"}}],"nets":[]}
            """,
            name: "sta-design.json",
            root: root
        )
        try await writeText(
            """
            library (fixture) {
              time_unit : "1ns";
              capacitive_load_unit (1, pf);
              cell (INV) {
                pin (A) { direction : input; capacitance : 0.01; }
                pin (Y) {
                  direction : output;
                  timing () {
                    related_pin : "A";
                    timing_sense : negative_unate;
                    cell_rise (t) { index_1 ("0.1"); index_2 ("0.0"); values ("1.0"); }
                    cell_fall (t) { index_1 ("0.1"); index_2 ("0.0"); values ("1.0"); }
                  }
                }
              }
            }
            """,
            name: "library.lib",
            root: root
        )
        try await writeText(
            """
            create_clock -name clk -period 10ns [get_ports in]
            set_input_delay 1ns -clock clk [get_ports in]
            set_output_delay 2ns -clock clk [get_ports out]
            """,
            name: "constraints.sdc",
            root: root
        )
    }

    private func writeStandardLayoutTechnology(root: URL) async throws {
        let url = root.appending(path: "tech/process.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(LayoutTechDatabase.standard()).write(
            to: url,
            options: [.atomic]
        )
    }

    private func matchingNetlist() -> String {
        """
        .subckt top
        .ends top
        """
    }

    private func layoutCommandRequest() -> String {
        """
        {
          "artifactManifestPath" : "ignored/manifest.json",
          "commands" : [
            {
              "createCell" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "makeTop" : true,
                "name" : "top"
              },
              "kind" : "createCell"
            },
            {
              "addNet" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "name" : "out",
                "netID" : "20000000-0000-0000-0000-000000000002"
              },
              "kind" : "addNet"
            },
            {
              "addRect" : {
                "cellID" : "20000000-0000-0000-0000-000000000001",
                "layer" : { "name" : "M1", "purpose" : "drawing" },
                "netID" : "20000000-0000-0000-0000-000000000002",
                "origin" : { "x" : 0, "y" : 0 },
                "properties" : { "role" : "wire" },
                "shapeID" : "20000000-0000-0000-0000-000000000003",
                "size" : { "height" : 2, "width" : 10 }
              },
              "kind" : "addRect"
            }
          ],
          "documentID" : "20000000-0000-0000-0000-000000000000",
          "documentName" : "flow-layout",
          "outputDocumentPath" : "ignored/layout.json",
          "resultPath" : "ignored/result.json",
          "schemaVersion" : 1
        }
        """
    }

    private func makeTestTechnology() -> TechnologyIR {
        TechnologyIR(
            processName: "e2e-process",
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

    private func writeJSON<Value: Encodable>(
        _ value: Value,
        name: String,
        root: URL,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(
            to: root.appending(path: name),
            options: .atomic
        )
        let data = try Data(contentsOf: root.appending(path: name))
        let locator = try ArtifactLocator(
            location: ArtifactLocation(workspaceRelativePath: name),
            role: .input,
            kind: kind,
            format: .json
        )
        return ArtifactReference(
            id: try ArtifactID(rawValue: name.replacingOccurrences(of: ".json", with: "")),
            locator: locator,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func writeText(_ text: String, name: String, root: URL) async throws {
        try Data(text.utf8).write(to: root.appending(path: name), options: .atomic)
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
