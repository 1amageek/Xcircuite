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

@Suite("PDK flow stage executors")
struct PDKFlowStageExecutorTests {
    @Test("discovery stage persists provenance through the run ledger")
    func discoveryPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-discovery-executor")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)
        let context = try await makeContext(root: root, runID: "pdk-discovery-executor")

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
        try await expectProducerLineage(
            in: result,
            as: PDKDiscoveryResult.self,
            context: context
        )
    }

    @Test("validation stage preserves a blocked result and its producer lineage")
    func validationPreservesBlockedResult() async throws {
        let root = try makeRoot(name: "pdk-validation-executor")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        try FileManager.default.removeItem(
            at: fixtureRoot.appending(path: "valid-pdk/models.spice")
        )
        let context = try await makeContext(root: root, runID: "pdk-validation-executor")

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
        try await expectProducerLineage(
            in: result,
            as: PDKValidationResult.self,
            context: context
        )
    }

    @Test("corpus stage persists retained evidence with producer lineage")
    func corpusPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-corpus-executor")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)
        let context = try await makeContext(root: root, runID: "pdk-corpus-executor")

        let result = try await PDKCorpusValidationFlowStageExecutor.local(
            suiteInput: .path("fixtures/pdk-corpus.json"),
            rootInput: .path("fixtures")
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKOperation.corpusValidation.rawValue,
                displayName: "PDK retained corpus"
            ),
            context: context
        )

        #expect(result.status == .succeeded, "Corpus diagnostics: \(result.diagnostics)")
        #expect(result.gates.contains { $0.status == .passed })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/pdk.validate-corpus/raw/pdk-result.json").path))
        try await expectProducerLineage(
            in: result,
            as: PDKCorpusValidationResult.self,
            context: context
        )
    }

    @Test("standard view, rule-deck, and oracle stages persist typed producer lineage")
    func standardViewRuleDeckAndOraclePersistProducerLineage() async throws {
        let root = try makeRoot(name: "pdk-evidence-executors")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)

        let standardContext = try await makeContext(root: root, runID: "pdk-standard-view-executor")
        let standardResult = try await PDKStandardViewInspectionFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "cells",
            format: .lef
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKOperation.standardViewInspection.rawValue,
                displayName: "PDK standard-view inspection"
            ),
            context: standardContext
        )
        #expect(standardResult.status == .succeeded, "Standard-view diagnostics: \(standardResult.diagnostics)")
        #expect(standardResult.artifacts.count == 1)
        try await expectProducerLineage(
            in: standardResult,
            as: PDKManifestViewInspectionResult.self,
            context: standardContext
        )

        let ruleDeckContext = try await makeContext(root: root, runID: "pdk-rule-deck-executor")
        let ruleDeckResult = try await PDKRuleDeckInspectionFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            assetID: "rules"
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKOperation.ruleDeckInspection.rawValue,
                displayName: "PDK rule-deck inspection"
            ),
            context: ruleDeckContext
        )
        #expect(ruleDeckResult.status == .succeeded, "Rule-deck diagnostics: \(ruleDeckResult.diagnostics)")
        #expect(ruleDeckResult.artifacts.count == 1)
        try await expectProducerLineage(
            in: ruleDeckResult,
            as: PDKRuleDeckInspectionResult.self,
            context: ruleDeckContext
        )
        let ruleDeckURL = try ruleDeckContext.xcircuiteRunDirectory()
            .appending(path: "stages")
            .appending(path: PDKOperation.ruleDeckInspection.rawValue)
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

        let oracleContext = try await makeContext(root: root, runID: "pdk-oracle-executor")
        let oracleResult = try await PDKOracleFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            oracleInput: .path("fixtures/standard-view-oracle.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKOperation.oracleComparison.rawValue,
                displayName: "PDK oracle comparison"
            ),
            context: oracleContext
        )
        #expect(oracleResult.status == .succeeded, "Oracle diagnostics: \(oracleResult.diagnostics)")
        #expect(oracleResult.artifacts.count == 1)
        try await expectProducerLineage(
            in: oracleResult,
            as: PDKOracleComparisonResult.self,
            context: oracleContext
        )

    }

    @Test("PDK runtime specifications round-trip through the agent-facing contract")
    func runtimeSpecRoundTripsPDKExecutors() async throws {
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

    private func expectProducerLineage<Result: Decodable & PDKStageExecutionResult>(
        in stageResult: FlowStageResult,
        as resultType: Result.Type,
        context: FlowExecutionContext
    ) async throws {
        let resultArtifact = try #require(stageResult.artifacts.first {
            $0.locator.location.value.hasSuffix("/pdk-result.json")
        })
        let store = try XcircuiteWorkspaceStore(
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let persistedResult = try JSONDecoder().decode(
            resultType,
            from: try await store.loadArtifactContent(for: resultArtifact)
        )
        let expectedProducer = persistedResult.provenance.producer
        let ledger = try await store.loadRunLedger(runID: context.runID)
        let manifest = try await store.loadRunManifest(runID: context.runID)

        #expect(resultArtifact.producer == expectedProducer)
        #expect(ledger.artifacts.first { $0.locator == resultArtifact.locator } == resultArtifact)
        #expect(manifest.artifacts.first { $0.locator == resultArtifact.locator } == resultArtifact)
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
