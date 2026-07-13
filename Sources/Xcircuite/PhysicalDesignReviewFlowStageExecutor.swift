import DesignFlowKernel
import CircuiteFoundation
import Foundation
import PhysicalDesignCore
import PhysicalDesignEngine
import DesignFlowKernel

/// Prepares an immutable physical-design review packet and binds the generic
/// Xcircuite approval record to the native physical-design resume gate.
public struct PhysicalDesignReviewFlowStageExecutor: FlowStageExecutor, FlowStageApprovalValidating {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let decisionScope: [String]

    public init(
        stageID: String = "physical.review",
        manifestInput: XcircuiteFlowInputReference,
        decisionScope: [String] = ["proposed_layout", "design_diff", "implementation_configuration"],
        toolID: String = "physical-design-review"
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.decisionScope = decisionScope
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try validate(stage: stage)
            let manifestURL = try manifestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let manifestReference = try foundationReference(
                for: manifestURL,
                projectRoot: context.projectRoot,
                artifactID: "physical-design-run-manifest",
                kind: .report,
                format: .json
            )
            let manifestArtifact = try StageArtifactReferenceBuilder().reference(
                for: manifestURL,
                projectRoot: context.projectRoot,
                artifactID: "physical-design-run-manifest",
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            )
            let gate = PhysicalDesignReviewGate(
                artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: context.projectRoot)
            )
            let packet = try await gate.prepareReview(
                manifestReference: manifestReference,
                decisionScope: decisionScope
            )
            try context.checkCancellation()
            let packetReference = try persist(
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
                artifacts: [manifestArtifact, packetReference]
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
        _ approval: XcircuiteApprovalRecord,
        reviewedResult: FlowStageResult,
        context: FlowExecutionContext
    ) throws -> [FlowDiagnostic] {
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
        let packetURL = try XcircuitePackage(projectRoot: context.projectRoot)
            .url(forProjectRelativePath: packetReference.path)
        let packetData = try Data(contentsOf: packetURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let packet = try decoder.decode(PhysicalDesignReviewPacket.self, from: packetData)
        var diagnostics = verifyPacketArtifacts(packet, projectRoot: context.projectRoot)
        guard diagnostics.isEmpty else { return diagnostics }

        let decision = PhysicalDesignReviewDecision(
            decisionID: "approval-\(approval.runID)-\(approval.stageID)-\(approval.createdAt.timeIntervalSince1970)",
            runID: approval.runID,
            stage: packet.stage,
            verdict: .approved,
            reviewer: approval.reviewer,
            reviewerKind: PhysicalDesignReviewerKind(rawValue: approval.reviewerKind.rawValue) ?? .system,
            note: approval.note,
            manifestDigest: packet.manifestDigest,
            proposedLayoutDigest: packet.proposedLayout.layoutDigest,
            decisionScope: packet.decisionScope,
            createdAt: approval.createdAt
        )
        let resumeRequest = PhysicalDesignResumeRequest(
            runID: approval.runID,
            stage: packet.stage,
            manifestDigest: packet.manifestDigest,
            expectedBaseLayoutDigest: packet.baseLayout?.layoutDigest,
            proposedLayoutDigest: packet.proposedLayout.layoutDigest,
            decision: decision
        )
        let result = PhysicalDesignReviewGate(
            artifactStore: FileSystemPhysicalDesignArtifactStore(projectRoot: context.projectRoot)
        ).validateResume(resumeRequest, packet: packet)
        diagnostics.append(contentsOf: result.diagnostics.map(flowDiagnostic))
        return diagnostics
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        guard !decisionScope.isEmpty, Set(decisionScope).count == decisionScope.count else {
            throw PhysicalDesignReviewFlowError.invalidDecisionScope
        }
    }

    private func verifyPacketArtifacts(
        _ packet: PhysicalDesignReviewPacket,
        projectRoot: URL
    ) -> [FlowDiagnostic] {
        var diagnostics: [FlowDiagnostic] = []
        let package = XcircuitePackage(projectRoot: projectRoot)
        let hasher = XcircuiteHasher()
        do {
            let manifestURL = try package.url(forProjectRelativePath: packet.manifestReference.path)
            let manifestData = try Data(contentsOf: manifestURL)
            let manifestDigest = hasher.sha256(data: manifestData)
            if manifestDigest != packet.manifestDigest || packet.manifestReference.sha256 != manifestDigest {
                diagnostics.append(diagnostic(
                    code: "PHYSICAL_DESIGN_REVIEW_MANIFEST_TAMPERED",
                    message: "The reviewed physical-design manifest changed after packet creation.",
                    actions: ["prepare_a_new_physical_design_review_packet"]
                ))
            }
            if Int64(manifestData.count) != Int64(packet.manifestReference.byteCount) {
                diagnostics.append(diagnostic(
                    code: "PHYSICAL_DESIGN_REVIEW_MANIFEST_SIZE_MISMATCH",
                    message: "The reviewed physical-design manifest byte count changed after packet creation.",
                    actions: ["prepare_a_new_physical_design_review_packet"]
                ))
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let currentManifest = try decoder.decode(PhysicalDesignRunManifest.self, from: manifestData)
            if currentManifest != packet.manifest {
                diagnostics.append(diagnostic(
                    code: "PHYSICAL_DESIGN_REVIEW_MANIFEST_PACKET_MISMATCH",
                    message: "The embedded physical-design manifest in the review packet does not match the current manifest artifact.",
                    actions: ["prepare_a_new_physical_design_review_packet"]
                ))
            }
            for (path, expectedDigest) in packet.artifactDigests {
                let artifactURL = try package.url(forProjectRelativePath: path)
                let artifactData = try Data(contentsOf: artifactURL)
                let actualDigest = hasher.sha256(data: artifactData)
                if actualDigest != expectedDigest {
                    diagnostics.append(diagnostic(
                        code: "PHYSICAL_DESIGN_REVIEW_ARTIFACT_TAMPERED",
                        message: "Reviewed artifact \(path) changed after packet creation.",
                        actions: ["prepare_a_new_physical_design_review_packet"]
                    ))
                }
                if let expectedByteCount = packet.manifest.artifacts.first(where: { $0.path == path })?.byteCount,
                   Int64(artifactData.count) != expectedByteCount {
                    diagnostics.append(diagnostic(
                        code: "PHYSICAL_DESIGN_REVIEW_ARTIFACT_SIZE_MISMATCH",
                        message: "Reviewed artifact (path) byte count changed after packet creation.",
                        actions: ["prepare_a_new_physical_design_review_packet"]
                    ))
                }
            }
        } catch {
            diagnostics.append(diagnostic(
                code: "PHYSICAL_DESIGN_REVIEW_ARTIFACT_UNAVAILABLE",
                message: "Reviewed physical-design artifact verification failed: \(error.localizedDescription)",
                actions: ["restore_review_artifacts", "prepare_a_new_physical_design_review_packet"]
            ))
        }
        return diagnostics
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
        let data = try PhysicalDesignJSONCodec().encode(value)
        try data.write(to: url, options: .atomic)
        return try StageArtifactReferenceBuilder().reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: .report,
            format: .json,
            producedByRunID: context.runID
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
    case invalidDecisionScope

    var errorDescription: String? {
        switch self {
        case .invalidDecisionScope:
            return "Physical-design review decision scope must be non-empty and unique."
        }
    }
}
