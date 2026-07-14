import CircuiteFoundation
import DesignFlowKernel
import ElectricalSignoffQualification
import Foundation
import ToolQualification

public struct ElectricalSignoffProcessQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let evaluator: any ElectricalSignoffProcessQualificationEvaluating
    private let artifactVerifier: any ElectricalSignoffProcessQualificationArtifactVerifying

    public init(
        stageID: String = "electrical-signoff.process-qualification",
        toolID: String = "native-electrical-signoff-process-qualification",
        requestInput: XcircuiteFlowInputReference,
        evaluator: any ElectricalSignoffProcessQualificationEvaluating = DefaultElectricalSignoffProcessQualificationEvaluator(),
        artifactVerifier: any ElectricalSignoffProcessQualificationArtifactVerifying = DefaultElectricalSignoffProcessQualificationArtifactVerifier()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.evaluator = evaluator
        self.artifactVerifier = artifactVerifier
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage, context: context)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let inputReference = try reference(
                for: requestURL,
                artifactID: "electrical-signoff-process-qualification-request",
                kind: .request,
                context: context
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(
                ElectricalSignoffProcessQualificationRequest.self,
                from: Data(contentsOf: requestURL)
            )
            guard request.qualificationReport.runID == context.runID else {
                return failureResult(
                    stageID: stage.stageID,
                    code: "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_RUN_ID_MISMATCH",
                    message: "The process qualification report must belong to the flow run.",
                    artifacts: [inputReference]
                )
            }
            let integrityIssues = artifactVerifier.verify(request, projectRoot: context.projectRoot)
            guard integrityIssues.isEmpty else {
                return artifactIntegrityFailureResult(
                    stageID: stage.stageID,
                    inputReference: inputReference,
                    issues: integrityIssues
                )
            }
            let result = try evaluator.evaluate(request)
            try context.checkCancellation()
            let resultReference = try persist(
                result,
                relativePath: ".xcircuite/runs/\(context.runID)/electrical-signoff/process-qualification.json",
                artifactID: "electrical-signoff-process-qualification",
                context: context
            )
            let evidenceReference = try persist(
                result.evidence,
                relativePath: ".xcircuite/runs/\(context.runID)/electrical-signoff/process-qualification-evidence.json",
                artifactID: "electrical-signoff-process-qualification-evidence",
                context: context
            )
            let diagnostics = result.blockers.map { blocker in
                FlowDiagnostic(
                    severity: .error,
                    code: "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_\(blocker.uppercased().replacingOccurrences(of: "-", with: "_"))",
                    message: "Electrical process qualification is blocked: \(blocker)."
                )
            }
            let gateStatus: FlowGateStatus = result.qualified ? .passed : .blocked
            return FlowStageResult(
                stageID: stage.stageID,
                status: result.qualified ? .succeeded : .blocked,
                diagnostics: diagnostics,
                gates: [FlowGateResult(
                    gateID: "electrical-process-qualification",
                    status: gateStatus,
                    diagnostics: diagnostics
                )],
                artifacts: [inputReference, resultReference, evidenceReference]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func validate(stage: FlowStageDefinition, context: FlowExecutionContext) throws {
        guard stage.stageID == stageID else {
            throw ElectricalSignoffProcessQualificationFlowError.stageMismatch
        }
        guard stage.requiresApproval else {
            throw ElectricalSignoffProcessQualificationFlowError.approvalGateRequired
        }
        guard !context.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElectricalSignoffProcessQualificationFlowError.invalidRunID
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        switch requestInput {
        case .artifact(let reference):
            _ = reference
        case .stageArtifact(let selector):
            guard selector.artifactID != nil else {
                throw ElectricalSignoffProcessQualificationFlowError.unboundStageArtifact
            }
        case .path, .stageRawArtifact:
            throw ElectricalSignoffProcessQualificationFlowError.unverifiedInput
        }
    }

    private func reference(
        for url: URL,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        _ = try projectRelativePath(for: url, projectRoot: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: ArtifactFormat.json
        )
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        relativePath: String,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let url = try context.storage.url(
            forProjectRelativePath: relativePath,
            inProjectAt: context.projectRoot
        )
        try context.storage.ensureDirectory(at: url.deletingLastPathComponent())
        try context.storage.writeJSON(value, to: url, forProjectAt: context.projectRoot)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: ArtifactKind.release,
            format: ArtifactFormat.json
        )
    }

    private func projectRelativePath(for url: URL, projectRoot: URL) throws -> String {
        let root = projectRoot.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix("\(root)/") else {
            throw ElectricalSignoffProcessQualificationFlowError.inputOutsideProject(path)
        }
        return String(path.dropFirst(root.count + 1))
    }

    private func failureResult(
        stageID: String,
        code: String,
        message: String,
        artifacts: [ArtifactReference] = []
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "electrical-process-qualification", status: .blocked, diagnostics: [diagnostic])],
            artifacts: artifacts
        )
    }

    private func artifactIntegrityFailureResult(
        stageID: String,
        inputReference: ArtifactReference,
        issues: [ElectricalSignoffProcessQualificationArtifactIntegrityIssue]
    ) -> FlowStageResult {
        let diagnostics = issues.map { issue in
            FlowDiagnostic(
                severity: .error,
                code: "ELECTRICAL_SIGNOFF_PROCESS_QUALIFICATION_ARTIFACT_INTEGRITY_INVALID",
                message: "\(issue.category) artifact failed integrity check: \(issue.integrity.issues.map { $0.code.rawValue }.joined(separator: ", "))"
            )
        }
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [FlowGateResult(
                gateID: "electrical-process-qualification",
                status: .blocked,
                diagnostics: diagnostics
            )],
            artifacts: [inputReference]
        )
    }
}

private enum ElectricalSignoffProcessQualificationFlowError: Error, LocalizedError {
    case stageMismatch
    case approvalGateRequired
    case invalidRunID
    case unverifiedInput
    case unboundStageArtifact
    case inputOutsideProject(String)

    var errorDescription: String? {
        switch self {
        case .stageMismatch:
            return "The configured electrical process qualification stage does not match the requested stage."
        case .approvalGateRequired:
            return "Electrical process qualification requires a human approval gate in the flow stage definition."
        case .invalidRunID:
            return "A flow run ID is required for electrical process qualification."
        case .unverifiedInput:
            return "The process qualification request must be a digest-bound artifact."
        case .unboundStageArtifact:
            return "The process qualification request stage artifact must select an artifact ID."
        case let .inputOutsideProject(path):
            return "The process qualification request is outside the project root: \(path)."
        }
    }
}
