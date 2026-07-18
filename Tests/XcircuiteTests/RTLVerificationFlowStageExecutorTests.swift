import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicIR
import RTLVerificationCore
import RTLVerificationEngine
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("RTL verification flow stage")
struct RTLVerificationFlowStageExecutorTests {
    @Test("native lint persists a headless stage artifact", .timeLimit(.minutes(1)))
    func nativeLintStage() async throws {
        let (_, context) = try await makeRTLStageFixture(
            runID: "rtl-stage-run",
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let executor = RTLVerificationFlowStageExecutor.native(
            analysis: .lint,
            rtlInput: .path("top.sv"),
            topModuleName: "top"
        )
        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.first?.status == .passed)
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-result" })
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-evidence-assessment" })
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-audit" })
    }

    @Test("same request resumes from an auditable stage result", .timeLimit(.minutes(1)))
    func resumesSameRequest() async throws {
        let (_, context) = try await makeRTLStageFixture(
            runID: "rtl-resume-run",
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let counter = ResumeExecutionCounter()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            topModuleName: "top",
            engine: ResumeVerificationEngine(counter: counter)
        )
        let stage = FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint")

        let first = try await executor.execute(stage: stage, context: context)
        let second = try await executor.execute(stage: stage, context: context)

        #expect(first.status == .succeeded)
        #expect(second.status == .succeeded)
        #expect(await counter.calls() == 1)
    }

    @Test("external tool stages block when qualification evidence is missing", .timeLimit(.minutes(1)))
    func missingExternalQualificationBlocksBeforeExecution() async throws {
        let (_, context) = try await makeRTLStageFixture(
            runID: "rtl-tool-gate-run",
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let counter = ResumeExecutionCounter()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            toolID: "unregistered-external",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            topModuleName: "top",
            engine: ResumeVerificationEngine(counter: counter)
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.gates.first?.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "RTL_TOOL_DESCRIPTOR_MISSING" })
        #expect(await counter.calls() == 0)
    }

    @Test("evidence input is passed into the typed RTL request", .timeLimit(.minutes(1)))
    func evidenceInputIsPassedIntoRequest() async throws {
        let (projectRoot, context) = try await makeRTLStageFixture(
            runID: "rtl-evidence-input-run",
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let evidenceInput = RTLVerificationEvidenceInput()
        try JSONEncoder().encode(evidenceInput)
            .write(to: projectRoot.appending(path: "evidence.json"))
        let capture = EvidenceRequestCapture()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            evidenceInput: .path("evidence.json"),
            topModuleName: "top",
            engine: EvidenceCaptureEngine(capture: capture)
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )
        let request = try #require(await capture.request())

        #expect(result.status == .succeeded)
        #expect(request.evidenceInput == evidenceInput)
        #expect(request.inputs.contains { $0.artifactID == "rtl-evidence-input" })
    }

    @Test("evidence artifact integrity blocks before engine execution", .timeLimit(.minutes(1)))
    func evidenceArtifactIntegrityBlocksBeforeEngine() async throws {
        let runID = "rtl-evidence-integrity-run"
        let (projectRoot, context) = try await makeRTLStageFixture(
            runID: runID,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let nativePath = projectRoot.appending(path: "evidence/native.json")
        let oraclePath = projectRoot.appending(path: "evidence/oracle.json")
        let nativeData = Data("native-evidence".utf8)
        let oracleData = Data("oracle-evidence".utf8)
        try FileManager.default.createDirectory(
            at: nativePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try nativeData.write(to: nativePath)
        try oracleData.write(to: oraclePath)
        let nativeArtifact = try artifactReference(
            artifactID: "native-evidence",
            path: "evidence/native.json",
            digest: SHA256ContentDigester().digest(data: nativeData),
            byteCount: UInt64(nativeData.count),
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "native-rtl-verification",
                version: "1.0.0"
            )
        )
        let oracleArtifact = try artifactReference(
            artifactID: "oracle-evidence",
            path: "evidence/oracle.json",
            digest: SHA256ContentDigester().digest(data: oracleData),
            byteCount: UInt64(oracleData.count),
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "independent-rtl-oracle",
                version: "1.0.0"
            )
        )
        let requestDigest = String(repeating: "d", count: 64)
        let report = RTLVerificationOracleCorrelationReport(
            caseID: "rtl.lint",
            nativeImplementationID: "native-rtl-verification",
            oracleImplementationID: "independent-rtl-oracle",
            nativeImplementationVersion: "1.0.0",
            oracleImplementationVersion: "1.0.0",
            independenceVerified: true,
            matched: true
        )
        let evidenceInput = RTLVerificationEvidenceInput(
            oracleReports: [report],
            oracleEvidence: [RTLVerificationOracleEvidence(
                evidenceID: "rtl-oracle-evidence",
                caseID: "rtl.lint",
                requestDigest: requestDigest,
                nativePayloadRequestDigest: requestDigest,
                oraclePayloadRequestDigest: requestDigest,
                nativeArtifact: nativeArtifact,
                oracleArtifact: oracleArtifact,
                report: report,
                oracleProvenance: "fixture"
            )]
        )
        try JSONEncoder().encode(evidenceInput)
            .write(to: projectRoot.appending(path: "evidence.json"))
        try Data("tampered-native-evidence".utf8).write(to: nativePath)

        let counter = ResumeExecutionCounter()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            evidenceInput: .path("evidence.json"),
            topModuleName: "top",
            engine: ResumeVerificationEngine(counter: counter)
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "RTL_QUALIFICATION_ARTIFACT_INTEGRITY_FAILED" })
        #expect(await counter.calls() == 0)
    }

    @Test("independent oracle correlation persists evidence and resumes", .timeLimit(.minutes(1)))
    func independentOracleCorrelationPersistsEvidenceAndResumes() async throws {
        let oracleToolID = "independent-rtl-oracle"
        var descriptor = RTLToolDescriptors.oracle(
            toolID: oracleToolID,
            executablePath: "/tmp/independent-rtl-oracle",
            version: "1.0.0",
            analysis: .lint,
            proofView: .rtlToRtlStructural
        )
        descriptor.trustProfile.level = .oracleChecked
        descriptor.trustProfile.evidence = QualifiedToolFixtures.evidenceSupporting(
            level: .oracleChecked,
            toolID: oracleToolID
        )
        let toolRegistry = try ToolRegistry(descriptors: [descriptor])
        let health = oracleHealthResult(toolID: oracleToolID)
        let (projectRoot, context) = try await makeRTLStageFixture(
            runID: "rtl-oracle-run",
            toolRegistry: toolRegistry,
            healthResults: [oracleToolID: health],
            qualifiedDescriptors: [descriptor]
        )
        let counter = ResumeExecutionCounter()
        let corpusEvidenceURL = projectRoot.appending(path: "oracle-corpus-evidence.json")
        try JSONEncoder().encode(RTLVerificationEvidenceInput(
            corpusEvaluations: [RTLVerificationCorpusEvaluation(
                caseID: "rtl.lint",
                matched: true,
                observedStatus: .completed,
                observedFindingCodes: [],
                mismatches: []
            )]
        )).write(to: corpusEvidenceURL, options: .atomic)
        let externalDescriptor = RTLExternalToolDescriptor(
            toolID: oracleToolID,
            executablePath: "/tmp/independent-rtl-oracle",
            version: "1.0.0",
            supportedAnalyses: [.lint],
            supportedProofViews: [.rtlToRtlStructural]
        )
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            evidenceInput: .path("oracle-corpus-evidence.json"),
            topModuleName: "top",
            engine: OracleNativeVerificationEngine(counter: counter),
            oracleToolID: oracleToolID,
            oracleExecutor: ExternalRTLVerificationOracleExecutor(
                descriptor: externalDescriptor,
                trustDecision: ToolTrustDecision(toolID: oracleToolID, status: .eligible),
                runner: FixtureOracleProcessRunner(
                    toolID: oracleToolID,
                    analyzedConstructs: 1
                )
            )
        )
        let stage = FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint")

        let first = try await executor.execute(stage: stage, context: context)
        let second = try await executor.execute(stage: stage, context: context)
        #expect(first.status == .succeeded, "First execution diagnostics: \(first.diagnostics)")
        #expect(second.status == .succeeded, "Resume diagnostics: \(second.diagnostics)")
        let resultURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-oracle-run")
            .appending(path: "stages")
            .appending(path: "rtl.lint")
            .appending(path: "raw")
            .appending(path: "rtl-verification-result.json")
        let envelope = try JSONDecoder().decode(
            RTLVerificationResult.self,
            from: Data(contentsOf: resultURL)
        )

        #expect(await counter.calls() == 1)
        #expect(envelope.artifacts.contains { $0.artifactID == "oracle-rtl.lint-evidence" })
        #expect(envelope.payload.record.evidence.contains { $0.kind == .oracleCorrelation })
        #expect(envelope.payload.record.maturity == .oracleCorrelated)
    }

    @Test("oracle semantic coverage mismatch blocks the stage", .timeLimit(.minutes(1)))
    func oracleSemanticCoverageMismatchBlocksStage() async throws {
        let oracleToolID = "diverging-rtl-oracle"
        var descriptor = RTLToolDescriptors.oracle(
            toolID: oracleToolID,
            executablePath: "/tmp/diverging-rtl-oracle",
            version: "1.0.0",
            analysis: .lint,
            proofView: .rtlToRtlStructural
        )
        descriptor.trustProfile.level = .oracleChecked
        descriptor.trustProfile.evidence = QualifiedToolFixtures.evidenceSupporting(
            level: .oracleChecked,
            toolID: oracleToolID
        )
        let health = oracleHealthResult(toolID: oracleToolID)
        let toolRegistry = try ToolRegistry(descriptors: [descriptor])
        let (projectRoot, context) = try await makeRTLStageFixture(
            runID: "rtl-oracle-mismatch-run",
            toolRegistry: toolRegistry,
            healthResults: [oracleToolID: health],
            qualifiedDescriptors: [descriptor]
        )
        let externalDescriptor = RTLExternalToolDescriptor(
            toolID: oracleToolID,
            executablePath: "/tmp/diverging-rtl-oracle",
            version: "1.0.0",
            supportedAnalyses: [.lint],
            supportedProofViews: [.rtlToRtlStructural]
        )
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            topModuleName: "top",
            engine: OracleNativeVerificationEngine(counter: ResumeExecutionCounter()),
            oracleToolID: oracleToolID,
            oracleExecutor: ExternalRTLVerificationOracleExecutor(
                descriptor: externalDescriptor,
                trustDecision: ToolTrustDecision(toolID: oracleToolID, status: .eligible),
                runner: FixtureOracleProcessRunner(
                    toolID: oracleToolID,
                    analyzedConstructs: 0
                )
            )
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )
        let evidenceURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-oracle-mismatch-run")
            .appending(path: "oracle-rtl.lint-evidence.json")

        #expect(result.status == .blocked, "Oracle mismatch diagnostics: \(result.diagnostics)")
        #expect(result.diagnostics.contains { $0.code == "RTL_ORACLE_CORRELATION_FAILED" })
        #expect(FileManager.default.fileExists(atPath: evidenceURL.path))
    }
}

private func makeRTLStageFixture(
    runID: String,
    toolRegistry: ToolRegistry,
    healthResults: [String: ToolHealthCheckResult],
    qualifiedDescriptors: [ToolDescriptor] = []
) async throws -> (projectRoot: URL, context: FlowExecutionContext) {
    let projectRoot = FileManager.default.temporaryDirectory
        .appending(path: "rtl-oracle-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try QualifiedToolFixtures.materializeEvidence(
        for: qualifiedDescriptors,
        in: projectRoot
    )
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
    try await workspaceStore.createWorkspace()
    try "module top(input logic a, output logic q); assign q = a; endmodule"
        .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
    _ = try await prepareTestRun(runID: runID, store: workspaceStore)
    let manifest = try await workspaceStore.loadManifest()
    return (
        projectRoot,
        FlowExecutionContext(
            workspaceID: try FlowWorkspaceID(rawValue: manifest.identity.projectID),
            runID: runID,
            infrastructure: workspaceStore,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
    )
}

private func artifactReference(
    artifactID: String,
    path: String,
    digest: ContentDigest,
    byteCount: UInt64,
    producer: ProducerIdentity
) throws -> ArtifactReference {
    ArtifactReference(
        id: try ArtifactID(rawValue: artifactID),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: .report,
            format: .json
        ),
        digest: digest,
        byteCount: byteCount,
        producer: producer
    )
}

private func oracleHealthResult(toolID: String) -> ToolHealthCheckResult {
    QualifiedToolFixtures.health(
        toolID: toolID,
        level: .oracleChecked
    )
}

private actor ResumeExecutionCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func calls() -> Int {
        count
    }
}

private struct OracleNativeVerificationEngine: RTLVerificationExecuting {
    let counter: ResumeExecutionCounter

    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> RTLVerificationResult {
        _ = await counter.increment()
        let now = Date()
        return RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "native-fixture-engine",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: RTLVerificationPayload(
                findingCount: 0,
                requestDigest: try RTLVerificationRequestDigest.make(request),
                analysis: request.analysis,
                coverage: RTLVerificationCoverage(
                    totalConstructs: 1,
                    analyzedConstructs: 1,
                    proofScope: request.analysis.rawValue
                ),
                record: RTLVerificationEvidenceAssessment(
                    implementationID: "native-fixture-engine",
                    implementationVersion: "1.0.0"
                ),
                proofView: request.proofView,
                assumptions: request.assumptions
            )
        )
    }
}

private struct FixtureOracleProcessRunner: RTLExternalToolProcessRunning {
    let toolID: String
    let analyzedConstructs: Int

    func run(
        executableURL: URL,
        arguments: [String],
        standardInput: Data
    ) async throws -> Data {
        let request = try JSONDecoder().decode(RTLVerificationRequest.self, from: standardInput)
        let now = Date()
        let payload = RTLVerificationPayload(
            findingCount: 0,
            requestDigest: try RTLVerificationRequestDigest.make(request),
            analysis: request.analysis,
            coverage: RTLVerificationCoverage(
                totalConstructs: 1,
                analyzedConstructs: analyzedConstructs,
                proofScope: request.analysis.rawValue
            ),
            record: RTLVerificationEvidenceAssessment(
                implementationID: toolID,
                implementationVersion: "1.0.0",
                maturity: .unassessed
            ),
            proofView: request.proofView,
            assumptions: request.assumptions
        )
        let envelope = RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: request.analysis.stageID,
                    version: "1.0.0",
                    build: toolID
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: payload
        )
        return try JSONEncoder().encode(envelope)
    }
}

private struct ResumeVerificationEngine: RTLVerificationExecuting {
    let counter: ResumeExecutionCounter

    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> RTLVerificationResult {
        guard await counter.increment() == 1 else {
            throw RTLVerificationExecutionError.externalToolFailed(
                tool: "resume-test",
                reason: "The engine must not execute after a resumable result exists."
            )
        }
        let now = Date()
        return RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "resume-test-engine",
                    version: "1"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: RTLVerificationPayload(
                findingCount: 0,
                analysis: request.analysis,
                coverage: RTLVerificationCoverage(proofScope: "lint")
            )
        )
    }
}

private actor EvidenceRequestCapture {
    private var capturedRequest: RTLVerificationRequest?

    func store(_ request: RTLVerificationRequest) {
        capturedRequest = request
    }

    func request() -> RTLVerificationRequest? {
        capturedRequest
    }
}

private struct EvidenceCaptureEngine: RTLVerificationExecuting {
    let capture: EvidenceRequestCapture

    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> RTLVerificationResult {
        await capture.store(request)
        let now = Date()
        return RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "evidence-capture",
                    version: "1"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: RTLVerificationPayload(
                findingCount: 0,
                analysis: request.analysis,
                coverage: RTLVerificationCoverage(proofScope: request.analysis.rawValue)
            )
        )
    }
}
