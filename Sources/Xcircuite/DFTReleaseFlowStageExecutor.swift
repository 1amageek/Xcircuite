import DFTCore
import DesignFlowKernel
import Foundation
import XcircuitePackage

public struct DFTReleaseFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let resultInput: XcircuiteFlowInputReference
    private let downstreamEvidenceInput: XcircuiteFlowInputReference
    private let approvalInput: XcircuiteFlowInputReference?

    public init(
        stageID: String,
        requestInput: XcircuiteFlowInputReference,
        resultInput: XcircuiteFlowInputReference,
        downstreamEvidenceInput: XcircuiteFlowInputReference,
        approvalInput: XcircuiteFlowInputReference? = nil,
        toolID: String = "dft-release-gate"
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.resultInput = resultInput
        self.downstreamEvidenceInput = downstreamEvidenceInput
        self.approvalInput = approvalInput
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let request = try loadRequest(context: context)
            let result = try loadResult(context: context)
            let downstreamEvidence = try loadDownstreamEvidence(context: context)
            let approval = try loadApproval(context: context)

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
                let gate = FlowGateResult(
                    gateID: "dft-release",
                    status: .passed,
                    diagnostics: []
                )
                return FlowStageResult(
                    stageID: stage.stageID,
                    status: .succeeded,
                    gates: [gate],
                    artifacts: [artifact]
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
                    requiredReviewItems: ["review_dft_artifacts", "confirm_downstream_signoff", "record_human_approval"],
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
                    ],
                    artifacts: [contractArtifact]
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
    ) throws -> XcircuiteEngineResultEnvelope<DFTPayload> {
        let data = try Data(contentsOf: try resultInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        ))
        return try decode(data, as: XcircuiteEngineResultEnvelope<DFTPayload>.self)
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
        guard let approvalInput else { return nil }
        let data = try Data(contentsOf: try approvalInput.resolveExisting(
            projectRoot: context.projectRoot,
            runDirectory: context.runDirectory
        ))
        return try decode(data, as: DFTReleaseReviewApproval.self)
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

    private func diagnosticCode(for error: DFTReleaseEligibilityError) -> String {
        switch error {
        case .runIDMismatch: return "DFT_RELEASE_RUN_ID_MISMATCH"
        case .executionNotCompleted: return "DFT_RELEASE_EXECUTION_INCOMPLETE"
        case .invalidExecutionMetadata: return "DFT_RELEASE_METADATA_INVALID"
        case .invalidArtifactReference: return "DFT_RELEASE_ARTIFACT_INVALID"
        case .transformedDesignMissing: return "DFT_RELEASE_TRANSFORMED_DESIGN_MISSING"
        case .designDiffMissing: return "DFT_RELEASE_DESIGN_DIFF_MISSING"
        case .coverageEvidenceMissing: return "DFT_RELEASE_COVERAGE_MISSING"
        case .coverageIncomplete: return "DFT_RELEASE_COVERAGE_INCOMPLETE"
        case .qualificationInsufficient: return "DFT_RELEASE_QUALIFICATION_INSUFFICIENT"
        case .downstreamEvidenceMissing: return "DFT_RELEASE_DOWNSTREAM_EVIDENCE_MISSING"
        case .approvalRequired: return "DFT_RELEASE_APPROVAL_REQUIRED"
        case .approvalRejected: return "DFT_RELEASE_APPROVAL_REJECTED"
        case .invalidReviewContract: return "DFT_RELEASE_REVIEW_CONTRACT_INVALID"
        }
    }
}
