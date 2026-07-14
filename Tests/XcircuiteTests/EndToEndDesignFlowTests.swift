import DesignFlowKernel
import CircuiteFoundation
import DRCEngine
import Foundation
import LVSEngine
import LogicEngineCore
import LogicIR
import LogicLowering
import LogicSimulation
import PDKCore
import PEXEngine
import PhysicalDesignCore
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
        try XcircuiteWorkspaceStore().ensureWorkspaceDirectory(forProjectAt: root)

        let runID = "end-to-end-design-flow"
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(
            rtl: RTLDesign(
                topModuleName: "e2e_top",
                modules: [RTLModule(
                    id: "module-e2e-top",
                    name: "e2e_top",
                    ports: [
                        RTLPort(id: "a", name: "a", direction: .input),
                        RTLPort(id: "b", name: "b", direction: .input),
                        RTLPort(id: "y", name: "y", direction: .output),
                    ],
                    assignments: [RTLAssignment(
                        id: "assignment-y",
                        target: .identifier("y"),
                        value: .binary(
                            operator: "&&",
                            left: .identifier("a"),
                            right: .identifier("b")
                        )
                    )]
                )]
            )
        ))
        let snapshotReference = try writeJSON(
            snapshot,
            name: "rtl-snapshot.json",
            root: root,
            kind: .rtl
        )
        let snapshotRevision: ContentDigest?
        if let digest = snapshot.designDigest {
            snapshotRevision = try ContentDigest(algorithm: .sha256, hexadecimalValue: digest)
        } else {
            snapshotRevision = nil
        }
        let loweringRequest = LogicLoweringRequest(
            runID: runID,
            inputs: [snapshotReference],
            design: LogicFoundationDesignReference(
                artifact: snapshotReference,
                topDesignName: "e2e_top",
                designRevision: snapshotRevision
            )
        )
        let loweringRequestPath = try writeJSON(
            loweringRequest,
            name: "logic-lowering-request.json",
            root: root,
            kind: .other
        ).locator.location.value

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
        let simulationRequest = LogicSimulationRequest(
            runID: runID,
            inputs: [logicDesignReference, stimulusReference],
            design: LogicFoundationDesignReference(
                artifact: logicDesignReference,
                topDesignName: "e2e_top",
                designRevision: logicDesignReference.digest
            ),
            stimulus: stimulusReference,
            seed: 7
        )
        let simulationRequestPath = try writeJSON(
            simulationRequest,
            name: "logic-simulation-request.json",
            root: root,
            kind: .other
        ).locator.location.value

        try writeSTAInputs(to: root)
        let pdkReference = try writeJSON(
            ["processID": "fixture-process", "version": "1"],
            name: "pdk.json",
            root: root,
            kind: .technology
        )
        let constraintsLegacyReference = try XcircuiteWorkspaceStore().fileReference(
            forProjectRelativePath: "constraints.sdc",
            artifactID: "e2e-constraints",
            kind: .constraint,
            format: .sdc,
            inProjectAt: root
        )
        let constraintsReference = try foundationReference(constraintsLegacyReference)
        let physicalRequest = PhysicalDesignRequest(
            runID: runID,
            inputs: [logicDesignReference, constraintsReference, pdkReference],
            design: LogicDesignReference(
                artifact: logicDesignReference.locator,
                topDesignName: "e2e_top",
                designDigest: logicDesignReference.digest.hexadecimalValue
            ),
            constraints: TimingConstraintReference(
                artifact: constraintsReference,
                modeIDs: ["functional"]
            ),
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

        let drcLayoutURL = root.appending(path: "drc-layout.json")
        _ = try writeJSON(
            NativeDRCLayout(
                technologyID: "e2e-technology",
                topCell: "TOP",
                rectangles: [
                    NativeDRCRectangle(
                        id: "m1-a",
                        layer: "met1",
                        xMin: 0,
                        yMin: 0,
                        xMax: 1,
                        yMax: 1
                    ),
                    NativeDRCRectangle(
                        id: "m1-b",
                        layer: "met1",
                        xMin: 2,
                        yMin: 0,
                        xMax: 3,
                        yMax: 1
                    ),
                ],
                rules: [
                    NativeDRCRule(
                        id: "met1-width",
                        kind: .minimumWidth,
                        layer: "met1",
                        value: 0.5
                    ),
                    NativeDRCRule(
                        id: "met1-spacing",
                        kind: .minimumSpacing,
                        layer: "met1",
                        value: 0.5
                    ),
                ]
            ),
            name: "drc-layout.json",
            root: root,
            kind: .layout
        )
        let schematicNetlistURL = root.appending(path: "schematic.spice")
        let layoutNetlistURL = root.appending(path: "layout.spice")
        try writeText(matchingNetlist(), name: "schematic.spice", root: root)
        try writeText(matchingNetlist(), name: "layout.spice", root: root)
        let pexLayoutURL = root.appending(path: "pex-layout.gds")
        let pexNetlistURL = root.appending(path: "pex-source.spice")
        try writeText("layout", name: "pex-layout.gds", root: root)
        try writeText(".subckt TESTCELL\n.ends TESTCELL\n", name: "pex-source.spice", root: root)

        let staInputs = TimingSTAFlowInputs(
            design: .path("sta-design.json"),
            libraries: [.path("library.lib")],
            constraints: .path("constraints.sdc"),
            pdkManifest: .path("pdk.json"),
            topDesignName: "top",
            processID: "fixture-process",
            pdkVersion: "1",
            pdkDigest: String(repeating: "0", count: 64),
            modeIDs: ["functional"],
            cornerIDs: ["typical"],
            analysisKinds: [.setup]
        )
        let reviewManifestPath = "runs/\(runID)/physical-design/floorplan/run-manifest.json"
        let executors: [any FlowStageExecutor] = [
            LogicLoweringFlowStageExecutor(requestInput: .path(loweringRequestPath)),
            LogicSimulationFlowStageExecutor(requestInput: .path(simulationRequestPath)),
            TimingSTAFlowStageExecutor(inputs: staInputs),
            PhysicalDesignFlowStageExecutor.local(
                stageID: "physical.floorplan",
                requestInput: .path(physicalRequestPath)
            ),
            DRCFlowStageExecutor.native(
                stageID: "signoff.drc",
                layoutURL: drcLayoutURL,
                topCell: "TOP"
            ),
            LVSFlowStageExecutor.native(
                stageID: "signoff.lvs",
                layoutNetlistURL: layoutNetlistURL,
                schematicNetlistURL: schematicNetlistURL,
                topCell: "TOP"
            ),
            PEXFlowStageExecutor.mock(
                stageID: "signoff.pex",
                layoutURL: pexLayoutURL,
                layoutFormat: .gds,
                sourceNetlistURL: pexNetlistURL,
                topCell: "TESTCELL",
                corners: [
                    PEXCorner(id: PEXCornerID("tt"), name: "tt", temperature: 25),
                    PEXCorner(id: PEXCornerID("ss"), name: "ss", temperature: 125),
                ],
                technology: .inline(makeTestTechnology()),
                technologyByCorner: ["ss": .inline(makeTestTechnology())]
            ),
            PhysicalDesignReviewFlowStageExecutor(manifestInput: .path(reviewManifestPath)),
        ]
        let stages = [
            FlowStageDefinition(stageID: "logic.lower", displayName: "Logic lowering"),
            FlowStageDefinition(stageID: "logic.simulate", displayName: "Logic simulation"),
            FlowStageDefinition(stageID: "timing.sta", displayName: "Timing STA"),
            FlowStageDefinition(stageID: "physical.floorplan", displayName: "Physical floorplan"),
            FlowStageDefinition(stageID: "signoff.drc", displayName: "DRC"),
            FlowStageDefinition(stageID: "signoff.lvs", displayName: "LVS"),
            FlowStageDefinition(stageID: "signoff.pex", displayName: "PEX"),
            FlowStageDefinition(
                stageID: "physical.review",
                displayName: "Physical design review",
                requiresApproval: true
            ),
        ]

        let initial = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Execute a retained multi-engine design flow and request human review.",
                stages: stages
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        if initial.status != .blocked {
            for stage in initial.stages {
                Issue.record(
                    "Unexpected end-to-end stage result \(stage.stageID): status=\(stage.status.rawValue), diagnostics=\(stage.diagnostics.map(\.code).joined(separator: ","))"
                )
            }
        }

        #expect(initial.status == .blocked, "Initial multi-engine stages: \(initial.stages)")
        #expect(initial.stages.count == stages.count)
        #expect(initial.stages.dropLast().allSatisfy { $0.status == .succeeded })
        #expect(initial.stages.last?.status == .blocked)
        #expect(initial.stages.last?.artifacts.contains { $0.artifactID == "physical-design-review-packet" } == true)
        #expect(initial.stages.last?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)

        let reviewBundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: root
        )
        #expect(reviewBundle.artifacts.contains { $0.stageID == "logic.lower" })
        #expect(reviewBundle.artifacts.contains { $0.stageID == "logic.simulate" })
        #expect(reviewBundle.artifacts.contains { $0.stageID == "timing.sta" })
        #expect(reviewBundle.artifacts.contains { $0.stageID == "signoff.drc" && $0.artifactID == "drc-summary" })
        #expect(reviewBundle.artifacts.contains { $0.stageID == "signoff.lvs" && $0.artifactID == "lvs-summary" })
        #expect(reviewBundle.artifacts.contains { $0.stageID == "signoff.pex" && $0.artifactID == "pex-summary" })
        #expect(reviewBundle.artifacts.contains {
            $0.stageID == "physical.review"
                && $0.artifactID == "physical-design-review-packet"
                && $0.integrity?.status == .verified
        })
        #expect((reviewBundle.coverageRefs ?? []).contains {
            $0.domain == "approval" && $0.stageID == "physical.review"
        } == false)

        _ = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: runID,
                stageID: "physical.review",
                verdict: .approved,
                reviewer: "e2e-human-reviewer",
                note: "Reviewed the multi-engine artifact bundle and physical revision."
            )
        )
        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.result.stages.allSatisfy { $0.status == .succeeded })
        #expect(resumed.summary.approvalCount == 1)
        #expect(Set(resumed.summary.stages.map(\.stageID)) == Set(stages.map(\.stageID)))
        #expect(resumed.summary.stages.allSatisfy { $0.artifactCount > 0 })

        let retainedBundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: root
        )
        #expect(retainedBundle.status == .succeeded)
        #expect(retainedBundle.approvals.count == 1)
        #expect(retainedBundle.artifacts.contains {
            $0.role == "approval"
                && $0.stageID == "physical.review"
                && $0.integrity?.status == .verified
        })
        #expect(retainedBundle.artifacts.contains {
            $0.stageID == "physical.review"
                && $0.artifactID == "physical-design-review-packet"
                && $0.integrity?.status == .verified
        })
    }

    private func writeSTAInputs(to root: URL) throws {
        try writeText(
            """
            {"schemaVersion":1,"topDesignName":"top","ports":[{"name":"in","direction":"input"},{"name":"out","direction":"output"}],"instances":[{"name":"U1","cell":"INV","connections":{"A":"in","Y":"out"}}],"nets":[]}
            """,
            name: "sta-design.json",
            root: root
        )
        try writeText(
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
        try writeText(
            """
            create_clock -name clk -period 10ns [get_ports in]
            set_input_delay 1ns -clock clk [get_ports in]
            set_output_delay 2ns -clock clk [get_ports out]
            """,
            name: "constraints.sdc",
            root: root
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

    private func writeText(_ text: String, name: String, root: URL) throws {
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
