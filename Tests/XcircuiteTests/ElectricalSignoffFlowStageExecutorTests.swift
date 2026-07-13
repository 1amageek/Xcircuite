import DesignFlowKernel
import CircuiteFoundation
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
@testable import Xcircuite

@Suite("Electrical signoff flow adapter")
struct ElectricalSignoffFlowStageExecutorTests {
    @Test("maps completed per-axis envelopes to passed flow gates", .timeLimit(.minutes(1)))
    func mapsCompletedEnvelopes() async throws {
        let request = try makeRequest(runID: "electrical-flow-run")
        let executor = ElectricalSignoffFlowStageExecutor(
            stageID: "electrical-signoff",
            request: request,
            axes: [.erc, .esd],
            engine: StubElectricalSignoffEngine()
        )
        let context = try makeContext(runID: request.runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed, .passed, .passed])
        #expect(result.gates.map(\.gateID) == ["erc", "esd", "artifact-integrity"])
        let foundationReference = try #require(
            result.artifacts.first { $0.artifactID == "electrical-signoff-foundation-evidence" }
        )
        #expect(foundationReference.sha256?.count == 64)
        let foundationURL = try XcircuitePackageStore().url(
            forProjectRelativePath: foundationReference.path,
            inProjectAt: context.projectRoot
        )
        let foundationEvidence = try JSONDecoder().decode(
            ElectricalSignoffFoundationEvidence.self,
            from: Data(contentsOf: foundationURL)
        )
        #expect(foundationEvidence.evidence.provenance.inputs.count == 3)
    }

    @Test("failed electrical axes retain a typed repair plan artifact", .timeLimit(.minutes(1)))
    func failedAxisPersistsRepairPlan() async throws {
        let request = try makeRequest(runID: "electrical-repair-plan-run")
        let executor = ElectricalSignoffFlowStageExecutor(
            stageID: "electrical-signoff",
            request: request,
            axes: [.erc],
            engine: RepairCandidateElectricalSignoffEngine()
        )
        let context = try makeContext(runID: request.runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: context
        )

        #expect(result.status == FlowStageStatus.failed)
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
        let request = try makeRequest(runID: "electrical-qualification-flow-run")
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

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed])
        #expect(result.artifacts.count == 6)
        let inputManifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-input-manifest"
        })
        let inputManifestURL = try XcircuitePackageStore().url(
            forProjectRelativePath: inputManifestReference.path,
            inProjectAt: root
        )
        let inputManifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: Data(contentsOf: inputManifestURL)
        )
        try inputManifest.validate()
        #expect(inputManifest.inputArtifacts.count == 1)
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
            suiteArtifact: try FoundationFlowProjection.artifactReference(from: suiteReference),
            qualificationReportArtifact: try FoundationFlowProjection.artifactReference(from: retainedReportReference),
            domainReportArtifacts: [try FoundationFlowProjection.artifactReference(from: qualificationReportReference)],
            evidenceArtifacts: [try FoundationFlowProjection.artifactReference(from: evidenceReference)],
            toolEvidence: [toolEvidence],
            policy: policy
        )
        let releaseEnvelope = try await DefaultRetainedQualificationEvaluator().execute(qualificationRequest)
        #expect(releaseEnvelope.status == .completed)
        #expect(releaseEnvelope.payload.qualified)
    }

    @Test("qualification stage retains the immutable independent oracle artifact", .timeLimit(.minutes(1)))
    func qualificationStageRetainsOracleArtifact() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = try makeRequest(runID: "electrical-qualification-oracle-run")
        let caseID = "clean-erc-oracle"
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-oracle-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: caseID,
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        let oracleObservation = ElectricalSignoffOracleObservation(
            oracleID: "independent-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: request.pdk.digest,
            status: .completed,
            violationCount: 0
        )
        let oracleSet = ElectricalSignoffOracleObservationSet(
            oracleID: oracleObservation.oracleID,
            toolVersion: oracleObservation.toolVersion,
            pdkDigest: oracleObservation.pdkDigest,
            observations: [
                ElectricalSignoffOracleObservationSet.Entry(
                    caseID: caseID,
                    observation: oracleObservation
                ),
            ]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        try JSONEncoder().encode(oracleSet).write(to: root.appending(path: "oracle.json"))
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: "binary",
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: request.pdk.digest
        )
        let executor = ElectricalSignoffQualificationFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleInput: .path("oracle.json"),
            qualificationScope: scope,
            runner: ElectricalSignoffQualificationRunner(
                engine: StubElectricalSignoffEngine(),
                oracle: try LocalElectricalSignoffQualificationOracle(observationSet: oracleSet)
            )
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

        #expect(result.status == FlowStageStatus.succeeded)
        let inputManifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-input-manifest"
        })
        let inputManifestURL = try XcircuitePackageStore().url(
            forProjectRelativePath: inputManifestReference.path,
            inProjectAt: root
        )
        let inputManifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: Data(contentsOf: inputManifestURL)
        )
        try inputManifest.validate()
        #expect(inputManifest.inputArtifacts.count == 2)
        let oracleReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-observations" })
        #expect(oracleReference.sha256?.count == 64)
        let suiteReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-retained-suite" })
        let suiteURL = try XcircuitePackageStore().url(forProjectRelativePath: suiteReference.path, inProjectAt: root)
        let suite = try JSONDecoder().decode(RetainedCorpusSuite.self, from: Data(contentsOf: suiteURL))
        let requirements = try #require(suite.requirements)
        #expect(requirements.requiredArtifacts.contains(oracleReference.path))
        #expect(requirements.requireExternalOracles)
    }

    @Test("qualification stage executes an external oracle process and retains process evidence", .timeLimit(.minutes(1)))
    func qualificationStageExecutesExternalOracleProcess() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-external-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-external-oracle-run"
        let request = try makeRequest(runID: runID)
        let caseID = "clean-erc-external-oracle"
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-external-oracle-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: caseID,
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        let oracleObservation = ElectricalSignoffOracleObservation(
            oracleID: "external-electrical-oracle",
            toolVersion: "fixture-1",
            pdkDigest: request.pdk.digest,
            status: .completed,
            violationCount: 0
        )
        let oracleSet = ElectricalSignoffOracleObservationSet(
            oracleID: oracleObservation.oracleID,
            toolVersion: oracleObservation.toolVersion,
            pdkDigest: oracleObservation.pdkDigest,
            observations: [
                ElectricalSignoffOracleObservationSet.Entry(
                    caseID: caseID,
                    observation: oracleObservation
                ),
            ]
        )
        let specURL = root.appending(path: "qualification.json")
        let sourceOracleURL = root.appending(path: "external-oracle-source.json")
        try JSONEncoder().encode(specification).write(to: specURL)
        try JSONEncoder().encode(oracleSet).write(to: sourceOracleURL)
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: "binary",
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: request.pdk.digest
        )
        let configuration = ElectricalSignoffOracleProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: [
                "-c",
                "test -f \"{{specPath}}\" && cp \"$0\" \"$1\" && echo oracle-complete",
                sourceOracleURL.path(percentEncoded: false),
                "{{outputPath}}",
            ],
            workingDirectoryPath: ".",
            timeoutSeconds: 10
        )
        let executor = ElectricalSignoffQualificationFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleProcessConfiguration: configuration,
            qualificationScope: scope,
            runner: ElectricalSignoffQualificationRunner(engine: StubElectricalSignoffEngine())
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.qualification", displayName: "Electrical qualification"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stdout" })
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stderr" })
        let executionReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-execution" })
        let executionURL = try XcircuitePackageStore().url(forProjectRelativePath: executionReference.path, inProjectAt: root)
        let execution = try JSONDecoder().decode(ElectricalSignoffOracleProcessExecution.self, from: Data(contentsOf: executionURL))
        #expect(execution.status == "completed")
        #expect(execution.exitCode == 0)
        #expect(execution.arguments.contains { $0.contains("oracle-complete") })

        let oracleReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-observations" })
        let oracleURL = try XcircuitePackageStore().url(forProjectRelativePath: oracleReference.path, inProjectAt: root)
        #expect(FileManager.default.fileExists(atPath: oracleURL.path(percentEncoded: false)))
        let suiteReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-retained-suite" })
        let suiteURL = try XcircuitePackageStore().url(forProjectRelativePath: suiteReference.path, inProjectAt: root)
        let suite = try JSONDecoder().decode(RetainedCorpusSuite.self, from: Data(contentsOf: suiteURL))
        let requirements = try #require(suite.requirements)
        #expect(requirements.requiredArtifacts.contains(executionReference.path))
        #expect(requirements.requiredArtifacts.contains(oracleReference.path))
        #expect(requirements.requireExternalOracles)
    }

    @Test("qualification stage reports external oracle process failures with retained evidence", .timeLimit(.minutes(1)))
    func qualificationStageReportsExternalOracleProcessFailure() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-external-oracle-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-external-oracle-failure-run"
        let request = try makeRequest(runID: runID)
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-external-oracle-failure-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: "clean-erc-external-oracle-failure",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        let configuration = ElectricalSignoffOracleProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: [
                "-c",
                "echo oracle-failed >&2; exit 7 # {{specPath}} {{outputPath}}",
            ],
            workingDirectoryPath: ".",
            timeoutSeconds: 10
        )
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: "binary",
            algorithmVersion: "1",
            processProfileID: "fixture",
            deckDigest: request.pdk.digest
        )
        let executor = ElectricalSignoffQualificationFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleProcessConfiguration: configuration,
            qualificationScope: scope,
            runner: ElectricalSignoffQualificationRunner(engine: StubElectricalSignoffEngine())
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.qualification", displayName: "Electrical qualification"),
            context: context
        )

        #expect(result.status == FlowStageStatus.failed)
        #expect(result.diagnostics.first?.code == "ELECTRICAL_SIGNOFF_EXTERNAL_ORACLE_PROCESS_FAILED")
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stdout" })
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stderr" })
        let executionReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-execution" })
        let executionURL = try XcircuitePackageStore().url(forProjectRelativePath: executionReference.path, inProjectAt: root)
        let execution = try JSONDecoder().decode(ElectricalSignoffOracleProcessExecution.self, from: Data(contentsOf: executionURL))
        #expect(execution.status == "failed")
        #expect(execution.exitCode == 7)
    }

    @Test("qualification stage participates in approval and resume without changing the run ID", .timeLimit(.minutes(1)))
    func qualificationStageApprovalAndResume() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-resume-run"
        let request = try makeRequest(runID: runID)
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
        #expect(blocked.status == FlowRunStatus.blocked)
        #expect(blocked.stages.first?.gates.contains { $0.gateID == "approval" && $0.status == FlowGateStatus.incomplete } == true)

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
        #expect(resumed.result.status == FlowRunStatus.succeeded)
        #expect(resumed.result.stages.first?.gates.contains { $0.gateID == "approval" && $0.status == FlowGateStatus.passed } == true)
    }

    @Test("release gate persists a reproducible all-corner signoff decision", .timeLimit(.minutes(1)))
    func releaseGatePersistsDecision() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-release-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = try makeReleaseGateRequest()
        let reportData = Data("electrical-report".utf8)
        try reportData.write(to: root.appending(path: "report.json"))
        let reportReference = try makeFoundationArtifactReference(
            id: "electrical-report",
            path: "report.json",
            role: .output,
            kind: .report,
            format: .json,
            data: reportData
        )
        let runResult = try makeCompleteRunResult(request: request, artifact: reportReference)
        let report = makeOracleQualificationReport(runID: request.runID, pdkDigest: request.pdk.digest)
        var policy = ElectricalSignoffReleaseGatePolicy(
            policyID: "electrical-release-v1",
            pdkDigest: request.pdk.digest,
            requiredAxes: [.erc, .esd],
            requiredCornerIDs: ["slow", "fast"]
        )
        policy.requireProcessQualificationEvidence = true
        let processQualificationEvidence = ToolProcessQualificationEvidence(
            qualificationID: "electrical-process-qualification-v1",
            toolID: "native-electrical-signoff",
            scope: ToolQualificationScope(
                implementationID: "native-electrical-signoff",
                binaryDigest: "binary-digest",
                algorithmVersion: "1",
                processProfileID: "fixture",
                deckDigest: "deck-digest",
                pdkID: "fixture-pdk",
                pdkDigest: request.pdk.digest
            ),
            status: .qualified,
            corpusEvidenceIDs: ["electrical-corpus-evidence"],
            oracleEvidenceIDs: ["electrical-oracle-evidence"],
            healthEvidenceIDs: ["electrical-health-evidence"],
            approvalEvidenceIDs: ["electrical-approval-evidence"],
            evidenceArtifactIDs: ["electrical-process-qualification-record"],
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSinceNow: -60),
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let specification = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-release-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [ElectricalSignoffQualificationCase(
                caseID: "release-clean",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(request).write(to: root.appending(path: "request.json"))
        try Data("source".utf8).write(to: root.appending(path: "input.json"))
        try JSONEncoder().encode(runResult).write(to: root.appending(path: "run-result.json"))
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification-spec.json"))
        try JSONEncoder().encode(report).write(to: root.appending(path: "qualification-report.json"))
        try JSONEncoder().encode(policy).write(to: root.appending(path: "release-policy.json"))
        try JSONEncoder().encode(processQualificationEvidence).write(
            to: root.appending(path: "process-qualification.json")
        )

        let packageStore = XcircuitePackageStore()
        let requestReference = try packageStore.fileReference(
            forProjectRelativePath: "request.json",
            artifactID: "release-request-input",
            kind: .report,
            format: .json,
            inProjectAt: root
        )
        let runResultReference = try packageStore.fileReference(
            forProjectRelativePath: "run-result.json",
            artifactID: "release-run-result-input",
            kind: .report,
            format: .json,
            inProjectAt: root
        )
        let qualificationSpecReference = try packageStore.fileReference(
            forProjectRelativePath: "qualification-spec.json",
            artifactID: "release-qualification-spec-input",
            kind: .report,
            format: .json,
            inProjectAt: root
        )
        let qualificationReportReference = try packageStore.fileReference(
            forProjectRelativePath: "qualification-report.json",
            artifactID: "release-qualification-report-input",
            kind: .report,
            format: .json,
            inProjectAt: root
        )
        let policyReference = try packageStore.fileReference(
            forProjectRelativePath: "release-policy.json",
            artifactID: "release-policy-input",
            kind: .technology,
            format: .json,
            inProjectAt: root
        )
        let processQualificationEvidenceReference = try packageStore.fileReference(
            forProjectRelativePath: "process-qualification.json",
            artifactID: "process-qualification-input",
            kind: .report,
            format: .json,
            inProjectAt: root
        )

        let executor = ElectricalSignoffReleaseGateFlowStageExecutor(
            requestInput: .artifact(requestReference),
            runResultInput: .artifact(runResultReference),
            qualificationSpecInput: .artifact(qualificationSpecReference),
            qualificationReportInput: .artifact(qualificationReportReference),
            policyInput: .artifact(policyReference),
            processQualificationEvidenceInput: .artifact(processQualificationEvidenceReference)
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.release-gate", displayName: "Electrical release gate"),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: request.runID,
                runDirectory: root.appending(path: "run"),
                packageStore: packageStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed])
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
        #expect(bundle.qualificationArtifacts.contains { $0.path == "process-qualification.json" })
        #expect(bundle.bundleDigest.isEmpty == false)

        try Data("tampered-policy".utf8).write(
            to: root.appending(path: "release-policy.json"),
            options: .atomic
        )
        let tampered = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.release-gate", displayName: "Electrical release gate"),
            context: FlowExecutionContext(
                projectRoot: root,
                runID: request.runID,
                runDirectory: root.appending(path: "run"),
                packageStore: packageStore,
                toolRegistry: ToolRegistry(),
                healthResults: [:]
            )
        )
        #expect(tampered.status == FlowStageStatus.failed)
        #expect(tampered.diagnostics.contains {
            $0.code == "ELECTRICAL_SIGNOFF_RELEASE_GATE_EXECUTION_ERROR"
                && $0.message.contains("byte count mismatch")
        }, "Tampered result: \(tampered)")
    }

    private func makeContext(runID: String) throws -> FlowExecutionContext {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Data("source".utf8)
        for path in ["design.json", "layout.json", "pdk.json"] {
            try fixture.write(to: root.appending(path: path), options: .atomic)
        }
        return FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            packageStore: XcircuitePackageStore(),
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
    }

    private func makeRequest(runID: String) throws -> ElectricalSignoffRequest {
        let inputData = Data("source".utf8)
        let reference = try makeFoundationArtifactReference(
            id: "electrical-input",
            path: "design.json",
            role: .input,
            kind: .netlist,
            format: .json,
            data: inputData
        )
        let layoutReference = try makeFoundationArtifactReference(
            id: "electrical-layout",
            path: "layout.json",
            role: .input,
            kind: .layout,
            format: .json,
            data: inputData
        )
        let pdkReference = try makeFoundationArtifactReference(
            id: "electrical-pdk",
            path: "pdk.json",
            role: .input,
            kind: .technology,
            format: .json,
            data: inputData
        )
        return ElectricalSignoffRequest(
            runID: runID,
            inputs: [reference],
            design: LogicDesignReference(artifact: reference.locator, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: layoutReference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: pdkReference, processID: "fixture", version: "1", digest: pdkReference.sha256)
        )
    }

    private func makeReleaseGateRequest() throws -> ElectricalSignoffRequest {
        let inputData = Data("source".utf8)
        let designReference = try makeFoundationArtifactReference(
            id: "release-design",
            path: "input.json",
            role: .input,
            kind: .netlist,
            format: .json,
            data: inputData
        )
        let layoutReference = try makeFoundationArtifactReference(
            id: "release-layout",
            path: "input.json",
            role: .input,
            kind: .layout,
            format: .json,
            data: inputData
        )
        let pdkReference = try makeFoundationArtifactReference(
            id: "release-pdk",
            path: "input.json",
            role: .input,
            kind: .technology,
            format: .json,
            data: inputData
        )
        return ElectricalSignoffRequest(
            runID: "electrical-release-gate-run",
            inputs: [designReference],
            design: LogicDesignReference(
                artifact: designReference.locator,
                topDesignName: "top",
                designDigest: "design"
            ),
            physicalDesign: PhysicalDesignReference(
                layoutArtifact: layoutReference,
                topCell: "top",
                layoutDigest: "layout"
            ),
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture",
                version: "1",
                digest: pdkReference.sha256
            ),
            configuration: ElectricalSignoffConfiguration(
                requiredAxes: [.erc, .esd],
                operatingConditions: [
                    ElectricalOperatingCondition(id: "slow", pdkCornerID: "slow", temperatureC: 125, supplyVoltageScale: 0.9, activityScale: 1),
                    ElectricalOperatingCondition(id: "fast", pdkCornerID: "fast", temperatureC: -40, supplyVoltageScale: 1.1, activityScale: 1),
                ]
            )
        )
    }

    private func makeCompleteRunResult(
        request: ElectricalSignoffRequest,
        artifact: ArtifactReference
    ) throws -> ElectricalSignoffRunResult {
        let metadata = try makeElectricalProvenance(identifier: "native-electrical-signoff", startedAt: 1, completedAt: 2)
        var corners: [String: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult]] = [:]
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
                corners[condition.id, default: [:]][axis] = ElectricalSignoffResult(
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
            cornerID: "slow",
            pdkCornerID: "slow",
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
        let metadata = try makeElectricalProvenance(identifier: "stub-electrical-signoff", startedAt: 1, completedAt: 1)
        let results: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult] = Dictionary(uniqueKeysWithValues: axes.map { axis in
            let payload = ElectricalSignoffPayload(violationCount: 0, axis: axis)
            let result = ElectricalSignoffResult(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                metadata: metadata,
                payload: payload
            )
            return (axis, result)
        })
        return ElectricalSignoffRunResult(runID: request.runID, status: .completed, axisResults: results)
    }
}

private struct RepairCandidateElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = try makeElectricalProvenance(identifier: "repair-stub", startedAt: 1, completedAt: 1)
        let results: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult] = Dictionary(uniqueKeysWithValues: axes.map { axis in
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
            return (axis, ElectricalSignoffResult(
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

private func makeFoundationArtifactReference(
    id: String,
    path: String,
    role: ArtifactRole,
    kind: ArtifactKind,
    format: ArtifactFormat,
    data: Data
) throws -> ArtifactReference {
    ArtifactReference(
        id: try ArtifactID(rawValue: id),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        ),
        digest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: try SHA256ContentDigester().digest(data: data).hexadecimalValue
        ),
        byteCount: UInt64(data.count)
    )
}

private func makeElectricalProvenance(
    identifier: String,
    startedAt: TimeInterval,
    completedAt: TimeInterval
) throws -> ExecutionProvenance {
    try ExecutionProvenance(
        producer: try ProducerIdentity(
            kind: .engine,
            identifier: identifier,
            version: "1"
        ),
        startedAt: Date(timeIntervalSince1970: startedAt),
        completedAt: Date(timeIntervalSince1970: completedAt)
    )
}
