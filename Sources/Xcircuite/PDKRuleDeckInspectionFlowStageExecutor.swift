import DesignFlowKernel
import Foundation
import PDKCore
import PDKKit
import PDKStandardViews

public struct PDKRuleDeckInspectionFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let assetID: String
    private let engine: any PDKRuleDeckInspecting
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = PDKKitAPI.ruleDeckInspectionStageID,
        toolID: String = "pdk-rule-deck-inspection",
        manifestInput: XcircuiteFlowInputReference,
        assetID: String,
        engine: any PDKRuleDeckInspecting
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.assetID = assetID
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = PDKKitAPI.ruleDeckInspectionStageID,
        manifestInput: XcircuiteFlowInputReference,
        assetID: String
    ) -> PDKRuleDeckInspectionFlowStageExecutor {
        PDKRuleDeckInspectionFlowStageExecutor(
            stageID: stageID,
            manifestInput: manifestInput,
            assetID: assetID,
            engine: LocalPDKRuleDeckInspector()
        )
    }

    public static func external(
        configuration: PDKExternalInspectionProcessConfiguration,
        stageID: String = PDKKitAPI.ruleDeckInspectionStageID,
        toolID: String = "pdk-rule-deck-inspection",
        manifestInput: XcircuiteFlowInputReference,
        assetID: String,
        runner: any PDKExternalInspectionProcessRunning = TimedPDKExternalInspectionProcessRunner()
    ) -> PDKRuleDeckInspectionFlowStageExecutor {
        PDKRuleDeckInspectionFlowStageExecutor(
            stageID: stageID,
            toolID: toolID,
            manifestInput: manifestInput,
            assetID: assetID,
            engine: ExternalPDKRuleDeckInspector(
                provider: ExternalPDKRuleDeckProcessProvider(
                    configuration: configuration,
                    stageID: stageID,
                    runner: runner
                )
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
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
            let request = PDKRuleDeckInspectionRequest(
                runID: context.runID,
                inputs: [pdk.manifest.locator],
                pdk: pdk,
                assetID: assetID,
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
                code: "PDK_RULE_DECK_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
