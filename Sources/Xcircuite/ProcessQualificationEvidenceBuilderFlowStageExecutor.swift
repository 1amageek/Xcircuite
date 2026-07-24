import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

/// Builds canonical process-qualification evidence from retained artifacts.
public struct ProcessQualificationEvidenceBuilderFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let buildRequestInput: XcircuiteFlowInputReference
    private let evidenceBuilder: any ToolProcessQualificationEvidenceBuilding
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "tool-qualification.process-evidence-build",
        toolID: String = "tool-qualification",
        buildRequestInput: XcircuiteFlowInputReference,
        evidenceBuilder: any ToolProcessQualificationEvidenceBuilding = ToolProcessQualificationEvidenceBuilder()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.buildRequestInput = buildRequestInput
        self.evidenceBuilder = evidenceBuilder
        self.support = LogicEngineStageExecutionSupport()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let projectRoot = try context.xcircuiteProjectRoot()
            let buildRequestURL = try await buildRequestInput.resolveExisting(
                projectRoot: projectRoot,
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let buildRequest = try JSONDecoder().decode(
                ToolProcessQualificationEvidenceBuildRequest.self,
                from: Data(contentsOf: buildRequestURL)
            )
            let evidence = try await evidenceBuilder.build(
                buildRequest,
                reading: LocalToolQualificationArtifactReader(workspaceRoot: projectRoot),
                at: Date()
            )
            let requestArtifact = try artifactBuilder.reference(
                for: buildRequestURL,
                projectRoot: projectRoot,
                artifactID: "tool-process-qualification-evidence-build-request",
                kind: .request,
                format: .json
            )
            let producer = try ProducerIdentity(
                kind: .engine,
                identifier: "xcircuite-process-qualification-evidence-builder",
                version: "1"
            )
            let evidenceArtifact = try await context.persistJSONArtifact(
                evidence,
                artifactID: "tool-process-qualification-evidence",
                stageID: stageID,
                fileName: "tool-process-qualification-evidence.json",
                role: .output,
                kind: .release,
                producer: producer,
                mode: .immutable
            )
            return FlowStageResult(
                stageID: stageID,
                status: .succeeded,
                gates: [FlowGateResult(gateID: "tool-process-qualification-evidence", status: .passed)],
                artifacts: [requestArtifact, evidenceArtifact]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            return support.blocked(
                stageID: stageID,
                gateID: "tool-process-qualification-evidence",
                code: "TOOL_PROCESS_QUALIFICATION_EVIDENCE_INVALID",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: "tool-process-qualification-evidence",
                code: "TOOL_PROCESS_QUALIFICATION_EVIDENCE_BUILD_FAILED",
                message: error.localizedDescription
            )
        }
    }
}
