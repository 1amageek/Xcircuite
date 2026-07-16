import Foundation
import LVSEngine
import Testing
import DesignFlowKernel
@testable import Xcircuite

@Suite("LVS stage artifact manifest coverage", .timeLimit(.minutes(1)))
struct LVSStageArtifactManifestCoverageGateBuilderTests {
    @Test func validCurrentArtifactFamilyPasses() async throws {
        let fixture = try makeFixture()
        defer { removeTemporaryRoot(fixture.root) }

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .passed, "Unexpected diagnostics: \(gate.diagnostics)")
        #expect(gate.diagnostics.isEmpty)
    }

    @Test func missingCorrespondenceFailsClosed() async throws {
        let fixture = try makeFixture(includeCorrespondence: false)
        defer { removeTemporaryRoot(fixture.root) }

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains {
            $0.code == "LVS_ARTIFACT_MANIFEST_REQUIRED_OUTPUT_INVALID"
        })
    }

    @Test func summaryReadinessMustMatchManifestLineage() async throws {
        let fixture = try makeFixture(summaryReadiness: .blocked)
        defer { removeTemporaryRoot(fixture.root) }

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains {
            $0.code == "LVS_SUMMARY_READINESS_LINEAGE_MISMATCH"
        })
    }

    @Test func indexedTransformLedgerMustBelongToManifest() async throws {
        var fixture = try makeFixture()
        defer { removeTemporaryRoot(fixture.root) }
        let ledgerURL = fixture.root
            .appending(path: ".xcircuite/runs/different-run/stages/008-lvs/raw")
            .appending(path: "lvs-transform-ledger.json")
        try FileManager.default.createDirectory(
            at: ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: ledgerURL, options: .atomic)
        fixture.artifacts.append(try StageArtifactReferenceBuilder().reference(
            for: ledgerURL,
            projectRoot: fixture.root,
            artifactID: "lvs-transform-ledger",
            kind: .report,
            format: .json,
        ))

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains {
            $0.code == "LVS_OPTIONAL_ARTIFACT_MANIFEST_LINEAGE_MISSING"
        })
    }

    @Test func retainedTransformLedgerMustShareRunLineage() async throws {
        var fixture = try makeFixture()
        defer { removeTemporaryRoot(fixture.root) }
        let ledgerURL = fixture.root
            .appending(path: ".xcircuite/runs/other-run/stages/008-lvs/raw")
            .appending(path: "lvs-transform-ledger.json")
        try FileManager.default.createDirectory(
            at: ledgerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: ledgerURL, options: .atomic)
        fixture.artifacts.append(try StageArtifactReferenceBuilder().reference(
            for: ledgerURL,
            projectRoot: fixture.root,
            artifactID: "lvs-transform-ledger",
            kind: .report,
            format: .json,
        ))
        let manifest = try JSONDecoder().decode(
            LVSArtifactManifest.self,
            from: Data(contentsOf: fixture.manifestURL)
        )
        let ledgerData = try Data(contentsOf: ledgerURL)
        let ledgerRecord = LVSArtifactRecord(
            id: "lvs-transform-ledger",
            kind: .report,
            path: ledgerURL.path(percentEncoded: false),
            byteCount: ledgerData.count,
            sha256: try fixtureSHA256(data: ledgerData)
        )
        let updatedManifest = LVSArtifactManifest(
            schemaVersion: manifest.schemaVersion,
            generatedAt: manifest.generatedAt,
            backendID: manifest.backendID,
            toolName: manifest.toolName,
            executionStatus: manifest.executionStatus,
            verdict: manifest.verdict,
            readiness: manifest.readiness,
            blockingReasons: manifest.blockingReasons,
            inputs: manifest.inputs,
            outputs: manifest.outputs + [ledgerRecord],
            diagnosticSummary: manifest.diagnosticSummary,
            waiverReport: manifest.waiverReport,
            devicePolicyReport: manifest.devicePolicyReport
        )
        try writeJSON(updatedManifest, to: fixture.manifestURL)

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains {
            $0.code == "LVS_OPTIONAL_ARTIFACT_RUN_LINEAGE_MISMATCH"
        })
    }

    @Test func indexedExtractedLayoutMustBelongToManifest() async throws {
        var fixture = try makeFixture()
        defer { removeTemporaryRoot(fixture.root) }
        let extractedURL = fixture.manifestURL.deletingLastPathComponent()
            .appending(path: "extracted-layout.spice")
        try Data(".subckt TOP\n.ends TOP\n".utf8).write(to: extractedURL, options: .atomic)
        fixture.artifacts.append(try StageArtifactReferenceBuilder().reference(
            for: extractedURL,
            projectRoot: fixture.root,
            kind: .netlist,
            format: .spice,
        ))

        let gate = StageArtifactManifestCoverageGateBuilder().lvsGate(
            manifestURL: fixture.manifestURL,
            artifacts: fixture.artifacts,
            projectRoot: fixture.root
        )

        #expect(gate.status == .failed)
        #expect(gate.diagnostics.contains {
            $0.code == "LVS_OPTIONAL_ARTIFACT_MANIFEST_LINEAGE_MISSING"
        })
    }

    private func makeFixture(
        includeCorrespondence: Bool = true,
        summaryReadiness: LVSReadinessStatus = .ready
    ) throws -> Fixture {
        let runID = "run-lvs-v2-coverage"
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-lvs-v2-coverage-\(UUID().uuidString)")
        let rawDirectory = root
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
            .appending(path: "stages")
            .appending(path: "008-lvs")
            .appending(path: "raw")
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)

        let reportURL = rawDirectory.appending(path: "lvs-report.json")
        let correspondenceURL = rawDirectory.appending(path: "lvs-correspondence.json")
        let manifestURL = rawDirectory.appending(path: "lvs-artifact-manifest.json")
        let summaryURL = rawDirectory.appending(path: "lvs-summary.json")
        try Data("{}".utf8).write(to: reportURL, options: .atomic)
        if includeCorrespondence {
            try Data("{}".utf8).write(to: correspondenceURL, options: .atomic)
        }

        var outputs = [
            try artifactRecord(id: "report", kind: .report, url: reportURL),
        ]
        if includeCorrespondence {
            outputs.append(try artifactRecord(
                id: "lvs-correspondence",
                kind: .correspondence,
                url: correspondenceURL
            ))
        }
        outputs.append(LVSArtifactRecord(
            id: "manifest",
            kind: .manifest,
            path: manifestURL.lastPathComponent,
            byteCount: nil,
            sha256: nil
        ))
        let manifest = LVSArtifactManifest(
            generatedAt: "2026-07-12T00:00:00Z",
            backendID: "native",
            toolName: "NativeLVS",
            executionStatus: .completed,
            verdict: .match,
            readiness: .ready,
            blockingReasons: [],
            inputs: [],
            outputs: outputs,
            diagnosticSummary: LVSDiagnosticSummary(
                infoCount: 0,
                warningCount: 0,
                errorCount: 0
            )
        )
        try writeJSON(manifest, to: manifestURL)

        let summary = LVSRunSummaryReport(
            reportURL: reportURL,
            manifestURL: manifestURL,
            summary: LVSRunSummary(
                executionStatus: .completed,
                verdict: .match,
                readiness: summaryReadiness,
                blockingReasons: [],
                backendID: "native",
                toolName: "NativeLVS",
                topCell: "TOP",
                layoutInputKind: "layout-netlist",
                diagnosticSummary: LVSDiagnosticSummary(
                    infoCount: 0,
                    warningCount: 0,
                    errorCount: 0
                ),
                activeMismatchCount: 0,
                waivedMismatchCount: 0,
                mismatchBuckets: [],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
        try writeJSON(summary, to: summaryURL)

        let artifactBuilder = StageArtifactReferenceBuilder()
        var artifacts = [
            try artifactBuilder.reference(
                for: reportURL,
                projectRoot: root,
                kind: .report,
                format: .json,
            ),
            try artifactBuilder.reference(
                for: manifestURL,
                projectRoot: root,
                kind: .report,
                format: .json,
            ),
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: root,
                artifactID: "lvs-summary",
                kind: .report,
                format: .json,
            ),
        ]
        if includeCorrespondence {
            artifacts.append(try artifactBuilder.reference(
                for: correspondenceURL,
                projectRoot: root,
                artifactID: "lvs-correspondence",
                kind: .report,
                format: .json,
            ))
        }
        return Fixture(
            root: root,
            runID: runID,
            manifestURL: manifestURL,
            artifacts: artifacts
        )
    }

    private func artifactRecord(
        id: String,
        kind: LVSArtifactRecord.Kind,
        url: URL
    ) throws -> LVSArtifactRecord {
        let data = try Data(contentsOf: url)
        return LVSArtifactRecord(
            id: id,
            kind: kind,
            path: url.lastPathComponent,
            byteCount: data.count,
            sha256: try fixtureSHA256(data: data)
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error.localizedDescription)")
        }
    }

    private struct Fixture {
        let root: URL
        let runID: String
        let manifestURL: URL
        var artifacts: [ArtifactReference]
    }
}
