import DFTCore
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicIR
import PDKCore
import Testing
import ToolQualification
import TimingCore
import DesignFlowKernel
@testable import Xcircuite

@Suite("DFT flow stage adapter")
struct DFTFlowStageExecutorTests {
    @Test("headless adapter executes scan insertion and verifies artifacts")
    func executesScanStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-adapter-run"
        let sourceSnapshot = try LogicDesignSnapshotCodec.finalized(makeGateSnapshot())
        let designData = try LogicDesignSnapshotCodec.encode(sourceSnapshot)
        let designDigest = try LogicDesignSnapshotCodec.digest(sourceSnapshot)
        let designPath = root.appending(path: "design.json")
        try designData.write(to: designPath, options: .atomic)
        let designArtifact = XcircuiteFileReference(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: designData),
            byteCount: Int64(designData.count)
        )
        let libraryManifest = makeCellLibraryManifest()
        let libraryData = try DFTCellLibraryManifestCodec.encode(libraryManifest)
        let libraryPath = root.appending(path: "cell-library.json")
        try libraryData.write(to: libraryPath, options: .atomic)
        let libraryArtifact = XcircuiteFileReference(
            artifactID: "cell-library",
            path: "cell-library.json",
            kind: .technology,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: libraryData),
            byteCount: Int64(libraryData.count)
        )
        let libraryReference = DFTCellLibraryReference(
            artifact: try foundationReference(libraryArtifact),
            processID: libraryManifest.processID,
            version: libraryManifest.version,
            manifestDigest: try DFTCellLibraryManifestCodec.digest(libraryManifest)
        )
        let request = try makeRequest(
            runID: runID,
            designArtifact: try foundationReference(designArtifact),
            designDigest: designDigest,
            cellLibraryReference: libraryReference
        )
        let requestURL = root.appending(path: "dft-request.json")
        let requestData = try DFTArtifactJSONEncoder().encode(request)
        try requestData.write(to: requestURL, options: .atomic)
        let context = makeContext(root: root, runID: runID)

        let result = try await DFTFlowStageExecutor(
            stageID: "dft.scan",
            requestInput: .path("dft-request.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.scan", displayName: "DFT scan insertion"),
            context: context
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.gateID == "dft" && $0.status == .passed })
        #expect(result.artifacts.count == 4)
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: "dft/runs/\(runID)/transformed-design.json")
            .path))
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: ".xcircuite/runs/\(runID)/stages/dft.scan/raw/foundation-evidence.json")
            .path))
    }

    @Test("DFT stage specs round-trip")
    func stageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.scan",
                requestPath: "dft-request.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT downstream evidence bundle spec is agent-operable")
    func downstreamEvidenceBundleSpecRoundTrip() throws {
        let sources = [
            DFTReleaseDownstreamEvidenceSource(domain: .equivalence, role: "equivalence", input: .path("equivalence.json")),
            DFTReleaseDownstreamEvidenceSource(domain: .drc, role: "drc", input: .path("drc.json")),
            DFTReleaseDownstreamEvidenceSource(domain: .lvs, role: "lvs", input: .path("lvs.json")),
            DFTReleaseDownstreamEvidenceSource(domain: .pex, role: "pex", input: .path("pex.json")),
        ]
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release-evidence",
                requestPath: "",
                releaseEvidenceSources: sources
            )
        )
        let runtimeSpec = XcircuiteFlowRuntimeSpec(executors: [spec])
        try runtimeSpec.validate(requireCompleteToolEvidence: false)
        let decoded = try JSONDecoder().decode(
            XcircuiteFlowStageExecutorSpec.self,
            from: JSONEncoder().encode(spec)
        )
        #expect(decoded == spec)
    }

    @Test("DFT downstream evidence bundle blocks when a required domain is missing")
    func blocksIncompleteDownstreamEvidenceBundle() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        for domain in ["equivalence", "drc", "lvs"] {
            try Data("{\"status\":\"passed\"}".utf8).write(
                to: root.appending(path: "\(domain).json"),
                options: .atomic
            )
        }
        let executor = DFTReleaseDownstreamEvidenceBundleFlowStageExecutor(
            sources: [
                DFTReleaseDownstreamEvidenceSource(domain: .equivalence, role: "equivalence", input: .path("equivalence.json")),
                DFTReleaseDownstreamEvidenceSource(domain: .drc, role: "drc", input: .path("drc.json")),
                DFTReleaseDownstreamEvidenceSource(domain: .lvs, role: "lvs", input: .path("lvs.json")),
            ]
        )

        let result = try await executor.execute(
            stage: FlowStageDefinition(stageID: "dft.release-evidence", displayName: "DFT downstream evidence"),
            context: makeContext(root: root, runID: "dft-evidence-negative")
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code == "DFT_RELEASE_EVIDENCE_BUNDLE_INVALID" && $0.message.contains("pex")
        })
        #expect(result.artifacts.isEmpty)
    }

    @Test("DFT release stage spec round-trips its review inputs")
    func releaseStageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseQualificationPath: "dft-qualification-provenance.json",
                releaseRequestDigest: String(repeating: "f", count: 64),
                releaseProcessQualificationEvidencePath: "dft-process-qualification-evidence.json",
                releaseDownstreamEvidencePath: "dft-downstream.json",
                releaseApprovalPath: "dft-approval.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT release spec requires independent process qualification evidence")
    func releaseSpecRequiresProcessQualificationEvidence() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseQualificationPath: "dft-qualification-provenance.json",
                releaseRequestDigest: String(repeating: "f", count: 64),
                releaseDownstreamEvidencePath: "dft-downstream.json"
            )
        )

        do {
            try XcircuiteFlowRuntimeSpec(executors: [spec]).validate(
                requireCompleteToolEvidence: false
            )
            Issue.record("DFT release spec unexpectedly validated without process qualification evidence.")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error.localizedDescription.contains("process qualification evidence input"))
        }
    }

    @Test("DFT release spec requires process evidence without retained qualification provenance")
    func releaseSpecRequiresProcessEvidenceWithoutQualificationProvenance() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseDownstreamEvidencePath: "dft-downstream.json"
            )
        )

        do {
            try XcircuiteFlowRuntimeSpec(executors: [spec]).validate(
                requireCompleteToolEvidence: false
            )
            Issue.record("DFT release spec unexpectedly validated without process qualification evidence.")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error.localizedDescription.contains("process qualification evidence input"))
        }
    }

    @Test("DFT release spec accepts a stage-bound process evidence input")
    func releaseSpecAcceptsStageBoundProcessEvidence() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseProcessQualificationEvidenceInput: .stageRawArtifact(
                    .init(
                        stageID: "dft.qualification",
                        relativePath: "dft-process-qualification-evidence.json"
                    )
                ),
                releaseDownstreamEvidencePath: "dft-downstream.json"
            )
        )

        try XcircuiteFlowRuntimeSpec(executors: [spec]).validate(
            requireCompleteToolEvidence: false
        )
        let decoded = try JSONDecoder().decode(
            XcircuiteFlowStageExecutorSpec.self,
            from: JSONEncoder().encode(spec)
        )
        #expect(decoded == spec)
    }

    @Test("DFT release spec accepts independent evidence without retained qualification provenance")
    func releaseSpecAcceptsIndependentProcessEvidenceWithoutQualificationProvenance() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.release",
                requestPath: "dft-request.json",
                releaseResultPath: "dft-result.json",
                releaseProcessQualificationEvidencePath: "dft-process-qualification-evidence.json",
                releaseDownstreamEvidencePath: "dft-downstream.json"
            )
        )

        try XcircuiteFlowRuntimeSpec(executors: [spec]).validate(
            requireCompleteToolEvidence: false
        )
    }

    @Test("DFT qualification stage spec round-trips its oracle inputs")
    func qualificationStageSpecRoundTrip() throws {
        let spec = XcircuiteFlowStageExecutorSpec.dft(
            XcircuiteFlowStageExecutorSpec.DFT(
                stageID: "dft.qualification",
                requestPath: "dft-request.json",
                qualificationCorpusPath: "dft-corpus.json",
                qualificationObservationsPath: "dft-observations.json",
                qualificationEvidencePath: "dft-qualification-evidence.json",
                qualificationProcessEvidenceBuildPath: "dft-process-qualification-build-request.json"
            )
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(XcircuiteFlowStageExecutorSpec.self, from: data)

        #expect(decoded == spec)
    }

    @Test("DFT qualification stage correlates retained artifacts and records provenance")
    func executesQualificationStage() async throws {
        let root = try makeRoot()
        defer { removeRoot(root) }
        let runID = "dft-qualification-run"
        let pdkDigest = String(repeating: "e", count: 64)
        let requestDigest = String(repeating: "a", count: 64)
        let expectation = DFTOracleCaseExpectation(expectedStatus: .completed)
        let expectationData = try JSONEncoder().encode(expectation)
        let oracleDirectory = root.appending(path: "oracle")
        try FileManager.default.createDirectory(
            at: oracleDirectory,
            withIntermediateDirectories: true
        )
        let oracleURL = oracleDirectory.appending(path: "expectation.json")
        try expectationData.write(to: oracleURL, options: .atomic)
        let oracleArtifact = XcircuiteFileReference(
            artifactID: "oracle-case",
            path: "oracle/expectation.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: expectationData),
            byteCount: Int64(expectationData.count)
        )
        let corpus = DFTOracleCorpus(
            corpusID: "fixture-corpus",
            revision: "fixture-revision",
            processID: "fixture-process",
            pdkDigest: pdkDigest,
            cases: [
                DFTOracleCorpusCase(
                    caseID: "scan-case",
                    operation: .scanInsertion,
                    requestDigest: requestDigest,
                    expectation: expectation,
                    oracleArtifact: try foundationReference(oracleArtifact)
                ),
            ]
        )
        let nativeResult = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: "native-case-run",
            status: .completed,
            metadata: DFTExecutionMetadata(
                engineID: "fixture-native",
                implementationID: "fixture-native",
                implementationVersion: "1",
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 2)
            ),
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil
            )
        )
        let observations = [
            DFTOracleCaseObservation(
                caseID: "scan-case",
                operation: .scanInsertion,
                requestDigest: requestDigest,
                result: nativeResult
            ),
        ]
        let corpusURL = root.appending(path: "dft-corpus.json")
        let observationsURL = root.appending(path: "dft-observations.json")
        try JSONEncoder().encode(corpus).write(to: corpusURL, options: .atomic)
        try JSONEncoder().encode(observations).write(to: observationsURL, options: .atomic)

        let correlation = try await DFTOracleCorrelationEngine(
            artifactLoader: FileSystemDFTOracleArtifactLoader(rootURL: root)
        ).correlate(corpus: corpus, observations: observations)
        let evidence = try correlation.makeQualificationEvidence(
            evidenceID: "fixture-qualification",
            engineID: "fixture-native",
            implementationID: "fixture-native",
            approvedBy: "reviewer",
            artifacts: [corpus.cases[0].oracleArtifact]
        )
        let evidenceURL = root.appending(path: "dft-qualification-evidence.json")
        try JSONEncoder().encode(evidence).write(to: evidenceURL, options: .atomic)

        let processArtifacts = try [
            ("corpus", "qualification/corpus.json"),
            ("oracle", "qualification/oracle.json"),
            ("health", "qualification/health.json"),
            ("approval", "qualification/approval.json"),
        ].map { id, path in
            try foundationReference(writeArtifact(
                root: root,
                path: path,
                artifactID: "process-\(id)",
                contents: "{\"evidence\":\"\(id)\"}"
            ))
        }
        let processScope = ToolQualificationScope(
            implementationID: "fixture-native",
            binaryDigest: String(repeating: "1", count: 64),
            algorithmVersion: "fixture-v1",
            processProfileID: corpus.processID,
            deckDigest: String(repeating: "2", count: 64),
            pdkID: "fixture-pdk",
            pdkDigest: corpus.pdkDigest
        )
        let makeProcessEvidence: (String, ToolEvidenceKind, ArtifactReference) -> ToolEvidence = {
            id,
            kind,
            artifact in
            ToolEvidence(
                evidenceID: id,
                kind: kind,
                artifact: artifact,
                qualification: ToolEvidenceQualificationSummary(
                    qualified: true,
                    scope: processScope,
                    qualificationID: "fixture-process-qualification",
                    independenceVerified: true
                ),
                checkedAt: Date()
            )
        }
        let processBuildRequest = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "fixture-process-qualification",
            toolID: "fixture-native",
            scope: processScope,
            corpusEvidence: [makeProcessEvidence("corpus", .corpus, processArtifacts[0])],
            oracleEvidence: [makeProcessEvidence("oracle", .oracle, processArtifacts[1])],
            healthEvidence: [makeProcessEvidence("health", .healthCheck, processArtifacts[2])],
            approvalEvidence: [makeProcessEvidence("approval", .productionApproval, processArtifacts[3])],
            evidenceArtifacts: processArtifacts,
            independenceVerified: true,
            qualifiedAt: Date().addingTimeInterval(-60),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let processBuildURL = root.appending(path: "dft-process-qualification-build-request.json")
        try JSONEncoder().encode(processBuildRequest).write(to: processBuildURL, options: .atomic)

        let result = try await DFTQualificationFlowStageExecutor(
            corpusInput: .path("dft-corpus.json"),
            observationsInput: .path("dft-observations.json"),
            qualificationEvidenceInput: .path("dft-qualification-evidence.json"),
            processQualificationEvidenceBuildInput: .path(
                "dft-process-qualification-build-request.json"
            )
        ).execute(
            stage: FlowStageDefinition(
                stageID: "dft.qualification",
                displayName: "DFT qualification"
            ),
            context: makeContext(root: root, runID: runID)
        )
        #expect(result.status == .succeeded)
        #expect(result.gates.contains {
            $0.gateID == "dft-qualification" && $0.status == .passed
        })
        #expect(FileManager.default.fileExists(atPath: root
            .appending(path: ".xcircuite/runs/\(runID)/stages/dft.qualification/raw/dft-qualification-provenance.json")
            .path))
        #expect(result.artifacts.contains {
            $0.artifactID == "dft-process-qualification-evidence"
        })
        let processEvidenceURL = root
            .appending(path: ".xcircuite/runs/\(runID)/stages/dft.qualification/raw/dft-process-qualification-evidence.json")
        let processEvidence = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: Data(contentsOf: processEvidenceURL)
        )
        #expect(processEvidence.isQualified(at: Date(), requirePDKScope: true))
    }

    @Test("DFT release stage verifies downstream artifacts and records eligibility")
    func executesReleaseStage() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }

        let result = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(result.status == .succeeded)
        #expect(result.gates.contains { $0.gateID == "dft-release" && $0.status == .passed })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-result" })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-eligibility" })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-artifact-bundle" })
        #expect(FileManager.default.fileExists(atPath: fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-eligibility.json")
            .path))
        let eligibilityURL = fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-eligibility.json")
        let eligibilityJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: eligibilityURL)
        ) as? [String: Any]
        let requiredArtifactIDs = eligibilityJSON?["requiredArtifactIDs"] as? [String] ?? []
        #expect(requiredArtifactIDs.contains("dft-process-qualification-evidence"))
        let bundleURL = fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-artifact-bundle.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(
            DFTReleaseArtifactBundle.self,
            from: Data(contentsOf: bundleURL)
        )
        #expect(bundle.runID == fixture.request.runID)
        #expect(bundle.result.artifactID == "dft-release-result")
        #expect(bundle.processQualificationEvidence.artifactID == "dft-process-qualification-evidence")
        #expect(bundle.downstreamEvidence.count == 4)
        #expect(bundle.candidateArtifacts.contains {
            $0.artifactID == "dft-process-qualification-evidence"
        })
        let qualifiedResult = try decoder.decode(
            DFTResult.self,
            from: Data(contentsOf: fixture.root.appending(path: bundle.result.path))
        )
        #expect(qualifiedResult.payload.qualification.status == .processQualified)
    }

    @Test("DFT release stage blocks without independent process qualification evidence")
    func blocksReleaseWithoutProcessQualificationEvidence() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }

        let result = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code == "DFT_RELEASE_PROCESS_QUALIFICATION_INVALID"
        })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-review-resume" })
    }

    @Test("DFT release stage blocks process qualification evidence for another PDK")
    func blocksMismatchedProcessQualificationEvidence() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }
        let evidenceURL = fixture.root.appending(path: "dft-process-qualification-evidence.json")
        var evidence = try JSONDecoder().decode(
            ToolProcessQualificationEvidence.self,
            from: Data(contentsOf: evidenceURL)
        )
        evidence.scope.pdkDigest = String(repeating: "f", count: 64)
        try DFTArtifactJSONEncoder().encode(evidence).write(to: evidenceURL, options: .atomic)

        let result = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code == "DFT_RELEASE_PROCESS_QUALIFICATION_INVALID"
                && $0.message.contains("DFT_PROCESS_QUALIFICATION_PDK_MISMATCH")
        })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-review-resume" })
    }

    @Test("DFT release binds process-specific model outcomes to qualified model evidence")
    func bindsProcessSpecificModelQualification() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }
        let resultURL = fixture.root.appending(path: "dft-result.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result = try decoder.decode(
            DFTResult.self,
            from: Data(contentsOf: resultURL)
        )
        result.payload.faultCoverage = 1
        result.payload.coverageEvidence = DFTCoverageEvidence(
            faultUniverseName: "process-faults",
            faultUniverseRevision: "r1",
            faultUniverseDigest: String(repeating: "1", count: 64),
            declaredFaultCount: 1,
            excludedFaultCount: 0,
            detectedFaultCount: 1,
            untestableFaultCount: 0,
            abortedFaultCount: 0,
            coverage: 1,
            assumptions: ["fixture process model"],
            qualification: result.payload.qualification,
            outcomes: [DFTFaultOutcome(
                faultID: "m1-leakage",
                status: .detected,
                patternID: "pattern-1",
                modelID: "process-model-a",
                reason: "fixture process model detected the fault"
            )]
        )
        try DFTArtifactJSONEncoder().encode(result).write(to: resultURL, options: .atomic)

        let executor = DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        )
        let stage = FlowStageDefinition(stageID: "dft.release", displayName: "DFT release")
        let context = makeContext(root: fixture.root, runID: fixture.request.runID)
        let blocked = try await executor.execute(stage: stage, context: context)

        #expect(blocked.status == .blocked)
        #expect(blocked.diagnostics.contains {
            $0.code == "DFT_RELEASE_PROCESS_QUALIFICATION_INVALID"
                && $0.message.contains("DFT_PROCESS_QUALIFICATION_MODEL_MISMATCH")
        })

        let evidenceURL = fixture.root.appending(path: "dft-process-qualification-evidence.json")
        var evidence = try decoder.decode(
            ToolProcessQualificationEvidence.self,
            from: Data(contentsOf: evidenceURL)
        )
        evidence.qualifiedModelIDs = ["process-model-a"]
        try DFTArtifactJSONEncoder().encode(evidence).write(to: evidenceURL, options: .atomic)

        let released = try await executor.execute(stage: stage, context: context)

        #expect(released.status == .succeeded)
        #expect(released.artifacts.contains { $0.artifactID == "dft-release-artifact-bundle" })
    }

    @Test("DFT release stage consumes process-qualified provenance from the qualification stage")
    func consumesQualificationProvenance() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }
        let resultURL = fixture.root.appending(path: "dft-result.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result = try decoder.decode(
            DFTResult.self,
            from: Data(contentsOf: resultURL)
        )
        result.payload.qualification = DFTQualificationProvenance(status: .smokeChecked)
        try DFTArtifactJSONEncoder().encode(result).write(to: resultURL, options: .atomic)

        let provenance = DFTQualificationProvenance(
            status: .processQualified,
            corpusRevision: "dft-corpus-r1",
            oracleEvidence: String(repeating: "b", count: 64),
            processID: fixture.request.pdk.processID,
            pdkDigest: fixture.request.pdk.digest,
            requestDigests: [String(repeating: "f", count: 64)]
        )
        let provenanceURL = fixture.root.appending(path: "dft-qualification-provenance.json")
        try DFTArtifactJSONEncoder().encode(provenance).write(to: provenanceURL, options: .atomic)

        let releaseResult = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json"),
            qualificationInput: .path("dft-qualification-provenance.json"),
            expectedQualificationRequestDigest: String(repeating: "f", count: 64),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(releaseResult.status == .succeeded)
        #expect(releaseResult.artifacts.contains { $0.artifactID == "dft-release-eligibility" })
        let eligibilityURL = fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-eligibility.json")
        let eligibilityJSON = try JSONSerialization.jsonObject(
            with: Data(contentsOf: eligibilityURL)
        ) as? [String: Any]
        let requiredArtifactIDs = eligibilityJSON?["requiredArtifactIDs"] as? [String] ?? []
        #expect(requiredArtifactIDs.contains("dft-qualification-provenance"))
    }

    @Test("DFT release stage blocks qualification provenance bound to another request")
    func blocksMismatchedQualificationRequestDigest() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }
        let resultURL = fixture.root.appending(path: "dft-result.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result = try decoder.decode(
            DFTResult.self,
            from: Data(contentsOf: resultURL)
        )
        result.payload.qualification = DFTQualificationProvenance(status: .smokeChecked)
        try DFTArtifactJSONEncoder().encode(result).write(to: resultURL, options: .atomic)

        let provenance = DFTQualificationProvenance(
            status: .processQualified,
            corpusRevision: "dft-corpus-r1",
            oracleEvidence: String(repeating: "b", count: 64),
            processID: fixture.request.pdk.processID,
            pdkDigest: fixture.request.pdk.digest,
            requestDigests: [String(repeating: "f", count: 64)]
        )
        try DFTArtifactJSONEncoder().encode(provenance).write(
            to: fixture.root.appending(path: "dft-qualification-provenance.json"),
            options: .atomic
        )

        let releaseResult = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            qualificationInput: .path("dft-qualification-provenance.json"),
            expectedQualificationRequestDigest: String(repeating: "a", count: 64),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(releaseResult.status == .blocked)
        #expect(releaseResult.diagnostics.contains {
            $0.code == "DFT_RELEASE_REVIEW_CONTRACT_INVALID"
        })
        #expect(releaseResult.artifacts.contains { $0.artifactID == "dft-release-review-resume" })
    }

    @Test("DFT release stage blocks tampered downstream artifacts before approval")
    func blocksTamperedReleaseArtifact() async throws {
        let fixture = try makeReleaseFixture(includeApproval: true)
        defer { removeRoot(fixture.root) }
        let transformedURL = fixture.root
            .appending(path: "dft/runs/\(fixture.request.runID)/transformed-design.json")
        try Data("tampered-design".utf8).write(to: transformedURL, options: .atomic)

        let result = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            approvalInput: .path("dft-approval.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code == "DFT_RELEASE_ARTIFACT_INTEGRITY_FAILED"
        })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-review-resume" })
    }

    @Test("DFT release stage persists a review resume contract when approval is missing")
    func blocksReleaseUntilApproval() async throws {
        let fixture = try makeReleaseFixture(includeApproval: false)
        defer { removeRoot(fixture.root) }

        let result = try await DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        ).execute(
            stage: FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
            context: makeContext(root: fixture.root, runID: fixture.request.runID)
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "DFT_RELEASE_APPROVAL_REQUIRED" })
        #expect(result.artifacts.contains { $0.artifactID == "dft-release-review-resume" })
        #expect(FileManager.default.fileExists(atPath: fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-review-resume.json")
            .path))
    }

    @Test("DFT release stage resumes through the Xcircuite generic approval gate")
    func resumesReleaseThroughFlowKernelApproval() async throws {
        let fixture = try makeReleaseFixture(includeApproval: false)
        defer { removeRoot(fixture.root) }
        let executor = DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .path("dft-downstream.json"),
            processQualificationEvidenceInput: .path("dft-process-qualification-evidence.json")
        )
        let stage = FlowStageDefinition(
            stageID: "dft.release",
            displayName: "DFT release",
            requiresApproval: false
        )
        let flowRequest = FlowOperationRequest(
            projectRoot: fixture.root,
            runID: fixture.request.runID,
            intent: "Run the DFT release review and resume flow.",
            stages: [stage]
        )
        let first = try await DefaultFlowOrchestrator().run(
            request: flowRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )

        #expect(first.status == .blocked)
        #expect(first.stages.first?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)

        let approval = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: fixture.root,
                runID: fixture.request.runID,
                stageID: "dft.release",
                verdict: .approved,
                reviewer: "human-reviewer",
                note: "Reviewed DFT, equivalence, DRC, LVS and PEX evidence."
            )
        )
        #expect(approval.approval.verdict == .approved)

        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(
                projectRoot: fixture.root,
                runID: fixture.request.runID
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [executor]
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.summary.approvalCount == 1)
        #expect(resumed.result.stages.first?.gates.contains {
            $0.gateID == "dft-release" && $0.status == .passed
        } == true)
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: fixture.request.runID,
            inProjectAt: fixture.root
        )
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-release-eligibility" })
    }

    @Test("DFT qualification and release stages compose through a retained provenance artifact")
    func composesQualificationAndReleaseStages() async throws {
        let fixture = try makeReleaseFixture(includeApproval: false)
        defer { removeRoot(fixture.root) }
        let pdkDigest = fixture.request.pdk.digest
        let requestDigest = String(repeating: "f", count: 64)
        let oracleDirectory = fixture.root.appending(path: "oracle")
        try FileManager.default.createDirectory(at: oracleDirectory, withIntermediateDirectories: true)
        let expectation = DFTOracleCaseExpectation(expectedStatus: .completed)
        let expectationData = try JSONEncoder().encode(expectation)
        let expectationURL = oracleDirectory.appending(path: "expectation.json")
        try expectationData.write(to: expectationURL, options: .atomic)
        let oracleArtifact = XcircuiteFileReference(
            artifactID: "oracle-case",
            path: "oracle/expectation.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: expectationData),
            byteCount: Int64(expectationData.count)
        )
        let corpus = DFTOracleCorpus(
            corpusID: "composed-corpus",
            revision: "composed-revision",
            processID: fixture.request.pdk.processID,
            pdkDigest: pdkDigest,
            cases: [
                DFTOracleCorpusCase(
                    caseID: "composed-case",
                    operation: .scanInsertion,
                    requestDigest: requestDigest,
                    expectation: expectation,
                    oracleArtifact: try foundationReference(oracleArtifact)
                ),
            ]
        )
        let timestamp = Date(timeIntervalSince1970: 1)
        let nativeResult = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: fixture.request.runID,
            status: .completed,
            metadata: DFTExecutionMetadata(
                engineID: "native-dft-fixture",
                implementationID: "native-dft-fixture",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: DFTPayload(transformedDesign: nil, faultCoverage: nil)
        )
        let observations = [
            DFTOracleCaseObservation(
                caseID: "composed-case",
                operation: .scanInsertion,
                requestDigest: requestDigest,
                result: nativeResult
            ),
        ]
        try JSONEncoder().encode(corpus).write(
            to: fixture.root.appending(path: "dft-corpus.json"),
            options: .atomic
        )
        try JSONEncoder().encode(observations).write(
            to: fixture.root.appending(path: "dft-observations.json"),
            options: .atomic
        )
        let correlation = try await DFTOracleCorrelationEngine(
            artifactLoader: FileSystemDFTOracleArtifactLoader(rootURL: fixture.root)
        ).correlate(corpus: corpus, observations: observations)
        let qualificationEvidence = try correlation.makeQualificationEvidence(
            evidenceID: "composed-qualification",
            engineID: "native-dft-fixture",
            implementationID: "native-dft-fixture",
            approvedBy: "qualification-reviewer",
            artifacts: [corpus.cases[0].oracleArtifact]
        )
        try JSONEncoder().encode(qualificationEvidence).write(
            to: fixture.root.appending(path: "dft-qualification-evidence.json"),
            options: .atomic
        )

        let resultURL = fixture.root.appending(path: "dft-result.json")
        let resultDecoder = JSONDecoder()
        resultDecoder.dateDecodingStrategy = .iso8601
        var releaseCandidate = try resultDecoder.decode(
            DFTResult.self,
            from: Data(contentsOf: resultURL)
        )
        releaseCandidate.payload.qualification = DFTQualificationProvenance(status: .smokeChecked)
        try DFTArtifactJSONEncoder().encode(releaseCandidate).write(to: resultURL, options: .atomic)
        try makeProcessQualificationBuildRequest(
            root: fixture.root,
            request: fixture.request,
            implementationID: "qualified-scan",
            toolID: "dft-engine"
        )

        let qualificationExecutor = DFTQualificationFlowStageExecutor(
            corpusInput: .path("dft-corpus.json"),
            observationsInput: .path("dft-observations.json"),
            qualificationEvidenceInput: .path("dft-qualification-evidence.json"),
            processQualificationEvidenceBuildInput: .path(
                "dft-process-qualification-build-request.json"
            )
        )
        let evidenceBundleExecutor = DFTReleaseDownstreamEvidenceBundleFlowStageExecutor(
            sources: [
                DFTReleaseDownstreamEvidenceSource(
                    domain: .equivalence,
                    role: "equivalence-signoff",
                    input: .path("signoff/equivalence.json")
                ),
                DFTReleaseDownstreamEvidenceSource(
                    domain: .drc,
                    role: "drc-signoff",
                    input: .path("signoff/drc.json")
                ),
                DFTReleaseDownstreamEvidenceSource(
                    domain: .lvs,
                    role: "lvs-signoff",
                    input: .path("signoff/lvs.json")
                ),
                DFTReleaseDownstreamEvidenceSource(
                    domain: .pex,
                    role: "pex-signoff",
                    input: .path("signoff/pex.json")
                ),
            ]
        )
        let releaseExecutor = DFTReleaseFlowStageExecutor(
            stageID: "dft.release",
            requestInput: .path("dft-request.json"),
            resultInput: .path("dft-result.json"),
            downstreamEvidenceInput: .stageRawArtifact(
                .init(stageID: "dft.release-evidence", relativePath: "dft-downstream-evidence.json")
            ),
            qualificationInput: .stageRawArtifact(
                .init(stageID: "dft.qualification", relativePath: "dft-qualification-provenance.json")
            ),
            expectedQualificationRequestDigest: requestDigest,
            processQualificationEvidenceInput: .stageRawArtifact(
                .init(
                    stageID: "dft.qualification",
                    relativePath: "dft-process-qualification-evidence.json"
                )
            )
        )
        let stages = [
            FlowStageDefinition(stageID: "dft.qualification", displayName: "DFT qualification"),
            FlowStageDefinition(stageID: "dft.release-evidence", displayName: "DFT downstream evidence"),
            FlowStageDefinition(stageID: "dft.release", displayName: "DFT release"),
        ]
        let flowRequest = FlowOperationRequest(
            projectRoot: fixture.root,
            runID: fixture.request.runID,
            intent: "Qualify DFT evidence and release through the review loop.",
            stages: stages
        )
        let executors: [any FlowStageExecutor] = [qualificationExecutor, evidenceBundleExecutor, releaseExecutor]
        let first = try await DefaultFlowOrchestrator().run(
            request: flowRequest,
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        #expect(first.status == .blocked)
        #expect(first.stages.map(\.stageID) == [
            "dft.qualification",
            "dft.release-evidence",
            "dft.release",
        ])
        #expect(first.stages.first?.status == .succeeded)
        #expect(first.stages.last?.gates.contains {
            $0.gateID == "approval" && $0.status == .incomplete
        } == true)

        _ = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: fixture.root,
                runID: fixture.request.runID,
                stageID: "dft.release",
                verdict: .approved,
                reviewer: "release-reviewer",
                note: "Reviewed retained qualification provenance and downstream signoff evidence."
            )
        )
        let resumed = try await DefaultFlowRunResumer().resumeRun(
            request: FlowRunResumeRequest(projectRoot: fixture.root, runID: fixture.request.runID),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: executors
        )

        #expect(resumed.result.status == .succeeded)
        #expect(resumed.summary.approvalCount == 1)
        #expect(resumed.result.stages.map(\.stageID) == [
            "dft.qualification",
            "dft.release-evidence",
            "dft.release",
        ])
        let manifest = try XcircuitePackageStore().loadRunManifest(
            runID: fixture.request.runID,
            inProjectAt: fixture.root
        )
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-qualification-provenance" })
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-downstream-evidence-bundle" })
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-release-eligibility" })
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-release-artifact-bundle" })
        #expect(manifest.artifacts.contains { $0.artifactID == "dft-release-result" })
        let bundleURL = fixture.root
            .appending(path: ".xcircuite/runs/\(fixture.request.runID)/stages/dft.release/raw/dft-release-artifact-bundle.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(
            DFTReleaseArtifactBundle.self,
            from: Data(contentsOf: bundleURL)
        )
        #expect(bundle.processQualificationSupportArtifacts.contains {
            $0.artifactID == "dft-process-qualification-build-request"
        })
        let qualifiedResult = try decoder.decode(
            DFTResult.self,
            from: Data(contentsOf: fixture.root.appending(path: bundle.result.path))
        )
        #expect(qualifiedResult.payload.qualification.status == .processQualified)
        #expect(qualifiedResult.payload.qualification.pdkDigest == fixture.request.pdk.digest)
    }

    private func makeProcessQualificationBuildRequest(
        root: URL,
        request: DFTRequest,
        implementationID: String,
        toolID: String
    ) throws {
        let artifacts = try [
            ("corpus", "qualification-build/corpus.json"),
            ("oracle", "qualification-build/oracle.json"),
            ("health", "qualification-build/health.json"),
            ("approval", "qualification-build/approval.json"),
        ].map { id, path in
            try foundationReference(writeArtifact(
                root: root,
                path: path,
                artifactID: "build-\(id)",
                contents: "{\"evidence\":\"\(id)\"}"
            ))
        }
        let scope = ToolQualificationScope(
            implementationID: implementationID,
            binaryDigest: String(repeating: "1", count: 64),
            algorithmVersion: "dft-v1",
            processProfileID: request.pdk.processID,
            deckDigest: String(repeating: "2", count: 64),
            pdkID: request.pdk.manifest.artifactID ?? "pdk",
            pdkDigest: request.pdk.digest
        )
        let makeEvidence: (String, ToolEvidenceKind, ArtifactReference) -> ToolEvidence = {
            id,
            kind,
            artifact in
            ToolEvidence(
                evidenceID: "build-\(id)",
                kind: kind,
                artifact: artifact,
                qualification: ToolEvidenceQualificationSummary(
                    qualified: true,
                    scope: scope,
                    qualificationID: "build-qualification",
                    independenceVerified: true
                ),
                checkedAt: Date()
            )
        }
        let buildRequest = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "build-qualification",
            toolID: toolID,
            scope: scope,
            corpusEvidence: [makeEvidence("corpus", .corpus, artifacts[0])],
            oracleEvidence: [makeEvidence("oracle", .oracle, artifacts[1])],
            healthEvidence: [makeEvidence("health", .healthCheck, artifacts[2])],
            approvalEvidence: [makeEvidence("approval", .productionApproval, artifacts[3])],
            evidenceArtifacts: artifacts,
            independenceVerified: true,
            qualifiedAt: Date().addingTimeInterval(-60),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        try JSONEncoder().encode(buildRequest).write(
            to: root.appending(path: "dft-process-qualification-build-request.json"),
            options: .atomic
        )
    }

    private func makeRequest(
        runID: String,
        designArtifact: ArtifactReference? = nil,
        designDigest: String = String(repeating: "b", count: 64),
        cellLibraryReference: DFTCellLibraryReference? = nil
    ) throws -> DFTRequest {
        let design = try designArtifact ?? foundationReference(XcircuiteFileReference(
            artifactID: "design",
            path: "design.json",
            kind: .netlist,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 10
        ))
        var inputs = [design]
        if let cellLibraryReference {
            inputs.append(cellLibraryReference.artifact)
        }
        return DFTRequest(
            runID: runID,
            inputs: inputs,
            design: LogicDesignReference(
                artifact: design.locator,
                topDesignName: "top",
                designDigest: designDigest
            ),
            constraints: DFTConstraintReference(
                artifact: try foundationReference(XcircuiteFileReference(
                    artifactID: "constraints",
                    path: "constraints.sdc",
                    kind: .constraint,
                    format: .sdc,
                    sha256: String(repeating: "c", count: 64),
                    byteCount: 1
                )),
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: try foundationReference(XcircuiteFileReference(
                    artifactID: "pdk",
                    path: "pdk.json",
                    kind: .technology,
                    format: .json,
                    sha256: String(repeating: "d", count: 64),
                    byteCount: 1
                )),
                processID: "fixture-process",
                version: "1",
                digest: String(repeating: "e", count: 64)
            ),
            cellLibrary: cellLibraryReference,
            operation: .scanInsertion,
            scanArchitecture: DFTScanArchitecture(
                name: "core-scan",
                clocks: [DFTScanClock(id: "clk", signalName: "scan_clk", periodNanoseconds: 10)],
                domains: [DFTScanDomain(id: "core", clockID: "clk", chainCount: 1, estimatedElementCount: 2)],
                scanEnableSignal: "scan_en",
                testModeSignal: "test_mode"
            ),
            insertionPolicy: DFTScanInsertionPolicy(scanCellName: "SDFF")
        )
    }

    private func makeReleaseFixture(
        includeApproval: Bool
    ) throws -> (root: URL, request: DFTRequest) {
        let root = try makeRoot()
        let runID = "dft-release-run"
        let designArtifact = try writeArtifact(
            root: root,
            path: "design.json",
            artifactID: "design",
            contents: "{\"kind\":\"source-design\"}"
        )
        let request = try makeRequest(
            runID: runID,
            designArtifact: try foundationReference(designArtifact),
            designDigest: String(repeating: "a", count: 64)
        )
        let transformedArtifact = try writeArtifact(
            root: root,
            path: "dft/runs/\(runID)/transformed-design.json",
            artifactID: "transformed-design",
            contents: "{\"kind\":\"transformed-design\"}"
        )
        let diffArtifact = try writeArtifact(
            root: root,
            path: "dft/runs/\(runID)/design-diff.json",
            artifactID: "design-diff",
            contents: "{\"kind\":\"design-diff\"}"
        )
        let designReference = try foundationReference(designArtifact)
        let transformedReference = try foundationReference(transformedArtifact)
        let diffReference = try foundationReference(diffArtifact)
        let payload = DFTPayload(
            transformedDesign: LogicDesignReference(
                artifact: transformedReference.locator,
                topDesignName: "top",
                designDigest: request.design.designDigest
            ),
            faultCoverage: nil,
            designDiff: DFTDesignDiff(
                runID: runID,
                title: "Qualified scan insertion",
                actor: "dft-engine",
                baseSnapshot: designReference,
                proposedSnapshot: transformedReference,
                changes: []
            ),
            qualification: DFTQualificationProvenance(
                status: .processQualified,
                corpusRevision: "dft-corpus-r1",
                oracleEvidence: String(repeating: "b", count: 64),
                processID: request.pdk.processID,
                pdkDigest: request.pdk.digest
            )
        )
        let timestamp = Date(timeIntervalSince1970: 10)
        let resultEnvelope = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: runID,
            status: .completed,
            artifacts: [transformedReference, diffReference],
            metadata: DFTExecutionMetadata(
                engineID: "dft-engine",
                implementationID: "qualified-scan",
                implementationVersion: "1",
                startedAt: timestamp,
                completedAt: timestamp.addingTimeInterval(1)
            ),
            payload: payload
        )
        let requestData = try DFTArtifactJSONEncoder().encode(request)
        try requestData.write(to: root.appending(path: "dft-request.json"), options: .atomic)
        let resultData = try DFTArtifactJSONEncoder().encode(resultEnvelope)
        try resultData.write(to: root.appending(path: "dft-result.json"), options: .atomic)
        let processQualifiedAt = Date().addingTimeInterval(-60)
        let processQualificationEvidence = ToolProcessQualificationEvidence(
            qualificationID: "dft-fixture-process-qualification",
            toolID: "dft-engine",
            scope: ToolQualificationScope(
                implementationID: "qualified-scan",
                binaryDigest: String(repeating: "1", count: 64),
                algorithmVersion: "1",
                processProfileID: request.pdk.processID,
                deckDigest: String(repeating: "2", count: 64),
                pdkID: "fixture-pdk",
                pdkDigest: request.pdk.digest
            ),
            status: .qualified,
            corpusEvidenceIDs: ["dft-corpus-r1"],
            oracleEvidenceIDs: ["dft-oracle-r1"],
            healthEvidenceIDs: ["dft-health-r1"],
            approvalEvidenceIDs: ["dft-approval-r1"],
            evidenceArtifactIDs: ["dft-process-qualification"],
            independenceVerified: true,
            qualifiedAt: processQualifiedAt,
            expiresAt: processQualifiedAt.addingTimeInterval(3_600)
        )
        let processQualificationData = try DFTArtifactJSONEncoder().encode(
            processQualificationEvidence
        )
        try processQualificationData.write(
            to: root.appending(path: "dft-process-qualification-evidence.json"),
            options: .atomic
        )

        let downstreamEvidence = try [
            DFTReleaseDownstreamEvidence.Domain.equivalence,
            .drc,
            .lvs,
            .pex,
        ].map { domain in
            let artifact = try writeArtifact(
                root: root,
                path: "signoff/\(domain.rawValue).json",
                artifactID: "\(domain.rawValue)-report",
                contents: "{\"domain\":\"\(domain.rawValue)\",\"status\":\"passed\"}"
            )
            return DFTReleaseDownstreamEvidence(
                domain: domain,
                role: "\(domain.rawValue)-signoff",
                artifact: try foundationReference(artifact)
            )
        }
        let downstreamData = try DFTArtifactJSONEncoder().encode(downstreamEvidence)
        try downstreamData.write(to: root.appending(path: "dft-downstream.json"), options: .atomic)
        if includeApproval {
            let approval = DFTReleaseReviewApproval(
                reviewerID: "human-reviewer",
                decision: .approved,
                reviewedAt: Date(timeIntervalSince1970: 12),
                note: "All DFT and downstream signoff artifacts reviewed."
            )
            let approvalData = try DFTArtifactJSONEncoder().encode(approval)
            try approvalData.write(to: root.appending(path: "dft-approval.json"), options: .atomic)
        }
        return (root, request)
    }

    private func writeArtifact(
        root: URL,
        path: String,
        artifactID: String,
        contents: String
    ) throws -> XcircuiteFileReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(contents.utf8)
        try data.write(to: url, options: .atomic)
        return XcircuiteFileReference(
            artifactID: artifactID,
            path: path,
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count)
        )
    }

    private func makeGateSnapshot() -> LogicDesignSnapshot {
        let cells = (0..<2).map { index in
            GateCell(
                id: "cell-\(index)",
                type: "DFF",
                instanceName: "u_ff\(index)",
                pins: [
                    GatePin(id: "pin-\(index)-d", name: "D", direction: .input, netID: "d-\(index)"),
                    GatePin(id: "pin-\(index)-q", name: "Q", direction: .output, netID: "q-\(index)"),
                    GatePin(id: "pin-\(index)-clk", name: "CLK", direction: .input, netID: "clk"),
                ]
            )
        }
        let nets = [
            GateNet(id: "d-0", name: "d0"),
            GateNet(id: "d-1", name: "d1"),
            GateNet(id: "q-0", name: "q0"),
            GateNet(id: "q-1", name: "q1"),
            GateNet(id: "clk", name: "scan_clk"),
        ]
        let gate = GateDesign(
            topModuleName: "top",
            modules: [
                GateModule(
                    id: "module-top",
                    name: "top",
                    ports: [RTLPort(id: "port-clk", name: "clk", direction: .input)],
                    cells: cells,
                    nets: nets
                )
            ]
        )
        return LogicDesignSnapshot(
            rtl: RTLDesign(topModuleName: "top"),
            gate: gate
        )
    }

    private func makeCellLibraryManifest() -> DFTCellLibraryManifest {
        DFTCellLibraryManifest(
            processID: "fixture-process",
            version: "1",
            pdkDigest: String(repeating: "e", count: 64),
            bindings: [
                DFTCellLibraryBinding(
                    bindingID: "dff-to-sdff",
                    functionalCellType: "DFF",
                    scanCellType: "SDFF",
                    dataPinName: "D",
                    outputPinName: "Q",
                    clockPinNames: ["CLK"],
                    scanInPinName: "SI",
                    scanEnablePinName: "SE",
                    testModePinName: "TM"
                )
            ],
            qualification: DFTQualificationProvenance(
                status: .corpusChecked,
                corpusRevision: "fixture-m2",
                notes: ["fixture binding only; no foundry qualification"]
            )
        )
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

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "dft-flow-adapter-\(UUID().uuidString)")
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
}
