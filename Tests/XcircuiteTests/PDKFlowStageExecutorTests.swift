import DesignFlowKernel
import Foundation
import PDKKit
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("PDK flow stage adapters")
struct PDKFlowStageExecutorTests {
    @Test("discovery adapter persists an envelope artifact")
    func discoveryPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-discovery-adapter")
        defer { removeRoot(root) }
        let pdkRoot = root.appending(path: "pdk")
        try FileManager.default.createDirectory(at: pdkRoot, withIntermediateDirectories: true)
        try Data("{\"processID\":\"adapter-process\",\"version\":\"1\"}".utf8)
            .write(to: pdkRoot.appending(path: "pdk.json"), options: [.atomic])
        let context = try makeContext(root: root, runID: "pdk-discovery-adapter")

        let result = try await PDKDiscoveryFlowStageExecutor.local(
            searchRoots: [.path(pdkRoot.path)],
            requiredProcessID: "adapter-process"
        ).execute(
            stage: FlowStageDefinition(stageID: "pdk.discover", displayName: "PDK discovery"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/pdk.discover/raw/pdk-result.json").path))
    }

    @Test("validation adapter preserves a blocked semantic result")
    func validationPreservesBlockedResult() async throws {
        let root = try makeRoot(name: "pdk-validation-adapter")
        defer { removeRoot(root) }
        let pdkRoot = root.appending(path: "pdk")
        try FileManager.default.createDirectory(at: pdkRoot, withIntermediateDirectories: true)
        let manifestURL = pdkRoot.appending(path: "pdk.json")
        try Data("{\"processID\":\"adapter-process\",\"version\":\"1\"}".utf8)
            .write(to: manifestURL, options: [.atomic])
        let context = try makeContext(root: root, runID: "pdk-validation-adapter")

        let result = try await PDKValidationFlowStageExecutor.local(
            manifestInput: .path(manifestURL.path)
        ).execute(
            stage: FlowStageDefinition(stageID: "pdk.validate", displayName: "PDK validation"),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/pdk.validate/raw/pdk-result.json").path))
    }

    @Test("corpus adapter persists a retained corpus envelope")
    func corpusPersistsArtifact() async throws {
        let root = try makeRoot(name: "pdk-corpus-adapter")
        defer { removeRoot(root) }
        _ = try makeFixtureProject(root: root)
        let context = try makeContext(root: root, runID: "pdk-corpus-adapter")

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

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.status == .passed })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/pdk.validate-corpus/raw/pdk-result.json").path))
    }

    @Test("standard view, oracle, and qualification adapters persist typed envelopes")
    func standardOracleAndQualificationPersistArtifacts() async throws {
        let root = try makeRoot(name: "pdk-evidence-adapters")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        try writeQualificationReports(root: root, fixtureRoot: fixtureRoot)

        let standardContext = try makeContext(root: root, runID: "pdk-standard-view-adapter")
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
        #expect(standardResult.status == .succeeded)
        #expect(standardResult.artifacts.count == 1)

        let ruleDeckContext = try makeContext(root: root, runID: "pdk-rule-deck-adapter")
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
        #expect(ruleDeckResult.status == .succeeded)
        #expect(ruleDeckResult.artifacts.count == 1)
        let ruleDeckURL = ruleDeckContext.runDirectory
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

        let oracleContext = try makeContext(root: root, runID: "pdk-oracle-adapter")
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
        #expect(oracleResult.status == .succeeded)
        #expect(oracleResult.artifacts.count == 1)

        let qualificationContext = try makeContext(root: root, runID: "pdk-qualification-adapter")
        let qualificationResult = try await PDKQualificationFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            corpusInput: .path("corpus-report.json"),
            oracleInput: .path("oracle-report.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: PDKKitAPI.qualificationStageID,
                displayName: "PDK local qualification"
            ),
            context: qualificationContext
        )
        #expect(qualificationResult.status == .succeeded)
        #expect(qualificationResult.artifacts.count == 1)

        let rawURL = qualificationContext.runDirectory
            .appending(path: "stages")
            .appending(path: PDKKitAPI.qualificationStageID)
            .appending(path: "raw/pdk-result.json")
        let rawData = try Data(contentsOf: rawURL)
        let result = try JSONDecoder().decode(
            PDKQualificationExecutionResult.self,
            from: rawData
        )
        #expect(result.payload.state == .oracleCorrelated)
    }

    @Test("qualification trust scope blocks mismatched evidence and resumes after approval")
    func qualificationScopeAndResumeAreAuditable() async throws {
        let root = try makeRoot(name: "pdk-qualification-resume")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        try writeQualificationReports(root: root, fixtureRoot: fixtureRoot)

        let scope = QualifiedToolFixtures.qualificationScope(toolID: "pdk-qualification")
        let descriptor = makeQualifiedDescriptor()
        try QualifiedToolFixtures.materializeEvidence(for: [descriptor], in: root)
        let executor = PDKQualificationFlowStageExecutor.local(
            manifestInput: .path("fixtures/valid-pdk/pdk.json"),
            corpusInput: .path("corpus-report.json"),
            oracleInput: .path("oracle-report.json")
        )
        let stage = FlowStageDefinition(
            stageID: PDKKitAPI.qualificationStageID,
            displayName: "PDK qualification",
            requiredTool: ToolTrustRequirement(
                kind: .reporting,
                operationID: "pdk-qualify",
                minimumLevel: .oracleChecked,
                requiredInputFormats: [.json],
                requiredOutputFormats: [.json],
                qualificationScope: scope
            ),
            requiresApproval: true
        )
        let runtime = XcircuiteFlowRuntime(
            descriptors: [descriptor],
            healthResults: [
                descriptor.toolID: QualifiedToolFixtures.health(
                    toolID: descriptor.toolID,
                    level: .oracleChecked
                ),
            ],
            executors: [executor],
            workspaceStore: try XcircuiteWorkspaceStore(projectRoot: root)
        )
        let request = FlowOperationRequest(
            projectRoot: root,
            runID: "pdk-qualification-resume",
            intent: "Execute and review PDK qualification evidence.",
            stages: [stage]
        )
        let first = try await runtime.run(request: request)
        #expect(first.status == .blocked)
        #expect(first.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)
        #expect(first.stages.first?.artifacts.isEmpty == false)

        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        let approval = try await DefaultFlowGateApprovalRecorder(
            loader: workspaceStore,
            inspector: DefaultFlowRunLedgerInspector(reviewBundler: reviewBundler),
            ledgerPersistence: workspaceStore
        ).recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: request.runID,
                stageID: stage.stageID,
                verdict: .approved,
                reviewer: "pdk-reviewer",
                note: "Reviewed manifest-bound corpus and oracle artifacts."
            )
        )
        #expect(approval.approval.verdict == .approved)

        let resumed = try await runtime.resume(
            request: FlowRunResumeRequest(projectRoot: root, runID: request.runID)
        )
        #expect(resumed.result.status == .succeeded)
        #expect(resumed.result.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .passed
        } == true)

        let wrongScope = ToolQualificationScope(
            implementationID: scope.implementationID,
            binaryDigest: String(repeating: "b", count: 64),
            algorithmVersion: scope.algorithmVersion,
            processProfileID: scope.processProfileID,
            processProfileDigest: scope.processProfileDigest,
            deckDigest: scope.deckDigest
        )
        let mismatchStage = FlowStageDefinition(
            stageID: PDKKitAPI.qualificationStageID,
            displayName: "PDK qualification with mismatched scope",
            requiredTool: ToolTrustRequirement(
                kind: .reporting,
                operationID: "pdk-qualify",
                minimumLevel: .oracleChecked,
                requiredInputFormats: [.json],
                requiredOutputFormats: [.json],
                qualificationScope: wrongScope
            ),
            requiresApproval: true
        )
        let mismatchRuntime = XcircuiteFlowRuntime(
            descriptors: [descriptor],
            healthResults: [
                descriptor.toolID: QualifiedToolFixtures.health(
                    toolID: descriptor.toolID,
                    level: .oracleChecked
                ),
            ],
            executors: [
                PDKQualificationFlowStageExecutor.local(
                    manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                    corpusInput: .path("corpus-report.json"),
                    oracleInput: .path("oracle-report.json")
                ),
            ],
            workspaceStore: try XcircuiteWorkspaceStore(projectRoot: root)
        )
        let mismatchRequest = FlowOperationRequest(
            projectRoot: root,
            runID: "pdk-qualification-scope-mismatch",
            intent: "Reject qualification evidence from a different tool build.",
            stages: [mismatchStage]
        )
        let mismatch = try await mismatchRuntime.run(request: mismatchRequest)
        #expect(mismatch.status == .blocked)
        #expect(mismatch.stages.first?.gates.contains {
            $0.gateID == "tool-trust" && $0.status == .failed
        } == true)
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
            .pdkQualification(.init(
                manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                corpusInput: .path("corpus-report.json"),
                oracleInput: .path("oracle-report.json")
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
            try XcircuiteFlowRuntimeSpec(executors: [decoded]).validate(
                requireCompleteToolEvidence: false
            )
        }
    }

    private func makeContext(root: URL, runID: String) throws -> FlowExecutionContext {
        let runDirectory = root
            .appending(path: XcircuiteWorkspaceLayout.directoryName)
            .appending(path: "runs")
            .appending(path: runID)
        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        } catch {
            Issue.record("Failed to create run directory: \(error)")
        }
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: runDirectory,
            infrastructure: try XcircuiteWorkspaceStore(projectRoot: root),
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
        let workspaceRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = workspaceRoot
            .appending(path: "PDKKit")
            .appending(path: "Tests/PDKKitTests/Fixtures")
        let destination = root.appending(path: "fixtures")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func writeQualificationReports(root: URL, fixtureRoot: URL) throws {
        let manifestURL = fixtureRoot.appending(path: "valid-pdk/pdk.json")
        let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
        let corpus = PDKCorpusValidationPayload(
            suiteID: "fixture-suite",
            processID: pdk.processID,
            version: pdk.version,
            isValid: true,
            caseResults: [PDKCorpusCaseResult(
                caseID: "valid",
                manifestPath: manifestURL.path,
                expectedOutcome: .valid,
                observedOutcome: .valid,
                passed: true,
                expectedFindingCodes: [],
                observedFindingCodes: [],
                missingExpectedFindingCodes: [],
                manifestReference: pdk.manifest
            )]
        )
        let oracle = PDKOracleComparisonPayload(
            isValid: true,
            oracleID: "fixture-oracle",
            pdkDigest: pdk.digest,
            comparisons: [
                PDKOracleViewComparison(
                    assetID: "cells",
                    format: .lef,
                    isMatch: true
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(corpus).write(
            to: root.appending(path: "corpus-report.json"),
            options: [.atomic]
        )
        try encoder.encode(oracle).write(
            to: root.appending(path: "oracle-report.json"),
            options: [.atomic]
        )
    }

    private func makeQualifiedDescriptor() -> ToolDescriptor {
        return ToolDescriptor(
            toolID: "pdk-qualification",
            displayName: "PDK qualification",
            kind: .reporting,
            version: "1",
            capabilities: [
                ToolCapability(
                    operationID: "pdk-qualify",
                    inputFormats: [.json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(
                level: .oracleChecked,
                evidence: QualifiedToolFixtures.evidenceSupporting(
                    level: .oracleChecked,
                    toolID: "pdk-qualification"
                )
            ),
            environment: ToolEnvironment(platform: "macOS")
        )
    }
}
