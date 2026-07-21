import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PDKKit
import PDKStandardViews
import PDKValidation

public struct PDKCorpusValidationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let suiteInput: XcircuiteFlowInputReference
    private let rootInput: XcircuiteFlowInputReference
    private let engine: any PDKCorpusValidating
    private let support: PDKStageExecutionSupport

    public init(
        stageID: String = PDKOperation.corpusValidation.rawValue,
        toolID: String = "pdk-corpus-validation",
        suiteInput: XcircuiteFlowInputReference,
        rootInput: XcircuiteFlowInputReference,
        engine: any PDKCorpusValidating
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.suiteInput = suiteInput
        self.rootInput = rootInput
        self.engine = engine
        self.support = PDKStageExecutionSupport()
    }

    public static func local(
        stageID: String = PDKOperation.corpusValidation.rawValue,
        suiteInput: XcircuiteFlowInputReference,
        rootInput: XcircuiteFlowInputReference
    ) -> PDKCorpusValidationFlowStageExecutor {
        PDKCorpusValidationFlowStageExecutor(
            stageID: stageID,
            suiteInput: suiteInput,
            rootInput: rootInput,
            engine: LocalPDKCorpusValidator()
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let suiteURL = try suiteInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            let rootURL = try rootInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory()
            )
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: rootURL.path(percentEncoded: false),
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return support.failureResult(
                    stageID: stageID,
                    code: "PDK_CORPUS_ROOT_INVALID",
                    message: "The PDK corpus root input is not a directory."
                )
            }
            let suiteReference = try support.inputLocator(
                for: suiteURL,
                context: context,
                artifactID: "pdk-corpus-suite",
                kind: .report,
                format: .json
            )
            let request = PDKCorpusValidationRequest(
                runID: context.runID,
                suitePath: suiteURL.path(percentEncoded: false),
                rootPath: rootURL.path(percentEncoded: false),
                inputs: [suiteReference]
            )
            let result = try await engine.execute(request)
            try await context.checkCancellation()
            let artifact = try await support.persistResult(result, stageID: stageID, context: context)
            return support.stageResult(result: result, stageID: stageID, artifact: artifact)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "PDK_CORPUS_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
