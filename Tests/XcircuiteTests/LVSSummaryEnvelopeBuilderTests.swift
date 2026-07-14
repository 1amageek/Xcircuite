import DesignFlowKernel
import Foundation
import LVSEngine
import Testing
import ToolQualification
@testable import Xcircuite
import DesignFlowKernel

@Suite("LVS summary envelope builder")
struct LVSSummaryEnvelopeBuilderTests {
    @Test func duplicateMismatchBucketsProduceUniqueFeedbackChannels() throws {
        let root = try makeTemporaryRoot("duplicate-lvs-buckets")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.createWorkspace(at: root)
        let runID = "run-lvs-envelope"
        let runDirectory = try workspaceStore.createRunDirectory(for: runID, inProjectAt: root)
        let rawDirectory = runDirectory
            .appending(path: "stages")
            .appending(path: "008-lvs")
            .appending(path: "raw")
        try workspaceStore.ensureDirectory(at: rawDirectory)

        let bucket = LVSMismatchBucketSummary(
            ruleID: "LVS_MODEL_MISMATCH",
            category: "model",
            componentSignature: "M",
            parameterName: nil,
            layoutModel: "nmos",
            schematicModel: "pmos",
            activeCount: 1,
            waivedCount: 0,
            layoutCount: nil,
            schematicCount: nil,
            layoutPorts: [],
            schematicPorts: [],
            suggestedFixes: ["repair-layout-or-schematic-mapping"]
        )
        let summary = LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                executionStatus: .completed,
                verdict: .mismatch,
                readiness: .ready,
                blockingReasons: [],
                backendID: "native",
                toolName: "SyntheticLVS",
                topCell: "TOP",
                layoutInputKind: "layout-netlist",
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 2),
                activeMismatchCount: 2,
                waivedMismatchCount: 0,
                mismatchBuckets: [bucket, bucket],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
        let summaryURL = rawDirectory.appending(path: "lvs-summary.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(to: summaryURL, options: .atomic)
        let summaryReference = try foundationReference(workspaceStore.fileReference(
            forProjectRelativePath: ".xcircuite/runs/\(runID)/stages/008-lvs/raw/lvs-summary.json",
            artifactID: "lvs-summary",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID
        ))

        let envelopeReference = try LVSSummaryEnvelopeBuilder().envelopeReference(
            summary: summary,
            summaryArtifactID: "lvs-summary",
            stageArtifacts: [summaryReference],
            gateStatus: .failed,
            diagnostics: [],
            stageID: "008-lvs",
            toolID: "native-lvs",
            context: FlowExecutionContext(
                projectRoot: root,
                runID: runID,
                runDirectory: runDirectory,
                workspaceStore: workspaceStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        let envelope = try JSONDecoder().decode(
            XcircuiteArtifactEnvelope.self,
            from: Data(contentsOf: root.appending(path: envelopeReference.path))
        )
        let feedbackSignals = try #require(envelope.evaluationResult?.feedbackSignals)
        let repairSignals = feedbackSignals.filter { $0.signalID.hasSuffix("-repair-feedback") }

        #expect(repairSignals.count == 2)
        #expect(Set(repairSignals.map { $0.signalID }).count == 2)
        #expect(Set(repairSignals.compactMap { $0.channelID }).count == 2)
        #expect(repairSignals.contains { $0.channelID == "lvs-mismatch-0-lvs-model-mismatch-active-count" })
        #expect(repairSignals.contains { $0.channelID == "lvs-mismatch-1-lvs-model-mismatch-active-count" })
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LVSSummaryEnvelopeBuilderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
