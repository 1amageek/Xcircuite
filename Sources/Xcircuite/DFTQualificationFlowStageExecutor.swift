import DFTCore
import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

public struct DFTQualificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let corpusInput: XcircuiteFlowInputReference
    private let observationsInput: XcircuiteFlowInputReference
    private let qualificationEvidenceInput: XcircuiteFlowInputReference?
    private let processQualificationEvidenceBuildInput: XcircuiteFlowInputReference?
    private let processQualificationEvidenceBuilder: any ToolProcessQualificationEvidenceBuilding
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "dft.qualification",
        toolID: String = "dft-qualification",
        corpusInput: XcircuiteFlowInputReference,
        observationsInput: XcircuiteFlowInputReference,
        qualificationEvidenceInput: XcircuiteFlowInputReference? = nil,
        processQualificationEvidenceBuildInput: XcircuiteFlowInputReference? = nil,
        processQualificationEvidenceBuilder: any ToolProcessQualificationEvidenceBuilding = ToolProcessQualificationEvidenceBuilder()
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.corpusInput = corpusInput
        self.observationsInput = observationsInput
        self.qualificationEvidenceInput = qualificationEvidenceInput
        self.processQualificationEvidenceBuildInput = processQualificationEvidenceBuildInput
        self.processQualificationEvidenceBuilder = processQualificationEvidenceBuilder
        self.support = LogicEngineStageExecutionSupport()
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)

            let corpusURL = try corpusInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let observationsURL = try observationsInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let corpus = try decode(corpusURL, as: DFTOracleCorpus.self)
            let observations = try decode(observationsURL, as: [DFTOracleCaseObservation].self)
            let sourceArtifacts = [
                try reference(
                    for: corpusURL,
                    artifactID: "dft-oracle-corpus",
                    kind: .report,
                    context: context
                ),
                try reference(
                    for: observationsURL,
                    artifactID: "dft-oracle-observations",
                    kind: .report,
                    context: context
                ),
            ]

            let loader = FileSystemDFTOracleArtifactLoader(rootURL: context.projectRoot)
            let correlation = try await DFTOracleCorrelationEngine(
                artifactLoader: loader
            ).correlate(
                corpus: corpus,
                observations: observations
            )

            var artifacts = sourceArtifacts
            var qualificationEvidence: DFTQualificationEvidence?
            if let qualificationEvidenceInput {
                let evidenceURL = try qualificationEvidenceInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                qualificationEvidence = try decode(
                    evidenceURL,
                    as: DFTQualificationEvidence.self
                )
                artifacts.append(
                    try reference(
                        for: evidenceURL,
                        artifactID: "dft-qualification-evidence",
                        kind: .release,
                        context: context
                    )
                )
            }

            let correlationStatus = correlation.status
            let correlationDiagnostics = correlation.diagnostics.map { message in
                FlowDiagnostic(
                    severity: .error,
                    code: "DFT_ORACLE_CORRELATION_MISMATCH",
                    message: message
                )
            }

            if correlationStatus != .correlated {
                return try persistBlocked(
                    correlation: correlation,
                    diagnostics: correlationDiagnostics + [
                        FlowDiagnostic(
                            severity: .error,
                            code: correlationStatus == .incomplete
                                ? "DFT_QUALIFICATION_CORRELATION_INCOMPLETE"
                                : "DFT_QUALIFICATION_CORRELATION_FAILED",
                            message: correlationStatus == .incomplete
                                ? "Every retained DFT oracle case must have a native observation."
                                : "Native DFT results do not match every retained oracle case."
                        ),
                    ],
                    artifacts: artifacts,
                    context: context
                )
            }

            guard let qualificationEvidence else {
                return try persistBlocked(
                    correlation: correlation,
                    diagnostics: [
                        FlowDiagnostic(
                            severity: .error,
                            code: "DFT_QUALIFICATION_APPROVAL_REQUIRED",
                            message: "Correlated DFT results require process qualification evidence and an approver."
                        ),
                    ],
                    artifacts: artifacts,
                    context: context
                )
            }

            guard qualificationEvidence.oracleEvidenceDigest == correlation.oracleEvidenceDigest else {
                return try persistBlocked(
                    correlation: correlation,
                    diagnostics: [
                        FlowDiagnostic(
                            severity: .error,
                            code: "DFT_QUALIFICATION_EVIDENCE_DIGEST_MISMATCH",
                            message: "Qualification evidence does not identify the current oracle correlation result."
                        ),
                    ],
                    artifacts: artifacts,
                    context: context
                )
            }

            var provenance = try DFTQualificationGate().evaluate(
                qualificationEvidence,
                expectedProcessID: corpus.processID,
                expectedPDKDigest: corpus.pdkDigest
            )
            provenance.requestDigests = corpus.cases.map(\.requestDigest).sorted()
            let provenanceArtifact = try persist(
                provenance,
                fileName: "dft-qualification-provenance.json",
                artifactID: "dft-qualification-provenance",
                kind: .release,
                context: context
            )
            artifacts.append(provenanceArtifact)

            if let processQualificationEvidenceBuildInput {
                let buildURL = try processQualificationEvidenceBuildInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let buildRequest = try decode(
                    buildURL,
                    as: ToolProcessQualificationEvidenceBuildRequest.self
                )
                let buildRequestArtifact = try reference(
                    for: buildURL,
                    artifactID: "dft-process-qualification-build-request",
                    kind: .request,
                    context: context
                )
                let verifier = LocalArtifactVerifier()
                for artifact in buildRequest.evidenceArtifacts {
                    let integrity = verifier.verify(
                        artifact,
                        relativeTo: context.projectRoot
                    )
                    guard integrity.isVerified else {
                        throw DFTQualificationError.invalidEvidence(
                            "process evidence artifact \(artifact.path) is not verified: \(integrity.issues)"
                        )
                    }
                }
                let processEvidence = try processQualificationEvidenceBuilder.build(
                    buildRequest,
                    at: Date()
                )
                let processEvidenceArtifact = try persist(
                    processEvidence,
                    fileName: "dft-process-qualification-evidence.json",
                    artifactID: "dft-process-qualification-evidence",
                    kind: .release,
                    context: context
                )
                artifacts.append(buildRequestArtifact)
                artifacts.append(contentsOf: buildRequest.evidenceArtifacts)
                artifacts.append(processEvidenceArtifact)
            }

            let resultArtifact = try persist(
                correlation,
                fileName: "dft-qualification-result.json",
                artifactID: "dft-qualification-result",
                kind: .report,
                context: context
            )
            return FlowStageResult(
                stageID: stageID,
                status: .succeeded,
                diagnostics: [],
                gates: [FlowGateResult(gateID: "dft-qualification", status: .passed, diagnostics: [])],
                artifacts: artifacts + [resultArtifact]
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as DFTOracleCorrelationError {
            return support.failure(
                stageID: stageID,
                gateID: "dft-qualification",
                code: "DFT_QUALIFICATION_CORPUS_INVALID",
                message: error.localizedDescription
            )
        } catch let error as DFTOracleArtifactError {
            return support.failure(
                stageID: stageID,
                gateID: "dft-qualification",
                code: "DFT_QUALIFICATION_ORACLE_ARTIFACT_INVALID",
                message: error.localizedDescription
            )
        } catch let error as ToolProcessQualificationEvidenceBuildError {
            return support.blocked(
                stageID: stageID,
                gateID: "dft-qualification",
                code: "DFT_QUALIFICATION_PROCESS_EVIDENCE_INVALID",
                message: error.localizedDescription
            )
        } catch let error as DFTQualificationError {
            return support.blocked(
                stageID: stageID,
                gateID: "dft-qualification",
                code: "DFT_QUALIFICATION_EVIDENCE_INVALID",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: "dft-qualification",
                code: "DFT_QUALIFICATION_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func decode<Value: Decodable>(
        _ url: URL,
        as type: Value.Type
    ) throws -> Value {
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
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: kind,
            format: ArtifactFormat.json
        )
    }

    private func persist<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        kind: ArtifactKind,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        try context.storage.ensureDirectory(at: directory)
        let url = directory.appending(path: fileName)
        try context.storage.writeJSON(value, to: url, forProjectAt: context.projectRoot)
        return try reference(
            for: url,
            artifactID: artifactID,
            kind: kind,
            context: context
        )
    }

    private func persistBlocked(
        correlation: DFTOracleCorrelationResult,
        diagnostics: [FlowDiagnostic],
        artifacts: [ArtifactReference],
        context: FlowExecutionContext
    ) throws -> FlowStageResult {
        let resultArtifact = try persist(
            correlation,
            fileName: "dft-qualification-result.json",
            artifactID: "dft-qualification-result",
            kind: .report,
            context: context
        )
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: "dft-qualification", status: .blocked, diagnostics: diagnostics)],
            artifacts: artifacts + [resultArtifact]
        )
    }
}
