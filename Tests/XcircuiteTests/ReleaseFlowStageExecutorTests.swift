import DesignFlowKernel
import Foundation
import PDKCore
import PhysicalDesignCore
import QualificationEngine
import ReleaseEngine
import ReleaseCore
import SignoffEngine
import TapeoutEngine
import Testing
import ToolQualification
import DesignFlowKernel
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
        let requestURL = root.appending(path: "signoff-request.json")
        try encode(request).write(to: requestURL, options: [.atomic])
        let context = makeContext(root: root, runID: runID)
        let result = try await ReleaseSignoffFlowStageExecutor(requestInput: .path("signoff-request.json"))
            .execute(
                stage: FlowStageDefinition(stageID: "release.signoff", displayName: "Release signoff"),
                context: context
            )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/release.signoff/raw/result.json").path))
    }

    @Test("tapeout executor persists a blocked prerequisite result")
    func tapeoutPersistsBlockedPrerequisite() async throws {
        let root = try makeRoot(name: "release-tapeout-stage")
        defer { removeRoot(root) }
        let runID = "release-tapeout-stage"
        let layout = try makeArtifact(
            path: "layout/top.gds",
            kind: .layout,
            format: .gdsii,
            sha256: String(repeating: "a", count: 64),
            byteCount: 4
        )
        let bundle = try makeArtifact(
            path: "release/signoff.json",
            kind: .release,
            format: .json,
            sha256: String(repeating: "b", count: 64),
            byteCount: 1
        )
        let physical = PhysicalDesignReference(layoutArtifact: layout, topCell: "TOP", layoutDigest: layout.sha256)
        let request = TapeoutRequest(
            runID: runID,
            inputs: [],
            signoffBundle: SignoffBundleReference(
                artifact: bundle,
                designDigest: String(repeating: "1", count: 64),
                pdkDigest: String(repeating: "2", count: 64),
                finalLayoutDigest: physical.layoutDigest,
                bundleDigest: String(repeating: "c", count: 64)
            ),
            physicalDesign: physical,
            pdk: PDKReference(
                manifest: bundle,
                processID: "process",
                version: "1",
                digest: String(repeating: "2", count: 64)
            ),
            foundryID: "foundry",
            releaseArtifact: bundle
        )
        let requestURL = root.appending(path: "tapeout-request.json")
        try encode(request).write(to: requestURL, options: [.atomic])
        let context = makeContext(root: root, runID: runID)
        let result = try await ReleaseTapeoutFlowStageExecutor(requestInput: .path("tapeout-request.json"))
            .execute(
                stage: FlowStageDefinition(stageID: "release.tapeout", displayName: "Release tapeout"),
                context: context
            )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/release.tapeout/raw/result.json").path))
    }

    @Test("qualification executor persists a blocked retained-artifact result")
    func qualificationPersistsBlockedResult() async throws {
        let root = try makeRoot(name: "release-qualification-stage")
        defer { removeRoot(root) }
        let runID = "release-qualification-stage"
        let suiteArtifact = try makeArtifact(
            path: "qualification/suite.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let reportArtifact = try makeArtifact(
            path: "qualification/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "b", count: 64),
            byteCount: 1
        )
        let scope = ToolQualificationScope(
            implementationID: "native-drc",
            binaryDigest: String(repeating: "c", count: 64),
            algorithmVersion: "native-drc-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "d", count: 64)
        )
        let lane = ReleaseQualificationLane(
            laneID: "drc:native-corpus",
            domain: "drc",
            kind: .nativeCorpus,
            reportPath: "reports/drc.json",
            evidenceExportPath: "evidence/drc.json"
        )
        let request = ReleaseQualificationRequest(
            runID: runID,
            projectRoot: nil,
            processProfileID: "sky130",
            suiteArtifact: suiteArtifact,
            qualificationReportArtifact: reportArtifact,
            domainReportArtifacts: [],
            evidenceArtifacts: [],
            toolEvidence: [],
            policy: ReleaseQualificationPolicy(
                policyID: "sky130-retained-corpus",
                processProfileID: "sky130",
                requiredLanes: [lane],
                requiredQualificationScope: scope
            )
        )
        let requestURL = root.appending(path: "qualification-request.json")
        try encode(request).write(to: requestURL, options: [.atomic])
        let context = makeContext(root: root, runID: runID)
        let result = try await ReleaseQualificationFlowStageExecutor(requestInput: .path("qualification-request.json"))
            .execute(
                stage: FlowStageDefinition(stageID: "release.qualification", displayName: "Release qualification"),
                context: context
            )

        #expect(result.status == .blocked)
        #expect(result.gates.contains { $0.status == .blocked })
        #expect(result.artifacts.count == 1)
        #expect(result.artifacts.first?.artifactID == "release-qualification-result")
        #expect(FileManager.default.fileExists(atPath: context.runDirectory
            .appending(path: "stages/release.qualification/raw/result.json").path))
    }

    @Test("qualification executor resumes through the shared approval gate")
    func qualificationParticipatesInApprovalAndResume() async throws {
        let root = try makeRoot(name: "release-qualification-resume")
        defer { removeRoot(root) }
        let runID = "release-qualification-resume"
        let request = ReleaseQualificationRequest(
            runID: runID,
            projectRoot: root.path,
            processProfileID: "fixture",
            suiteArtifact: try makeArtifact(path: "suite.json", kind: .report, format: .json),
            qualificationReportArtifact: try makeArtifact(path: "report.json", kind: .report, format: .json),
            domainReportArtifacts: [],
            evidenceArtifacts: [],
            toolEvidence: [],
            policy: ReleaseQualificationPolicy(
                policyID: "fixture-policy",
                processProfileID: "fixture",
                requiredLanes: [],
                requiredQualificationLevel: .corpusChecked
            )
        )
        try encode(request).write(to: root.appending(path: "qualification-request.json"), options: [.atomic])

        let stage = FlowStageDefinition(
            stageID: "release.qualification",
            displayName: "Release qualification",
            requiresApproval: true
        )
        let executor = ReleaseQualificationFlowStageExecutor(
            requestInput: .path("qualification-request.json"),
            engine: StubReleaseQualificationEvaluator()
        )
        let blocked = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Run release qualification and request human approval",
                stages: [stage]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )

        #expect(blocked.status == .blocked)
        #expect(blocked.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)

        let approval = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: runID,
                stageID: stage.stageID,
                verdict: .approved,
                reviewer: "release-reviewer"
            )
        )
        #expect(approval.approval.planSHA256 != nil)

        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.summary.runID == runID)
        #expect(resumed.summary.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .passed
        } == true)
        #expect(resumed.summary.approvalCount == 1)
        let manifest = try XcircuitePackageStore().loadRunManifest(runID: runID, inProjectAt: root)
        #expect(manifest.artifacts.contains { $0.artifactID == "release-qualification-result" })
    }

    @Test("release profile stages preserve one run lineage across approval and resume")
    func releaseProfilePreservesRunLineage() async throws {
        let root = try makeRoot(name: "release-profile-lineage")
        defer { removeRoot(root) }
        let runID = "release-profile-lineage"

        let signoffRequest = SignoffRequest(
            runID: runID,
            inputs: [],
            profileID: "digital",
            designDigest: String(repeating: "1", count: 64),
            pdkDigest: String(repeating: "2", count: 64),
            evidence: []
        )
        try encode(signoffRequest).write(
            to: root.appending(path: "signoff-request.json"),
            options: [.atomic]
        )

        let qualificationRequest = ReleaseQualificationRequest(
            runID: runID,
            projectRoot: root.path,
            processProfileID: "sky130",
            suiteArtifact: try makeArtifact(path: "suite.json", kind: .report, format: .json),
            qualificationReportArtifact: try makeArtifact(path: "report.json", kind: .report, format: .json),
            domainReportArtifacts: [],
            evidenceArtifacts: [],
            toolEvidence: [],
            policy: ReleaseQualificationPolicy(
                policyID: "lineage-policy",
                processProfileID: "sky130",
                requiredLanes: [],
                requiredQualificationLevel: .corpusChecked
            )
        )
        try encode(qualificationRequest).write(
            to: root.appending(path: "qualification-request.json"),
            options: [.atomic]
        )

        let tapeoutRequest = try makeTapeoutRequest(runID: runID)
        try encode(tapeoutRequest).write(
            to: root.appending(path: "tapeout-request.json"),
            options: [.atomic]
        )

        let profileRequest = try makeProfileRequest(runID: runID)
        try encode(profileRequest).write(
            to: root.appending(path: "profile-request.json"),
            options: [.atomic]
        )

        let stages = [
            FlowStageDefinition(
                stageID: "release.signoff",
                displayName: "Release signoff",
                requiresApproval: true
            ),
            FlowStageDefinition(
                stageID: "release.qualification",
                displayName: "Release qualification",
                requiresApproval: true
            ),
            FlowStageDefinition(
                stageID: "release.tapeout",
                displayName: "Release tapeout",
                requiresApproval: true
            ),
            FlowStageDefinition(
                stageID: "release.profile",
                displayName: "Release profile eligibility"
            ),
        ]
        let signoff = ReleaseSignoffFlowStageExecutor(
            requestInput: .path("signoff-request.json"),
            engine: StubSignoffEvaluator()
        )
        let qualification = ReleaseQualificationFlowStageExecutor(
            requestInput: .path("qualification-request.json"),
            engine: StubReleaseQualificationEvaluator()
        )
        let tapeout = ReleaseTapeoutFlowStageExecutor(
            requestInput: .path("tapeout-request.json"),
            engine: StubTapeoutPackaging()
        )
        let profile = ReleaseProfileEligibilityFlowStageExecutor(
            requestInput: .path("profile-request.json"),
            engine: StubReleaseProfileEligibilityEvaluator()
        )
        let executors: [any FlowStageExecutor] = [signoff, qualification, tapeout, profile]
        let request = FlowOperationRequest(
            projectRoot: root,
            runID: runID,
            intent: "Execute the complete release profile flow.",
            stages: stages
        )

        let first = try await DefaultFlowOrchestrator().run(
            request: request,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(first.status == .blocked)
        #expect(first.runID == runID)
        #expect(first.stages.map(\.stageID) == ["release.signoff"])

        _ = try recordApproval(root: root, runID: runID, stageID: "release.signoff")
        let afterSignoff = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(afterSignoff.result.status == .blocked)
        #expect(afterSignoff.summary.runID == runID)
        #expect(afterSignoff.summary.stages.map(\.stageID) == [
            "release.qualification",
            "release.signoff",
        ])

        _ = try recordApproval(root: root, runID: runID, stageID: "release.qualification")
        let afterQualification = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(afterQualification.result.status == .blocked)
        #expect(afterQualification.summary.runID == runID)
        #expect(afterQualification.summary.stages.map(\.stageID) == [
            "release.qualification",
            "release.signoff",
            "release.tapeout",
        ])

        _ = try recordApproval(root: root, runID: runID, stageID: "release.tapeout")
        let completed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )
        #expect(completed.result.status == .succeeded)
        #expect(completed.summary.runID == runID)
        #expect(completed.summary.stages.map(\.stageID) == [
            "release.profile",
            "release.qualification",
            "release.signoff",
            "release.tapeout",
        ])
        #expect(completed.summary.approvalCount == 3)

        let manifest = try XcircuitePackageStore().loadRunManifest(runID: runID, inProjectAt: root)
        #expect(manifest.runID == runID)
        #expect(manifest.artifacts.contains { $0.artifactID == "release-signoff-result" })
        #expect(manifest.artifacts.contains { $0.artifactID == "release-qualification-result" })
        #expect(manifest.artifacts.contains { $0.artifactID == "release-tapeout-result" })
        #expect(manifest.artifacts.contains { $0.artifactID == "release-profile-eligibility-result" })
        #expect(manifest.artifacts.contains { $0.artifactID == "approval-review-release-signoff" })
        #expect(manifest.artifacts.contains { $0.artifactID == "approval-review-release-qualification" })
        #expect(manifest.artifacts.contains { $0.artifactID == "approval-review-release-tapeout" })
        #expect(manifest.artifacts.allSatisfy { $0.producedByRunID == nil || $0.producedByRunID == runID })
    }

    @Test("release stage runtime specs round-trip through the agent-facing contract")
    func releaseRuntimeSpecsRoundTrip() throws {
        let specs: [XcircuiteFlowStageExecutorSpec] = [
            .releaseQualification(.init(requestPath: "requests/qualification.json")),
            .releaseSignoff(.init(requestPath: "requests/signoff.json")),
            .releaseTapeout(.init(requestPath: "requests/tapeout.json")),
            .releaseProfile(.init(requestPath: "requests/profile.json")),
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
            "release.qualification",
            "release.signoff",
            "release.tapeout",
            "release.profile",
        ])
        #expect(decoded.executors.map { $0.makeDescriptor().toolID } == [
            "native-release-qualification",
            "native-release-signoff",
            "native-release-tapeout",
            "native-release-profile-eligibility",
        ])
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
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
        let root = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
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

    private func recordApproval(root: URL, runID: String, stageID: String) throws -> FlowGateApprovalResult {
        try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: runID,
                stageID: stageID,
                verdict: .approved,
                reviewer: "release-reviewer"
            )
        )
    }

    private func makeTapeoutRequest(runID: String) throws -> TapeoutRequest {
        let artifact = try makeArtifact(
            path: "release/signoff.json",
            kind: .release,
            format: .json,
            sha256: String(repeating: "b", count: 64),
            byteCount: 1
        )
        let physical = PhysicalDesignReference(
            layoutArtifact: artifact,
            topCell: "TOP",
            layoutDigest: artifact.sha256
        )
        return TapeoutRequest(
            runID: runID,
            inputs: [],
            signoffBundle: SignoffBundleReference(
                artifact: artifact,
                designDigest: String(repeating: "1", count: 64),
                pdkDigest: String(repeating: "2", count: 64),
                finalLayoutDigest: physical.layoutDigest,
                bundleDigest: String(repeating: "c", count: 64)
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

    private func makeProfileRequest(runID: String) throws -> ReleaseProfileEligibilityRequest {
        let artifact: (String, String) throws -> ArtifactReference = { (id: String, digest: String) in
            try makeArtifact(
                artifactID: id,
                path: ".xcircuite/runs/\(runID)/\(id).json",
                kind: .report,
                format: .json,
                sha256: digest,
                byteCount: 1
            )
        }
        let packet = try artifact("decision-packet", String(repeating: "d", count: 64))
        return ReleaseProfileEligibilityRequest(
            runID: runID,
            profileID: "digital",
            processProfileID: "sky130",
            requiredQualificationLevel: .corpusChecked,
            requiredPromotionStatus: .corpusChecked,
            signoff: ReleaseProfileStageEvidence(
                stageID: "release.signoff",
                runID: runID,
                status: .completed,
                resultArtifact: try artifact("signoff", String(repeating: "a", count: 64)),
                profileID: "digital",
                designDigest: String(repeating: "1", count: 64),
                pdkDigest: String(repeating: "2", count: 64),
                approved: true
            ),
            qualification: ReleaseProfileStageEvidence(
                stageID: "release.qualification",
                runID: runID,
                status: .completed,
                resultArtifact: try artifact("qualification", String(repeating: "b", count: 64)),
                processProfileID: "sky130",
                qualified: true,
                qualificationLevel: .corpusChecked,
                promotionStatus: .corpusChecked
            ),
            tapeout: ReleaseProfileStageEvidence(
                stageID: "release.tapeout",
                runID: runID,
                status: .completed,
                resultArtifact: try artifact("tapeout", String(repeating: "c", count: 64)),
                processProfileID: "sky130",
                designDigest: String(repeating: "1", count: 64),
                pdkDigest: String(repeating: "2", count: 64),
                approved: true
            ),
            decisionPacketArtifact: packet,
            approval: ReleaseApprovalRecord(
                runID: runID,
                stageID: "release.profile",
                verdict: .approved,
                reviewer: "release-reviewer",
                reviewerKind: .human,
                stageResultSHA256: packet.sha256,
                stageResultByteCount: Int64(packet.byteCount)
            )
        )
    }
    private func makeArtifact(
        artifactID: String? = nil,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        sha256: String? = nil,
        byteCount: UInt64? = nil
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
                hexadecimalValue: sha256 ?? String(repeating: "0", count: 64)
            ),
            byteCount: byteCount ?? 1
        )
    }
}

private struct StubSignoffEvaluator: SignoffEvaluating {
    func execute(_ request: SignoffRequest) async throws -> SignoffResult {
        let now = Date()
        return SignoffResult(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            metadata: try ExecutionProvenance(
                producer: try ProducerIdentity(
                    kind: .engine,
                    identifier: "stub-release-signoff",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: SignoffPayload(
                approved: true,
                blockedAxes: [],
                bundle: nil,
                profileID: request.profileID,
                designDigest: request.designDigest,
                pdkDigest: request.pdkDigest
            )
        )
    }
}

private struct StubTapeoutPackaging: TapeoutPackaging {
    func execute(_ request: TapeoutRequest) async throws -> TapeoutResult {
        let now = Date()
        return TapeoutResult(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            metadata: try ExecutionProvenance(
                producer: try ProducerIdentity(
                    kind: .engine,
                    identifier: "stub-release-tapeout",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: TapeoutPayload(
                releaseArtifact: request.releaseArtifact,
                checksum: String(repeating: "e", count: 64),
                approved: true,
                signoffBundleDigest: request.signoffBundle.bundleDigest,
                layoutDigest: request.physicalDesign.layoutDigest,
                pdkDigest: request.pdk.digest
            )
        )
    }
}

private struct StubReleaseProfileEligibilityEvaluator: ReleaseProfileEligibilityEvaluating {
    func execute(_ request: ReleaseProfileEligibilityRequest) async throws -> ReleaseProfileEligibilityResult {
        let now = Date()
        return ReleaseProfileEligibilityResult(
            schemaVersion: 1,
            runID: request.runID,
            status: .completed,
            metadata: try ExecutionProvenance(
                producer: try ProducerIdentity(
                    kind: .engine,
                    identifier: "stub-release-profile",
                    version: "1.0.0"
                ),
                startedAt: now,
                completedAt: now
            ),
            payload: ReleaseProfileEligibilityPayload(
                eligible: true,
                status: .eligible,
                profileID: request.profileID,
                processProfileID: request.processProfileID,
                requiredQualificationLevel: request.requiredQualificationLevel,
                requiredPromotionStatus: request.requiredPromotionStatus,
                decisionPacketDigest: request.decisionPacketArtifact.sha256
            )
        )
    }
}
