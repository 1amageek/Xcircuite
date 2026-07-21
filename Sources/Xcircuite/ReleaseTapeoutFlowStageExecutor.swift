import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import TapeoutEngine
import ToolQualification

public struct ReleaseTapeoutFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let geometricXOR: XcircuiteFlowStageExecutorSpec.ReleaseTapeout.GeometricXOR?
    private let injectedEngine: (any TapeoutPackaging)?
    private let support: ReleaseStageExecutionSupport

    public init(
        stageID: String = "release.tapeout",
        toolID: String = "native-release-tapeout",
        requestInput: XcircuiteFlowInputReference,
        geometricXOR: XcircuiteFlowStageExecutorSpec.ReleaseTapeout.GeometricXOR? = nil,
        engine: (any TapeoutPackaging)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.geometricXOR = geometricXOR
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
            let projectRoot = try context.xcircuiteProjectRoot()
            let requestReference = try requestInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: try context.xcircuiteRunDirectory(),
                artifactID: "release-tapeout-request",
                kind: .request,
                format: .json
            )
            let requestURL = try requestReference.locator.location.resolvedFileURL(
                relativeTo: projectRoot
            )
            let data = try Data(contentsOf: requestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var request = try decoder.decode(TapeoutRequest.self, from: data)
            guard request.runID == context.runID else {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_RUN_ID_MISMATCH", message: "Tapeout request run ID does not match the flow run.")
            }
            if let requestedProjectRoot = request.projectRoot,
               URL(fileURLWithPath: requestedProjectRoot).standardizedFileURL != projectRoot.standardizedFileURL {
                return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_PROJECT_ROOT_MISMATCH", message: "Tapeout request project root does not match the flow context.")
            }
            request.projectRoot = projectRoot.path
            let configuredEngine: (any TapeoutPackaging)?
            if let injectedEngine {
                configuredEngine = injectedEngine
            } else if let geometricXOR {
                let qualificationReference = try geometricXOR.qualificationInput
                    .resolveArtifactReference(
                        projectRoot: projectRoot,
                        runDirectory: try context.xcircuiteRunDirectory(),
                        artifactID: "release-geometric-xor-qualification",
                        kind: .evidence,
                        format: .json
                    )
                let qualificationData = try await context.infrastructure.loadArtifactContent(
                    for: qualificationReference
                )
                let qualification = try ToolProcessQualificationEvidence.decodeCanonical(
                    from: qualificationData
                )
                let xorConfiguration = try GeometricXORToolConfiguration(
                    qualification: qualification,
                    reportOutput: geometricXOR.reportOutput,
                    arguments: geometricXOR.arguments,
                    environment: geometricXOR.environment,
                    timeoutSeconds: geometricXOR.timeoutSeconds
                )
                request.inputs = uniqueArtifacts(request.inputs + [qualificationReference])
                let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
                configuredEngine = DefaultTapeoutPackaging(
                    artifactPersister: workspaceStore,
                    xorComparator: QualifiedGeometricXORExecutor(
                        configuration: xorConfiguration,
                        artifactPersister: workspaceStore
                    )
                )
            } else {
                configuredEngine = nil
            }
            let retainedRequest = try await support.persistRequest(
                try support.encodeRequest(request),
                stageID: stageID,
                artifactID: "release-tapeout-request",
                context: context
            )
            let engine: any TapeoutPackaging
            if let configuredEngine {
                engine = configuredEngine
            } else {
                let workspaceStore = try XcircuiteWorkspaceStore(
                    projectRoot: projectRoot
                )
                engine = DefaultTapeoutPackaging(artifactPersister: workspaceStore)
            }
            let engineResult = try await engine.execute(request)
            let result = TapeoutResult(
                schemaVersion: engineResult.schemaVersion,
                runID: engineResult.runID,
                status: engineResult.status,
                diagnostics: engineResult.diagnostics,
                artifacts: engineResult.artifacts,
                metadata: try support.provenance(
                    engineResult.provenance,
                    retaining: retainedRequest
                ),
                payload: engineResult.payload
            )
            try await context.checkCancellation()
            let artifact = try await support.persistResult(
                result,
                stageID: stageID,
                artifactID: "release-tapeout-result",
                context: context,
                producer: result.provenance.producer
            )
            return support.stageResult(
                result: result,
                stageID: stageID,
                artifacts: result.artifacts + [retainedRequest, artifact],
                approved: result.payload.completed
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(stageID: stage.stageID, code: "RELEASE_TAPEOUT_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.id.rawValue < $1.id.rawValue }
    }
}
