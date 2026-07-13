import DesignFlowKernel
import Foundation
import QualificationEngine
import XcircuitePackage

public struct ReleaseQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let engine: any ReleaseQualificationEvaluating
    private let support: ReleaseStageExecutionAdapterSupport

    public init(
        stageID: String = "release.qualification",
        toolID: String = "native-release-qualification",
        requestInput: XcircuiteFlowInputReference,
        engine: any ReleaseQualificationEvaluating = DefaultRetainedQualificationEvaluator()
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
            var request = try decoder.decode(ReleaseQualificationRequest.self, from: data)
            guard request.runID == context.runID else {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_QUALIFICATION_RUN_ID_MISMATCH", message: "Qualification request run ID does not match the flow run.")
            }
            if let projectRoot = request.projectRoot,
               URL(fileURLWithPath: projectRoot).standardizedFileURL != context.projectRoot.standardizedFileURL {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_QUALIFICATION_PROJECT_ROOT_MISMATCH", message: "Qualification request project root does not match the flow context.")
            }
            request.projectRoot = context.projectRoot.path
            let envelope = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistEnvelope(
                envelope,
                stageID: stageID,
                artifactID: "release-qualification-result",
                context: context
            )
            return support.stageResult(
                envelope: envelope,
                stageID: stageID,
                artifacts: envelope.artifacts + [artifact],
                approved: envelope.payload.qualified
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(stageID: stage.stageID, code: "RELEASE_QUALIFICATION_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }
}
