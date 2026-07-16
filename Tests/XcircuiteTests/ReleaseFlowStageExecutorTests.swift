import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import ReleaseEngine
import SignoffEngine
import TapeoutEngine
import Testing
import ToolQualification
@testable import Xcircuite

@Suite("Release flow stage executors")
struct ReleaseFlowStageExecutorTests {
    @Test("signoff executor persists a blocked result")
    func signoffPersistsBlockedResult() async throws {
        let root = try makeRoot(name: "release-signoff-stage")
        defer { removeRoot(root) }
        let runID = "release-signoff-stage"
        let request = SignoffRequest(
            runID: runID,
            inputs: [],
            profileID: "digital",
            designDigest: String(repeating: "1", count: 64),
            pdkDigest: String(repeating: "2", count: 64),
            evidence: []
        )
        try encode(request).write(
            to: root.appending(path: "signoff-request.json"),
            options: [.atomic]
        )
        let context = try await makeContext(root: root, runID: runID)

        let result = try await ReleaseSignoffFlowStageExecutor(
            requestInput: .path("signoff-request.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: "release.signoff",
                displayName: "Release signoff"
            ),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/release.signoff/raw/result.json").path))
    }

    @Test("authorization executor persists a blocked result")
    func authorizationPersistsBlockedResult() async throws {
        let root = try makeRoot(name: "release-authorization-stage")
        defer { removeRoot(root) }
        let runID = "release-authorization-stage"
        let request = try makeAuthorizationRequest(runID: runID)
        try encode(request).write(
            to: root.appending(path: "authorization-request.json"),
            options: [.atomic]
        )
        let context = try await makeContext(root: root, runID: runID)

        let result = try await ReleaseAuthorizationFlowStageExecutor(
            requestInput: .path("authorization-request.json"),
            authorizerFactory: { _ in StubReleaseAuthorizer(status: .blocked) }
        ).execute(
            stage: FlowStageDefinition(
                stageID: "release.authorization",
                displayName: "Release authorization"
            ),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.gates == [FlowGateResult(
            gateID: "release-authorization",
            status: .blocked
        )])
        #expect(result.artifacts.count == 1)
        #expect(result.artifacts.first?.artifactID == "release-authorization-result")
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/release.authorization/raw/result.json").path))
    }

    @Test("tapeout executor persists a blocked prerequisite result")
    func tapeoutPersistsBlockedPrerequisite() async throws {
        let root = try makeRoot(name: "release-tapeout-stage")
        defer { removeRoot(root) }
        let runID = "release-tapeout-stage"
        let request = try makeTapeoutRequest(runID: runID)
        try encode(request).write(
            to: root.appending(path: "tapeout-request.json"),
            options: [.atomic]
        )
        let context = try await makeContext(root: root, runID: runID)

        let result = try await ReleaseTapeoutFlowStageExecutor(
            requestInput: .path("tapeout-request.json")
        ).execute(
            stage: FlowStageDefinition(
                stageID: "release.tapeout",
                displayName: "Release tapeout"
            ),
            context: context
        )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/release.tapeout/raw/result.json").path))
    }

    @Test("release stage runtime specs round-trip through the agent-facing contract")
    func releaseRuntimeSpecsRoundTrip() throws {
        let specs: [XcircuiteFlowStageExecutorSpec] = [
            .releaseSignoff(.init(requestPath: "requests/signoff.json")),
            .releaseAuthorization(.init(requestPath: "requests/authorization.json")),
            .releaseTapeout(.init(requestPath: "requests/tapeout.json")),
        ]
        let runtimeSpec = XcircuiteFlowRuntimeSpec(executors: specs)
        try runtimeSpec.validate(requireCompleteToolEvidence: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoded = try JSONDecoder().decode(
            XcircuiteFlowRuntimeSpec.self,
            from: try encoder.encode(runtimeSpec)
        )

        #expect(decoded.executors.map(\.stageID) == [
            "release.signoff",
            "release.authorization",
            "release.tapeout",
        ])
        #expect(decoded.executors.map { $0.makeDescriptor().toolID } == [
            "native-release-signoff",
            "native-release-authorization",
            "native-release-tapeout",
        ])
    }

    private func makeAuthorizationRequest(runID: String) throws -> ReleaseAuthorizationRequest {
        let producer = try releaseFixtureProducer()
        let bundleArtifact = try makeArtifact(
            artifactID: "signoff-bundle",
            path: "release/signoff-bundle.json",
            kind: .release,
            format: .json,
            digestHexadecimalValue: String(repeating: "b", count: 64),
            producer: producer
        )
        let planArtifact = try makeArtifact(
            artifactID: "release-plan",
            path: "release/plan.json",
            kind: .request,
            format: .json,
            digestHexadecimalValue: String(repeating: "a", count: 64),
            producer: producer
        )
        let signoffBundle = SignoffBundleReference(
            artifact: bundleArtifact,
            designDigest: String(repeating: "1", count: 64),
            pdkDigest: String(repeating: "2", count: 64),
            finalLayoutDigest: String(repeating: "3", count: 64)
        )
        let evaluatedAt = Date()
        return ReleaseAuthorizationRequest(
            runID: runID,
            stageID: "release.authorization",
            signoffBundle: signoffBundle,
            approval: FlowApprovalRecord(
                runID: runID,
                stageID: "release.authorization",
                verdict: .approved,
                reviewer: "release-reviewer",
                createdAt: evaluatedAt,
                evidence: FlowApprovalEvidenceBinding(
                    plan: planArtifact,
                    stageResult: bundleArtifact
                )
            ),
            toolTrustDecisions: [],
            toolQualificationRequests: [],
            requiredToolIDs: [],
            evaluatedAt: evaluatedAt
        )
    }

    private func makeTapeoutRequest(runID: String) throws -> TapeoutRequest {
        let producer = try releaseFixtureProducer()
        let artifact = try makeArtifact(
            path: "release/signoff.json",
            kind: .release,
            format: .json,
            digestHexadecimalValue: String(repeating: "b", count: 64),
            producer: producer
        )
        let physical = PhysicalDesignReference(
            layoutArtifact: artifact,
            topCell: "TOP",
            layoutDigest: artifact.digest.hexadecimalValue
        )
        return TapeoutRequest(
            runID: runID,
            inputs: [],
            signoffBundle: SignoffBundleReference(
                artifact: artifact,
                designDigest: String(repeating: "1", count: 64),
                pdkDigest: String(repeating: "2", count: 64),
                finalLayoutDigest: physical.layoutDigest
            ),
            physicalDesign: physical,
            pdk: PDKReference(
                manifest: artifact,
                processID: "sky130",
                version: "1",
                digest: String(repeating: "2", count: 64)
            ),
            foundryID: "foundry",
            releaseArtifact: artifact
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
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

    private func makeArtifact(
        artifactID: String? = nil,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        digestHexadecimalValue: String,
        byteCount: UInt64 = 1,
        producer: ProducerIdentity
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try artifactID.map { try ArtifactID(rawValue: $0) },
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: digestHexadecimalValue
            ),
            byteCount: byteCount,
            producer: producer
        )
    }

    private func releaseFixtureProducer() throws -> ProducerIdentity {
        try ProducerIdentity(
            kind: .engine,
            identifier: "release-flow-stage-tests",
            version: "1"
        )
    }
}

private struct StubReleaseAuthorizer: ReleaseAuthorizing {
    let status: ReleaseAuthorizationStatus

    func execute(_ request: ReleaseAuthorizationRequest) async throws -> ReleaseAuthorizationResult {
        let now = Date()
        return ReleaseAuthorizationResult(
            status: status,
            signoffBundle: status == .authorized ? request.signoffBundle : nil,
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "release.authorization",
                    version: "1.0.0",
                    build: "stub.release.authorization"
                ),
                invocation: ExecutionInvocation.inProcess(
                    entryPoint: "stub.release.authorization"
                ),
                startedAt: now,
                completedAt: now
            )
        )
    }
}
