import DesignFlowKernel
import CircuiteFoundation
import Foundation
import LogicDesign

public struct LogicElaborationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let sourceInput: XcircuiteFlowInputReference
    private let topDesignName: String
    private let injectedEngine: (any LogicElaborating)?
    private let support: LogicDesignFlowStageSupport

    public init(
        stageID: String = "logic.elaborate",
        toolID: String = "logic-design.native",
        sourceInput: XcircuiteFlowInputReference,
        topDesignName: String,
        engine: (any LogicElaborating)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.sourceInput = sourceInput
        self.topDesignName = topDesignName
        self.injectedEngine = engine
        self.support = LogicDesignFlowStageSupport()
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
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let sourceReference = try support.artifactBuilder.reference(
                for: sourceURL,
                projectRoot: context.projectRoot,
                kind: .rtl,
                format: sourceURL.pathExtension.lowercased() == "v" ? .verilog : .systemVerilog,
                producedByRunID: context.runID
            )
            let request = LogicElaborationRequest(
                runID: context.runID,
                inputs: [try FoundationFlowProjection.locator(from: sourceReference)],
                topDesignName: topDesignName,
                sources: [SystemVerilogSourceUnit(
                    path: sourceReference.path,
                    source: source
                )]
            )
            let engine = injectedEngine ?? LogicElaboratingEngine(
                sourceProvider: FileSystemSystemVerilogSourceProvider(root: context.projectRoot)
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()

            var persistedResult = envelope
            var resultArtifacts = [sourceReference]
            if let snapshot = envelope.payload.snapshot {
                let directory = context.runDirectory
                    .appending(path: "stages")
                    .appending(path: stageID)
                    .appending(path: "raw")
                try context.packageStore.ensureDirectory(at: directory)
                let snapshotURL = directory.appending(path: "logic-design.json")
                try context.packageStore.writeJSON(
                    snapshot,
                    to: snapshotURL,
                    forProjectAt: context.projectRoot
                )
                let snapshotReference = try support.artifactBuilder.reference(
                    for: snapshotURL,
                    projectRoot: context.projectRoot,
                    artifactID: "logic-design",
                    kind: .rtl,
                    format: .json,
                    producedByRunID: context.runID
                )
                var payload = persistedResult.payload
                let designDigest: String
                if let snapshotDigest = snapshot.designDigest {
                    designDigest = snapshotDigest
                } else {
                    designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
                }
                payload.design = LogicDesignReference(
                    artifact: try FoundationFlowProjection.locator(from: snapshotReference),
                    topDesignName: snapshot.rtl.topModuleName,
                    designDigest: designDigest,
                    provenance: LogicDesignProvenance(
                        sourceDesignDigest: designDigest,
                        transformationID: "systemverilog-elaboration",
                        producerID: persistedResult.metadata.engineID,
                        producerVersion: persistedResult.metadata.implementationVersion,
                        runID: context.runID
                    )
                )
                persistedResult = LogicElaborationResult(
                    schemaVersion: persistedResult.schemaVersion,
                    runID: persistedResult.runID,
                    status: persistedResult.status,
                    diagnostics: persistedResult.diagnostics,
                    metadata: persistedResult.metadata,
                    payload: payload
                )
                resultArtifacts.append(snapshotReference)
            }
            let resultArtifact = try support.writeResult(
                persistedResult,
                stageID: stageID,
                context: context,
                fileName: "logic-result.json"
            )
            return support.stageResult(
                resultArtifact: resultArtifact,
                status: persistedResult.status,
                diagnostics: persistedResult.diagnostics,
                stageID: stageID,
                artifacts: resultArtifacts,
                context: context
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return support.failureResult(
                stageID: stageID,
                code: "LOGIC_ELABORATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
