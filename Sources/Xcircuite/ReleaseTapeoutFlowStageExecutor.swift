import DesignFlowKernel
import Foundation
import ReleaseCore
import TapeoutEngine
import DesignFlowKernel

public struct ReleaseTapeoutFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let engine: any TapeoutPackaging
    private let support: ReleaseStageExecutionSupport

    public init(
        stageID: String = "release.tapeout",
        toolID: String = "native-release-tapeout",
        requestInput: XcircuiteFlowInputReference,
        engine: any TapeoutPackaging = DefaultTapeoutPackaging()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.engine = engine
        self.support = ReleaseStageExecutionSupport()
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
            var request = try decoder.decode(TapeoutRequest.self, from: data)
            guard request.runID == context.runID else {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_RUN_ID_MISMATCH", message: "Tapeout request run ID does not match the flow run.")
            }
            if let projectRoot = request.projectRoot,
               URL(fileURLWithPath: projectRoot).standardizedFileURL != context.projectRoot.standardizedFileURL {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_PROJECT_ROOT_MISMATCH", message: "Tapeout request project root does not match the flow context.")
            }
            request.projectRoot = context.projectRoot.path
            if var streamOut = request.streamOut {
                streamOut.projectRoot = context.projectRoot.path
                request.streamOut = streamOut
            }
            let result = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistResult(
                result,
                stageID: stageID,
                artifactID: "release-tapeout-result",
                context: context
            )
            return support.stageResult(
                result: result,
                stageID: stageID,
                artifacts: [artifact],
                approved: result.payload.approved
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }
}
