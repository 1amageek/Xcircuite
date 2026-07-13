import DesignFlowKernel
import Foundation
import Testing
import ToolQualification
import Xcircuite
import DesignFlowKernel

@Suite("Timing headless flow")
struct TimingHeadlessFlowTests {
    @Test("STA stage persists a digest-bound raw result", .timeLimit(.minutes(1)))
    func staStagePersistsResult() async throws {
        let projectRoot = try makeProjectRoot(name: "timing-sta-headless")
        try writeSTAInputs(to: projectRoot)
        let context = try makeContext(projectRoot: projectRoot, runID: "sta-headless")
        let inputs = TimingSTAFlowInputs(
            design: .path("design.json"),
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
        let result = try await TimingSTAFlowStageExecutor(inputs: inputs).execute(
            stage: FlowStageDefinition(stageID: "timing.sta", displayName: "Timing STA"),
            context: context
        )
        #expect(result.status == .succeeded)
        #expect(result.gates.first?.status == .passed)
        #expect(result.artifacts.contains { $0.artifactID == "timing-sta-result" })
        #expect(result.artifacts.first { $0.artifactID == "timing-sta-result" }.map { fileExists($0, projectRoot: projectRoot) } == true)
    }

    @Test("Timing STA artifact is reviewable and survives approval resume", .timeLimit(.minutes(1)))
    func staArtifactSurvivesReviewAndResume() async throws {
        let projectRoot = try makeProjectRoot(name: "timing-review-resume")
        try writeSTAInputs(to: projectRoot)
        let runID = "timing-review-resume"
        let inputs = TimingSTAFlowInputs(
            design: .path("design.json"),
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
        let executor = TimingSTAFlowStageExecutor(inputs: inputs)

        let blocked = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: projectRoot,
                runID: runID,
                intent: "Run timing STA with human review",
                stages: [
                    FlowStageDefinition(
                        stageID: "timing.sta",
                        displayName: "Timing STA",
                        requiresApproval: true
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(blocked.status == .blocked)

        let bundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: projectRoot
        )
        let timingArtifact = try #require(bundle.artifacts.first {
            $0.stageID == "timing.sta"
                && $0.path.hasSuffix("stages/timing.sta/raw/timing-sta-result.json")
        })
        #expect(timingArtifact.integrity?.status == .verified)
        #expect(timingArtifact.sha256 != nil)
        #expect((timingArtifact.byteCount ?? 0) > 0)

        let approval = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: projectRoot,
                runID: runID,
                stageID: "timing.sta",
                verdict: .approved,
                reviewer: "timing-reviewer"
            )
        )
        #expect(approval.approval.stageID == "timing.sta")

        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: projectRoot, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(resumed.result.status == .succeeded)
        #expect(resumed.summary.approvalCount == 1)
        #expect(resumed.summary.stages.contains { stage in
            stage.stageID == "timing.sta"
                && stage.artifactCount > 0
        })

        let resumedBundle = try DefaultFlowRunReviewBundler().makeReviewBundle(
            runID: runID,
            projectRoot: projectRoot
        )
        #expect(resumedBundle.artifacts.contains {
            $0.stageID == "timing.sta"
                && $0.path.hasSuffix("stages/timing.sta/raw/timing-sta-result.json")
                && $0.integrity?.status == .verified
        })
    }

    @Test("SI stage persists a reviewable result and fails its gate on violations", .timeLimit(.minutes(1)))
    func signalIntegrityStagePersistsResult() async throws {
        let projectRoot = try makeProjectRoot(name: "timing-si-headless")
        try writeSTAInputs(to: projectRoot)
        try """
        *SPEF "IEEE 1481-1998"
        *CAP_UNIT 1 PF
        *RES_UNIT 1 OHM
        *D_NET victim 0.03
        *CONN
        *P victim O
        *CAP
        1 victim 0.01
        2 victim aggressor 0.02
        *RES
        1 victim aggressor 100
        *END
        """.write(to: projectRoot.appending(path: "positive.spef"), atomically: true, encoding: .utf8)
        let context = try makeContext(projectRoot: projectRoot, runID: "si-headless")
        let inputs = TimingSIFlowInputs(
            design: .path("design.json"),
            constraints: .path("constraints.sdc"),
            pdkManifest: .path("pdk.json"),
            parasitics: .path("positive.spef"),
            topDesignName: "top",
            processID: "fixture-process",
            pdkVersion: "1",
            pdkDigest: String(repeating: "0", count: 64),
            modeIDs: ["functional"],
            maxDeltaDelay: 1e-12
        )
        let result = try await TimingSIFlowStageExecutor(inputs: inputs).execute(
            stage: FlowStageDefinition(stageID: "timing.signal-integrity", displayName: "Signal integrity"),
            context: context
        )
        #expect(result.status == .succeeded)
        #expect(result.gates.first?.status == .failed)
        #expect(result.artifacts.contains { $0.artifactID == "timing-signal-integrity-result" })
    }

    private func makeProjectRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeContext(projectRoot: URL, runID: String) throws -> FlowExecutionContext {
        let packageStore = XcircuitePackageStore()
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        let runDirectory = projectRoot.appending(path: ".xcircuite/runs/\(runID)")
        try packageStore.ensureDirectory(at: runDirectory)
        return FlowExecutionContext(
            projectRoot: projectRoot,
            runID: runID,
            runDirectory: runDirectory,
            packageStore: packageStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func writeSTAInputs(to projectRoot: URL) throws {
        try """
        {"schemaVersion":1,"topDesignName":"top","ports":[{"name":"in","direction":"input"},{"name":"out","direction":"output"}],"instances":[{"name":"U1","cell":"INV","connections":{"A":"in","Y":"out"}}],"nets":[]}
        """.write(to: projectRoot.appending(path: "design.json"), atomically: true, encoding: .utf8)
        try """
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
        """.write(to: projectRoot.appending(path: "library.lib"), atomically: true, encoding: .utf8)
        try """
        create_clock -name clk -period 10ns [get_ports in]
        set_input_delay 1ns -clock clk [get_ports in]
        set_output_delay 2ns -clock clk [get_ports out]
        """.write(to: projectRoot.appending(path: "constraints.sdc"), atomically: true, encoding: .utf8)
        try "{}".write(to: projectRoot.appending(path: "pdk.json"), atomically: true, encoding: .utf8)
    }

    private func fileExists(_ reference: ArtifactReference, projectRoot: URL) -> Bool {
        let url = reference.path.hasPrefix("/") ? URL(filePath: reference.path) : projectRoot.appending(path: reference.path)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
