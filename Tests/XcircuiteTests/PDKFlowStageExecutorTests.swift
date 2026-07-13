import DesignFlowKernel
import Foundation
import PDKKit
import Testing
import ToolQualification
import XcircuitePackage
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
        let context = makeContext(root: root, runID: "pdk-discovery-adapter")

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
        let context = makeContext(root: root, runID: "pdk-validation-adapter")

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
        let context = makeContext(root: root, runID: "pdk-corpus-adapter")

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

        let standardContext = makeContext(root: root, runID: "pdk-standard-view-adapter")
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

        let ruleDeckContext = makeContext(root: root, runID: "pdk-rule-deck-adapter")
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
        let ruleDeckEnvelope = try JSONDecoder().decode(
            XcircuiteEngineResultEnvelope<PDKRuleDeckInspectionPayload>.self,
            from: ruleDeckData
        )
        #expect(ruleDeckEnvelope.payload.observedLayerIDs == ["active", "metal1"])

        let oracleContext = makeContext(root: root, runID: "pdk-oracle-adapter")
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

        let qualificationContext = makeContext(root: root, runID: "pdk-qualification-adapter")
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
        let envelope = try JSONDecoder().decode(
            XcircuiteEngineResultEnvelope<PDKQualificationAssessment>.self,
            from: rawData
        )
        #expect(envelope.payload.state == .oracleCorrelated)
    }

    @Test("qualification trust scope blocks mismatched evidence and resumes after approval")
    func qualificationScopeAndResumeAreAuditable() async throws {
        let root = try makeRoot(name: "pdk-qualification-resume")
        defer { removeRoot(root) }
        let fixtureRoot = try makeFixtureProject(root: root)
        try writeQualificationReports(root: root, fixtureRoot: fixtureRoot)

        let scope = ToolQualificationScope(
            implementationID: "pdk-qualification",
            binaryDigest: "binary-a",
            algorithmVersion: "1",
            processProfileID: "fixture-180nm:2026.1",
            deckDigest: "fixture-deck"
        )
        let descriptor = makeQualifiedDescriptor(scope: scope)
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
                maximumEvidenceAgeSeconds: 3_600,
                qualificationScope: scope
            ),
            requiresApproval: true
        )
        let runtime = XcircuiteFlowRuntime(
            descriptors: [descriptor],
            healthResults: [
                descriptor.toolID: ToolHealthCheckResult(
                    toolID: descriptor.toolID,
                    status: .passed
                ),
            ],
            executors: [executor]
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

        let approval = try DefaultFlowGateApprovalRecorder().recordApproval(
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
            binaryDigest: "binary-b",
            algorithmVersion: scope.algorithmVersion,
            processProfileID: scope.processProfileID,
            deckDigest: scope.deckDigest
        )
        let mismatchDescriptor = makeQualifiedDescriptor(scope: wrongScope)
        let mismatchRuntime = XcircuiteFlowRuntime(
            descriptors: [mismatchDescriptor],
            healthResults: [
                mismatchDescriptor.toolID: ToolHealthCheckResult(
                    toolID: mismatchDescriptor.toolID,
                    status: .passed
                ),
            ],
            executors: [
                PDKQualificationFlowStageExecutor.local(
                    manifestInput: .path("fixtures/valid-pdk/pdk.json"),
                    corpusInput: .path("corpus-report.json"),
                    oracleInput: .path("oracle-report.json")
                ),
            ]
        )
        let mismatchRequest = FlowOperationRequest(
            projectRoot: root,
            runID: "pdk-qualification-scope-mismatch",
            intent: "Reject qualification evidence from a different tool build.",
            stages: [stage]
        )
        let mismatch = try await mismatchRuntime.run(request: mismatchRequest)
        #expect(mismatch.status == .blocked)
        #expect(mismatch.stages.first?.gates.contains {
            $0.gateID == "tool-trust" && $0.status == .failed
        } == true)
    }

    @Test("PDK runtime specifications round-trip through the agent-facing contract")
    func runtimeSpecRoundTripsPDKAdapters() throws {
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

    private func makeContext(root: URL, runID: String) -> FlowExecutionContext {
        let runDirectory = root
            .appending(path: XcircuitePackage.directoryName)
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
            packageStore: XcircuitePackageStore(),
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

    private func makeQualifiedDescriptor(scope: ToolQualificationScope) -> ToolDescriptor {
        let evidenceKinds: [(ToolEvidenceKind, String)] = [
            (.corpus, "pdk-corpus-evidence"),
            (.oracle, "pdk-oracle-evidence"),
        ]
        let evidence = evidenceKinds.map { kind, evidenceID in
            ToolEvidence(
                evidenceID: evidenceID,
                kind: kind,
                qualification: ToolEvidenceQualificationSummary(
                    qualified: true,
                    policyID: "fixture-process-policy",
                    observedCounts: ["caseCount": 1],
                    scope: scope
                ),
                checkedAt: Date()
            )
        }
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
                evidence: evidence
            ),
            environment: ToolEnvironment(platform: "macOS")
        )
    }
}
