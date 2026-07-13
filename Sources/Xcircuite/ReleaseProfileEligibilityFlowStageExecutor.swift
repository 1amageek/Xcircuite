import DesignFlowKernel
import Foundation
import ReleaseEngine
import XcircuitePackage

public struct ReleaseProfileEligibilityFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let engine: any ReleaseProfileEligibilityEvaluating
    private let support: ReleaseStageExecutionAdapterSupport

    public init(
        stageID: String = "release.profile",
        toolID: String = "native-release-profile-eligibility",
        requestInput: XcircuiteFlowInputReference,
        engine: any ReleaseProfileEligibilityEvaluating = DefaultReleaseProfileEligibilityEvaluator()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.engine = engine
        self.support = ReleaseStageExecutionAdapterSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let data = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(ReleaseProfileEligibilityRequest.self, from: data)
            guard request.runID == context.runID else {
                return support.failureResult(
                    stageID: stage.stageID,
                    code: "RELEASE_PROFILE_RUN_ID_MISMATCH",
                    message: "Release profile eligibility request run ID does not match the flow context."
                )
            }
            let envelope = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistEnvelope(
                envelope,
                stageID: stageID,
                artifactID: "release-profile-eligibility-result",
                context: context
            )
            return support.stageResult(
                envelope: envelope,
                stageID: stageID,
                artifacts: envelope.artifacts + [artifact],
                approved: envelope.payload.eligible
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stage.stageID,
                code: "RELEASE_PROFILE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
