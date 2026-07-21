import DesignFlowKernel
import CircuiteFoundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffEvidence
import Foundation
import LogicIR
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("Electrical signoff flow executor")
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
        let (store, context) = try await makeContext(runID: request.runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed, .passed, .passed])
        #expect(result.gates.map(\.gateID) == ["erc", "esd", "artifact-integrity"])
        let runResultReference = try #require(
            result.artifacts.first { $0.artifactID == "electrical-signoff-run-result" }
        )
        #expect(runResultReference.digest.hexadecimalValue.count == 64)
        let persistedRunResult = try JSONDecoder().decode(
            ElectricalSignoffRunResult.self,
            from: try await store.read(from: runResultReference.path)
        )
        #expect(persistedRunResult.evidence.provenance.inputs.count == 3)
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
        let (store, context) = try await makeContext(runID: request.runID)
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff", displayName: "Electrical signoff"),
            context: context
        )

        #expect(result.status == FlowStageStatus.failed)
        let reference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-repair-plan" })
        let plan = try JSONDecoder().decode(
            ElectricalSignoffRepairPlan.self,
            from: try await store.read(from: reference.path)
        )
        #expect(plan.candidates.count == 1)
        #expect(plan.candidates.first?.axis == .erc)
        #expect(plan.applicationPolicy.contains("new immutable design revision"))
    }

    @Test("corpus stage persists raw artifact-bound observations", .timeLimit(.minutes(1)))
    func corpusStagePersistsRawObservations() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = try makeRequest(runID: "electrical-qualification-flow-run")
        let specification = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-flow-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            cases: [ElectricalSignoffCorpusCase(
                caseID: "clean-erc",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        let (store, context) = try await makeContext(root: root, runID: request.runID)
        let executor = ElectricalSignoffCorpusFlowStageExecutor(
            requestInput: .path("qualification.json"),
            runner: ElectricalSignoffCorpusRunner(engine: StubElectricalSignoffEngine())
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.corpus", displayName: "Electrical corpus"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed])
        #expect(result.artifacts.count == 3)
        let inputManifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-input-manifest"
        })
        let inputManifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: try await store.read(from: inputManifestReference.path)
        )
        try inputManifest.validate()
        #expect(inputManifest.inputArtifacts.count == 1)
        let reportReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-corpus-report"
        })
        let report = try JSONDecoder().decode(
            ElectricalSignoffCorpusReport.self,
            from: try await store.read(from: reportReference.path)
        )
        #expect(report.passed)
        #expect(report.observationMaturity == .corpusObserved)
    }

    @Test("corpus stage retains the immutable independent oracle artifact", .timeLimit(.minutes(1)))
    func corpusStageRetainsOracleArtifact() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = try makeRequest(runID: "electrical-qualification-oracle-run")
        let caseID = "clean-erc-oracle"
        let specification = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-oracle-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireExternalOracleEvidence: true,
            cases: [ElectricalSignoffCorpusCase(
                caseID: caseID,
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        let oracleObservation = try makeOracleObservation(
            oracleID: "independent-electrical-oracle",
            toolVersion: "fixture-1",
            request: request
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
        let (store, context) = try await makeContext(root: root, runID: request.runID)
        let executor = ElectricalSignoffCorpusFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleInput: .path("oracle.json"),
            runner: ElectricalSignoffCorpusRunner(
                engine: StubElectricalSignoffEngine(),
                oracle: try LocalElectricalSignoffOracle(observationSet: oracleSet)
            )
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.corpus", displayName: "Electrical corpus"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        let inputManifestReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-input-manifest"
        })
        let inputManifest = try JSONDecoder().decode(
            ElectricalSignoffInputArtifactManifest.self,
            from: try await store.read(from: inputManifestReference.path)
        )
        try inputManifest.validate()
        #expect(inputManifest.inputArtifacts.count == 2)
        let oracleReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-observations" })
        #expect(oracleReference.digest.hexadecimalValue.count == 64)
        let reportReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-corpus-report" })
        let report = try JSONDecoder().decode(
            ElectricalSignoffCorpusReport.self,
            from: try await store.read(from: reportReference.path)
        )
        #expect(report.observationMaturity == .oracleCorrelated)
    }

    @Test("corpus stage executes an external oracle process and retains process observations", .timeLimit(.minutes(1)))
    func corpusStageExecutesExternalOracleProcess() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-external-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-external-oracle-run"
        let request = try makeRequest(runID: runID)
        let caseID = "clean-erc-external-oracle"
        let specification = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-external-oracle-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireExternalOracleEvidence: true,
            cases: [ElectricalSignoffCorpusCase(
                caseID: caseID,
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        let oracleObservation = try makeOracleObservation(
            oracleID: "external-electrical-oracle",
            toolVersion: "fixture-1",
            request: request
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
        let (store, context) = try await makeContext(root: root, runID: runID)
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
        let executor = ElectricalSignoffCorpusFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleProcessConfiguration: configuration,
            runner: ElectricalSignoffCorpusRunner(engine: StubElectricalSignoffEngine())
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.corpus", displayName: "Electrical corpus"),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stdout" })
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stderr" })
        let executionReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-execution" })
        let execution = try JSONDecoder().decode(
            ElectricalSignoffOracleProcessExecution.self,
            from: try await store.read(from: executionReference.path)
        )
        #expect(execution.status == "completed")
        #expect(execution.exitCode == 0)
        #expect(execution.arguments.contains { $0.contains("oracle-complete") })

        let oracleReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-observations" })
        #expect(try await store.read(from: oracleReference.path).isEmpty == false)
        #expect(result.artifacts.contains { $0 == executionReference })
        #expect(result.artifacts.contains { $0 == oracleReference })
    }

    @Test("corpus stage reports external oracle process failures with retained observations", .timeLimit(.minutes(1)))
    func corpusStageReportsExternalOracleProcessFailure() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-qualification-external-oracle-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-qualification-external-oracle-failure-run"
        let request = try makeRequest(runID: runID)
        let specification = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-external-oracle-failure-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireExternalOracleEvidence: true,
            cases: [ElectricalSignoffCorpusCase(
                caseID: "clean-erc-external-oracle-failure",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "qualification.json"))
        let (store, context) = try await makeContext(root: root, runID: runID)
        let configuration = ElectricalSignoffOracleProcessConfiguration(
            executablePath: "/bin/sh",
            arguments: [
                "-c",
                "echo oracle-failed >&2; exit 7 # {{specPath}} {{outputPath}}",
            ],
            workingDirectoryPath: ".",
            timeoutSeconds: 10
        )
        let executor = ElectricalSignoffCorpusFlowStageExecutor(
            requestInput: .path("qualification.json"),
            oracleProcessConfiguration: configuration,
            runner: ElectricalSignoffCorpusRunner(engine: StubElectricalSignoffEngine())
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.corpus", displayName: "Electrical corpus"),
            context: context
        )

        #expect(result.status == FlowStageStatus.failed)
        #expect(result.diagnostics.first?.code == "ELECTRICAL_SIGNOFF_EXTERNAL_ORACLE_PROCESS_FAILED")
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stdout" })
        #expect(result.artifacts.contains { $0.artifactID == "electrical-signoff-oracle-stderr" })
        let executionReference = try #require(result.artifacts.first { $0.artifactID == "electrical-signoff-oracle-execution" })
        let execution = try JSONDecoder().decode(
            ElectricalSignoffOracleProcessExecution.self,
            from: try await store.read(from: executionReference.path)
        )
        #expect(execution.status == "failed")
        #expect(execution.exitCode == 7)
    }

    @Test("corpus execution does not create approval authority", .timeLimit(.minutes(1)))
    func corpusExecutionDoesNotCreateApprovalAuthority() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-corpus-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-corpus-boundary-run"
        let request = try makeRequest(runID: runID)
        let specification = ElectricalSignoffCorpusSpec(
            corpusID: "electrical-boundary-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            cases: [ElectricalSignoffCorpusCase(
                caseID: "clean-erc",
                kind: .positive,
                axis: .erc,
                request: request,
                expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
            )]
        )
        try JSONEncoder().encode(specification).write(to: root.appending(path: "corpus.json"))
        let (_, context) = try await makeContext(root: root, runID: runID)
        let result = try await ElectricalSignoffCorpusFlowStageExecutor(
            requestInput: .path("corpus.json"),
            runner: ElectricalSignoffCorpusRunner(engine: StubElectricalSignoffEngine())
        ).execute(
            stage: FlowStageDefinition(stageID: "electrical-signoff.corpus", displayName: "Electrical corpus"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.map(\.gateID) == ["corpus-observations"])
        #expect(result.gates.contains { $0.gateID == "approval" } == false)
    }

    @Test("electrical catalog delegates release authority to ReleaseEngine", .timeLimit(.minutes(1)))
    func electricalCatalogDelegatesReleaseAuthority() async throws {
        let electrical = try #require(
            try XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ElectricalSignoffEngine" }
        )
        let release = try #require(
            try XcircuiteEnginePackageCatalog.descriptors.first { $0.packageID == "ReleaseEngine" }
        )

        #expect(electrical.stageIDs.contains("electrical-signoff.corpus"))
        #expect(electrical.stageIDs.contains { $0.contains("qualification") || $0.contains("release") } == false)
        #expect(release.stageIDs == ["release.authorization", "release.signoff", "release.tapeout"])
    }

    private func makeContext(
        runID: String
    ) async throws -> (store: XcircuiteWorkspaceStore, context: FlowExecutionContext) {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Data("source".utf8)
        for path in ["design.json", "layout.json", "pdk.json"] {
            try fixture.write(to: root.appending(path: path), options: .atomic)
        }
        return try await makeContext(root: root, runID: runID)
    }

    private func makeContext(
        root: URL,
        runID: String
    ) async throws -> (store: XcircuiteWorkspaceStore, context: FlowExecutionContext) {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        _ = try await prepareTestRun(runID: runID, store: store)
        let manifest = try await store.loadManifest()
        let context = FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        return (store, context)
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
            design: LogicDesignReference(artifact: reference, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: layoutReference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(
                manifest: pdkReference,
                processID: "fixture",
                version: "1",
                digest: pdkReference.digest.hexadecimalValue
            )
        )
    }

    private func makeOracleObservation(
        oracleID: String,
        toolVersion: String,
        request: ElectricalSignoffRequest
    ) throws -> ElectricalSignoffOracleObservation {
        let inputArtifact = try #require(request.inputs.first)
        let evidenceArtifact = request.physicalDesign.layoutArtifact
        return ElectricalSignoffOracleObservation(
            oracleID: oracleID,
            toolVersion: toolVersion,
            pdkDigest: request.pdk.digest,
            status: .completed,
            violationCount: 0,
            inputArtifacts: [inputArtifact],
            artifacts: [evidenceArtifact],
            evidenceArtifact: evidenceArtifact
        )
    }

}

private struct StubElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = try makeElectricalProvenance(
            identifier: "stub-electrical-signoff",
            inputs: request.executionInputArtifacts,
            startedAt: 1,
            completedAt: 1
        )
        let results: [ElectricalSignoffAnalysisAxis: ElectricalSignoffResult] = Dictionary(uniqueKeysWithValues: axes.map { axis in
            let payload = ElectricalSignoffPayload(violationCount: 0, axis: axis)
            let result = ElectricalSignoffResult(
                schemaVersion: 1,
                runID: request.runID,
                status: .completed,
                provenance: metadata,
                payload: payload
            )
            return (axis, result)
        })
        return ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: results,
            provenance: try makeElectricalProvenance(
                identifier: "stub-electrical-signoff-run",
                inputs: request.executionInputArtifacts,
                supportingTools: [metadata.producer],
                startedAt: 1,
                completedAt: 1
            )
        )
    }
}

private struct RepairCandidateElectricalSignoffEngine: ElectricalSignoffExecuting {
    func execute(
        _ request: ElectricalSignoffRequest,
        axes: [ElectricalSignoffAnalysisAxis]
    ) async throws -> ElectricalSignoffRunResult {
        let metadata = try makeElectricalProvenance(
            identifier: "repair-stub",
            inputs: request.executionInputArtifacts,
            startedAt: 1,
            completedAt: 1
        )
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
                provenance: metadata,
                payload: payload
            ))
        })
        return ElectricalSignoffRunResult(
            runID: request.runID,
            status: .completed,
            axisResults: results,
            provenance: try makeElectricalProvenance(
                identifier: "repair-stub-run",
                inputs: request.executionInputArtifacts,
                supportingTools: [metadata.producer],
                startedAt: 1,
                completedAt: 1
            )
        )
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
    inputs: [ArtifactReference] = [],
    supportingTools: [ProducerIdentity] = [],
    startedAt: TimeInterval,
    completedAt: TimeInterval
) throws -> ExecutionProvenance {
    try ExecutionProvenance(
        producer: try ProducerIdentity(
            kind: .engine,
            identifier: identifier,
            version: "1",
            build: String(repeating: "e", count: 64)
        ),
        supportingTools: supportingTools,
        inputs: inputs,
        invocation: try .inProcess(entryPoint: "XcircuiteTests.\(identifier)"),
        environment: try ExecutionEnvironmentFingerprint(
            platform: "test",
            architecture: "test",
            toolchain: "test",
            environmentDigest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "f", count: 64)
            )
        ),
        startedAt: Date(timeIntervalSince1970: startedAt),
        completedAt: Date(timeIntervalSince1970: completedAt)
    )
}
