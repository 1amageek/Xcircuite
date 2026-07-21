import DesignFlowKernel
import Foundation
import ReleaseCore
import SignoffEngine

public struct ReleaseSignoffFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any SignoffEvaluating)?
    private let support: ReleaseStageExecutionSupport

    public init(
        stageID: String = "release.signoff",
        toolID: String = "native-release-signoff",
        requestInput: XcircuiteFlowInputReference,
        engine: (any SignoffEvaluating)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.injectedEngine = engine
        self.support = ReleaseStageExecutionSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let data = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var request = try decoder.decode(SignoffRequest.self, from: data)
            guard request.runID == context.runID else {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_SIGNOFF_RUN_ID_MISMATCH", message: "Signoff request run ID does not match the flow run.")
            }
            if let projectRoot = request.projectRoot,
               URL(fileURLWithPath: projectRoot).standardizedFileURL != (try context.xcircuiteProjectRoot()).standardizedFileURL {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_SIGNOFF_PROJECT_ROOT_MISMATCH", message: "Signoff request project root does not match the flow context.")
            }
            request.projectRoot = try context.xcircuiteProjectRoot().path
            let requestArtifact = try await support.persistRequest(
                try support.encodeRequest(request),
                stageID: stageID,
                artifactID: "release-signoff-request",
                context: context
            )
            let engine: any SignoffEvaluating
            if let injectedEngine {
                engine = injectedEngine
            } else {
                let workspaceStore = try XcircuiteWorkspaceStore(
                    projectRoot: try context.xcircuiteProjectRoot()
                )
                engine = DefaultSignoffEvaluator(artifactPersister: workspaceStore)
            }
            let engineResult = try await engine.execute(request)
            let result = SignoffResult(
                schemaVersion: engineResult.schemaVersion,
                runID: engineResult.runID,
                status: engineResult.status,
                diagnostics: engineResult.diagnostics,
                artifacts: engineResult.artifacts,
                metadata: try support.provenance(
                    engineResult.provenance,
                    retaining: requestArtifact
                ),
                payload: engineResult.payload
            )
            try await context.checkCancellation()
            let artifact = try await support.persistResult(
                result,
                stageID: stageID,
                artifactID: "release-signoff-result",
                context: context,
                producer: result.provenance.producer
            )
            return support.stageResult(
                result: result,
                stageID: stageID,
                artifacts: result.artifacts + [requestArtifact, artifact],
                approved: result.payload.passed
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(stageID: stage.stageID, code: "RELEASE_SIGNOFF_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }
}
