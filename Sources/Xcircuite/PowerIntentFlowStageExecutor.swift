import DesignFlowKernel
import Foundation
import LogicDesign
import XcircuitePackage

public struct PowerIntentFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let sourceInput: XcircuiteFlowInputReference
    private let designInput: XcircuiteFlowInputReference
    private let topDesignName: String
    private let format: PowerIntentFormat
    private let engine: any PowerIntentParsing
    private let support: LogicDesignFlowStageAdapterSupport

    public init(
        stageID: String = "logic.power-intent",
        toolID: String = "logic-design.power-intent",
        sourceInput: XcircuiteFlowInputReference,
        designInput: XcircuiteFlowInputReference,
        topDesignName: String,
        format: PowerIntentFormat = .upf,
        engine: any PowerIntentParsing = PowerIntentParsingEngine()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.sourceInput = sourceInput
        self.designInput = designInput
        self.topDesignName = topDesignName
        self.format = format
        self.engine = engine
        self.support = LogicDesignFlowStageAdapterSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let sourceURL = try sourceInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let designURL = try designInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let snapshot = try LogicDesignSnapshotCodec.decode(Data(contentsOf: designURL))
            let designDigest: String
            if let snapshotDigest = snapshot.designDigest {
                designDigest = snapshotDigest
            } else {
                designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
            }
            let sourceReference = try support.artifactBuilder.reference(
                for: sourceURL,
                projectRoot: context.projectRoot,
                kind: .powerIntent,
                format: format == .upf ? .upf : .cpf,
                producedByRunID: context.runID
            )
            let designReference = try support.artifactBuilder.reference(
                for: designURL,
                projectRoot: context.projectRoot,
                kind: .rtl,
                format: .json,
                producedByRunID: context.runID
            )
            let request = PowerIntentParsingRequest(
                runID: context.runID,
                inputs: [sourceReference, designReference],
                design: LogicDesignReference(
                    artifact: designReference,
                    topDesignName: topDesignName,
                    designDigest: designDigest
                ),
                format: format,
                sources: [PowerIntentSourceUnit(path: sourceReference.path, source: source, format: format)]
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()

            var persistedEnvelope = envelope
            if let intent = envelope.payload.intent {
                let directory = context.runDirectory
                    .appending(path: "stages")
                    .appending(path: stageID)
                    .appending(path: "raw")
                try context.packageStore.ensureDirectory(at: directory)
                let intentURL = directory.appending(path: "power-intent.json")
                try context.packageStore.writeJSON(
                    intent,
                    to: intentURL,
                    forProjectAt: context.projectRoot
                )
                let intentReference = try support.artifactBuilder.reference(
                    for: intentURL,
                    projectRoot: context.projectRoot,
                    artifactID: "power-intent",
                    kind: .powerIntent,
                    format: .json,
                    producedByRunID: context.runID
                )
                var payload = persistedEnvelope.payload
                payload.reference = PowerIntentReference(
                    artifact: intentReference,
                    designDigest: designDigest
                )
                persistedEnvelope.payload = payload
                persistedEnvelope.artifacts.append(intentReference)
            }
            let resultArtifact = try support.writeEnvelope(
                persistedEnvelope,
                stageID: stageID,
                context: context,
                fileName: "power-intent-result.json"
            )
            return support.stageResult(
                resultArtifact: resultArtifact,
                envelopeStatus: persistedEnvelope.status,
                diagnostics: persistedEnvelope.diagnostics,
                stageID: stageID,
                artifacts: persistedEnvelope.artifacts,
                context: context
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "POWER_INTENT_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

}
