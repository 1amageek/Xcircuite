import DesignFlowKernel
import CircuiteFoundation
import Foundation
import PDKKit
import DesignFlowKernel

public struct PDKQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let corpusInput: XcircuiteFlowInputReference
    private let oracleInput: XcircuiteFlowInputReference
    private let engine: any PDKQualificationExecuting
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = PDKKitAPI.qualificationStageID,
        toolID: String = "pdk-qualification",
        manifestInput: XcircuiteFlowInputReference,
        corpusInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference,
        engine: any PDKQualificationExecuting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.corpusInput = corpusInput
        self.oracleInput = oracleInput
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = PDKKitAPI.qualificationStageID,
        manifestInput: XcircuiteFlowInputReference,
        corpusInput: XcircuiteFlowInputReference,
        oracleInput: XcircuiteFlowInputReference
    ) -> PDKQualificationFlowStageExecutor {
        PDKQualificationFlowStageExecutor(
            stageID: stageID,
            manifestInput: manifestInput,
            corpusInput: corpusInput,
            oracleInput: oracleInput,
            engine: LocalPDKQualificationEvaluator()
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let manifestURL = try manifestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let corpusURL = try corpusInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let oracleURL = try oracleInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
            let corpus = try support.inputReference(
                for: corpusURL,
                context: context,
                artifactID: "pdk-corpus-report",
                kind: .report,
                format: .json
            )
            let oracle = try support.inputReference(
                for: oracleURL,
                context: context,
                artifactID: "pdk-oracle-report",
                kind: .report,
                format: .json
            )
            let request = PDKQualificationRequest(
                runID: context.runID,
                pdk: pdk,
                corpusReport: corpus,
                oracleReport: oracle,
                projectRootPath: context.projectRoot.path(percentEncoded: false)
            )
            let result = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistResult(result, stageID: stageID, context: context)
            return support.stageResult(result: result, stageID: stageID, artifact: artifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "PDK_QUALIFICATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
