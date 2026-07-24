import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation

public struct LogicSimulationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference?
    private let designInput: XcircuiteFlowInputReference?
    private let pdkInput: XcircuiteFlowInputReference?
    private let topDesignName: String?
    private let stimulusInput: XcircuiteFlowInputReference?
    private let seed: UInt64?
    private let waveformFormat: LogicWaveformFormat
    private let injectedEngine: (any LogicSimulationExecuting)?
    private let support: LogicEngineStageExecutionSupport

    public init(
        stageID: String = "logic.simulate",
        toolID: String = "logic-simulation",
        requestInput: XcircuiteFlowInputReference,
        engine: (any LogicSimulationExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.designInput = nil
        self.pdkInput = nil
        self.topDesignName = nil
        self.stimulusInput = nil
        self.seed = nil
        self.waveformFormat = .vcd
        self.injectedEngine = engine
        self.support = LogicEngineStageExecutionSupport()
    }

    public init(
        stageID: String = "logic.simulate",
        toolID: String = "logic-simulation",
        designInput: XcircuiteFlowInputReference,
        pdkInput: XcircuiteFlowInputReference,
        topDesignName: String,
        stimulusInput: XcircuiteFlowInputReference? = nil,
        seed: UInt64? = nil,
        waveformFormat: LogicWaveformFormat = .vcd,
        engine: (any LogicSimulationExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = nil
        self.designInput = designInput
        self.pdkInput = pdkInput
        self.topDesignName = topDesignName
        self.stimulusInput = stimulusInput
        self.seed = seed
        self.waveformFormat = waveformFormat
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
                    code: "LOGIC_SIMULATION_RUN_ID_MISMATCH",
                    message: "Logic simulation request run ID does not match the flow run."
                )
            }
            let rawDirectory = try context.xcircuiteRunDirectory()
                .appending(path: "stages")
                .appending(path: stageID)
                .appending(path: "raw")
            request.artifactDirectory = rawDirectory.path(percentEncoded: false)
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "logic-simulation-request",
                stageID: stageID,
                fileName: "logic-simulation-request.json",
            role: .input,
            kind: .request,
            mode: .immutable
            )
            let engine: any LogicSimulationExecuting
            if let injectedEngine {
                engine = injectedEngine
            } else {
                engine = NativeLogicSimulationEngine(
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
                fileName: "logic-simulation-result.json",
                artifactID: "logic-simulation-result",
                stageID: stageID,
            context: context,
            producer: result.provenance.producer,
            mode: .replaceable
            )
            return try support.result(
                status: result.status,
                diagnostics: result.diagnostics,
                artifacts: result.artifacts + [requestArtifact],
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
                code: "LOGIC_SIMULATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func makeRequest(context: FlowExecutionContext) async throws -> LogicSimulationRequest {
        let projectRoot = try context.xcircuiteProjectRoot()
        let runDirectory = try context.xcircuiteRunDirectory()
        if let requestInput {
            let requestURL = try await requestInput.resolveExisting(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure
            )
            return try JSONDecoder().decode(
                LogicSimulationRequest.self,
                from: Data(contentsOf: requestURL)
            )
        }
        guard let designInput, let pdkInput, let topDesignName else {
            throw XcircuiteRuntimeError.invalidInputReference(
                "Logic simulation requires a request input or a producer design input."
            )
        }
        let designArtifact = try await designInput.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            infrastructure: context.infrastructure,
            artifactID: "logic-simulation-design-input",
            kind: .netlist,
            format: .json
        )
        let stimulusArtifact: ArtifactReference?
        if let stimulusInput {
            stimulusArtifact = try await stimulusInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "logic-simulation-stimulus-input",
                kind: .testPattern,
                format: .json
            )
        } else {
            stimulusArtifact = nil
        }
        let pdkArtifact = try await pdkInput.resolveArtifactReference(
            projectRoot: projectRoot,
            runDirectory: runDirectory,
            infrastructure: context.infrastructure,
            artifactID: "logic-simulation-pdk-input",
            kind: .technology,
            format: .json
        )
        return LogicSimulationRequest(
            runID: context.runID,
            inputs: [designArtifact, pdkArtifact] + (stimulusArtifact.map { [$0] } ?? []),
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: topDesignName,
                designRevision: designArtifact.digest
            ),
            stimulus: stimulusArtifact,
            seed: seed,
            waveformFormat: waveformFormat
        )
    }
}
