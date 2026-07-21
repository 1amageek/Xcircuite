import CircuiteFoundation
import Foundation
import SignoffToolSupport
import Testing

@testable import Xcircuite

@Suite("Platform capability retained evidence")
struct XcircuitePlatformCapabilityRetainedEvidenceTests {
    @Test("operation maturity rejects malformed open tokens")
    func operationMaturityRejectsMalformedOpenTokens() throws {
        let operation = XcircuiteActionDomainOperation(
            operationID: "test-operation",
            maturity: .implemented,
            inputRefs: [],
            preconditions: [],
            effects: [],
            producedArtifacts: [],
            verificationGates: [],
            reversible: true
        )
        let encoded = try JSONEncoder().encode(operation)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["maturity"] = "../passed"
        let malformed = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: XcircuiteOperationMaturityError.invalidToken("../passed")) {
            try JSONDecoder().decode(XcircuiteActionDomainOperation.self, from: malformed)
        }
    }

    @Test("self-reported passing status cannot establish readiness")
    func selfReportedPassingStatusIsRejected() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "self-reported",
            generatedAt: "1970-01-01T00:00:00Z"
        )
        let baseline = assessor.assess(actionDomainSnapshot: snapshot)
        let claimed = baseline.testEvidence.map { evidence in
            var value = evidence
            value.exitStatus = 0
            return value
        }

        let report = assessor.assess(actionDomainSnapshot: snapshot, testEvidence: claimed)

        #expect(report.status == .failed)
        #expect(report.summary.passedTestEvidenceCount == 0)
        #expect(report.diagnostics.contains { $0.code == "test-evidence-root-missing" })
    }

    @Test("runner receipt and retained bytes establish passing test evidence")
    func runnerReceiptEstablishesPassingReadiness() async throws {
        let fixture = try await makeFixture()

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(
            actionDomainSnapshot: fixture.snapshot,
            testEvidence: fixture.evidence,
            evidenceRoot: fixture.root,
            verifications: fixture.verifications
        )

        #expect(report.status == .failed)
        #expect(report.summary.passedTestEvidenceCount == report.summary.testEvidenceCount)
        #expect(report.summary.invalidTestEvidenceCount == 0)
        #expect(report.diagnostics.contains {
            $0.code == "required-test-evidence-missing"
                && $0.message.contains("production-qualified-release-flow")
        })
    }

    @Test("digest drift invalidates retained readiness")
    func digestDriftInvalidatesRetainedReadiness() async throws {
        let fixture = try await makeFixture()
        let reference = try #require(fixture.evidence.first?.resultArtifact)
        let url = try reference.locator.location.resolvedFileURL(relativeTo: fixture.root)
        try Data("tampered".utf8).write(to: url, options: .atomic)

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(
            actionDomainSnapshot: fixture.snapshot,
            testEvidence: fixture.evidence,
            evidenceRoot: fixture.root,
            verifications: fixture.verifications
        )

        #expect(report.status == .failed)
        #expect(report.diagnostics.contains { $0.code == "test-evidence-artifact-integrity-failed" })
    }

    @Test("persisted passing records remain unverified without a runner receipt")
    func persistedRecordCannotPromoteItself() async throws {
        let fixture = try await makeFixture()

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(
            actionDomainSnapshot: fixture.snapshot,
            testEvidence: fixture.evidence,
            evidenceRoot: fixture.root
        )

        #expect(report.status == .failed)
        #expect(report.summary.passedTestEvidenceCount == 0)
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-independent-verification-required"
        })
    }

    @Test("runner receipts reject retained evidence mutation")
    func runnerReceiptRejectsRetainedEvidenceMutation() async throws {
        let fixture = try await makeFixture()
        var evidence = fixture.evidence
        var first = try #require(evidence.first)
        first.coveredArtifactKinds.append("mutated-coverage-claim")
        evidence[0] = first

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(
            actionDomainSnapshot: fixture.snapshot,
            testEvidence: evidence,
            evidenceRoot: fixture.root,
            verifications: fixture.verifications
        )

        #expect(report.status == .failed)
        #expect(report.diagnostics.contains { $0.code == "test-evidence-receipt-mismatch" })
    }

    @Test("declarations cannot inject pre-existing execution results")
    func declarationExecutionResultsAreRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-stale-evidence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Xcircuite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "stale-evidence",
            generatedAt: "1970-01-01T00:00:00Z"
        )
        var declaration = try #require(
            XcircuitePlatformCapabilityReadinessAssessor()
                .assess(actionDomainSnapshot: snapshot)
                .testEvidence
                .first { $0.packagePath == "Xcircuite" }
        )
        let retainedURL = root.appending(path: "evidence/stale.json")
        try FileManager.default.createDirectory(
            at: retainedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let retainedData = Data("stale".utf8)
        try retainedData.write(to: retainedURL, options: .atomic)
        let retainedReference = ArtifactReference(
            id: ArtifactID(stableKey: "stale-retained-artifact"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "evidence/stale.json"),
                role: .output,
                kind: .report,
                format: .json
            ),
            digest: try SHA256ContentDigester().digest(data: retainedData, using: .sha256),
            byteCount: UInt64(retainedData.count)
        )
        declaration.retainedArtifacts = [retainedReference]
        let runner = XcircuitePlatformCapabilityTestRunner(
            processRunner: SuccessfulTestProcessRunner()
        )

        await #expect(throws: XcircuitePlatformCapabilityTestRunnerError.declarationContainsExecutionResults) {
            try await runner.run(declaration: declaration, evidenceRoot: root)
        }
    }

    @Test("runner binds receipts to the selected xcodebuild executable")
    func runnerBindsReceiptToSelectedXcodebuildExecutable() async throws {
        let root = try makeEvidenceRoot(prefix: "xcircuite-tool-identity")
        defer { removeTemporaryRoot(root) }
        let firstExecutable = root.appending(path: "tools/first/xcodebuild")
        let secondExecutable = root.appending(path: "tools/second/xcodebuild")
        try FileManager.default.createDirectory(
            at: firstExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first-xcodebuild".utf8).write(to: firstExecutable, options: .atomic)
        try Data("second-xcodebuild".utf8).write(to: secondExecutable, options: .atomic)
        var firstDeclaration = try xcircuiteDeclaration()
        firstDeclaration.invocation.xcodebuildPath = firstExecutable.path
        var secondDeclaration = firstDeclaration
        secondDeclaration.invocation.xcodebuildPath = secondExecutable.path
        let runner = XcircuitePlatformCapabilityTestRunner(
            processRunner: SuccessfulTestProcessRunner()
        )

        let firstRun = try await runner.run(
            declaration: firstDeclaration,
            evidenceRoot: root
        )
        let secondRun = try await runner.run(
            declaration: secondDeclaration,
            evidenceRoot: root
        )
        let firstProvenance = try #require(firstRun.evidence.provenance)
        let secondProvenance = try #require(secondRun.evidence.provenance)

        #expect(firstProvenance.supportingTools != secondProvenance.supportingTools)
        #expect(firstProvenance.environment != secondProvenance.environment)
        #expect(firstRun.verification.evidenceDigest != secondRun.verification.evidenceDigest)
        #expect(firstRun.evidence.command.contains(firstExecutable.resolvingSymlinksInPath().path))
        #expect(secondRun.evidence.command.contains(secondExecutable.resolvingSymlinksInPath().path))
    }

    @Test("runner refuses a receipt when xcodebuild changes during execution")
    func runnerRejectsXcodebuildMutationDuringExecution() async throws {
        let root = try makeEvidenceRoot(prefix: "xcircuite-tool-mutation")
        defer { removeTemporaryRoot(root) }
        let executable = root.appending(path: "tools/xcodebuild")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("xcodebuild-before".utf8).write(to: executable, options: .atomic)
        var declaration = try xcircuiteDeclaration()
        declaration.invocation.xcodebuildPath = executable.path
        let runner = XcircuitePlatformCapabilityTestRunner(
            processRunner: MutatingTestProcessRunner(executableURL: executable)
        )

        await #expect(throws: XcircuitePlatformCapabilityTestRunnerError
            .xcodebuildExecutableChangedDuringExecution(executable.path)) {
            try await runner.run(declaration: declaration, evidenceRoot: root)
        }
    }

    private func makeFixture() async throws -> (
        root: URL,
        snapshot: XcircuitePlanningActionDomainSnapshot,
        evidence: [XcircuitePlatformCapabilityTestEvidence],
        verifications: [XcircuitePlatformCapabilityTestEvidenceVerification]
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-retained-evidence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Xcircuite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "DRCEngine", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "retained-evidence",
            generatedAt: "1970-01-01T00:00:00Z"
        )
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let declarations = assessor.assess(actionDomainSnapshot: snapshot).testEvidence
        var evidence: [XcircuitePlatformCapabilityTestEvidence] = []
        var verifications: [XcircuitePlatformCapabilityTestEvidenceVerification] = []
        for declaration in declarations {
            let runner = XcircuitePlatformCapabilityTestRunner(
                processRunner: SuccessfulTestProcessRunner()
            )
            let run = try await runner.run(declaration: declaration, evidenceRoot: root)
            evidence.append(run.evidence)
            verifications.append(run.verification)
        }
        return (root, snapshot, evidence, verifications)
    }

    private func makeEvidenceRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Xcircuite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return root
    }

    private func xcircuiteDeclaration() throws -> XcircuitePlatformCapabilityTestEvidence {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "tool-identity",
            generatedAt: "1970-01-01T00:00:00Z"
        )
        return try #require(
            XcircuitePlatformCapabilityReadinessAssessor()
                .assess(actionDomainSnapshot: snapshot)
                .testEvidence
                .first { $0.packagePath == "Xcircuite" }
        )
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary evidence root: \(error.localizedDescription)")
        }
    }
}

private struct SuccessfulTestProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        return TimedProcessResult(
            exitCode: 0,
            standardOutput: "** TEST SUCCEEDED **",
            standardError: ""
        )
    }
}

private struct MutatingTestProcessRunner: TimedProcessRunning {
    let executableURL: URL

    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        try Data("xcodebuild-after".utf8).write(to: executableURL, options: .atomic)
        return TimedProcessResult(
            exitCode: 0,
            standardOutput: "** TEST SUCCEEDED **",
            standardError: ""
        )
    }
}
