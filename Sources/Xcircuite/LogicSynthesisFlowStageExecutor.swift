import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicSynthesis

public struct LogicSynthesisFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any LogicSynthesisExecuting)?
    private let support: LogicEngineStageExecutionSupport

    public init(
        stageID: String = "logic.synthesize",
        toolID: String = "logic-synthesis",
        requestInput: XcircuiteFlowInputReference,
        engine: (any LogicSynthesisExecuting)? = nil
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
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            var request = try JSONDecoder().decode(
                LogicSynthesisRequest.self,
                from: Data(contentsOf: requestURL)
            )
            guard request.runID == context.runID else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_SYNTHESIS_RUN_ID_MISMATCH",
                    message: "Logic synthesis request run ID does not match the flow run."
                )
            }
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stageID)
                .appending(path: "raw")
            request.artifactDirectory = rawDirectory.path(percentEncoded: false)
            let engine = injectedEngine ?? NativeLogicSynthesisEngine(
                artifactStore: FileSystemLogicArtifactStore(
                    rootDirectory: context.projectRoot,
                    defaultOutputDirectory: rawDirectory
                )
            )
            let result = try await engine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try support.persistResult(
                result,
                fileName: "logic-synthesis-result.json",
                artifactID: "logic-synthesis-result",
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
                code: "LOGIC_SYNTHESIS_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
