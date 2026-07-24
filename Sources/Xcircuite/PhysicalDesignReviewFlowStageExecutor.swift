import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PhysicalDesignCore

/// Prepares an immutable physical-design review packet and validates the
/// reviewed artifact set against the generic Xcircuite approval record.
public struct PhysicalDesignReviewFlowStageExecutor: FlowStageExecutor, FlowStageApprovalValidating {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let reviewScope: [String]

    public init(
        stageID: String = "physical.review",
        manifestInput: XcircuiteFlowInputReference,
        reviewScope: [String] = ["proposed_layout", "design_diff", "implementation_configuration"],
        toolID: String = "physical-design-review"
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.reviewScope = reviewScope
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let manifestURL = try await manifestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let manifestReference = try foundationReference(
                for: manifestURL,
                projectRoot: try context.xcircuiteProjectRoot(),
                artifactID: "physical-design-run-manifest",
                kind: .report,
                format: .json
            )
            let validator = PhysicalDesignArtifactReviewValidator(
                artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: try context.xcircuiteProjectRoot())
            )
            let packet = try await validator.preparePacket(
                manifestReference: manifestReference,
                reviewScope: reviewScope
            )
            try await context.checkCancellation()
            let packetReference = try await persist(
                packet,
                fileName: "physical-design-review-packet.json",
                artifactID: "physical-design-review-packet",
                context: context
            )
            let diagnostic = FlowDiagnostic(
                severity: .info,
                code: "PHYSICAL_DESIGN_REVIEW_PACKET_READY",
                message: "Immutable physical-design review packet is ready for human approval."
            )
            return FlowStageResult(
                stageID: stage.stageID,
                status: .succeeded,
                diagnostics: [diagnostic],
                gates: [
                    FlowGateResult(
                        gateID: "physical-design-review",
                        status: .passed,
                        diagnostics: [diagnostic]
                    )
                ],
                artifacts: [packetReference]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(
                stageID: stage.stageID,
                code: "PHYSICAL_DESIGN_REVIEW_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    public func validateApproval(
        _ approval: FlowApprovalRecord,
        reviewedResult: FlowStageResult,
        context: FlowExecutionContext
    ) async throws -> [FlowDiagnostic] {
        guard approval.verdict == .approved else { return [] }
        guard approval.runID == context.runID, approval.stageID == stageID else {
            return [diagnostic(
                code: "PHYSICAL_DESIGN_REVIEW_APPROVAL_SCOPE_MISMATCH",
                message: "Physical-design approval does not match the reviewed run and stage.",
                actions: ["record_approval_for_the_reviewed_physical_design_stage"]
            )]
        }
        guard let packetReference = reviewedResult.artifacts.first(where: { $0.artifactID == "physical-design-review-packet" }) else {
            return [diagnostic(
                code: "PHYSICAL_DESIGN_REVIEW_PACKET_MISSING",
                message: "The approved stage result does not contain an immutable physical-design review packet.",
                actions: ["rerun_physical_design_review_stage"]
            )]
        }
        let packetURL = try XcircuiteWorkspaceLayout(projectRoot: try context.xcircuiteProjectRoot())
            .url(forProjectRelativePath: packetReference.path)
        let packetData = try Data(contentsOf: packetURL)
        let packet = try PhysicalDesignJSONCodec().decode(
            PhysicalDesignReviewPacket.self,
            from: packetData
        )
        let diagnostics = await PhysicalDesignArtifactReviewValidator(
            artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: try context.xcircuiteProjectRoot())
        ).validateCurrentArtifacts(packet)
        return diagnostics.map(flowDiagnostic)
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        guard !reviewScope.isEmpty, Set(reviewScope).count == reviewScope.count else {
            throw PhysicalDesignReviewFlowError.invalidReviewScope
        }
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        let data = try PhysicalDesignJSONCodec().encode(value)
        return try await context.persistArtifact(
            data,
            artifactID: artifactID,
            stageID: stageID,
            fileName: fileName,
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func foundationReference(
        for url: URL,
        projectRoot: URL,
        artifactID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let path = try ProjectPathBoundary().relativePath(for: url, projectRoot: projectRoot)
        let data = try Data(contentsOf: url)
        return ArtifactReference(
            id: try ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            ),
            digest: try SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count)
        )
    }

    private func flowDiagnostic(_ diagnostic: DesignDiagnostic) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: diagnostic.severity == .warning ? .warning : .error,
            code: diagnostic.code.rawValue,
            message: diagnostic.summary
        )
    }

    private func diagnostic(
        code: String,
        message: String,
        actions: [String]
    ) -> FlowDiagnostic {
        FlowDiagnostic(
            severity: .error,
            code: code,
            message: message + " Suggested actions: " + actions.joined(separator: ", ") + "."
        )
    }

    private func failureResult(
        stageID: String,
        code: String,
        message: String
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: "physical-design-review", status: .failed, diagnostics: [diagnostic])]
        )
    }
}

private enum PhysicalDesignReviewFlowError: Error, LocalizedError {
    case invalidReviewScope

    var errorDescription: String? {
        switch self {
        case .invalidReviewScope:
            return "Physical-design review scope must be non-empty and unique."
        }
    }
}
