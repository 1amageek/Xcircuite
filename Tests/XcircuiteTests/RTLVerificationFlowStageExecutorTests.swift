import DesignFlowKernel
import Foundation
import LogicIR
import RTLVerificationCore
import RTLVerificationEngine
import Testing
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("RTL verification flow stage")
struct RTLVerificationFlowStageExecutorTests {
    @Test("native lint persists a headless stage artifact", .timeLimit(.minutes(1)))
    func nativeLintStage() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
        let rtlURL = projectRoot.appending(path: "top.sv")
        let source = "module top(input logic a, output logic q); assign q = a; endmodule"
        try source.write(to: rtlURL, atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-stage-run")
        try workspaceStore.ensureDirectory(at: runDirectory)

        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-stage-run",
            runDirectory: runDirectory,
            storage: workspaceStore,
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
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-report" })
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-qualification" })
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-review" })
        #expect(result.artifacts.contains { $0.artifactID == "rtl-verification-audit" })
    }

    @Test("same request resumes from an auditable stage result", .timeLimit(.minutes(1)))
    func resumesSameRequest() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
        let rtlURL = projectRoot.appending(path: "top.sv")
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: rtlURL, atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-resume-run")
        try workspaceStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-resume-run",
            runDirectory: runDirectory,
            storage: workspaceStore,
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
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-tool-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-tool-gate-run")
        try workspaceStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-tool-gate-run",
            runDirectory: runDirectory,
            storage: workspaceStore,
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

    @Test("qualification input is passed into the typed RTL request", .timeLimit(.minutes(1)))
    func qualificationInputIsPassedIntoRequest() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-qualification-input-(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
        let qualificationInput = RTLVerificationQualificationInput()
        try JSONEncoder().encode(qualificationInput)
            .write(to: projectRoot.appending(path: "qualification.json"))
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-qualification-input-run")
        try workspaceStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-qualification-input-run",
            runDirectory: runDirectory,
            storage: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let capture = QualificationRequestCapture()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            qualificationInput: .path("qualification.json"),
            topModuleName: "top",
            engine: QualificationCaptureEngine(capture: capture)
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint"),
            context: context
        )
        let request = try #require(await capture.request())

        #expect(result.status == .succeeded)
        #expect(request.qualificationInput == qualificationInput)
        #expect(request.inputs.contains { $0.artifactID == "rtl-qualification-input" })
    }

    @Test("qualification artifact integrity blocks before engine execution", .timeLimit(.minutes(1)))
    func qualificationArtifactIntegrityBlocksBeforeEngine() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-qualification-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let workspaceStore = XcircuiteWorkspaceStore()
        try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)

        let retainedPath = projectRoot.appending(path: "qualification/process.json")
        let retainedData = Data("retained-process-evidence".utf8)
        try FileManager.default.createDirectory(
            at: retainedPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try retainedData.write(to: retainedPath)
        let retainedArtifact = XcircuiteFileReference(
            artifactID: "process-artifact",
            path: "qualification/process.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: retainedData),
            byteCount: Int64(retainedData.count)
        )
        let qualificationInput = RTLVerificationQualificationInput(
            processEvidence: [try makeProcessEvidence(artifact: retainedArtifact)]
        )
        let qualificationURL = projectRoot.appending(path: "qualification.json")
        try JSONEncoder().encode(qualificationInput).write(to: qualificationURL)
        try Data("tampered-process-evidence".utf8).write(to: retainedPath)

        let runID = "rtl-qualification-integrity-run"
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: runID)
        try workspaceStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: runID,
            runDirectory: runDirectory,
            storage: workspaceStore,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let counter = ResumeExecutionCounter()
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            qualificationInput: .path("qualification.json"),
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
            proofView: .rtlToRtlStructural,
            level: .oracleChecked
        )
        descriptor.trustProfile.evidence = QualifiedToolFixtures.evidenceSupporting(level: .oracleChecked)
        let toolRegistry = try ToolRegistry(validating: [descriptor])
        var health = QualifiedToolFixtures.health(
            toolID: oracleToolID,
            level: .oracleChecked
        )
        health.evidence.append(ToolEvidence(
            evidenceID: "health-\(oracleToolID)",
            kind: .healthCheck,
            checkedAt: Date()
        ))
        let (projectRoot, context) = try makeRTLStageFixture(
            runID: "rtl-oracle-run",
            toolRegistry: toolRegistry,
            healthResults: [oracleToolID: health]
        )
        let counter = ResumeExecutionCounter()
        let externalDescriptor = RTLExternalToolDescriptor(
            toolID: oracleToolID,
            executablePath: "/tmp/independent-rtl-oracle",
            version: "1.0.0",
            supportedAnalyses: [.lint],
            supportedProofViews: [.rtlToRtlStructural],
            qualified: true,
            qualification: RTLVerificationQualificationReport(
                implementationID: oracleToolID,
                implementationVersion: "1.0.0",
                state: .oracleCorrelated,
                blockers: []
            )
        )
        let executor = RTLVerificationFlowStageExecutor(
            stageID: "rtl.lint",
            analysis: .lint,
            rtlInput: .path("top.sv"),
            topModuleName: "top",
            engine: OracleNativeVerificationEngine(counter: counter),
            oracleToolID: oracleToolID,
            oracleExecutor: ExternalRTLVerificationOracleExecutor(
                descriptor: externalDescriptor,
                runner: FixtureOracleProcessRunner(
                    toolID: oracleToolID,
                    analyzedConstructs: 1
                )
            )
        )
        let stage = FlowStageDefinition(stageID: "rtl.lint", displayName: "RTL lint")

        let first = try await executor.execute(stage: stage, context: context)
        let second = try await executor.execute(stage: stage, context: context)
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

        #expect(first.status == .succeeded)
        #expect(second.status == .succeeded)
        #expect(await counter.calls() == 1)
        #expect(envelope.artifacts.contains { $0.artifactID == "oracle-rtl.lint-evidence" })
        #expect(envelope.payload.qualification.evidence.contains { $0.kind == .oracleCorrelation })
        #expect(envelope.payload.qualification.blockers.contains("independent_corpus_validation_required"))
    }

    @Test("oracle semantic coverage mismatch blocks the stage", .timeLimit(.minutes(1)))
    func oracleSemanticCoverageMismatchBlocksStage() async throws {
        let oracleToolID = "diverging-rtl-oracle"
        var descriptor = RTLToolDescriptors.oracle(
            toolID: oracleToolID,
            executablePath: "/tmp/diverging-rtl-oracle",
            version: "1.0.0",
            analysis: .lint,
            proofView: .rtlToRtlStructural,
            level: .oracleChecked
        )
        descriptor.trustProfile.evidence = QualifiedToolFixtures.evidenceSupporting(level: .oracleChecked)
        var health = QualifiedToolFixtures.health(toolID: oracleToolID, level: .oracleChecked)
        health.evidence.append(ToolEvidence(
            evidenceID: "health-\(oracleToolID)",
            kind: .healthCheck,
            checkedAt: Date()
        ))
        let toolRegistry = try ToolRegistry(validating: [descriptor])
        let (projectRoot, context) = try makeRTLStageFixture(
            runID: "rtl-oracle-mismatch-run",
            toolRegistry: toolRegistry,
            healthResults: [oracleToolID: health]
        )
        let externalDescriptor = RTLExternalToolDescriptor(
            toolID: oracleToolID,
            executablePath: "/tmp/diverging-rtl-oracle",
            version: "1.0.0",
            supportedAnalyses: [.lint],
            supportedProofViews: [.rtlToRtlStructural],
            qualified: true,
            qualification: RTLVerificationQualificationReport(
                implementationID: oracleToolID,
                implementationVersion: "1.0.0",
                state: .oracleCorrelated,
                blockers: []
            )
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

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "RTL_ORACLE_CORRELATION_FAILED" })
        #expect(FileManager.default.fileExists(atPath: evidenceURL.path))
    }
}

private func makeRTLStageFixture(
    runID: String,
    toolRegistry: ToolRegistry,
    healthResults: [String: ToolHealthCheckResult]
) throws -> (projectRoot: URL, context: FlowExecutionContext) {
    let projectRoot = FileManager.default.temporaryDirectory
        .appending(path: "rtl-oracle-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let workspaceStore = XcircuiteWorkspaceStore()
    try workspaceStore.ensureWorkspaceDirectory(forProjectAt: projectRoot)
    try "module top(input logic a, output logic q); assign q = a; endmodule"
        .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
    let runDirectory = projectRoot
        .appending(path: ".xcircuite")
        .appending(path: "runs")
        .appending(path: runID)
    try workspaceStore.ensureDirectory(at: runDirectory)
    return (
        projectRoot,
        FlowExecutionContext(
            projectRoot: projectRoot,
            runID: runID,
            runDirectory: runDirectory,
            storage: workspaceStore,
            toolRegistry: toolRegistry,
            healthResults: healthResults
        )
    )
}

private func makeProcessEvidence(
    artifact: XcircuiteFileReference
) throws -> RTLVerificationProcessQualificationEvidence {
    let recordedAt = Date()
    let qualification = RTLVerificationProcessQualificationRecord(
        qualificationID: "qualification-1",
        scope: RTLVerificationProcessQualificationScope(
            implementationID: "rtl-tool",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "1",
            processProfileID: "profile-1",
            pdkID: "pdk-1",
            pdkDigest: String(repeating: "b", count: 64),
            deckDigest: String(repeating: "c", count: 64),
            analyses: [.lint]
        ),
        status: .qualified,
        corpusEvidenceIDs: ["corpus-1"],
        oracleEvidenceIDs: ["oracle-1"],
        healthEvidenceIDs: ["health-1"],
        qualifiedAt: recordedAt.addingTimeInterval(-10),
        expiresAt: recordedAt.addingTimeInterval(3_600)
    )
    return RTLVerificationProcessQualificationEvidence(
        evidenceID: "process-evidence-1",
        qualificationID: qualification.qualificationID,
        qualification: qualification,
        artifactIDs: [artifact.artifactID].compactMap { $0 },
        artifacts: [try foundationReference(artifact)],
        provenance: "fixture",
        recordedAt: recordedAt
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
            metadata: RTLExecutionMetadata(
                engineID: request.analysis.stageID,
                implementationID: "native-fixture-engine",
                implementationVersion: "1.0.0",
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
                qualification: RTLVerificationQualificationReport(
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
    ) throws -> Data {
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
            qualification: RTLVerificationQualificationReport(
                implementationID: toolID,
                implementationVersion: "1.0.0",
                state: .unassessed,
                blockers: []
            ),
            proofView: request.proofView,
            assumptions: request.assumptions
        )
        let envelope = RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            metadata: RTLExecutionMetadata(
                engineID: request.analysis.stageID,
                implementationID: toolID,
                implementationVersion: "1.0.0",
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
            metadata: RTLExecutionMetadata(
                engineID: request.analysis.stageID,
                implementationID: "resume-test-engine",
                implementationVersion: "1",
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

private actor QualificationRequestCapture {
    private var capturedRequest: RTLVerificationRequest?

    func store(_ request: RTLVerificationRequest) {
        capturedRequest = request
    }

    func request() -> RTLVerificationRequest? {
        capturedRequest
    }
}

private struct QualificationCaptureEngine: RTLVerificationExecuting {
    let capture: QualificationRequestCapture

    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> RTLVerificationResult {
        await capture.store(request)
        let now = Date()
        return RTLVerificationResult(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            metadata: RTLExecutionMetadata(
                engineID: request.analysis.stageID,
                implementationID: "qualification-capture",
                implementationVersion: "1",
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
