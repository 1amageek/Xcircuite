import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PDKCore
import PDKKit
import PDKStandardViews

public struct PDKOracleFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let oracleInput: XcircuiteFlowInputReference
    private let engine: any PDKOracleComparing
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = PDKOperation.oracleComparison.rawValue,
        toolID: String = "pdk-oracle-comparison",
        manifestInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference,
        engine: any PDKOracleComparing
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.oracleInput = oracleInput
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = PDKOperation.oracleComparison.rawValue,
        manifestInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference
    ) -> PDKOracleFlowStageExecutor {
        PDKOracleFlowStageExecutor(
            stageID: stageID,
            manifestInput: manifestInput,
            oracleInput: oracleInput,
            engine: LocalPDKOracleComparator()
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let manifestURL = try manifestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let oracleURL = try oracleInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
            let oracle = try support.inputReference(
                for: oracleURL,
                context: context,
                artifactID: "pdk-oracle",
                kind: .technology,
                format: .json
            )
            let request = PDKOracleRequest(
                runID: context.runID,
                pdk: pdk,
                oracle: oracle,
                projectRootPath: try context.xcircuiteProjectRoot().path(percentEncoded: false)
            )
            let result = try await engine.execute(request)
            try await context.checkCancellation()
            let artifact = try support.persistResult(result, stageID: stageID, context: context)
            return support.stageResult(result: result, stageID: stageID, artifact: artifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "PDK_ORACLE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
