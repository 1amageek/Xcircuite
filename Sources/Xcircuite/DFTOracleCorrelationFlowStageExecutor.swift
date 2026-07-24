import CircuiteFoundation
import DesignFlowKernel
import DFTCore
import Foundation

/// Produces DFT oracle-correlation evidence. Tool acceptance remains a
/// ToolQualification and DesignFlowKernel responsibility.
public struct DFTOracleCorrelationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let corpusInput: XcircuiteFlowInputReference
    private let observationsInput: XcircuiteFlowInputReference
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "dft.oracle-correlation",
        toolID: String = "dft-oracle-correlation",
        corpusInput: XcircuiteFlowInputReference,
        observationsInput: XcircuiteFlowInputReference
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.corpusInput = corpusInput
        self.observationsInput = observationsInput
        self.support = LogicEngineStageExecutionSupport()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)

            let corpusURL = try await corpusInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let observationsURL = try await observationsInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let corpus = try decode(corpusURL, as: DFTOracleCorpus.self)
            let observations = try decode(observationsURL, as: [DFTOracleCaseObservation].self)
            var artifacts = [
                try reference(for: corpusURL, artifactID: "dft-oracle-corpus", kind: .report, context: context),
                try reference(for: observationsURL, artifactID: "dft-oracle-observations", kind: .report, context: context),
            ]

            let correlation = try await DFTOracleCorrelationEngine(
                artifactLoader: FileSystemDFTOracleArtifactLoader(rootURL: try context.xcircuiteProjectRoot())
            ).correlate(corpus: corpus, observations: observations)
            let correlationArtifact = try await persist(
                correlation,
                fileName: "dft-oracle-correlation.json",
                artifactID: "dft-oracle-correlation",
                kind: .report,
                context: context
            )
            artifacts.append(correlationArtifact)

            guard correlation.status == .correlated else {
                let diagnostics = correlation.diagnostics.map {
                    FlowDiagnostic(
                        severity: .error,
                        code: "DFT_ORACLE_CORRELATION_MISMATCH",
                        message: $0
                    )
                } + [
                    FlowDiagnostic(
                        severity: .error,
                        code: correlation.status == .incomplete
                            ? "DFT_ORACLE_CORRELATION_INCOMPLETE"
                            : "DFT_ORACLE_CORRELATION_FAILED",
                        message: correlation.status == .incomplete
                            ? "Every retained DFT oracle case must have a native observation."
                            : "Native DFT results do not match every retained oracle case."
                    ),
                ]
                return blocked(diagnostics: diagnostics, artifacts: artifacts)
            }

            let provenance = DFTEvidenceProvenance(
                status: .oracleCorrelated,
                corpusRevision: corpus.revision,
                oracleEvidence: correlation.oracleEvidenceDigest,
                processID: corpus.processID,
                pdkDigest: corpus.pdkDigest,
                requestDigests: corpus.cases.map(\.requestDigest)
            )
            artifacts.append(
                try await persist(
                    provenance,
                    fileName: "dft-evidence-provenance.json",
                    artifactID: "dft-evidence-provenance",
                    kind: .report,
                    context: context
                )
            )

            return FlowStageResult(
                stageID: stageID,
                status: .succeeded,
                gates: [FlowGateResult(gateID: "dft-oracle-correlation", status: .passed)],
                artifacts: artifacts
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as DFTOracleCorrelationError {
            return support.failure(
                stageID: stageID,
                gateID: "dft-oracle-correlation",
                code: "DFT_ORACLE_CORPUS_INVALID",
                message: error.localizedDescription
            )
        } catch let error as DFTOracleArtifactError {
            return support.failure(
                stageID: stageID,
                gateID: "dft-oracle-correlation",
                code: "DFT_ORACLE_ARTIFACT_INVALID",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: "dft-oracle-correlation",
                code: "DFT_ORACLE_CORRELATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func decode<Value: Decodable>(_ url: URL, as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private func reference(
        for url: URL,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        try artifactBuilder.reference(
            for: url,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: artifactID,
            kind: kind,
            format: .json
        )
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            value,
            artifactID: artifactID,
            stageID: stageID,
            fileName: fileName,
            role: .output,
            kind: kind
        )
    }

    private func blocked(
        diagnostics: [FlowDiagnostic],
        artifacts: [ArtifactReference]
    ) -> FlowStageResult {
        FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [
                FlowGateResult(
                    gateID: "dft-oracle-correlation",
                    status: .blocked,
                    diagnostics: diagnostics
                ),
            ],
            artifacts: artifacts
        )
    }
}
