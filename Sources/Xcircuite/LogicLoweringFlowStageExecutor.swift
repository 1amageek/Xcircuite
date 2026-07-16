import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicLowering

public struct LogicLoweringFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any LogicLoweringExecuting)?
    private let support: LogicEngineStageExecutionSupport

    public init(
        stageID: String = "logic.lower",
        toolID: String = "logic-lowering",
        requestInput: XcircuiteFlowInputReference,
        engine: (any LogicLoweringExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.injectedEngine = engine
        self.support = LogicEngineStageExecutionSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            var request = try JSONDecoder().decode(
                LogicLoweringRequest.self,
                from: Data(contentsOf: requestURL)
            )
            guard request.runID == context.runID else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_LOWERING_RUN_ID_MISMATCH",
                    message: "Logic lowering request run ID does not match the flow run."
                )
            }
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stageID)
                .appending(path: "raw")
            request.artifactDirectory = rawDirectory.path(percentEncoded: false)
            let engine = injectedEngine ?? NativeLogicLoweringEngine(
                artifactStore: FileSystemLogicArtifactStore(
                    rootDirectory: context.projectRoot,
                    defaultOutputDirectory: rawDirectory
                )
            )
            let result = try await engine.execute(request)
            try await context.checkCancellation()
            let resultArtifact = try await support.persistResult(
                result,
                fileName: "logic-lowering-result.json",
                artifactID: "logic-lowering-result",
                stageID: stageID,
                context: context
            )
            return support.result(
                status: result.status,
                diagnostics: result.diagnostics,
                artifacts: result.artifacts,
                resultArtifact: resultArtifact,
                stageID: stageID,
                gateID: stageID,
                context: context
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_LOWERING_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
