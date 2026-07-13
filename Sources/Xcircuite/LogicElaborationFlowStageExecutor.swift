import DesignFlowKernel
import Foundation
import LogicDesign
import XcircuitePackage

public struct LogicElaborationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let sourceInput: XcircuiteFlowInputReference
    private let topDesignName: String
    private let injectedEngine: (any LogicElaborating)?
    private let support: LogicDesignFlowStageAdapterSupport

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
                inputs: [sourceReference],
                topDesignName: topDesignName,
                sources: [SystemVerilogSourceUnit(path: sourceReference.path, source: source)]
            )
            let engine = injectedEngine ?? LogicElaboratingEngine(
                sourceProvider: FileSystemSystemVerilogSourceProvider(root: context.projectRoot)
            )
            let envelope = try await engine.execute(request)
            try context.checkCancellation()

            var persistedEnvelope = envelope
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
                var payload = persistedEnvelope.payload
                let designDigest: String
                if let snapshotDigest = snapshot.designDigest {
                    designDigest = snapshotDigest
                } else {
                    designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
                }
                payload.design = LogicDesignReference(
                    artifact: snapshotReference,
                    topDesignName: snapshot.rtl.topModuleName,
                    designDigest: designDigest,
                    provenance: LogicDesignProvenance(
                        sourceDesignDigest: designDigest,
                        transformationID: "systemverilog-elaboration",
                        producerID: persistedEnvelope.metadata.engineID,
                        producerVersion: persistedEnvelope.metadata.implementationVersion,
                        runID: context.runID
                    )
                )
                persistedEnvelope.payload = payload
                persistedEnvelope.artifacts.append(snapshotReference)
            }
            let resultArtifact = try support.writeEnvelope(
                persistedEnvelope,
                stageID: stageID,
                context: context,
                fileName: "logic-result.json"
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
                code: "LOGIC_ELABORATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }
}
