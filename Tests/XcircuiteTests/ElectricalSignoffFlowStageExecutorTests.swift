import DesignFlowKernel
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import LogicIR
import PDKCore
import PhysicalDesignCore
import QualificationEngine
import Testing
import ToolQualification
import XcircuitePackage
@testable import Xcircuite

@Suite("Electrical signoff flow adapter")
struct ElectricalSignoffFlowStageExecutorTests {
    @Test("maps completed per-axis envelopes to passed flow gates", .timeLimit(.minutes(1)))
    func mapsCompletedEnvelopes() async throws {
        let request = makeRequest(runID: "electrical-flow-run")
        let executor = ElectricalSignoffFlowStageExecutor(
            stageID: "electrical-signoff",
            request: request,
            axes: [.erc, .esd],
            engine: StubElectricalSignoffEngine()
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: makeContext(runID: request.runID)
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.map(\.status) == [.passed, .passed])
        #expect(result.gates.map(\.gateID) == ["erc", "esd"])
    }

    @Test("failed electrical axes retain a typed repair plan artifact", .timeLimit(.minutes(1)))
    func failedAxisPersistsRepairPlan() async throws {
        let request = makeRequest(runID: "electrical-repair-plan-run")
        let executor = ElectricalSignoffFlowStageExecutor(
            stageID: "electrical-signoff",
            request: request,
            axes: [.erc],
            engine: RepairCandidateElectricalSignoffEngine()
        )
        let context = makeContext(runID: request.runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: context
        )

        #expect(result.status == .failed)
        let reference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-repair-plan" })
        let root = context.projectRoot
        let url = try XcircuitePackageStore().url(forProjectRelativePath: reference.path, inProjectAt: root)
        let plan = try JSONDecoder().decode(ElectricalSignoffRepairPlan.self, from: Data(contentsOf: url))
        #expect(plan.candidates.count == 1)
        #expect(plan.candidates.first?.axis == .erc)
        #expect(plan.applicationPolicy.contains("new immutable design revision"))
    }

    @Test("qualification stage persists ToolEvidence and retained release artifacts", .timeLimit(.minutes(1)))
    func qualificationStagePersistsReleaseArtifacts() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = makeRequest(runID: "electrical-qualification-flow-run")
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-flow-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            cases: [ElectricalSignoffQualificationCase(
                caseID: "clean-erc",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: "binary",
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: request.pdk.digest
        )
        let executor = ElectricalSignoffQualificationFlowStageExecutor(
            requestInput: .path("qualification.json"),
            qualificationScope: scope,
            runner: ElectricalSignoffQualificationRunner(engine: StubElectricalSignoffEngine())
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: request.runID,
            runDirectory: root.appending(path: "run"),
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.qualification", displayName: "Electrical qualification"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.map(\.status) == [.passed])
        #expect(result.artifacts.count == 5)
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-tool-evidence" })
        let suiteReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-retained-suite" })
        let suiteURL = try XcircuitePackageStore().url(forProjectRelativePath: suiteReference.path, inProjectAt: root)
        let suite = try JSONDecoder().decode(RetainedCorpusSuite.self, from: Data(contentsOf: suiteURL))
        #expect(suite.isValid)
        #expect(suite.lanes.first?.domain == "electrical-signoff")

        let retainedReportReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-retained-report" })
        let qualificationReportReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-qualification-report" })
        let evidenceReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-tool-evidence" })
        let evidenceURL = try XcircuitePackageStore().url(forProjectRelativePath: evidenceReference.path, inProjectAt: root)
        let toolEvidence = try JSONDecoder().decode(ToolEvidence.self, from: Data(contentsOf: evidenceURL))
        let lane = try #require(suite.lanes.first)
        let policy = ReleaseQualificationPolicy(
            policyID: "electrical-flow-policy",
            processProfileID: "fixture",
            requiredLanes: [lane],
            requiredEvidenceKinds: [.corpus],
            requiredQualifiedEvidenceKinds: [.corpus],
            requiredQualificationLevel: .corpusChecked,
            requiredQualificationScope: scope
        )
        let qualificationRequest = ReleaseQualificationRequest(
            runID: request.runID,
            projectRoot: root.path,
            processProfileID: "fixture",
            suiteArtifact: suiteReference,
            qualificationReportArtifact: retainedReportReference,
            domainReportArtifacts: [qualificationReportReference],
            evidenceArtifacts: [evidenceReference],
            toolEvidence: [toolEvidence],
            policy: policy
        )
        let releaseEnvelope = try await DefaultRetainedQualificationEvaluator().execute(qualificationRequest)
        #expect(releaseEnvelope.status == .completed)
        #expect(releaseEnvelope.payload.qualified)
    }

    @Test("qualification stage participates in approval and resume without changing the run ID", .timeLimit(.minutes(1)))
    func qualificationStageApprovalAndResume() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-resume-run"
        let request = makeRequest(runID: runID)
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-resume-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            cases: [ElectricalSignoffQualificationCase(
                caseID: "clean-erc",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: "binary",
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: request.pdk.digest
        )
        let executor = ElectricalSignoffQualificationFlowStageExecutor(
            requestInput: .path("qualification.json"),
            qualificationScope: scope,
            runner: ElectricalSignoffQualificationRunner(engine: StubElectricalSignoffEngine())
        )
        let stage = FlowStageDefinition(
            stageID: "electrical-signoff.qualification",
            displayName: "Electrical qualification",
            requiresApproval: true
        )
        let operation = FlowOperationRequest(
            projectRoot: root,
            runID: runID,
            intent: "Run electrical qualification and request human approval",
            stages: [stage]
        )
        let blocked = try await DefaultFlowOrchestrator().run(
            request: operation,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(blocked.status == .blocked)
        #expect(blocked.stages.first?.gates.contains { $0.gateID == "approval" && $0.status == .incomplete } == true)

        _ = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: runID,
                stageID: stage.stageID,
                verdict: .approved,
                reviewer: "electrical-reviewer"
            )
        )
        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(resumed.result.status == .succeeded)
        #expect(resumed.result.stages.first?.gates.contains { $0.gateID == "approval" && $0.status == .passed } == true)
    }

    @Test("release gate persists a reproducible all-corner signoff decision", .timeLimit(.minutes(1)))
    func releaseGatePersistsDecision() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-release-gate-(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = ElectricalSignoffRequest(
            runID: "electrical-release-gate-run",
            inputs: [],
            design: LogicDesignReference(
                artifact: XcircuiteFileReference(path: "input.json", kind: .other, format: .json),
                topDesignName: "top",
                designDigest: "design"
            ),
            physicalDesign: PhysicalDesignReference(
                layoutArtifact: XcircuiteFileReference(path: "input.json", kind: .other, format: .json),
                topCell: "top",
                layoutDigest: "layout"
            ),
            pdk: PDKReference(
                manifest: XcircuiteFileReference(path: "input.json", kind: .other, format: .json),
                processID: "fixture",
                version: "1",
                digest: "pdk"
            ),
            configuration: ElectricalSignoffConfiguration(
                requiredAxes: [.erc, .esd],
                operatingConditions: [
                    ElectricalOperatingCondition(id: "slow", pdkCornerID: "slow", temperatureC: 125, supplyVoltageScale: 0.9, activityScale: 1),
                    ElectricalOperatingCondition(id: "fast", pdkCornerID: "fast", temperatureC: -40, supplyVoltageScale: 1.1, activityScale: 1),
                ]
            )
        )
        let reportData = Data("electrical-report".utf8)
        try reportData.write(to: root.appending(path: "report.json"))
        let reportReference = XcircuiteFileReference(
            artifactID: "electrical-report",
            path: "report.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: reportData),
            byteCount: Int64(reportData.count)
        )
        let runResult = makeCompleteRunResult(request: request, artifact: reportReference)
        let report = makeOracleQualificationReport(runID: request.runID, pdkDigest: request.pdk.digest)
        let policy = ElectricalSignoffReleaseGatePolicy(
            policyID: "electrical-release-v1",
            pdkDigest: request.pdk.digest,
            requiredAxes: [.erc, .esd],
            requiredCornerIDs: ["slow", "fast"]
        )
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-release-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            cases: []
        )
        try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
        try Data("source".utf8).write(to: root.appending(path: "input.json"))
        try JSONEncoder().encode(runResult).write(to: root.appending(path: "run-result.json"))
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification-spec.json"))
        try JSONEncoder().encode(report).write(to: root.appending(path: "qualification-report.json"))
        try JSONEncoder().encode(policy).write(to: root.appending(path: "release-policy.json"))

        let executor = ElectricalSignoffReleaseGateFlowStageExecutor(
            requestInput: .path("request.json"),
            runResultInput: .path("run-result.json"),
            qualificationSpecInput: .path("qualification-spec.json"),
            qualificationReportInput: .path("qualification-report.json"),
            policyInput: .path("release-policy.json")
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.release-gate", displayName: "Electrical release gate"),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: request.runID,
                runDirectory: root.appending(path: "run"),
                packageStore: XcircuitePackageStore(),
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.map(\.status) == [.passed])
        let reference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-release-gate" })
        let url = try XcircuitePackageStore().url(forProjectRelativePath: reference.path, inProjectAt: root)
        let gate = try JSONDecoder().decode(ElectricalSignoffReleaseGateResult.self, from: Data(contentsOf: url))
        #expect(gate.isReleaseReady)
        #expect(gate.checks.contains { $0.checkID == "corner-axis-coverage" && $0.passed })
        let bundleReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-release-artifact-bundle" })
        let bundleURL = try XcircuitePackageStore().url(forProjectRelativePath: bundleReference.path, inProjectAt: root)
        let bundle = try JSONDecoder().decode(ElectricalSignoffReleaseArtifactBundle.self, from: Data(contentsOf: bundleURL))
        #expect(bundle.runID == request.runID)
        #expect(bundle.request.path == "request.json")
        #expect(bundle.gateResult.path == reference.path)
        #expect(bundle.bundleDigest.isEmpty == false)
    }

    private func makeContext(runID: String) -> FlowExecutionContext {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-flow-\(UUID().uuidString)")
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRequest(runID: String) -> ElectricalSignoffRequest {
        let reference = XcircuiteFileReference(path: "input.json", kind: .other, format: .json)
        return ElectricalSignoffRequest(
            runID: runID,
            inputs: [reference],
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: reference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: reference, processID: "fixture", version: "1", digest: "pdk")
        )
    }

    private func makeCompleteRunResult(
        request: ElectricalSignoffRequest,
        artifact: XcircuiteFileReference
    ) -> ElectricalSignoffRunResult {
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "native",
            implementationID: "native-electrical-signoff",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
        var corners: [String: [ElectricalSignoffAnalysisAxis: XcircuiteEngineResultEnvelope<ElectricalSignoffPayload>]] = [:]
        for condition in request.configuration.operatingConditions {
            for axis in request.configuration.requiredAxes {
                let payload = ElectricalSignoffPayload(
                    violationCount: 0,
                    axis: axis,
                    provenance: ElectricalSignoffPayload.Provenance(
                        designDigest: "design",
                        layoutDigest: "layout",
                        pdkDigest: request.pdk.digest,
                        parasiticDigest: nil,
                        topCell: "top",
                        inputArtifactIDs: []
                    ),
                    cornerID: condition.id
                )
                corners[condition.id, default: [:]][axis] = XcircuiteEngineResultEnvelope(
                    schemaVersion: 1,
                    runID: request.runID,
                    status: .completed,
                    artifacts: [artifact],
                    metadata: metadata,
                    payload: payload
                )
            }
        }
        return ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: corners["slow"] ?? [:],
            cornerResults: corners
        )
    }

    private func makeOracleQualificationReport(runID: String, pdkDigest: String) -> ElectricalSignoffQualificationReport {
        let caseResult = ElectricalSignoffQualificationCaseResult(
            caseID: "release-clean",
            axis: .erc,
            nativeStatus: .completed,
            nativeViolationCount: 0,
            nativeDiagnosticCodes: [],
            nativeMetrics: [],
            nativeArtifacts: [],
            metricComparisons: [],
            oracle: ElectricalSignoffOracleObservation(
                oracleID: "independent-oracle",
                toolVersion: "1",
                pdkDigest: pdkDigest,
                status: .completed,
                violationCount: 0
            ),
            oracleAgreementPassed: true,
            passed: true,
            failureCodes: []
        )
        return ElectricalSignoffQualificationReport(
            corpusID: "electrical-release-corpus",
            corpusVersion: "1",
            pdkDigest: pdkDigest,
            runID: runID,
            implementationID: "native-electrical-signoff",
            generatedAt: Date(),
            completed: true,
            passed: true,
            qualificationLevel: .oracleChecked,
            caseResults: [caseResult]
        )
    }
}

private struct StubElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "stub-electrical-signoff",
            implementationID: "stub",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 1)
        )
        let results = Dictionary(uniqueKeysWithValues: axes.map { axis in
            let payload = ElectricalSignoffPayload(violationCount: 0, axis: axis)
            let envelope = XcircuiteEngineResultEnvelope(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                metadata: metadata,
                payload: payload
            )
            return (axis, envelope)
        })
        return ElectricalSignoffRunResult(runID: request.runID, status: .completed, axisResults: results)
    }
}

private struct RepairCandidateElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "repair-stub",
            implementationID: "repair-stub",
            implementationVersion: "1",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 1)
        )
        let results = Dictionary(uniqueKeysWithValues: axes.map { axis in
            let payload = ElectricalSignoffPayload(
                violationCount: 1,
                axis: axis,
                repairCandidates: [ElectricalSignoffPayload.RepairCandidate(
                    candidateID: "repair-erc-1",
                    kind: "connect-domain-isolation",
                    entity: "U1:VDD",
                    rationale: "The failing domain connection requires an explicit isolation repair.",
                    actions: ["insert_domain_isolation"]
                )]
            )
            return (axis, XcircuiteEngineResultEnvelope(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                metadata: metadata,
                payload: payload
            ))
        })
        return ElectricalSignoffRunResult(runID: request.runID, status: .completed, axisResults: results)
    }
}
