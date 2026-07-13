import DesignFlowKernel
import Foundation
import LogicIR
import RTLVerificationCore
import RTLVerificationEngine
import Testing
import ToolQualification
import XcircuitePackage
@testable import Xcircuite

@Suite("RTL verification flow stage")
struct RTLVerificationFlowStageExecutorTests {
    @Test("native lint persists a headless stage artifact", .timeLimit(.minutes(1)))
    func nativeLintStage() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "rtl-verification-stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let packageStore = XcircuitePackageStore()
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        let rtlURL = projectRoot.appending(path: "top.sv")
        let source = "module top(input logic a, output logic q); assign q = a; endmodule"
        try source.write(to: rtlURL, atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-stage-run")
        try packageStore.ensureDirectory(at: runDirectory)

        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-stage-run",
            runDirectory: runDirectory,
            packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        let rtlURL = projectRoot.appending(path: "top.sv")
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: rtlURL, atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-resume-run")
        try packageStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-resume-run",
            runDirectory: runDirectory,
            packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-tool-gate-run")
        try packageStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-tool-gate-run",
            runDirectory: runDirectory,
            packageStore: packageStore,
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
        let packageStore = XcircuitePackageStore()
        try packageStore.ensurePackageDirectory(forProjectAt: projectRoot)
        try "module top(input logic a, output logic q); assign q = a; endmodule"
            .write(to: projectRoot.appending(path: "top.sv"), atomically: true, encoding: .utf8)
        let qualificationInput = RTLVerificationQualificationInput()
        try JSONEncoder().encode(qualificationInput)
            .write(to: projectRoot.appending(path: "qualification.json"))
        let runDirectory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: "rtl-qualification-input-run")
        try packageStore.ensureDirectory(at: runDirectory)
        let context = FlowExecutionContext(
            projectRoot: projectRoot,
            runID: "rtl-qualification-input-run",
            runDirectory: runDirectory,
            packageStore: packageStore,
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

private struct ResumeVerificationEngine: RTLVerificationExecuting {
    let counter: ResumeExecutionCounter

    func execute(
        _ request: RTLVerificationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<RTLVerificationPayload> {
        guard await counter.increment() == 1 else {
            throw RTLVerificationExecutionError.externalToolFailed(
                tool: "resume-test",
                reason: "The engine must not execute after a resumable result exists."
            )
        }
        let now = Date()
        return XcircuiteEngineResultEnvelope(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            metadata: XcircuiteEngineExecutionMetadata(
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
    ) async throws -> XcircuiteEngineResultEnvelope<RTLVerificationPayload> {
        await capture.store(request)
        let now = Date()
        return XcircuiteEngineResultEnvelope(
            schemaVersion: RTLVerificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            metadata: XcircuiteEngineExecutionMetadata(
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
