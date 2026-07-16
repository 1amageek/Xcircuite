import CircuiteFoundation
import DesignFlowKernel
import DFTCore
import Foundation
import ToolQualification

/// Packages a completed DFT result after process evidence, downstream evidence,
/// artifact integrity, and the kernel-owned approval have all been verified.
public struct DFTReleaseFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let resultInput: XcircuiteFlowInputReference
    private let downstreamEvidenceInput: XcircuiteFlowInputReference
    private let processQualificationEvidenceInput: XcircuiteFlowInputReference
    private let processQualificationEvidenceValidator: any ToolProcessQualificationEvidenceValidating
    private let verifier: LocalArtifactVerifier
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        resultInput: XcircuiteFlowInputReference,
        downstreamEvidenceInput: XcircuiteFlowInputReference,
        processQualificationEvidenceInput: XcircuiteFlowInputReference,
        toolID: String = "dft-release-gate",
        processQualificationEvidenceValidator: any ToolProcessQualificationEvidenceValidating = ToolProcessQualificationEvidenceValidator()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.resultInput = resultInput
        self.downstreamEvidenceInput = downstreamEvidenceInput
        self.processQualificationEvidenceInput = processQualificationEvidenceInput
        self.processQualificationEvidenceValidator = processQualificationEvidenceValidator
        self.verifier = LocalArtifactVerifier()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)

            let request = try load(DFTRequest.self, from: requestInput, context: context)
            let result = try load(DFTResult.self, from: resultInput, context: context)
            guard request.runID == context.runID, result.runID == context.runID else {
                return blocked(code: "DFT_RELEASE_RUN_ID_MISMATCH", message: "DFT request and result must belong to the active flow run.")
            }
            guard result.status == .completed else {
                return blocked(code: "DFT_RELEASE_RESULT_INCOMPLETE", message: "Only a completed DFT result can be released.")
            }
            guard result.payload.evidenceProvenance.status == .oracleCorrelated else {
                return blocked(code: "DFT_RELEASE_ORACLE_EVIDENCE_REQUIRED", message: "DFT release requires oracle-correlated evidence provenance.")
            }

            let processEvidence = try load(
                ToolProcessQualificationEvidence.self,
                from: processQualificationEvidenceInput,
                context: context
            )
            do {
                try await processQualificationEvidenceValidator.validate(
                    processEvidence,
                    reading: LocalToolQualificationArtifactReader(workspaceRoot: context.projectRoot),
                    at: Date()
                )
                try validateEvidenceBindings(processEvidence, request: request, result: result)
            } catch {
                return blocked(
                    code: "DFT_RELEASE_PROCESS_EVIDENCE_INVALID",
                    message: error.localizedDescription
                )
            }

            let downstreamEvidence = try load(
                [DFTReleaseDownstreamEvidence].self,
                from: downstreamEvidenceInput,
                context: context
            )
            try validateDownstreamEvidence(downstreamEvidence, context: context)

            guard let approval = try await context.infrastructure.loadApproval(
                runID: context.runID,
                stageID: stageID
            ) else {
                return blocked(code: "DFT_RELEASE_APPROVAL_REQUIRED", message: "The DesignFlowKernel approval record is required.")
            }
            guard approval.runID == context.runID,
                  approval.stageID == stageID,
                  approval.verdict == .approved || approval.verdict == .waived else {
                return blocked(code: "DFT_RELEASE_APPROVAL_INVALID", message: "The approval does not authorize this DFT release stage.")
            }
            try verify([approval.evidence.plan, approval.evidence.stageResult], context: context)

            let requestArtifact = try reference(requestInput, artifactID: "dft-request", kind: .request, context: context)
            let processEvidenceArtifact = try reference(
                processQualificationEvidenceInput,
                artifactID: "dft-process-qualification-evidence",
                kind: .release,
                context: context
            )
            let downstreamBundleArtifact = try reference(
                downstreamEvidenceInput,
                artifactID: "dft-downstream-evidence-bundle",
                kind: .release,
                context: context
            )
            let resultArtifact = try await context.persistJSONArtifact(
                result,
                artifactID: "dft-release-result",
                stageID: stageID,
                fileName: "dft-release-result.json",
                role: .output,
                kind: .report
            )
            let retainedArtifacts = unique(
                result.artifacts
                    + downstreamEvidence.map(\.artifact)
                    + [requestArtifact, resultArtifact, processEvidenceArtifact, downstreamBundleArtifact]
            )
            try verify(retainedArtifacts, context: context)

            let bundle = DFTReleaseArtifactBundle(
                runID: context.runID,
                request: requestArtifact,
                result: resultArtifact,
                processQualificationEvidence: processEvidenceArtifact,
                downstreamEvidenceBundle: downstreamBundleArtifact,
                downstreamEvidence: downstreamEvidence,
                candidateArtifacts: retainedArtifacts,
                approval: approval
            )
            let bundleArtifact = try await context.persistJSONArtifact(
                bundle,
                artifactID: "dft-release-artifact-bundle",
                stageID: stageID,
                fileName: "dft-release-artifact-bundle.json",
                role: .output,
                kind: .release
            )
            return FlowStageResult(
                stageID: stageID,
                status: .succeeded,
                gates: [FlowGateResult(gateID: "dft-release", status: .passed)],
                artifacts: retainedArtifacts + [bundleArtifact]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return blocked(code: "DFT_RELEASE_VALIDATION_FAILED", message: error.localizedDescription)
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        guard stage.requiresApproval else {
            throw XcircuiteRuntimeError.invalidConfiguration("DFT release stage must require approval.")
        }
    }

    private func load<Value: Decodable>(
        _ type: Value.Type,
        from input: XcircuiteFlowInputReference,
        context: FlowExecutionContext
    ) throws -> Value {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func reference(
        _ input: XcircuiteFlowInputReference,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let url = try input.resolveExisting(projectRoot: context.projectRoot, runDirectory: context.runDirectory)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: .json
        )
    }

    private func validateDownstreamEvidence(
        _ evidence: [DFTReleaseDownstreamEvidence],
        context: FlowExecutionContext
    ) throws {
        let domains = Set(evidence.map(\.domain))
        let required: Set<DFTReleaseDownstreamEvidence.Domain> = [.equivalence, .drc, .lvs, .pex]
        guard required.isSubset(of: domains), domains.count == evidence.count else {
            throw XcircuiteRuntimeError.invalidConfiguration("DFT downstream evidence must contain one artifact for each required domain.")
        }
        try verify(evidence.map(\.artifact), context: context)
    }

    private func validateEvidenceBindings(
        _ evidence: ToolProcessQualificationEvidence,
        request: DFTRequest,
        result: DFTResult
    ) throws {
        let producer = result.provenance.producer
        let implementationID = producer.build ?? producer.identifier
        guard evidence.toolID == producer.identifier else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "DFT qualification evidence tool does not match the result producer."
            )
        }
        guard evidence.scope.implementationID == implementationID else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "DFT qualification evidence implementation does not match the result producer."
            )
        }
        guard evidence.scope.processProfileID == request.pdk.processID,
              evidence.scope.pdkDigest?.caseInsensitiveCompare(request.pdk.digest) == .orderedSame else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "DFT qualification evidence does not match the requested process and PDK digest."
            )
        }
        let requiredModelIDs = Set(
            result.payload.coverageEvidence?.outcomes.compactMap(\.modelID) ?? []
        )
        guard requiredModelIDs.isSubset(of: Set(evidence.qualifiedModelIDs)) else {
            throw XcircuiteRuntimeError.invalidConfiguration(
                "DFT qualification evidence does not cover every model used by the result."
            )
        }
    }

    private func verify(_ artifacts: [ArtifactReference], context: FlowExecutionContext) throws {
        for artifact in artifacts {
            let integrity = verifier.verify(artifact, relativeTo: context.projectRoot)
            guard integrity.isVerified else {
                throw XcircuiteRuntimeError.invalidConfiguration(
                    "Artifact integrity failed for \(artifact.id.rawValue): \(integrity.issues)"
                )
            }
        }
    }

    private func unique(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        var retained: [String: ArtifactReference] = [:]
        for artifact in artifacts {
            retained[artifact.id.rawValue] = artifact
        }
        return retained.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func blocked(code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "dft-release", status: .blocked, diagnostics: [diagnostic])]
        )
    }
}
