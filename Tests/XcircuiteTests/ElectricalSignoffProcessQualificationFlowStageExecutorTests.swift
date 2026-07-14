import DesignFlowKernel
import CircuiteFoundation
import ElectricalSignoffCore
import ElectricalSignoffEngine
import ElectricalSignoffQualification
import Foundation
import LogicIR
import PDKCore
import PhysicalDesignCore
import Testing
import ToolQualification
import DesignFlowKernel
@testable import Xcircuite

@Suite("Electrical signoff process qualification flow adapter")
struct ElectricalSignoffProcessQualificationFlowStageExecutorTests {
    @Test("process qualification stage persists qualified evidence and review artifacts", .timeLimit(.minutes(1)))
    func persistsQualifiedEvidence() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-process-qualification-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-process-qualification-flow-run"
        let store = XcircuiteWorkspaceStore()
        let processRequest = try materializeArtifactReferences(
            try makeProcessQualificationRequest(runID: runID),
            root: root,
            store: store,
            runID: runID
        )
        let requestURL = root.appending(path: "process-qualification.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(processRequest).write(to: requestURL)
        let requestReference = try store.fileReference(
            forProjectRelativePath: "process-qualification.json",
            artifactID: "process-qualification-input",
            kind: .request,
            format: .json,
            inProjectAt: root,
            verifiedByRunID: runID
        )
        let executor = ElectricalSignoffProcessQualificationFlowStageExecutor(
            requestInput: .artifact(try foundationReference(requestReference))
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            storage: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.process-qualification",
                displayName: "Electrical process qualification",
                requiresApproval: true
            ),
            context: context
        )

        #expect(result.status == FlowStageStatus.succeeded)
        #expect(result.gates.map(\.status) == [FlowGateStatus.passed])
        let evidenceReference = try #require(result.artifacts.first {
            $0.artifactID == "electrical-signoff-process-qualification-evidence"
        })
        let evidenceURL = try store.url(forProjectRelativePath: evidenceReference.path, inProjectAt: root)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let evidence = try decoder.decode(ToolProcessQualificationEvidence.self, from: Data(contentsOf: evidenceURL))
        #expect(evidence.status == ToolProcessQualificationStatus.qualified)
        #expect(evidence.scope.isCompleteForPDK)
        #expect(evidence.independenceVerified)
    }

    @Test("process qualification resumes only after a human flow approval", .timeLimit(.minutes(1)))
    func resumesAfterHumanApproval() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-process-qualification-resume-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-process-qualification-resume-run"
        let store = XcircuiteWorkspaceStore()
        let processRequest = try materializeArtifactReferences(
            try makeProcessQualificationRequest(runID: runID),
            root: root,
            store: store,
            runID: runID
        )
        let requestURL = root.appending(path: "process-qualification.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(processRequest).write(to: requestURL)
        let requestReference = try store.fileReference(
            forProjectRelativePath: "process-qualification.json",
            artifactID: "process-qualification-input",
            kind: .request,
            format: .json,
            inProjectAt: root,
            verifiedByRunID: runID
        )
        let stage = FlowStageDefinition(
            stageID: ElectricalSignoffProcessQualificationRequest.requiredApprovalStageID,
            displayName: "Electrical process qualification",
            requiresApproval: true
        )
        let executor = ElectricalSignoffProcessQualificationFlowStageExecutor(
            requestInput: .artifact(try foundationReference(requestReference))
        )
        let operation = FlowOperationRequest(
            projectRoot: root,
            runID: runID,
            intent: "Qualify the electrical signoff implementation with human review.",
            stages: [stage]
        )
        let first = try await DefaultFlowOrchestrator().run(
            request: operation,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(first.status == FlowRunStatus.blocked)
        #expect(first.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == FlowGateStatus.incomplete
        } == true)

        let approval = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: runID,
                stageID: stage.stageID,
                verdict: .approved,
                reviewer: "human-reviewer",
                reviewerKind: .human,
                decidedAt: Date(timeIntervalSince1970: 1_100)
            )
        )
        #expect(approval.approval.reviewerKind == .human)

        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: root, runID: runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )
        #expect(resumed.result.status == FlowRunStatus.succeeded)
        #expect(resumed.result.stages.first?.status == FlowStageStatus.succeeded)
    }

    @Test("process qualification blocks when a retained artifact is missing", .timeLimit(.minutes(1)))
    func blocksMissingArtifact() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-process-qualification-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-process-qualification-missing-run"
        let processRequest = try makeProcessQualificationRequest(runID: runID)
        let requestURL = root.appending(path: "process-qualification.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(processRequest).write(to: requestURL)
        let store = XcircuiteWorkspaceStore()
        let requestReference = try store.fileReference(
            forProjectRelativePath: "process-qualification.json",
            artifactID: "process-qualification-input",
            kind: .request,
            format: .json,
            inProjectAt: root,
            verifiedByRunID: runID
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            storage: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let result = try await ElectricalSignoffProcessQualificationFlowStageExecutor(
            requestInput: .artifact(try foundationReference(requestReference))
        ).execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.process-qualification",
                displayName: "Electrical process qualification",
                requiresApproval: true
            ),
            context: context
        )

        #expect(result.status == FlowStageStatus.blocked)
        #expect(result.diagnostics.contains {
            $0.code == "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_ARTIFACT_INTEGRITY_INVALID"
        })
        #expect(result.artifacts.count == 1)
    }

    @Test("process qualification blocks an automated or rejected approval record", .timeLimit(.minutes(1)))
    func blocksNonHumanApproval() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "electrical-process-qualification-approval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runID = "electrical-process-qualification-approval-run"
        let store = XcircuiteWorkspaceStore()
        var processRequest = try materializeArtifactReferences(
            try makeProcessQualificationRequest(runID: runID),
            root: root,
            store: store,
            runID: runID
        )
        let approvalURL = root.appending(path: "qualification/human-approval.json")
        try JSONEncoder().encode(XcircuiteApprovalRecord(
            runID: runID,
            stageID: ElectricalSignoffProcessQualificationRequest.requiredApprovalStageID,
            verdict: .approved,
            reviewer: "automated-reviewer",
            reviewerKind: .agent
        )).write(to: approvalURL)
        let updatedApprovalLegacyReference = try store.fileReference(
            forProjectRelativePath: "qualification/human-approval.json",
            artifactID: "human-approval",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID,
            verifiedByRunID: runID
        )
        let updatedApprovalReference = try foundationReference(updatedApprovalLegacyReference)
        var processEvidence = processRequest.processEvidence
        processEvidence.evidenceArtifacts = processEvidence.evidenceArtifacts.map {
            $0.artifactID == "human-approval" ? updatedApprovalReference : $0
        }
        processEvidence.approvalEvidence = processEvidence.approvalEvidence.map { item in
            var updated = item
            if item.artifact?.artifactID == "human-approval" {
                updated.artifact = updatedApprovalReference
            }
            return updated
        }
        processRequest.processEvidence = processEvidence
        let integrityIssues = DefaultElectricalSignoffProcessQualificationArtifactVerifier().verify(
            processRequest,
            projectRoot: root
        )
        #expect(integrityIssues.contains(where: { (issue: ElectricalSignoffProcessQualificationArtifactIntegrityIssue) in
            issue.category == "approval"
                && issue.integrity.issues.contains {
                    $0.detail?.contains("approved human decision") == true
                }
        }))
        let requestURL = root.appending(path: "process-qualification.json")
        let requestEncoder = JSONEncoder()
        requestEncoder.dateEncodingStrategy = .iso8601
        try requestEncoder.encode(processRequest).write(to: requestURL)
        let requestReference = try store.fileReference(
            forProjectRelativePath: "process-qualification.json",
            artifactID: "process-qualification-input",
            kind: .request,
            format: .json,
            inProjectAt: root,
            verifiedByRunID: runID
        )
        let context = FlowExecutionContext(
            projectRoot: root,
            runID: runID,
            runDirectory: root.appending(path: "run"),
            storage: store,
            toolRegistry: ToolRegistry(),
            healthResults: [:]
        )
        let result = try await ElectricalSignoffProcessQualificationFlowStageExecutor(
            requestInput: .artifact(try foundationReference(requestReference))
        ).execute(
            stage: FlowStageDefinition(
                stageID: "electrical-signoff.process-qualification",
                displayName: "Electrical process qualification",
                requiresApproval: true
            ),
            context: context
        )

        #expect(result.status == FlowStageStatus.blocked)
        #expect(result.diagnostics.contains {
            $0.code == "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_ARTIFACT_INTEGRITY_INVALID"
        })
    }

    private func makeProcessQualificationRequest(runID: String) throws -> ElectricalSignoffProcessQualificationRequest {
        let data = Data("retained-input".utf8)
        let reference = try makeFoundationArtifact(
            id: "fixture-input",
            path: "fixture.json",
            role: .input,
            kind: .netlist,
            format: .json,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
        let layoutReference = try makeFoundationArtifact(
            id: "fixture-layout",
            path: "fixture.json",
            role: .input,
            kind: .layout,
            format: .json,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
        let pdkReference = try makeFoundationArtifact(
            id: "fixture-pdk",
            path: "fixture.json",
            role: .input,
            kind: .technology,
            format: .json,
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
        let request = ElectricalSignoffRequest(
            runID: runID,
            inputs: [reference],
            design: LogicDesignReference(artifact: reference.locator, topDesignName: "top", designDigest: "design"),
            physicalDesign: PhysicalDesignReference(layoutArtifact: layoutReference, topCell: "top", layoutDigest: "layout"),
            pdk: PDKReference(manifest: pdkReference, processID: "fixture", version: "1", digest: pdkReference.sha256),
            configuration: ElectricalSignoffConfiguration(requiredAxes: [.erc])
        )
        let qualificationCase = ElectricalSignoffQualificationCase(
            caseID: "clean-erc",
            kind: .positive,
            axis: .erc,
            request: request,
            expected: ElectricalSignoffExpectedObservation(status: .completed, violationCount: 0)
        )
        let spec = ElectricalSignoffQualificationSpec(
            corpusID: "electrical-process-corpus",
            corpusVersion: "1",
            pdkDigest: request.pdk.digest,
            requireIndependentOracle: true,
            cases: [qualificationCase]
        )
        let oracle = ElectricalSignoffOracleObservation(
            oracleID: "independent-electrical-oracle",
            toolVersion: "oracle-1",
            pdkDigest: request.pdk.digest,
            status: .completed,
            violationCount: 0
        )
        let caseResult = ElectricalSignoffQualificationCaseResult(
            caseID: qualificationCase.caseID,
            axis: .erc,
            cornerID: request.configuration.operatingCondition.id,
            pdkCornerID: request.configuration.operatingCondition.pdkCornerID,
            nativeStatus: .completed,
            nativeViolationCount: 0,
            nativeDiagnosticCodes: [],
            nativeMetrics: [],
            nativeArtifacts: [],
            metricComparisons: [],
            oracle: oracle,
            oracleAgreementPassed: true,
            passed: true,
            failureCodes: []
        )
        let report = ElectricalSignoffQualificationReport(
            corpusID: spec.corpusID,
            corpusVersion: spec.corpusVersion,
            pdkDigest: spec.pdkDigest,
            runID: runID,
            implementationID: "native-electrical-signoff",
            generatedAt: Date(timeIntervalSince1970: 900),
            completed: true,
            passed: true,
            qualificationLevel: .oracleChecked,
            caseResults: [caseResult]
        )
        let scope = ToolQualificationScope(
            implementationID: "native-electrical-signoff",
            binaryDigest: String(repeating: "b", count: 64),
            algorithmVersion: "1",
            processProfileID: request.pdk.processID,
            deckDigest: "deck-digest",
            pdkID: request.pdk.processID,
            pdkDigest: request.pdk.digest
        )
        let processEvidence = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "electrical-process-qualification",
            toolID: "native-electrical-signoff",
            scope: scope,
            corpusEvidence: [evidence(
                id: "corpus-evidence",
                kind: .corpus,
                artifact: try artifact(id: "corpus-report", character: "a"),
                scope: scope
            )],
            oracleEvidence: [evidence(
                id: "oracle-evidence",
                kind: .oracle,
                artifact: try artifact(id: "oracle-observation", character: "b"),
                scope: scope
            )],
            healthEvidence: [evidence(
                id: "health-evidence",
                kind: .healthCheck,
                artifact: try artifact(id: "health-check", character: "c"),
                scope: scope
            )],
            approvalEvidence: [evidence(
                id: "approval-evidence",
                kind: .productionApproval,
                artifact: try artifact(id: "human-approval", character: "d"),
                scope: scope
            )],
            evidenceArtifacts: [
                try artifact(id: "corpus-report", character: "a"),
                try artifact(id: "oracle-observation", character: "b"),
                try artifact(id: "health-check", character: "c"),
                try artifact(id: "human-approval", character: "d"),
            ],
            independenceVerified: true,
            qualifiedAt: Date(timeIntervalSince1970: 900),
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )
        return ElectricalSignoffProcessQualificationRequest(
            qualificationID: "electrical-process-qualification",
            toolID: "native-electrical-signoff",
            qualificationSpec: spec,
            qualificationReport: report,
            scope: scope,
            processEvidence: processEvidence,
            qualifiedAt: Date(timeIntervalSince1970: 900),
            expiresAt: Date(timeIntervalSince1970: 2_000),
            evaluatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func evidence(
        id: String,
        kind: ToolEvidenceKind,
        artifact: ArtifactReference,
        scope: ToolQualificationScope
    ) -> ToolEvidence {
        ToolEvidence(
            evidenceID: id,
            kind: kind,
            artifact: artifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                observedCounts: ["evidence": 1],
                scope: scope,
                qualificationID: "electrical-process-qualification",
                independenceVerified: true
            ),
            checkedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func artifact(id: String, character: Character) throws -> ArtifactReference {
        try makeFoundationArtifact(
            id: id,
            path: "qualification/\(id).json",
            role: .input,
            kind: .report,
            format: .json,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: character, count: 64)
            ),
            byteCount: 1
        )
    }

    private func materializeArtifactReferences(
        _ request: ElectricalSignoffProcessQualificationRequest,
        root: URL,
        store: XcircuiteWorkspaceStore,
        runID: String
    ) throws -> ElectricalSignoffProcessQualificationRequest {
        var materialized = request
        var processEvidence = request.processEvidence
        processEvidence.corpusEvidence = try materializeEvidence(
            processEvidence.corpusEvidence,
            root: root,
            store: store,
            runID: runID
        )
        processEvidence.oracleEvidence = try materializeEvidence(
            processEvidence.oracleEvidence,
            root: root,
            store: store,
            runID: runID
        )
        processEvidence.healthEvidence = try materializeEvidence(
            processEvidence.healthEvidence,
            root: root,
            store: store,
            runID: runID
        )
        processEvidence.approvalEvidence = try materializeEvidence(
            processEvidence.approvalEvidence,
            root: root,
            store: store,
            runID: runID
        )
        processEvidence.evidenceArtifacts = try materialize(
            processEvidence.evidenceArtifacts,
            root: root,
            store: store,
            runID: runID
        )
        processEvidence.corpusEvidence = rebindEvidence(
            processEvidence.corpusEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.oracleEvidence = rebindEvidence(
            processEvidence.oracleEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.healthEvidence = rebindEvidence(
            processEvidence.healthEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        processEvidence.approvalEvidence = rebindEvidence(
            processEvidence.approvalEvidence,
            artifacts: processEvidence.evidenceArtifacts
        )
        materialized.processEvidence = processEvidence
        return materialized
    }

    private func rebindEvidence(
        _ evidence: [ToolEvidence],
        artifacts: [ArtifactReference]
    ) -> [ToolEvidence] {
        let artifactsByKey = Dictionary(
            uniqueKeysWithValues: artifacts.map {
                ("\($0.artifactID ?? "")|\($0.path)", $0)
            }
        )
        return evidence.map { item in
            var rebound = item
            if let artifact = item.artifact {
                let key = "\(artifact.artifactID ?? "")|\(artifact.path)"
                rebound.artifact = artifactsByKey[key]
            }
            return rebound
        }
    }

    private func materializeEvidence(
        _ evidence: [ToolEvidence],
        root: URL,
        store: XcircuiteWorkspaceStore,
        runID: String
    ) throws -> [ToolEvidence] {
        try evidence.map { item in
            var materialized = item
            if let artifact = item.artifact {
                materialized.artifact = try materialize(
                    [artifact],
                    root: root,
                    store: store,
                    runID: runID
                )[0]
            }
            return materialized
        }
    }

    private func materialize(
        _ references: [ArtifactReference],
        root: URL,
        store: XcircuiteWorkspaceStore,
        runID: String
    ) throws -> [ArtifactReference] {
        try references.map { reference in
            let url = root.appending(path: reference.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data: Data
            if reference.artifactID == "human-approval" {
                data = try JSONEncoder().encode(XcircuiteApprovalRecord(
                    runID: runID,
                    stageID: ElectricalSignoffProcessQualificationRequest.requiredApprovalStageID,
                    verdict: .approved,
                    reviewer: "human-reviewer",
                    reviewerKind: .human,
                    createdAt: Date(timeIntervalSince1970: 950)
                ))
            } else {
                data = Data("retained-artifact".utf8)
            }
            try data.write(to: url)
            let legacyReference = try store.fileReference(
                forProjectRelativePath: reference.path,
                artifactID: reference.artifactID,
                kind: .report,
                format: .json,
                inProjectAt: root,
                producedByRunID: runID,
                verifiedByRunID: runID
            )
            return try foundationReference(legacyReference, role: reference.locator.role)
        }
    }
}

private func makeFoundationArtifact(
    id: String,
    path: String,
    role: ArtifactRole,
    kind: ArtifactKind,
    format: ArtifactFormat,
    digest: ContentDigest,
    byteCount: UInt64
) throws -> ArtifactReference {
    ArtifactReference(
        id: try ArtifactID(rawValue: id),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        ),
        digest: digest,
        byteCount: byteCount
    )
}
