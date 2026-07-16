import DesignFlowKernel
import Foundation
import PDKKit
import PDKCore
import PDKDiscovery
import PDKStandardViews
import PDKValidation
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("PDK flow stage adapters")
struct PDKFlowStageExecutorTests {
    @Test("discovery adapter persists an envelope artifact")
    func discoveryPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-discovery-adapter")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)
        let context = try await makeContext(root: root, runID: "pdk-discovery-adapter")

        let result = try await PDKDiscoveryFlowStageExecutor.local(
            searchRoots: [.path("fixtures")],
            requiredProcessID: "fixture-180nm"
        ).execute(
            stage: FlowStageDefinition(stageID: "pdk.discover", displayName: "PDK discovery"),
            context: context
        )

        #expect(result.status == .succeeded, "Discovery diagnostics: \(result.diagnostics)")
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/pdk.discover/raw/pdk-result.json").path))
    }

    @Test("validation adapter preserves a blocked semantic result")
    func validationPreservesBlockedResult() async throws {
        let root = try makeRoot(name: "pdk-validation-adapter")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        try FileManager.default.removeItem(
            at: fixtureRoot.appending(path: "valid-pdk/models.spice")
        )
        let context = try await makeContext(root: root, runID: "pdk-validation-adapter")

        let result = try await PDKValidationFlowStageExecutor.local(
            manifestInput: .path(manifestURL.path)
        ).execute(
            stage: FlowStageDefinition(stageID: "pdk.validate", displayName: "PDK validation"),
            context: context
        )

        #expect(result.status == .blocked, "Validation diagnostics: \(result.diagnostics)")
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/pdk.validate/raw/pdk-result.json").path))
    }

    @Test("corpus adapter persists a retained corpus envelope")
    func corpusPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-corpus-adapter")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)
        let context = try await makeContext(root: root, runID: "pdk-corpus-adapter")

        let result = try await PDKCorpusValidationFlowStageExecutor.local(
            suiteInput: .path("fixtures/pdk-corpus.json"),
            rootInput: .path("fixtures")
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKKitAPI.corpusValidationStageID,
                displayName: "PDK retained corpus"
            ),
            context: context
        )

        #expect(result.status == .succeeded, "Corpus diagnostics: \(result.diagnostics)")
        #expect(result.gates.contains { $0.status == .passed })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/pdk.validate-corpus/raw/pdk-result.json").path))
    }

    @Test("standard view and oracle stages persist typed raw evidence")
    func standardOracleAndQualificationPersistArtifacts() async throws {
        let root = try makeRoot(name: "pdk-evidence-adapters")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)

        let standardContext = try await makeContext(root: root, runID: "pdk-standard-view-adapter")
        let standardResult = try await PDKStandardViewInspectionFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "cells",
            format: .lef
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKKitAPI.standardViewInspectionStageID,
                displayName: "PDK standard-view inspection"
            ),
            context: standardContext
        )
        #expect(standardResult.status == .succeeded, "Standard-view diagnostics: \(standardResult.diagnostics)")
        #expect(standardResult.artifacts.count == 1)

        let ruleDeckContext = try await makeContext(root: root, runID: "pdk-rule-deck-adapter")
        let ruleDeckResult = try await PDKRuleDeckInspectionFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "rules"
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKKitAPI.ruleDeckInspectionStageID,
                displayName: "PDK rule-deck inspection"
            ),
            context: ruleDeckContext
        )
        #expect(ruleDeckResult.status == .succeeded, "Rule-deck diagnostics: \(ruleDeckResult.diagnostics)")
        #expect(ruleDeckResult.artifacts.count == 1)
        let ruleDeckURL = try ruleDeckContext.xcircuiteRunDirectory()
            .appending(path: "stages")
            .appending(path: PDKKitAPI.ruleDeckInspectionStageID)
            .appending(path: "raw/pdk-result.json")
        let ruleDeckData = try Data(contentsOf: ruleDeckURL)
        let ruleDeckInspectionResult = try JSONDecoder().decode(
            PDKRuleDeckInspectionResult.self,
            from: ruleDeckData
        )
        #expect(ruleDeckInspectionResult.payload.observedLayerIDs == ["active", "metal1"])
        let sourceArtifact = try #require(ruleDeckInspectionResult.payload.sourceArtifact)
        #expect(sourceArtifact.byteCount > 0)
        #expect(sourceArtifact.locator.role == .input)

        let oracleContext = try await makeContext(root: root, runID: "pdk-oracle-adapter")
        let oracleResult = try await PDKOracleFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            oracleInput: .path("fixtures/standard-view-oracle.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKKitAPI.oracleComparisonStageID,
                displayName: "PDK oracle comparison"
            ),
            context: oracleContext
        )
        #expect(oracleResult.status == .succeeded, "Oracle diagnostics: \(oracleResult.diagnostics)")
        #expect(oracleResult.artifacts.count == 1)

    }

    @Test("PDK runtime specifications round-trip through the agent-facing contract")
    func runtimeSpecRoundTripsPDKAdapters() async throws {
        let specs: [XcircuiteFlowStageExecutorSpec] = [
            .pdkDiscovery(.init(searchRoots: [.path("fixtures")])),
            .pdkValidation(.init(manifestInput: .path("fixtures/valid-pdk/pdk.json"))),
            .pdkCorpus(.init(
                suiteInput: .path("fixtures/pdk-corpus.json"),
                rootInput: .path("fixtures")
            )),
            .pdkStandardView(.init(
                manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                assetID: "cells",
                format: .lef
            )),
            .pdkRuleDeck(.init(
                manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                assetID: "rules"
            )),
            .pdkOracle(.init(
                manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                oracleInput: .path("fixtures/standard-view-oracle.json")
            )),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for spec in specs {
            let data = try encoder.encode(spec)
            let decoded = try JSONDecoder().decode(
                XcircuiteFlowStageExecutorSpec.self,
                from: data
            )
            #expect(decoded == spec)
            try XcircuiteFlowRuntimeSpec(executors: [decoded]).validate()
        }
    }

    private func makeContext(root: URL, runID: String) async throws -> FlowExecutionContext {
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()
        _ = try await prepareTestRun(runID: runID, store: workspaceStore)
        let manifest = try await workspaceStore.loadManifest()
        return FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(name)-\(UUID().uuidString)")
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

    private func makeFixtureProject(root: URL) throws -> URL {
        let destination = root.appending(path: "fixtures")
        try PDKFixtureMaterializer.materialize(in: destination)
        return destination
    }

}
