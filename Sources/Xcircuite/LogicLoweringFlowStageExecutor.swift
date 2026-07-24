import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicLowering

public struct LogicLoweringFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference?
    private let designInput: XcircuiteFlowInputReference?
    private let topDesignName: String?
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
        self.designInput = nil
        self.topDesignName = nil
        self.injectedEngine = engine
        self.support = LogicEngineStageExecutionSupport()
    }

    public init(
        stageID: String = "logic.lower",
        toolID: String = "logic-lowering",
        designInput: XcircuiteFlowInputReference,
        topDesignName: String,
        engine: (any LogicLoweringExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = nil
        self.designInput = designInput
        self.topDesignName = topDesignName
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
            var request = try await makeRequest(context: context)
            guard request.runID == context.runID else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_LOWERING_RUN_ID_MISMATCH",
                    message: "Logic lowering request run ID does not match the flow run."
                )
            }
            let rawDirectory = try context.xcircuiteRunDirectory()
                .appending(path: "stages")
                .appending(path: stageID)
                .appending(path: "raw")
            request.artifactDirectory = rawDirectory.path(percentEncoded: false)
            let engine: any LogicLoweringExecuting
            if let injectedEngine {
                engine = injectedEngine
            } else {
                engine = NativeLogicLoweringEngine(
                    artifactStore: FileSystemLogicArtifactStore(
                        rootDirectory: try context.xcircuiteProjectRoot(),
                        defaultOutputDirectory: rawDirectory
                    )
                )
            }
            let result = try await engine.execute(request)
            try await context.checkCancellation()
            let resultArtifact = try await support.persistResult(
                result,
                fileName: "logic-lowering-result.json",
                artifactID: "logic-lowering-result",
                stageID: stageID,
                context: context,
                producer: result.provenance.producer,
                mode: .replaceable
            )
            return try support.result(
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

    private func makeRequest(context: FlowExecutionContext) async throws -> LogicLoweringRequest {
        let projectRoot = try context.xcircuiteProjectRoot()
        let runDirectory = try context.xcircuiteRunDirectory()
        if let requestInput {
            let requestURL = try await requestInput.resolveExisting(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure
            )
            return try JSONDecoder().decode(
                LogicLoweringRequest.self,
                from: Data(contentsOf: requestURL)
            )
        }
        guard let designInput, let topDesignName else {
            throw XcircuiteRuntimeError.invalidInputReference(
                "Logic lowering requires a request input or a producer design input."
            )
        }
        let designArtifact = try await designInput.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            infrastructure: context.infrastructure,
            artifactID: "logic-lowering-design-input",
            kind: .rtl,
            format: .json
        )
        let designURL = try designArtifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
        let snapshot = try LogicDesignSnapshotCodec.decode(Data(contentsOf: designURL))
        let designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        guard snapshot.rtl.topModuleName == topDesignName else {
            throw XcircuiteRuntimeError.invalidInputReference(
                "Logic lowering top design does not match the producer snapshot."
            )
        }
        return LogicLoweringRequest(
            runID: context.runID,
            inputs: [designArtifact],
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: topDesignName,
                designDigest: designDigest
            )
        )
    }
}
