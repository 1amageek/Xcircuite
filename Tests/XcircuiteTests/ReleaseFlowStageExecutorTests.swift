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
            evidence: [],
            bundleOutput: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(runID)/release/signoff-bundle.json"
                ),
                role: .output,
                kind: .evidence,
                format: .json
            )
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
        #expect(result.artifacts.contains {
            $0.artifactID == "release-signoff-request" && $0.locator.role == .input
        })
        #expect(result.artifacts.first {
            $0.artifactID == "release-signoff-result"
        }?.producer?.identifier == "native.release.signoff")
        let signoffRequestArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-signoff-request"
        })
        let signoffResultArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-signoff-result"
        })
        let signoffResultData = try await context.infrastructure.loadArtifactContent(
            for: signoffResultArtifact
        )
        let persistedSignoff = try decode(
            SignoffResult.self,
            from: signoffResultData
        )
        #expect(persistedSignoff.provenance.inputs.contains(signoffRequestArtifact))
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
        #expect(result.artifacts.contains {
            $0.artifactID == "release-authorization-request" && $0.locator.role == .input
        })
        #expect(result.artifacts.first {
            $0.artifactID == "release-authorization-result"
        }?.producer?.identifier == "release.authorization")
        let authorizationRequestArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-authorization-request"
        })
        let authorizationResultArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-authorization-result"
        })
        let authorizationResultData = try await context.infrastructure.loadArtifactContent(
            for: authorizationResultArtifact
        )
        let persistedAuthorization = try decode(
            ReleaseAuthorizationResult.self,
            from: authorizationResultData
        )
        #expect(persistedAuthorization.evidence.provenance.inputs.contains(
            authorizationRequestArtifact
        ))
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/release.authorization/raw/result.json").path))
    }

    @Test("authorization executor rejects an inconsistent authorized result")
    func authorizationRejectsInconsistentAuthorizedResult() async throws {
        let root = try makeRoot(name: "release-authorization-invalid-result")
        defer { removeRoot(root) }
        let runID = "release-authorization-invalid-result"
        let request = try makeAuthorizationRequest(runID: runID)
        try encode(request).write(
            to: root.appending(path: "authorization-request.json"),
            options: [.atomic]
        )
        let context = try await makeContext(root: root, runID: runID)

        let result = try await ReleaseAuthorizationFlowStageExecutor(
            requestInput: .path("authorization-request.json"),
            authorizerFactory: { _ in InconsistentAuthorizedReleaseAuthorizer() }
        ).execute(
            stage: FlowStageDefinition(
                stageID: "release.authorization",
                displayName: "Release authorization"
            ),
            context: context
        )

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains {
            $0.code == "RELEASE_AUTHORIZATION_RESULT_INVALID"
        })
        #expect(!result.artifacts.contains {
            $0.artifactID == "release-authorization-result"
        })
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
        #expect(result.artifacts.contains { $0.artifactID == "release-tapeout-result" })
        #expect(result.artifacts.contains {
            $0.artifactID == "release-tapeout-request" && $0.locator.role == .input
        })
        #expect(result.artifacts.first {
            $0.artifactID == "release-tapeout-result"
        }?.producer?.identifier == "native.release.tapeout")
        let tapeoutRequestArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-tapeout-request"
        })
        let tapeoutResultArtifact = try #require(result.artifacts.first {
            $0.artifactID == "release-tapeout-result"
        })
        let tapeoutResultData = try await context.infrastructure.loadArtifactContent(
            for: tapeoutResultArtifact
        )
        let persistedTapeout = try decode(
            TapeoutResult.self,
            from: tapeoutResultData
        )
        #expect(persistedTapeout.provenance.inputs.contains(tapeoutRequestArtifact))
        #expect(result.artifacts.contains(request.signoffBundle.artifact))
        #expect(FileManager.default.fileExists(atPath: try context.xcircuiteRunDirectory()
            .appending(path: "stages/release.tapeout/raw/result.json").path))
    }

    @Test("tapeout executor persists stream-out but blocks handoff without qualified geometric XOR")
    func tapeoutBlocksUnqualifiedHandoffThroughWorkspaceStore() async throws {
        let root = try makeRoot(name: "release-tapeout-completed-stage")
        defer { removeRoot(root) }
        let runID = "release-tapeout-completed-stage"
        let request = try makeCompletedTapeoutRequest(root: root, runID: runID)
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
        #expect(result.diagnostics.contains { $0.code == "LAYOUT_XOR_QUALIFICATION_REQUIRED" })
        #expect(result.artifacts.contains { $0.locator == request.handoffOutput } == false)
        let streamOut = try #require(result.artifacts.first {
            $0.locator == request.streamOut.output
        })
        #expect(streamOut.producer?.identifier == request.streamOut.generatorID)
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let retainedStream = try await store.load(streamOut, relativeTo: root)
        let sourceStream = try Data(
            contentsOf: root.appending(path: request.physicalDesign.layoutArtifact.path)
        )
        #expect(retainedStream == sourceStream)
    }

    @Test("release stage runtime specs round-trip through the agent-facing contract")
    func releaseRuntimeSpecsRoundTrip() throws {
        let specs: [XcircuiteFlowStageExecutorSpec] = [
            .releaseEvidenceAssembly(.init(requestInput: .path("requests/evidence-assembly.json"))),
            .releaseSignoff(.init(requestInput: .path("requests/signoff.json"))),
            .releaseAuthorization(.init(requestInput: .path("requests/authorization.json"))),
            .releaseTapeout(.init(
                requestInput: .path("requests/tapeout.json"),
                geometricXOR: .init(
                    qualificationInput: .stageArtifact(.init(
                        stageID: "qualification.layout-xor",
                        kind: .evidence,
                        format: .json
                    )),
                    reportOutput: ArtifactLocator(
                        location: try ArtifactLocation(
                            workspaceRelativePath: ".xcircuite/runs/release/xor/report.json"
                        ),
                        role: .output,
                        kind: .report,
                        format: .json
                    ),
                    timeoutSeconds: 120
                )
            )),
        ]
        let runtimeSpec = XcircuiteFlowRuntimeSpec(executors: specs)
        try runtimeSpec.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoded = try JSONDecoder().decode(
            XcircuiteFlowRuntimeSpec.self,
            from: try encoder.encode(runtimeSpec)
        )

        #expect(decoded.executors == specs)

        #expect(decoded.executors.map(\.stageID) == [
            "release.evidence-assembly",
            "release.signoff",
            "release.authorization",
            "release.tapeout",
        ])
        #expect(decoded.executors.map { $0.makeDescriptor().toolID } == [
            "xcircuite.release-evidence-assembler",
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
        let requirements = TapeoutReleaseRequirements(
            expectedTopCell: physical.topCell,
            expectedUnitsPerDatabaseUnit: 1_000,
            requiredLayerIDs: ["metal1"],
            requiredPadCells: ["PAD"],
            requiredSeal: "seal"
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
            authorization: artifact,
            physicalDesign: physical,
            pdk: PDKReference(
                manifest: artifact,
                processID: "sky130",
                version: "1",
                digest: String(repeating: "2", count: 64)
            ),
            streamOut: StreamOutGenerationRequest(
                output: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: "release/top.gds"),
                    role: .output,
                    kind: .layout,
                    format: .gdsii
                ),
                topCell: physical.topCell,
                unitsPerDatabaseUnit: 1_000,
                layerMap: ["metal1": 1],
                hierarchyDepth: 1,
                seal: "seal",
                padCells: ["PAD"],
                generatorID: "native.release.stream-out",
                generatorVersion: "1.0.0",
                requirements: requirements
            ),
            foundryID: "foundry",
            handoffOutput: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/handoff.json"),
                role: .output,
                kind: .release,
                format: .json
            )
        )
    }

    private func makeCompletedTapeoutRequest(root: URL, runID: String) throws -> TapeoutRequest {
        let layout = try writeArtifact(
            Data([0, 6, 0, 2, 0, 4, 0, 0, 0, 0]),
            path: "layout/top.gds",
            kind: .layout,
            format: .gdsii,
            root: root,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "physical-design",
                version: "1.0.0"
            )
        )
        let pdkManifest = try writeArtifact(
            Data("pdk".utf8),
            path: "pdk/manifest.json",
            kind: .technology,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "pdk-kit",
                version: "1.0.0"
            )
        )
        let evidence = try writeArtifact(
            Data("release-evidence".utf8),
            path: "reports/signoff.json",
            kind: .report,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .tool,
                identifier: "fixture-signoff-tool",
                version: "1.0.0"
            )
        )
        let designDigest = String(repeating: "1", count: 64)
        let issuedAt = Date(timeIntervalSince1970: 2_000)
        let bundle = SignoffBundle(
            bundleID: "release-bundle",
            profileID: "digital",
            designDigest: designDigest,
            pdkDigest: pdkManifest.digest.hexadecimalValue,
            finalLayoutDigest: layout.digest.hexadecimalValue,
            axisResults: ReleaseSignoffAxis.allCases.map {
                SignoffAxisResult(
                    axis: $0,
                    disposition: .passed,
                    evidenceIDs: ["evidence-\($0.rawValue)"],
                    reason: "passed"
                )
            },
            waivers: [],
            evidenceArtifacts: [evidence],
            toolQualificationScopes: [ToolQualificationScope(
                implementationID: "fixture-signoff-tool",
                toolVersion: "1.0.0",
                binaryDigest: String(repeating: "a", count: 64),
                algorithmVersion: "fixture-v1",
                processProfileID: "fixture-process",
                processProfileDigest: String(repeating: "b", count: 64),
                deckDigest: String(repeating: "c", count: 64),
                pdkID: "fixture-pdk",
                pdkDigest: pdkManifest.digest.hexadecimalValue,
                oracle: ToolOracleQualificationScope(
                    implementationID: "fixture-signoff-oracle",
                    version: "1.0.0",
                    binaryDigest: String(repeating: "d", count: 64)
                )
            )],
            evidenceDigest: evidence.digest.hexadecimalValue,
            issuedAt: issuedAt
        )
        let bundleArtifact = try writeArtifact(
            bundle.canonicalData(),
            path: "release/signoff-bundle.json",
            kind: .release,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                build: String(repeating: "a", count: 64)
            )
        )
        let planArtifact = try writeArtifact(
            Data("approved plan".utf8),
            path: "release/plan.json",
            kind: .request,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel",
                version: "1.0.0"
            )
        )
        let approval = FlowApprovalRecord(
            runID: runID,
            stageID: "release.authorization",
            verdict: .approved,
            reviewer: "human-reviewer",
            reviewerKind: .human,
            createdAt: issuedAt.addingTimeInterval(0.25),
            evidence: FlowApprovalEvidenceBinding(
                plan: planArtifact,
                stageResult: bundleArtifact
            )
        )
        let authorizationProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            build: String(repeating: "b", count: 64)
        )
        let authorizationResult = ReleaseAuthorizationResult(
            status: .authorized,
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: designDigest,
                pdkDigest: pdkManifest.digest.hexadecimalValue,
                finalLayoutDigest: layout.digest.hexadecimalValue
            ),
            approval: approval,
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: authorizationProducer,
                inputs: [bundleArtifact, planArtifact, evidence],
                startedAt: issuedAt.addingTimeInterval(0.25),
                completedAt: issuedAt.addingTimeInterval(0.5)
            )
        )
        let authorizationArtifact = try writeArtifact(
            encode(authorizationResult),
            path: "release/authorization.json",
            kind: .report,
            format: .json,
            root: root,
            producer: authorizationProducer
        )
        let physicalDesign = PhysicalDesignReference(
            layoutArtifact: layout,
            topCell: "TOP",
            layoutDigest: layout.digest.hexadecimalValue
        )
        let requirements = TapeoutReleaseRequirements(
            expectedTopCell: physicalDesign.topCell,
            expectedUnitsPerDatabaseUnit: 1_000,
            requiredLayerIDs: ["metal1"],
            requiredPadCells: ["PAD"],
            requiredSeal: "seal"
        )
        return TapeoutRequest(
            runID: runID,
            inputs: [authorizationArtifact, bundleArtifact, pdkManifest, layout, evidence],
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: designDigest,
                pdkDigest: pdkManifest.digest.hexadecimalValue,
                finalLayoutDigest: layout.digest.hexadecimalValue
            ),
            authorization: authorizationArtifact,
            physicalDesign: physicalDesign,
            pdk: PDKReference(
                manifest: pdkManifest,
                processID: "fixture-process",
                version: "1",
                digest: pdkManifest.digest.hexadecimalValue
            ),
            streamOut: StreamOutGenerationRequest(
                output: ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: "release/top.gds"),
                    role: .output,
                    kind: .layout,
                    format: .gdsii
                ),
                topCell: physicalDesign.topCell,
                unitsPerDatabaseUnit: 1_000,
                layerMap: ["metal1": 1],
                hierarchyDepth: 1,
                seal: "seal",
                padCells: ["PAD"],
                generatorID: "native.release.stream-out",
                generatorVersion: "1.0.0",
                requirements: requirements
            ),
            foundryID: "fixture-foundry",
            handoffOutput: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/handoff.json"),
                role: .output,
                kind: .release,
                format: .json
            ),
            evidence: [evidence]
        )
    }

    private func writeArtifact(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        root: URL,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: format
            ),
            relativeTo: root,
            producer: producer
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
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
            approval: request.approval,
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

private struct InconsistentAuthorizedReleaseAuthorizer: ReleaseAuthorizing {
    func execute(_ request: ReleaseAuthorizationRequest) async throws -> ReleaseAuthorizationResult {
        let now = Date()
        return ReleaseAuthorizationResult(
            status: .authorized,
            signoffBundle: nil,
            approval: request.approval,
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "release.authorization.invalid",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            )
        )
    }
}
