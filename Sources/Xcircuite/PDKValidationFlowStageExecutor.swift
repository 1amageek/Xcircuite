import DesignFlowKernel
import Foundation
import PDKCore
import PDKValidation
import XcircuitePackage

public struct PDKValidationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let manifestInput: XcircuiteFlowInputReference
    private let requiredAssetRoles: [PDKAssetRole]
    private let validateCrossViews: Bool
    private let engine: any PDKValidating
    private let support: PDKStageExecutionAdapterSupport

    public init(
        stageID: String = "pdk.validate",
        toolID: String = "pdk-validation",
        manifestInput: XcircuiteFlowInputReference,
        requiredAssetRoles: [PDKAssetRole] = [],
        validateCrossViews: Bool = true,
        engine: any PDKValidating
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.manifestInput = manifestInput
        self.requiredAssetRoles = requiredAssetRoles
        self.validateCrossViews = validateCrossViews
        self.engine = engine
        self.support = PDKStageExecutionAdapterSupport()
    }

    public static func local(
        stageID: String = "pdk.validate",
        manifestInput: XcircuiteFlowInputReference,
        requiredAssetRoles: [PDKAssetRole] = [],
        validateCrossViews: Bool = true
    ) -> PDKValidationFlowStageExecutor {
        PDKValidationFlowStageExecutor(
            stageID: stageID,
            manifestInput: manifestInput,
            requiredAssetRoles: requiredAssetRoles,
            validateCrossViews: validateCrossViews,
            engine: LocalPDKValidator()
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
            let pdk = try PDKManifestReferenceBuilder().makeReference(for: manifestURL)
            let request = PDKValidationRequest(
                runID: context.runID,
                inputs: [pdk.manifest],
                pdk: pdk,
                requiredAssetRoles: requiredAssetRoles,
                validateCrossViews: validateCrossViews
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()
            let artifact = try support.persistEnvelope(envelope, stageID: stageID, context: context)
            return support.stageResult(envelope: envelope, stageID: stageID, artifact: artifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "PDK_VALIDATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
