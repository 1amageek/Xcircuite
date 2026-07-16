import Foundation
import Testing
import ToolQualification
@testable import Xcircuite
import XcircuiteFlowCLISupport

/// `scaffold-run` is the authoring entry point for flow specs: it
/// writes a run-spec + runtime-config pair that decodes through the real
/// spec types, passes `validate` unchanged, keeps the mock PEX stage at
/// the runtime's mock contract and never fabricates qualification evidence.
@Suite("xcircuite-flow scaffold-run", .timeLimit(.minutes(3)))
struct XcircuiteFlowScaffoldRunCLITests {

    private struct ScaffoldRunSummary: Decodable {
        var status: String
        var runID: String
        var runSpecPath: String
        var runtimeConfigPath: String
        var stageIDs: [String]
        var placeholderPaths: [String]
        var nextActions: [String]
    }

    private struct ValidationSummary: Decodable {
        var status: String
        var validated: [String]
        var runStageCount: Int?
        var runtimeExecutorCount: Int?
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-scaffold-run-tests")
            .appending(path: "\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    @Test
    func scaffoldRunWritesSpecPairThatValidatesUnchanged() async throws {
        let root = try makeTemporaryRoot("default-stages")
        defer { removeTemporaryRoot(root) }
        let runSpecURL = root.appending(path: "run.json")
        let runtimeConfigURL = root.appending(path: "runtime.json")

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "scaffold-run",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "scaffold-run-001",
            "--out-run-spec", runSpecURL.path(percentEncoded: false),
            "--out-runtime-config", runtimeConfigURL.path(percentEncoded: false),
            "--pretty",
        ])
        let summaryData = try #require(output.data(using: .utf8))
        let summary = try JSONDecoder().decode(ScaffoldRunSummary.self, from: summaryData)
        #expect(summary.status == "scaffolded")
        #expect(summary.runID == "scaffold-run-001")
        #expect(summary.stageIDs == [
            "001-core-spice-simulation",
            "002-mock-pex",
            "003-post-layout-comparison",
        ])
        #expect(!summary.placeholderPaths.isEmpty)
        #expect(summary.nextActions.contains { $0.contains("xcircuite-flow validate") })

        // The written files decode through the REAL spec types and cover
        // each other.
        let runSpec = try XcircuiteFlowRunSpec.load(from: runSpecURL)
        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
        try runtimeSpec.validateCoverage(for: runSpec)
        #expect(runSpec.stages.count == 3)
        #expect(runtimeSpec.executors.count == 3)
        #expect(runSpec.stages.allSatisfy { $0.requiresApproval == false })

        // A scaffold cannot claim qualification that has not been performed.
        let simulationStage = try #require(
            runSpec.stages.first { $0.stageID == "001-core-spice-simulation" }
        )
        let simulationRequirement = try #require(simulationStage.requiredTool)
        #expect(simulationRequirement.minimumLevel == .unknown)
        #expect(simulationRequirement.requiredQualifiedEvidenceKinds.isEmpty)

        // The `validate` subcommand accepts the pair unchanged.
        let validateOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate",
            "--project-root", root.path(percentEncoded: false),
            "--run-spec", runSpecURL.path(percentEncoded: false),
            "--runtime-config", runtimeConfigURL.path(percentEncoded: false),
        ])
        let validateData = try #require(validateOutput.data(using: .utf8))
        let validation = try JSONDecoder().decode(ValidationSummary.self, from: validateData)
        #expect(validation.status == "valid")
        #expect(validation.validated.contains("coverage"))
        #expect(validation.runStageCount == 3)
        #expect(validation.runtimeExecutorCount == 3)
    }

    @Test
    func scaffoldedMockPEXStageKeepsMockContract() async throws {
        let root = try makeTemporaryRoot("mock-contract")
        defer { removeTemporaryRoot(root) }
        let runSpecURL = root.appending(path: "run.json")
        let runtimeConfigURL = root.appending(path: "runtime.json")

        _ = try await XcircuiteFlowCLICommand.run(arguments: [
            "scaffold-run",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "scaffold-run-mock",
            "--out-run-spec", runSpecURL.path(percentEncoded: false),
            "--out-runtime-config", runtimeConfigURL.path(percentEncoded: false),
        ])

        let runSpec = try XcircuiteFlowRunSpec.load(from: runSpecURL)
        let mockStage = try #require(runSpec.stages.first { $0.stageID == "002-mock-pex" })
        let mockRequirement = try #require(mockStage.requiredTool)
        #expect(mockRequirement.minimumLevel == .unknown)
        #expect(mockRequirement.requiredQualifiedEvidenceKinds.isEmpty)
        #expect(mockRequirement.kind == .pex)
        #expect(mockRequirement.operationID == "run-pex")

        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
        let mockExecutor = try #require(runtimeSpec.executors.first { executor in
            if case .mockPEX = executor {
                return true
            }
            return false
        })
        guard case .mockPEX(let mockSpec) = mockExecutor else {
            Issue.record("Expected a mockPEX executor")
            return
        }
        #expect(mockSpec.tool.qualificationLevel == .unknown)
        #expect(mockSpec.tool.evidence.isEmpty)
    }

    @Test
    func scaffoldDoesNotFabricateQualificationEvidence() async throws {
        let root = try makeTemporaryRoot("qualification-evidence")
        defer { removeTemporaryRoot(root) }
        let runSpecURL = root.appending(path: "run.json")
        let runtimeConfigURL = root.appending(path: "runtime.json")

        _ = try await XcircuiteFlowCLICommand.run(arguments: [
            "scaffold-run",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "scaffold-run-clock",
            "--out-run-spec", runSpecURL.path(percentEncoded: false),
            "--out-runtime-config", runtimeConfigURL.path(percentEncoded: false),
        ])

        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
        for executor in runtimeSpec.executors {
            let descriptor = executor.makeDescriptor()
            #expect(descriptor.trustProfile.level == .unknown)
            #expect(executor.makeHealthResult().evidence.isEmpty)
        }
    }

    @Test
    func scaffoldRunHonorsStageSelectionOrder() async throws {
        let root = try makeTemporaryRoot("stage-selection")
        defer { removeTemporaryRoot(root) }
        let runSpecURL = root.appending(path: "run.json")
        let runtimeConfigURL = root.appending(path: "runtime.json")

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "scaffold-run",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "scaffold-run-subset",
            "--out-run-spec", runSpecURL.path(percentEncoded: false),
            "--out-runtime-config", runtimeConfigURL.path(percentEncoded: false),
            "--stage", "coreSpiceSimulation,postLayoutComparison",
        ])
        let summaryData = try #require(output.data(using: .utf8))
        let summary = try JSONDecoder().decode(ScaffoldRunSummary.self, from: summaryData)
        #expect(summary.stageIDs == [
            "001-core-spice-simulation",
            "002-post-layout-comparison",
        ])

        let runSpec = try XcircuiteFlowRunSpec.load(from: runSpecURL)
        let runtimeSpec = try XcircuiteFlowRuntimeSpec.load(from: runtimeConfigURL)
        try runtimeSpec.validateCoverage(for: runSpec)
        #expect(runSpec.stages.count == 2)
    }

    @Test
    func scaffoldRunRejectsUnknownStageKind() async throws {
        let root = try makeTemporaryRoot("unknown-stage")
        defer { removeTemporaryRoot(root) }

        await #expect(throws: XcircuiteFlowCLIError.self) {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "scaffold-run",
                "--run-id", "scaffold-run-bad",
                "--out-run-spec", root.appending(path: "run.json").path(percentEncoded: false),
                "--out-runtime-config", root.appending(path: "runtime.json").path(percentEncoded: false),
                "--stage", "nativeDRC",
            ])
        }
    }

    @Test
    func validateReportsMissingRunSpecKeyWithJSONPath() async throws {
        let root = try makeTemporaryRoot("missing-run-spec-key")
        defer { removeTemporaryRoot(root) }
        let runSpecURL = root.appending(path: "run.json")
        let runtimeConfigURL = root.appending(path: "runtime.json")

        _ = try await XcircuiteFlowCLICommand.run(arguments: [
            "scaffold-run",
            "--project-root", root.path(percentEncoded: false),
            "--run-id", "scaffold-run-invalid",
            "--out-run-spec", runSpecURL.path(percentEncoded: false),
            "--out-runtime-config", runtimeConfigURL.path(percentEncoded: false),
        ])

        let data = try Data(contentsOf: runSpecURL)
        var document = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var stages = try #require(document["stages"] as? [[String: Any]])
        stages[0].removeValue(forKey: "retryPolicy")
        document["stages"] = stages
        let malformedData = try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
        try malformedData.write(to: runSpecURL, options: .atomic)

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "validate",
                "--run-spec", runSpecURL.path(percentEncoded: false),
                "--runtime-config", runtimeConfigURL.path(percentEncoded: false),
            ])
            Issue.record("Expected validate to reject a run spec without retryPolicy.")
        } catch let error as XcircuiteFlowCLIError {
            guard case .readFailed(let reason) = error else {
                Issue.record("Expected readFailed, got \(error).")
                return
            }
            #expect(reason.contains("Invalid JSON for --run-spec"))
            #expect(reason.contains("Missing key 'retryPolicy'"))
            #expect(reason.contains("stages.Index 0"))
        }
    }

    @Test
    func scaffoldRunRequiresOutputPaths() async throws {
        await #expect(throws: XcircuiteFlowCLIError.self) {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "scaffold-run",
                "--run-id", "scaffold-run-missing",
            ])
        }
    }
}
