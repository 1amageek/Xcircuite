import DesignFlowKernel
import Foundation
import LogicEngineCore
import LogicSimulation
import XcircuitePackage

public struct LogicSimulationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any LogicSimulationExecuting)?
    private let support: LogicEngineStageExecutionAdapterSupport

    public init(
        stageID: String = "logic.simulate",
        toolID: String = "logic-simulation",
        requestInput: XcircuiteFlowInputReference,
        engine: (any LogicSimulationExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.injectedEngine = engine
        self.support = LogicEngineStageExecutionAdapterSupport()
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
                LogicSimulationRequest.self,
                from: Data(contentsOf: requestURL)
            )
            guard request.runID == context.runID else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_SIMULATION_RUN_ID_MISMATCH",
                    message: "Logic simulation request run ID does not match the flow run."
                )
            }
            let rawDirectory = context.runDirectory
                .appending(path: "stages")
                .appending(path: stageID)
                .appending(path: "raw")
            request.artifactDirectory = rawDirectory.path(percentEncoded: false)
            let engine = injectedEngine ?? NativeLogicSimulationEngine(
                artifactStore: FileSystemLogicArtifactStore(
                    rootDirectory: context.projectRoot,
                    defaultOutputDirectory: rawDirectory
                )
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()
            let resultArtifact = try support.persistEnvelope(
                envelope,
                fileName: "logic-simulation-result.json",
                artifactID: "logic-simulation-result",
                stageID: stageID,
                context: context
            )
            return support.result(
                envelope: envelope,
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
                code: "LOGIC_SIMULATION_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
