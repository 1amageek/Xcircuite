import DFTCore
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

public struct DFTReleaseFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let resultInput: XcircuiteFlowInputReference
    private let qualificationInput: XcircuiteFlowInputReference?
    private let downstreamEvidenceInput: XcircuiteFlowInputReference
    private let approvalInput: XcircuiteFlowInputReference?
    private let processQualificationEvidenceInput: XcircuiteFlowInputReference?
    private let artifactIntegrityVerifier: XcircuiteFileReferenceVerifier
    private let expectedQualificationRequestDigest: String?
    private let processQualificationEvidenceValidator: any DFTProcessQualificationEvidenceValidating

    public init(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        resultInput: XcircuiteFlowInputReference,
        downstreamEvidenceInput: XcircuiteFlowInputReference,
        approvalInput: XcircuiteFlowInputReference? = nil,
        toolID: String = "dft-release-gate",
        artifactIntegrityVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        qualificationInput: XcircuiteFlowInputReference? = nil,
        expectedQualificationRequestDigest: String? = nil,
        processQualificationEvidenceInput: XcircuiteFlowInputReference? = nil,
        processQualificationEvidenceValidator: any DFTProcessQualificationEvidenceValidating = DFTProcessQualificationEvidenceValidator()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.resultInput = resultInput
        self.qualificationInput = qualificationInput
        self.downstreamEvidenceInput = downstreamEvidenceInput
        self.approvalInput = approvalInput
        self.artifactIntegrityVerifier = artifactIntegrityVerifier
        self.expectedQualificationRequestDigest = expectedQualificationRequestDigest
        self.processQualificationEvidenceInput = processQualificationEvidenceInput
        self.processQualificationEvidenceValidator = processQualificationEvidenceValidator
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let request = try loadRequest(context: context)
            let unqualifiedResult = try loadResult(context: context)
            let result: DFTResult
            do {
                result = try applyQualification(
                    to: unqualifiedResult,
                    request: request,
                    context: context
                )
            } catch let error as DFTReleaseEligibilityError {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: diagnosticCode(for: error),
                    message: error.localizedDescription
                )
                return try blockedResult(
                    request: request,
                    result: unqualifiedResult,
                    diagnostics: [diagnostic],
                    context: context
                )
            }
            let qualifiedResultArtifact = try persist(
                result,
                fileName: "dft-release-result.json",
                artifactID: "dft-release-result",
                context: context
            )
            let downstreamEvidence = try loadDownstreamEvidence(context: context)
            let approval = try loadApproval(context: context)

            let candidateArtifacts = FoundationFlowProjection.legacyReferences(from: result.artifacts)
                + [qualifiedResultArtifact]
                + FoundationFlowProjection.legacyReferences(from: downstreamEvidence.map(\.artifact))
            let integrityDiagnostics = candidateArtifacts.compactMap { artifact -> FlowDiagnostic? in
                let integrity = artifactIntegrityVerifier.verify(
                    artifact,
                    projectRoot: context.projectRoot
                )
                guard integrity.status != .verified else {
                    return nil
                }
                return FlowDiagnostic(
                    severity: .error,
                    code: "DFT_RELEASE_\(integrity.status.rawValue.uppercased())",
                    message: "DFT release artifact integrity verification failed for \(artifact.artifactID ?? artifact.path): \(integrity.message)"
                )
            }
            if !integrityDiagnostics.isEmpty {
                return try blockedResult(
                    request: request,
                    result: result,
                    resultArtifact: qualifiedResultArtifact,
                    diagnostics: integrityDiagnostics,
                    context: context
                )
            }

            do {
                let eligibility = try DFTReleaseEligibilityGate().evaluate(
                    request: request,
                    result: result,
                    downstreamEvidence: downstreamEvidence,
                    approval: approval,
                    sourceStageID: "dft",
                    resumeStageID: stageID
                )
                let artifact = try persist(
                    eligibility,
                    fileName: "dft-release-eligibility.json",
                    artifactID: "dft-release-eligibility",
                    context: context
                )
                guard let approval else {
                    throw DFTReleaseEligibilityError.approvalRequired
                }
                let bundle = try makeReleaseArtifactBundle(
                    eligibilityArtifact: artifact,
                    result: result,
                    resultArtifact: qualifiedResultArtifact,
                    downstreamEvidence: downstreamEvidence,
                    approval: approval,
                    context: context
                )
                let bundleArtifact = try persist(
                    bundle,
                    fileName: "dft-release-artifact-bundle.json",
                    artifactID: "dft-release-artifact-bundle",
                    context: context
                )
                let gate = FlowGateResult(
                    gateID: "dft-release",
                    status: .passed,
                    diagnostics: []
                )
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .succeeded,
                    gates: [gate],
                    artifacts: [qualifiedResultArtifact, artifact, bundleArtifact]
                )
            } catch let error as DFTReleaseEligibilityError {
                let diagnostic = FlowDiagnostic(
                    severity: .error,
                    code: diagnosticCode(for: error),
                    message: error.localizedDescription
                )
                let contract = DFTReleaseReviewResumeContract(
                    runID: context.runID,
                    sourceStageID: "dft",
                    resumeStageID: stageID,
                    designDigest: request.design.designDigest,
                    candidateArtifactIDs: result.artifacts.compactMap(\.artifactID).sorted(),
                    blockerCodes: [diagnostic.code],
                    requiredReviewItems: [
                        "review_dft_artifacts",
                        "confirm_process_qualification_evidence",
                        "confirm_downstream_signoff",
                        "record_human_approval",
                    ],
                    decision: error == .approvalRejected ? .rejected : .pending
                )
                let contractArtifact = try persist(
                    contract,
                    fileName: "dft-release-review-resume.json",
                    artifactID: "dft-release-review-resume",
                    context: context
                )
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .blocked,
                    diagnostics: [diagnostic],
                    gates: [
                        FlowGateResult(
                            gateID: "dft-release",
                            status: .blocked,
                            diagnostics: [diagnostic]
                        )
                    ] + approvalGates(for: error),
                    artifacts: [qualifiedResultArtifact, contractArtifact]
                )
            }
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "DFT_RELEASE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .failed,
                diagnostics: [diagnostic],
                gates: [FlowGateResult(gateID: "dft-release", status: .failed, diagnostics: [diagnostic])]
            )
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
    }

    private func loadRequest(context: FlowExecutionContext) throws -> DFTRequest {
        let data = try Data(contentsOf: try requestInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        ))
        return try decode(data, as: DFTRequest.self)
    }

    private func loadResult(
        context: FlowExecutionContext
    ) throws -> DFTResult {
        let data = try Data(contentsOf: try resultInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        ))
        return try decode(data, as: DFTResult.self)
    }

    private func applyQualification(
        to unqualifiedResult: DFTResult,
        request: DFTRequest,
        context: FlowExecutionContext
    ) throws -> DFTResult {
        var result = unqualifiedResult
        if let qualificationInput {
            let qualificationURL = try qualificationInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let provenance = try decode(
                Data(contentsOf: qualificationURL),
                as: DFTQualificationProvenance.self
            )
            guard provenance.status == .processQualified else {
                throw DFTReleaseEligibilityError.qualificationInsufficient(provenance.status)
            }
            guard provenance.processID == request.pdk.processID,
                  provenance.pdkDigest == request.pdk.digest,
                  let oracleEvidence = provenance.oracleEvidence,
                  !oracleEvidence.isEmpty else {
                throw DFTReleaseEligibilityError.invalidReviewContract(
                    "qualification provenance does not match the request process, PDK or oracle evidence"
                )
            }
            guard let expectedQualificationRequestDigest,
                  provenance.requestDigests.contains(expectedQualificationRequestDigest) else {
                throw DFTReleaseEligibilityError.invalidReviewContract(
                    "qualification provenance does not cover the expected DFT request digest"
                )
            }

            if result.payload.qualification.status == .processQualified {
                guard result.payload.qualification.processID == provenance.processID,
                      result.payload.qualification.pdkDigest == provenance.pdkDigest,
                      result.payload.qualification.oracleEvidence == provenance.oracleEvidence else {
                    throw DFTReleaseEligibilityError.invalidReviewContract(
                        "qualified result provenance conflicts with the retained qualification artifact"
                    )
                }
            }

            let qualificationArtifact = try StageArtifactReferenceBuilder().reference(
                for: qualificationURL,
                projectRoot: context.projectRoot,
                artifactID: "dft-qualification-provenance",
                kind: .release,
                format: .json,
                producedByRunID: context.runID
            )
            result.payload.qualification = provenance
            let qualificationReference = try FoundationFlowProjection.artifactReference(from: qualificationArtifact)
            if !result.artifacts.contains(qualificationReference) {
                result.artifacts.append(qualificationReference)
            }
        }

        guard let processQualificationEvidenceInput else {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "independent process qualification evidence is required for every DFT release"
            )
        }
        let processQualificationURL: URL
        do {
            processQualificationURL = try processQualificationEvidenceInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
        } catch {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "process qualification evidence could not be resolved: \(error.localizedDescription)"
            )
        }
        let processQualificationEvidence: ToolProcessQualificationEvidence
        do {
            processQualificationEvidence = try decode(
                Data(contentsOf: processQualificationURL),
                as: ToolProcessQualificationEvidence.self
            )
        } catch {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "process qualification evidence could not be decoded: \(error.localizedDescription)"
            )
        }
        do {
            try processQualificationEvidenceValidator.validate(
                processQualificationEvidence,
                request: request,
                result: result,
                at: Date()
            )
        } catch let error as DFTProcessQualificationEvidenceValidationError {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "\(error.code): \(error.localizedDescription)"
            )
        }
        let processQualificationArtifact = try StageArtifactReferenceBuilder().reference(
            for: processQualificationURL,
            projectRoot: context.projectRoot,
            artifactID: "dft-process-qualification-evidence",
            kind: .release,
            format: .json,
            producedByRunID: context.runID
        )
        let processQualificationReference = try FoundationFlowProjection.artifactReference(from: processQualificationArtifact)
        if let existing = result.artifacts.first(where: {
            $0.id.rawValue == processQualificationReference.id.rawValue
        }) {
            guard existing == processQualificationReference else {
                throw DFTReleaseEligibilityError.processQualificationInvalid(
                    "process qualification artifact identity conflicts with the retained result artifact"
                )
            }
        } else {
            result.artifacts.append(processQualificationReference)
        }
        return result
    }

    private func loadDownstreamEvidence(
        context: FlowExecutionContext
    ) throws -> [DFTReleaseDownstreamEvidence] {
        let data = try Data(contentsOf: try downstreamEvidenceInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        ))
        return try decode(data, as: [DFTReleaseDownstreamEvidence].self)
    }

    private func loadApproval(
        context: FlowExecutionContext
    ) throws -> DFTReleaseReviewApproval? {
        if let approvalInput {
            let data = try Data(contentsOf: try approvalInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            ))
            return try decode(data, as: DFTReleaseReviewApproval.self)
        }

        guard let record = try context.packageStore.loadApproval(
            runID: context.runID,
            stageID: stageID,
            inProjectAt: context.projectRoot
        ) else {
            return nil
        }
        guard record.runID == context.runID,
              record.stageID == stageID,
              let stageResultSHA256 = record.stageResultSHA256,
              let stageResultByteCount = record.stageResultByteCount else {
            return nil
        }

        let stageResultURL = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "result.json")
        let digester = SHA256ContentDigester()
        guard FileManager.default.fileExists(atPath: stageResultURL.path(percentEncoded: false)),
              try digester.digest(fileAt: stageResultURL).hexadecimalValue == stageResultSHA256,
              try UInt64(Data(contentsOf: stageResultURL).count) == stageResultByteCount else {
            return nil
        }

        return DFTReleaseReviewApproval(
            reviewerID: record.reviewer,
            decision: record.verdict == .approved ? .approved : .rejected,
            reviewedAt: record.createdAt,
            note: record.note
        )
    }

    private func decode<Value: Decodable>(_ data: Data, as type: Value.Type) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: .release,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func makeReleaseArtifactBundle(
        eligibilityArtifact: XcircuiteFileReference,
        result: DFTResult,
        resultArtifact: XcircuiteFileReference,
        downstreamEvidence: [DFTReleaseDownstreamEvidence],
        approval: DFTReleaseReviewApproval,
        context: FlowExecutionContext
    ) throws -> DFTReleaseArtifactBundle {
        let requestArtifact = try reference(
            requestInput,
            artifactID: "dft-request",
            kind: .request,
            context: context
        )
        let downstreamBundleArtifact = try reference(
            downstreamEvidenceInput,
            artifactID: "dft-downstream-evidence",
            kind: .release,
            context: context
        )
        let qualificationArtifact = try qualificationInput.map {
            try reference(
                $0,
                artifactID: "dft-qualification-provenance",
                kind: .release,
                context: context
            )
        }
        guard let processQualificationArtifact = result.artifacts.first(where: {
            $0.artifactID == "dft-process-qualification-evidence"
        }) else {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "validated process qualification artifact is missing from the release candidate"
            )
        }
        let processQualificationSupportArtifacts = try processQualificationSupportArtifacts(
            context: context
        )
        let manifestCandidates = [
            eligibilityArtifact,
            requestArtifact,
            resultArtifact,
            qualificationArtifact,
            FoundationFlowProjection.legacyReference(from: processQualificationArtifact),
        ]
        .compactMap { $0 }
            + processQualificationSupportArtifacts
            + [downstreamBundleArtifact]
            + FoundationFlowProjection.legacyReferences(from: downstreamEvidence.map(\.artifact))
        try verifyReleaseManifestArtifacts(
            manifestCandidates,
            context: context
        )
        let manifestArtifacts = uniqueArtifacts(manifestCandidates)
        return DFTReleaseArtifactBundle(
            runID: context.runID,
            eligibility: eligibilityArtifact,
            request: requestArtifact,
            result: resultArtifact,
            qualificationProvenance: qualificationArtifact,
            processQualificationEvidence: FoundationFlowProjection.legacyReference(from: processQualificationArtifact),
            processQualificationSupportArtifacts: processQualificationSupportArtifacts,
            downstreamEvidenceBundle: downstreamBundleArtifact,
            downstreamEvidence: downstreamEvidence,
            candidateArtifacts: uniqueArtifacts(
                FoundationFlowProjection.legacyReferences(from: result.artifacts) + manifestArtifacts
            ),
            approval: approval
        )
    }

    private func verifyReleaseManifestArtifacts(
        _ artifacts: [XcircuiteFileReference],
        context: FlowExecutionContext
    ) throws {
        var artifactsByID: [String: XcircuiteFileReference] = [:]
        for artifact in artifacts {
            if let artifactID = artifact.artifactID,
               let existing = artifactsByID[artifactID],
               existing != artifact {
                throw DFTReleaseEligibilityError.invalidReviewContract(
                    "release manifest artifact ID \(artifactID) resolves to conflicting references"
                )
            }
            if let artifactID = artifact.artifactID {
                artifactsByID[artifactID] = artifact
            }
            let integrity = artifactIntegrityVerifier.verify(
                artifact,
                projectRoot: context.projectRoot
            )
            guard integrity.status == .verified else {
                throw DFTReleaseEligibilityError.invalidReviewContract(
                    "release manifest artifact \(artifact.artifactID ?? artifact.path) is not verified: \(integrity.message)"
                )
            }
        }
    }

    private func processQualificationSupportArtifacts(
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        let stageID: String
        switch processQualificationEvidenceInput {
        case .stageArtifact(let selector):
            stageID = selector.stageID
        case .stageRawArtifact(let selector):
            stageID = selector.stageID
        case .path, .artifact, .none:
            return []
        }
        let resultURL = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "result.json")
        guard FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) else {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "stage-bound process qualification evidence has no persisted source stage result"
            )
        }
        let result = try context.packageStore.readJSON(
            FlowStageResult.self,
            from: resultURL
        )
        guard result.status == .succeeded else {
            throw DFTReleaseEligibilityError.processQualificationInvalid(
                "stage-bound process qualification evidence source stage is not successful"
            )
        }
        // The primary process-qualification artifact is materialized from the
        // stage-bound input above. Keep only the supporting artifacts from the
        // source stage result so the same artifact ID cannot be registered with
        // a legacy projection that differs only in producer metadata.
        return uniqueArtifacts(result.artifacts).filter {
            $0.artifactID != "dft-process-qualification-evidence"
        }
    }

    private func reference(
        _ input: XcircuiteFlowInputReference,
        artifactID: String,
        kind: XcircuiteFileKind,
        context: FlowExecutionContext
    ) throws -> XcircuiteFileReference {
        let url = try input.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        )
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: .json,
            producedByRunID: context.runID
        )
    }

    private func uniqueArtifacts(
        _ artifacts: [XcircuiteFileReference]
    ) -> [XcircuiteFileReference] {
        var seen = Set<String>()
        return artifacts.filter { artifact in
            let key = artifact.artifactID ?? artifact.path
            return seen.insert(key).inserted
        }
    }

    private func blockedResult(
        request: DFTRequest,
        result: DFTResult,
        resultArtifact: XcircuiteFileReference? = nil,
        diagnostics: [FlowDiagnostic],
        context: FlowExecutionContext
    ) throws -> FlowStageResult {
        let contract = DFTReleaseReviewResumeContract(
            runID: context.runID,
            sourceStageID: "dft",
            resumeStageID: stageID,
            designDigest: request.design.designDigest,
            candidateArtifactIDs: result.artifacts.compactMap(\.artifactID).sorted(),
            blockerCodes: diagnostics.map(\.code),
            requiredReviewItems: [
                "restore_verified_dft_artifacts",
                "confirm_process_qualification_evidence",
                "confirm_downstream_signoff",
                "record_human_approval",
            ],
            decision: .pending
        )
        let contractArtifact = try persist(
            contract,
            fileName: "dft-release-review-resume.json",
            artifactID: "dft-release-review-resume",
            context: context
        )
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [
                FlowGateResult(
                    gateID: "dft-release",
                    status: .blocked,
                    diagnostics: diagnostics
                )
            ],
            artifacts: resultArtifact.map { [$0, contractArtifact] } ?? [contractArtifact]
        )
    }

    private func approvalGates(
        for error: DFTReleaseEligibilityError
    ) -> [FlowGateResult] {
        switch error {
        case .approvalRequired:
            let diagnostic = FlowDiagnostic(
                severity: .warning,
                code: "DFT_RELEASE_APPROVAL_REQUIRED",
                message: "DFT release is ready for review and requires a content-bound approval before resume."
            )
            return [FlowGateResult(gateID: "approval", status: .incomplete, diagnostics: [diagnostic])]
        case .approvalRejected:
            let diagnostic = FlowDiagnostic(
                severity: .error,
                code: "DFT_RELEASE_APPROVAL_REJECTED",
                message: "DFT release approval was rejected and requires a new review decision."
            )
            return [FlowGateResult(gateID: "approval", status: .failed, diagnostics: [diagnostic])]
        default:
            return []
        }
    }

    private func diagnosticCode(for error: DFTReleaseEligibilityError) -> String {
        switch error {
        case .runIDMismatch: return "DFT_RELEASE_RUN_ID_MISMATCH"
        case .executionNotCompleted: return "DFT_RELEASE_EXECUTION_INCOMPLETE"
        case .invalidExecutionMetadata: return "DFT_RELEASE_METADATA_INVALID"
        case .invalidArtifactReference: return "DFT_RELEASE_ARTIFACT_INVALID"
        case .transformedDesignMissing: return "DFT_RELEASE_TRANSFORMED_DESIGN_MISSING"
        case .designDiffMissing: return "DFT_RELEASE_DESIGN_DIFF_MISSING"
        case .designDiffInvalid: return "DFT_RELEASE_DESIGN_DIFF_INVALID"
        case .coverageEvidenceMissing: return "DFT_RELEASE_COVERAGE_MISSING"
        case .coverageIncomplete: return "DFT_RELEASE_COVERAGE_INCOMPLETE"
        case .qualificationInsufficient: return "DFT_RELEASE_QUALIFICATION_INSUFFICIENT"
        case .qualificationProvenanceInvalid: return "DFT_RELEASE_QUALIFICATION_PROVENANCE_INVALID"
        case .processQualificationInvalid: return "DFT_RELEASE_PROCESS_QUALIFICATION_INVALID"
        case .downstreamEvidenceMissing: return "DFT_RELEASE_DOWNSTREAM_EVIDENCE_MISSING"
        case .approvalRequired: return "DFT_RELEASE_APPROVAL_REQUIRED"
        case .approvalRejected: return "DFT_RELEASE_APPROVAL_REJECTED"
        case .invalidReviewContract: return "DFT_RELEASE_REVIEW_CONTRACT_INVALID"
        }
    }
}
