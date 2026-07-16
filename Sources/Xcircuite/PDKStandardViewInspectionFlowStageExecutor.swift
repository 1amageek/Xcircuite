import DesignFlowKernel
import Foundation
import PDKKit
import DesignFlowKernel

public struct PDKStandardViewInspectionFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let assetID: String
    private let format: PDKStandardViewFormat
    private let engine: any PDKManifestViewInspecting
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = PDKKitAPI.standardViewInspectionStageID,
        toolID: String = "pdk-standard-view-inspection",
        manifestInput: XcircuiteFlowInputReference,
        assetID: String,
        format: PDKStandardViewFormat,
        engine: any PDKManifestViewInspecting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.assetID = assetID
        self.format = format
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = PDKKitAPI.standardViewInspectionStageID,
        manifestInput: XcircuiteFlowInputReference,
        assetID: String,
        format: PDKStandardViewFormat
    ) -> PDKStandardViewInspectionFlowStageExecutor {
        PDKStandardViewInspectionFlowStageExecutor(
            stageID: stageID,
            manifestInput: manifestInput,
            assetID: assetID,
            format: format,
            engine: LocalPDKManifestViewInspector()
        )
    }

    public static func external(
        configuration: PDKExternalInspectionProcessConfiguration,
        stageID: String = PDKKitAPI.standardViewInspectionStageID,
        toolID: String = "pdk-standard-view-inspection",
        manifestInput: XcircuiteFlowInputReference,
        assetID: String,
        format: PDKStandardViewFormat,
        runner: any PDKExternalInspectionProcessRunning = TimedPDKExternalInspectionProcessRunner()
    ) -> PDKStandardViewInspectionFlowStageExecutor {
        let provider = ExternalPDKStandardViewProcessProvider(
            configuration: configuration,
            stageID: stageID,
            runner: runner
        )
        return PDKStandardViewInspectionFlowStageExecutor(
            stageID: stageID,
            toolID: toolID,
            manifestInput: manifestInput,
            assetID: assetID,
            format: format,
            engine: LocalPDKManifestViewInspector(
                standardInspector: ExternalPDKStandardViewInspector(provider: provider)
            )
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
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
            let request = PDKManifestViewInspectionRequest(
                runID: context.runID,
                inputs: [pdk.manifest.locator],
                pdk: pdk,
                assetID: assetID,
                format: format,
                projectRootPath: context.projectRoot.path(percentEncoded: false)
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
                code: "PDK_STANDARD_VIEW_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
