import DesignFlowKernel
import Foundation
import Testing
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("xcircuite-flow agent loop", .timeLimit(.minutes(2)))
struct XcircuiteAgentLoopCLITests {
    @Test func evaluateRunGuardReportsMissingEvidence() async throws {
        let root = try makeTemporaryRoot("missing-evidence")
        defer { removeTemporaryRoot(root) }
        let runID = "run-xcircuite-agent-loop"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try store.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "action-1",
                runID: runID,
                actor: XcircuiteRunActionActor(kind: .agent, identifier: "external-agent"),
                actionKind: "layout.edit",
                status: .succeeded
            ),
            inProjectAt: root
        )
        let profile = XcircuiteAgentLoopProfile(
            profileID: "xcircuite-loop-profile",
            requiredEvidence: [
                XcircuiteAgentLoopProfile.RequiredEvidence(
                    evidenceID: "required-drc",
                    artifactRole: "drc-summary"
                ),
            ]
        )
        let profileURL = root.appending(path: "agent-loop-profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: profileURL, options: .atomic)

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-run-guard",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--profile",
            profileURL.path(percentEncoded: false),
        ])
        let data = try #require(output.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunGuardEvaluationResult.self, from: data)

        #expect(result.verdict.status == .needsHumanReview)
        #expect(result.verdict.triggeredDetectors.contains { $0.detectorID == "missingRequiredEvidence" })
    }

    @Test func compareArtifactsPersistsEvaluation() async throws {
        let root = try makeTemporaryRoot("compare-artifacts")
        defer { removeTemporaryRoot(root) }
        let runID = "run-xcircuite-compare-artifacts"
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.ensureRunDirectory(for: runID, inProjectAt: root)
        try writeSimulationSummaryEnvelope(root: root, runID: runID)

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "compare-artifacts",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--pretty",
        ])
        let data = try #require(output.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunCrossArtifactEvaluationResult.self, from: data)

        #expect(result.evaluation.status == .accepted)
        #expect(fileExists(".xcircuite/runs/\(runID)/reports/cross-artifact-evaluation.json", in: root))
    }

    @Test func writeOpAmpEvaluationProfileProducesDeveloperUsableProfile() async throws {
        let root = try makeTemporaryRoot("opamp-profile")
        defer { removeTemporaryRoot(root) }
        let profileURL = root.appending(path: "profiles/opamp-evaluation-profile.json")

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "write-opamp-evaluation-profile",
            "--out",
            profileURL.path(percentEncoded: false),
            "--profile-id",
            "opamp-profile-test",
            "--pretty",
        ])
        let outputData = try #require(output.data(using: .utf8))
        let outputProfile = try JSONDecoder().decode(XcircuiteEvaluationProfile.self, from: outputData)
        let fileProfile = try JSONDecoder().decode(
            XcircuiteEvaluationProfile.self,
            from: Data(contentsOf: profileURL)
        )

        #expect(outputProfile.profileID == "opamp-profile-test")
        #expect(fileProfile.metricChannels.contains { $0.channelID == "ac.dcGain" })
        #expect(fileProfile.requiredAnalyses.contains { $0.analysisID == "dc-operating-point" })
        #expect(fileProfile.artifactRoles.contains { $0.role == "simulation-summary" && $0.required })
    }

    private func writeSimulationSummaryEnvelope(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        let summaryPath = ".xcircuite/runs/\(runID)/evidence/simulation-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"status":"accepted"}"#.utf8).write(to: summaryURL, options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: summaryPath,
            artifactID: "simulation-summary",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID
        )
        let envelope = XcircuiteArtifactEnvelope(
            artifactID: "simulation-summary",
            role: "simulation-summary",
            reference: try foundationReference(reference),
            evaluationResult: XcircuiteEvaluationResult(
                evaluationID: "simulation-evaluation",
                specID: "opamp-spec",
                status: .accepted,
                channelResults: [
                    XcircuiteEvaluationChannelResult(
                        channelID: "gain",
                        status: .accepted,
                        observedValue: .number(60)
                    ),
                ],
                summary: "Simulation summary accepted."
            )
        )
        try store.writeArtifactEnvelope(envelope, runID: runID, inProjectAt: root)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteAgentLoopCLITests-\(name)-\(UUID().uuidString)")
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

    private func fileExists(_ relativePath: String, in root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: root.appending(path: relativePath).path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }
}
