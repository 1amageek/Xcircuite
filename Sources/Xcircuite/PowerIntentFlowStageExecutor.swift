import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicDesign
import LogicIR
import PowerIntent

public struct PowerIntentFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let sourceInput: XcircuiteFlowInputReference
    private let designInput: XcircuiteFlowInputReference
    private let pdkInput: XcircuiteFlowInputReference
    private let topDesignName: String
    private let format: PowerIntentFormat
    private let engine: any PowerIntentParsing
    private let support: LogicDesignFlowStageSupport

    public init(
        stageID: String = "logic.power-intent",
        toolID: String = "logic-design.power-intent",
        sourceInput: XcircuiteFlowInputReference,
        designInput: XcircuiteFlowInputReference,
        pdkInput: XcircuiteFlowInputReference,
        topDesignName: String,
        format: PowerIntentFormat = .upf,
        engine: any PowerIntentParsing = PowerIntentParsingEngine()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.sourceInput = sourceInput
        self.designInput = designInput
        self.pdkInput = pdkInput
        self.topDesignName = topDesignName
        self.format = format
        self.engine = engine
        self.support = LogicDesignFlowStageSupport()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let projectRoot = try context.xcircuiteProjectRoot()
            let runDirectory = try context.xcircuiteRunDirectory()
            let sourceReference = try await sourceInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "power-intent-source",
                kind: ArtifactKind.powerIntent,
                format: format == .upf ? ArtifactFormat.upf : ArtifactFormat.cpf
            )
            let designReference = try await designInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "power-intent-design",
                kind: ArtifactKind.rtl,
                format: ArtifactFormat.json
            )
            let pdkReference = try await pdkInput.resolveArtifactReference(
                projectRoot: projectRoot,
                runDirectory: runDirectory,
                infrastructure: context.infrastructure,
                artifactID: "power-intent-pdk",
                kind: ArtifactKind.technology,
                format: ArtifactFormat.json
            )
            let sourceURL = try sourceReference.locator.location.resolvedFileURL(relativeTo: projectRoot)
            let designURL = try designReference.locator.location.resolvedFileURL(relativeTo: projectRoot)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let snapshot = try LogicDesignSnapshotCodec.decode(Data(contentsOf: designURL))
            let designDigest: String
            if let snapshotDigest = snapshot.designDigest {
                designDigest = snapshotDigest
            } else {
                designDigest = try LogicDesignSnapshotCodec.digest(snapshot)
            }
            let request = PowerIntentParsingRequest(
                runID: context.runID,
                inputs: [sourceReference, designReference, pdkReference],
                design: LogicDesignReference(
                    artifact: designReference,
                    topDesignName: topDesignName,
                    designDigest: designDigest
                ),
                format: format,
                sources: [PowerIntentSourceUnit(path: sourceReference.path, source: source, format: format)]
            )
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "power-intent-request",
                stageID: stageID,
                fileName: "power-intent-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )
            let result = try await engine.execute(request)
            try await context.checkCancellation()

            var persistedResult = result
            var artifacts = [sourceReference, designReference, pdkReference, requestArtifact]
            if let intent = result.payload.intent {
                let intentReference = try await context.persistJSONArtifact(
                    intent,
                    artifactID: "power-intent",
                    stageID: stageID,
                    fileName: "power-intent.json",
                    kind: ArtifactKind.powerIntent,
                    mode: .replaceable
                )
                var payload = result.payload
                payload.reference = PowerIntentReference(
                    artifact: intentReference,
                    designDigest: designDigest
                )
                persistedResult = PowerIntentParsingResult(
                    schemaVersion: result.schemaVersion,
                    runID: result.runID,
                    status: result.status,
                    logicDiagnostics: result.logicDiagnostics,
                    provenance: result.provenance,
                    payload: payload
                )
                artifacts.append(intentReference)
            }
            let resultArtifact = try await persistResult(persistedResult, context: context)
            return try makeStageResult(
                result: persistedResult,
                resultArtifact: resultArtifact,
                artifacts: artifacts,
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

    private func persistResult(
        _ result: PowerIntentParsingResult,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            result,
            artifactID: "\(stageID)-domain-result",
            stageID: stageID,
            fileName: "power-intent-result.json",
            kind: ArtifactKind.report,
            producer: result.provenance.producer,
            mode: .replaceable
        )
    }

    private func makeStageResult(
        result: PowerIntentParsingResult,
        resultArtifact: ArtifactReference,
        artifacts: [ArtifactReference],
        context: FlowExecutionContext
    ) throws -> FlowStageResult {
        let diagnostics = result.diagnostics.map { diagnostic in
            let severity: FlowDiagnosticSeverity
            switch diagnostic.severity {
            case .information: severity = .info
            case .warning: severity = .warning
            case .error: severity = .error
            }
            return FlowDiagnostic(
                severity: severity,
                code: diagnostic.code.rawValue,
                message: diagnostic.summary
            )
        }
        let allArtifacts = artifacts + [resultArtifact]
        let integrityGate = StageArtifactIntegrityGateBuilder().gate(
            for: allArtifacts,
            projectRoot: try context.xcircuiteProjectRoot()
        )
        let gateStatus: FlowGateStatus
        let stageStatus: FlowStageStatus
        switch result.status {
        case .completed:
            gateStatus = integrityGate.status == .passed ? .passed : .failed
            stageStatus = integrityGate.status == .passed ? .succeeded : .failed
        case .blocked:
            gateStatus = .blocked
            stageStatus = .blocked
        case .failed:
            gateStatus = .failed
            stageStatus = .failed
        case .cancelled:
            gateStatus = .incomplete
            stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics + integrityGate.diagnostics,
            gates: [
                FlowGateResult(gateID: stageID, status: gateStatus, diagnostics: diagnostics),
                integrityGate,
            ],
            artifacts: allArtifacts
        )
    }

}
