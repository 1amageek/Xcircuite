import DesignFlowKernel
import CircuiteFoundation
import ElectricalSignoffEngine
import Foundation
import LogicIR
import PDKCore
import PhysicalDesignCore
import Testing
import TimingCore
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("Electrical signoff repair revision")
struct ElectricalSignoffRepairRevisionFlowStageExecutorTests {
    @Test("selected repair candidate produces a new digest-bound physical revision", .timeLimit(.minutes(1)))
    func appliesSelectedCandidateAsImmutableRevision() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-repair-revision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-repair-revision-run"
        let store = XcircuitePackageStore()
        let snapshot = PhysicalDesignSnapshot(
            topCell: "top",
            die: PhysicalDesignSnapshot.Rect(x: 0, y: 0, width: 100_000, height: 100_000),
            core: PhysicalDesignSnapshot.Rect(x: 10_000, y: 10_000, width: 80_000, height: 80_000),
            rows: [PhysicalDesignSnapshot.Row(id: "row-0", originX: 10_000, originY: 10_000, siteWidth: 100, height: 1_000, siteCount: 800)],
            cells: [PhysicalDesignSnapshot.Cell(id: "U1", master: "INV_X1", x: 20_000, y: 10_000, width: 1_000, height: 1_000, placed: true)],
            pins: [PhysicalDesignSnapshot.Pin(id: "P1", cellID: "U1", name: "Y", x: 20_000, y: 10_000, netID: "N1", direction: "output")],
            nets: [PhysicalDesignSnapshot.Net(id: "N1", pinIDs: ["P1"])]
        )
        let snapshotData = try PhysicalDesignJSONCodec().encode(snapshot)
        let layoutPath = ".xcircuite/input/layout.json"
        let layoutURL = try store.url(forProjectRelativePath: layoutPath, inProjectAt: root)
        try store.ensureDirectory(at: layoutURL.deletingLastPathComponent())
        try snapshotData.write(to: layoutURL)
        let layoutDigest = try SHA256ContentDigester().digest(data: snapshotData).hexadecimalValue
        let layoutReference = XcircuiteFileReference(
            artifactID: "base-layout",
            path: layoutPath,
            kind: .layout,
            format: .json,
            sha256: layoutDigest,
            byteCount: Int64(snapshotData.count)
        )
        let plan = ElectricalSignoffRepairPlan(
            runID: runID,
            designDigest: "design-digest",
            layoutDigest: layoutDigest,
            pdkDigest: String(repeating: "c", count: 64),
            candidates: [ElectricalSignoffRepairPlan.Candidate(
                candidateID: "repair-1",
                axis: .erc,
                cornerID: "typical",
                kind: "electrical-eco",
                entity: "U1",
                rationale: "Resize the selected device in a new revision.",
                actions: ["resize_cell"]
            )],
            sourceArtifactIDs: ["electrical-signoff-run-result"]
        )
        let planData = try JSONEncoder().encode(plan)
        let planPath = ".xcircuite/repair-plan.json"
        let planURL = try store.url(forProjectRelativePath: planPath, inProjectAt: root)
        try planData.write(to: planURL)
        let planReference = XcircuiteFileReference(
            artifactID: "electrical-signoff-repair-plan",
            path: planPath,
            kind: .report,
            format: .json,
            sha256: try SHA256ContentDigester().digest(data: planData).hexadecimalValue,
            byteCount: Int64(planData.count)
        )
        let designReference = try makeFoundationReference(
            id: "design-input",
            path: "design.json",
            kind: .netlist,
            format: .json,
            digest: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let constraintReference = try makeFoundationReference(
            id: "constraint-input",
            path: "constraints.sdc",
            kind: .constraint,
            format: .sdc,
            digest: String(repeating: "b", count: 64),
            byteCount: 1
        )
        let pdkReference = try makeFoundationReference(
            id: "pdk-input",
            path: "pdk.json",
            kind: .technology,
            format: .json,
            digest: String(repeating: "c", count: 64),
            byteCount: 1
        )
        let layoutFoundationReference = try FoundationFlowProjection.artifactReference(from: layoutReference)
        let physicalRequest = PhysicalDesignRequest(
            runID: runID,
            inputs: [],
            design: LogicDesignReference(
                artifact: designReference.locator,
                topDesignName: "top",
                designDigest: "design-digest"
            ),
            constraints: TimingConstraintReference(
                artifact: constraintReference,
                modeIDs: ["functional"]
            ),
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture",
                version: "1",
                digest: pdkReference.sha256
            ),
            inputLayout: PhysicalDesignReference(
                layoutArtifact: layoutFoundationReference,
                topCell: "top",
                layoutDigest: layoutDigest
            ),
            stage: .timingECO,
            configuration: PhysicalDesignConfiguration(
                ecoAction: .resizeCell,
                ecoTargetCellID: "U1"
            )
        )
        let request = XcircuiteElectricalRepairRevisionRequest(
            runID: runID,
            repairPlanArtifact: planReference,
            selectedCandidateID: "repair-1",
            physicalDesignRequest: physicalRequest
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: ".xcircuite/runs/\(runID)"),
            packageStore: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let executor = ElectricalSignoffRepairRevisionFlowStageExecutor(request: request)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.repair-revision", displayName: "Electrical repair revision"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        let wrapperReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-repair-revision" })
        let wrapperURL = try store.url(forProjectRelativePath: wrapperReference.path, inProjectAt: root)
        let persisted = try JSONDecoder().decode(XcircuiteElectricalRepairRevisionResult.self, from: Data(contentsOf: wrapperURL))
        #expect(persisted.committedNewRevision)
        #expect(persisted.rerunRequired)
        #expect(persisted.digestLineage.parentLayoutDigest == layoutDigest)
        #expect(persisted.digestLineage.newLayoutDigest != layoutDigest)
    }
}

private func makeFoundationReference(
    id: String,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    digest: String,
    byteCount: UInt64
) throws -> ArtifactReference {
    ArtifactReference(
        id: try ArtifactID(rawValue: id),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: kind,
            format: format
        ),
        digest: try ContentDigest(algorithm: .sha256, hexadecimalValue: digest),
        byteCount: byteCount
    )
}
