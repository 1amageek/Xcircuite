import CircuiteFoundation
import DesignFlowKernel
import Foundation
import LogicEngineCore
import LogicSynthesis
import RTLVerificationCore
import RTLVerificationEngine

public struct LogicEquivalenceFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let requestInput: XcircuiteFlowInputReference
    private let injectedEngine: (any RTLVerificationExecuting)?
    private let support: LogicEngineStageExecutionSupport
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String = "logic.equivalence",
        toolID: String = "native-rtl-verification",
        requestInput: XcircuiteFlowInputReference,
        engine: (any RTLVerificationExecuting)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.requestInput = requestInput
        self.injectedEngine = engine
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
            let requestURL = try await requestInput.resolveExisting(
                projectRoot: try context.xcircuiteProjectRoot(),
                runDirectory: try context.xcircuiteRunDirectory(),
                infrastructure: context.infrastructure
            )
            let request = try JSONDecoder().decode(
                LogicSynthesisEquivalenceRequest.self,
                from: Data(contentsOf: requestURL)
            )
            try request.validate()
            guard request.runID == context.runID else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_EQUIVALENCE_RUN_ID_MISMATCH",
                    message: "Logic equivalence request run ID does not match the flow run."
                )
            }
            guard let proofView = proofView(for: request.proofScope) else {
                return support.blocked(
                    stageID: stageID,
                    gateID: stageID,
                    code: "LOGIC_EQUIVALENCE_PROOF_SCOPE_UNSUPPORTED",
                    message: "The requested logic equivalence proof scope is not supported by this engine."
                )
            }
            let requestArtifact = try await context.persistJSONArtifact(
                request,
                artifactID: "logic-equivalence-request",
                stageID: stageID,
                fileName: "logic-equivalence-request.json",
                role: .input,
                kind: .request,
                mode: .immutable
            )

            if let resumed = try loadResumableResult(
                request: request,
                requestArtifact: requestArtifact,
                context: context
            ) {
                return resumed
            }

            let verificationRequest = RTLVerificationRequest(
                runID: request.runID,
                inputs: [
                    request.sourceDesign.artifact,
                    request.mappedDesign.artifact,
                    request.synthesisProvenance,
                    request.pdkArtifact,
                ],
                design: request.sourceDesign,
                referenceDesign: request.mappedDesign,
                analysis: .formalEquivalence,
                policy: RTLVerificationPolicy(requiredProof: true),
                proofView: proofView
            )
            let verificationEngine: any RTLVerificationExecuting
            if let injectedEngine {
                verificationEngine = injectedEngine
            } else {
                let environment = RTLVerificationEnvironment(
                    reader: FileSystemRTLArtifactReader(projectRoot: try context.xcircuiteProjectRoot()),
                    writer: try FileSystemRTLArtifactStore(
                        artifactRoot: context.xcircuiteProjectRoot(),
                        namespace: RTLArtifactNamespace(validating: ".xcircuite/runs")
                    )
                )
                verificationEngine = RTLVerificationEngine(environment: environment)
            }
            let result = try await verificationEngine.execute(verificationRequest)
            try await context.checkCancellation()

            let resultArtifact = try await support.persistResult(
                result,
                fileName: "logic-equivalence-result.json",
                artifactID: "logic-equivalence-result",
                stageID: stageID,
                context: context,
                producer: result.provenance.producer,
                mode: .replaceable
            )
            let evidence = makeEvidence(request: request, result: result)
            try evidence.validate()
            let evidenceArtifact = try await persistJSON(
                evidence,
                fileName: "logic-equivalence-evidence.json",
                artifactID: "logic-equivalence-evidence",
                stageID: stageID,
                context: context,
                producer: evidence.provenance.producer,
                mode: .replaceable
            )
            let acceptance = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
                request: request,
                evidence: evidence
            )
            let acceptanceArtifact = try await persistJSON(
                acceptance,
                fileName: "logic-synthesis-acceptance.json",
                artifactID: "logic-synthesis-acceptance",
                stageID: stageID,
                context: context
            )
            let accepted = acceptance.state == .accepted
            let audit = try makeAuditRecord(
                request: request,
                result: result,
                acceptance: acceptance,
                artifactIDs: [
                    "logic-equivalence-result",
                    "logic-equivalence-request",
                    "logic-equivalence-evidence",
                    "logic-synthesis-acceptance",
                    "logic-equivalence-audit",
                ]
            )
            let auditArtifact = try await persistJSON(
                audit,
                fileName: "logic-equivalence-audit.json",
                artifactID: "logic-equivalence-audit",
                stageID: stageID,
                context: context,
                directoryName: "audit"
            )
            let stageStatus: FlowStageStatus
            let gateStatus: FlowGateStatus
            if accepted {
                stageStatus = .succeeded
                gateStatus = .passed
            } else if result.status == .failed {
                stageStatus = .failed
                gateStatus = .failed
            } else {
                stageStatus = .blocked
                gateStatus = .blocked
            }
            return try support.rtlResult(
                result,
                resultArtifact: resultArtifact,
                stageID: stageID,
                gateID: stageID,
                context: context,
                additionalArtifacts: [
                    requestArtifact,
                    evidenceArtifact,
                    acceptanceArtifact,
                    auditArtifact,
                ],
                additionalDiagnostics: acceptance.diagnostics,
                stageStatusOverride: stageStatus,
                gateStatusOverride: gateStatus
            )
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch let error as LogicExecutionError {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_EQUIVALENCE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_EQUIVALENCE_EXECUTION_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func loadResumableResult(
        request: LogicSynthesisEquivalenceRequest,
        requestArtifact: ArtifactReference,
        context: FlowExecutionContext
    ) throws -> FlowStageResult? {
        let rawDirectory = try context.xcircuiteRunDirectory()
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        let auditDirectory = try context.xcircuiteRunDirectory()
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "audit")
        let resultURL = rawDirectory.appending(path: "logic-equivalence-result.json")
        let evidenceURL = rawDirectory.appending(path: "logic-equivalence-evidence.json")
        let acceptanceURL = rawDirectory.appending(path: "logic-synthesis-acceptance.json")
        let auditURL = auditDirectory.appending(path: "logic-equivalence-audit.json")
        let requiredURLs = [resultURL, evidenceURL, acceptanceURL, auditURL]
        guard requiredURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let audit = try JSONDecoder().decode(
            RTLVerificationStageAuditRecord.self,
            from: Data(contentsOf: auditURL)
        )
        let requiredArtifactIDs = [
            "logic-equivalence-result",
            "logic-equivalence-request",
            "logic-equivalence-evidence",
            "logic-synthesis-acceptance",
            "logic-equivalence-audit",
        ]
        guard audit.stageID == stageID,
              audit.runID == context.runID,
              audit.resumable,
              audit.status == .completed || audit.status == .blocked,
              requiredArtifactIDs.allSatisfy({ audit.artifactIDs.contains($0) }),
              audit.requestDigest == (try digest(for: request)) else {
            return nil
        }

        let result = try JSONDecoder().decode(
            RTLVerificationResult.self,
            from: Data(contentsOf: resultURL)
        )
        guard result.runID == context.runID,
              result.status == audit.status else {
            return nil
        }
        let evidence = try JSONDecoder().decode(
            LogicSynthesisEquivalenceEvidence.self,
            from: Data(contentsOf: evidenceURL)
        )
        try evidence.validate()
        guard evidence.runID == request.runID,
              evidence.sourceDesignDigest == request.sourceDesign.designDigest,
              evidence.mappedDesignDigest == request.mappedDesign.designDigest,
              evidence.proofScope == request.proofScope else {
            throw LogicExecutionError.invalidArtifact(
                "The persisted logic equivalence evidence does not match the request."
            )
        }
        let acceptance = try JSONDecoder().decode(
            LogicSynthesisAcceptanceResult.self,
            from: Data(contentsOf: acceptanceURL)
        )
        let expectedAcceptance = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
            request: request,
            evidence: evidence
        )
        guard acceptance == expectedAcceptance else {
            throw LogicExecutionError.invalidArtifact(
                "The persisted synthesis acceptance does not match the equivalence evidence."
            )
        }
        guard audit.status == result.status,
              audit.evidenceMaturity == result.payload.record.maturity else {
            throw LogicExecutionError.invalidArtifact(
                "The persisted logic equivalence audit does not match the result envelope."
            )
        }

        let resultArtifact = try artifactBuilder.reference(
            for: resultURL,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "logic-equivalence-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json,
            producer: result.provenance.producer
        )
        let evidenceArtifact = try artifactBuilder.reference(
            for: evidenceURL,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "logic-equivalence-evidence",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json,
            producer: evidence.provenance.producer
        )
        let acceptanceArtifact = try artifactBuilder.reference(
            for: acceptanceURL,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "logic-synthesis-acceptance",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let auditArtifact = try artifactBuilder.reference(
            for: auditURL,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: "logic-equivalence-audit",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let accepted = acceptance.state == .accepted
        let stageStatus: FlowStageStatus
        let gateStatus: FlowGateStatus
        if accepted {
            stageStatus = .succeeded
            gateStatus = .passed
        } else if result.status == .failed {
            stageStatus = .failed
            gateStatus = .failed
        } else {
            stageStatus = .blocked
            gateStatus = .blocked
        }
        return try support.rtlResult(
            result,
            resultArtifact: resultArtifact,
            stageID: stageID,
            gateID: stageID,
            context: context,
            additionalArtifacts: [
                requestArtifact,
                evidenceArtifact,
                acceptanceArtifact,
                auditArtifact,
            ],
            additionalDiagnostics: acceptance.diagnostics,
            stageStatusOverride: stageStatus,
            gateStatusOverride: gateStatus
        )
    }

    private func proofView(for scope: String) -> RTLVerificationProofView? {
        switch scope {
        case "rtl-to-mapped-structural":
            return .rtlToMappedExecutionStructural
        default:
            return nil
        }
    }

    private func makeEvidence(
        request: LogicSynthesisEquivalenceRequest,
        result: RTLVerificationResult
    ) -> LogicSynthesisEquivalenceEvidence {
        let isProved = result.status == .completed && result.payload.proofStatus == "proved"
        let status: LogicEquivalenceEvidenceStatus
        if isProved {
            status = .proved
        } else if result.payload.proofStatus == "unproven" {
            status = .unproven
        } else {
            status = .blocked
        }
        return LogicSynthesisEquivalenceEvidence(
            runID: request.runID,
            sourceDesignDigest: request.sourceDesign.designDigest,
            mappedDesignDigest: request.mappedDesign.designDigest,
            proofScope: request.proofScope,
            status: status,
            proofArtifact: isProved
                ? result.artifacts.first(where: { $0.artifactID == "rtl-verification-report" })
                : nil,
            provenance: result.provenance
        )
    }

    private func persistJSON<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        stageID: String,
        context: FlowExecutionContext,
        producer: ProducerIdentity? = nil,
        mode: FlowArtifactPersistenceMode = .replaceable,
        directoryName: String = "raw"
    ) async throws -> ArtifactReference {
        try await context.persistJSONArtifact(
            value,
            artifactID: artifactID,
            stageID: stageID,
            directory: directoryName,
            fileName: fileName,
            producer: producer,
            mode: mode
        )
    }

    private func suggestedActions(
        result: RTLVerificationResult,
        acceptance: LogicSynthesisAcceptanceResult
    ) -> [String] {
        let findingActions = result.payload.findings.flatMap(\.suggestedActions)
        let resultActions = result.rtlDiagnostics.flatMap(\.suggestedActions)
        let acceptanceActions = acceptance.diagnostics.flatMap { diagnostic in
            diagnostic.suggestedActions.map(\.code)
        }
        var actionSet = Set(findingActions)
        actionSet.formUnion(resultActions)
        actionSet.formUnion(acceptanceActions)
        if acceptance.state != .accepted {
            actionSet.insert("inspect_logic_synthesis_acceptance")
        }
        return actionSet.sorted()
    }

    private func makeAuditRecord(
        request: LogicSynthesisEquivalenceRequest,
        result: RTLVerificationResult,
        acceptance: LogicSynthesisAcceptanceResult,
        artifactIDs: [String]
    ) throws -> RTLVerificationStageAuditRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestDigest = try SHA256ContentDigester()
            .digest(data: try encoder.encode(request))
            .hexadecimalValue
        return RTLVerificationStageAuditRecord(
            stageID: stageID,
            runID: result.runID,
            requestDigest: requestDigest,
            status: result.status,
            evidenceMaturity: result.payload.record.maturity,
            artifactIDs: artifactIDs,
            resumable: result.status == .completed || result.status == .blocked,
            nextActions: suggestedActions(result: result, acceptance: acceptance)
        )
    }

    private func digest(for request: LogicSynthesisEquivalenceRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try SHA256ContentDigester()
            .digest(data: try encoder.encode(request))
            .hexadecimalValue
    }

    private func materializedReference(
        _ locator: ArtifactLocator,
        artifactID: String,
        context: FlowExecutionContext
    ) throws -> ArtifactReference {
        let url = try locator.location.resolvedFileURL(relativeTo: try context.xcircuiteProjectRoot())
        return try artifactBuilder.reference(
            for: url,
            projectRoot: try context.xcircuiteProjectRoot(),
            artifactID: artifactID,
            role: .input,
            kind: ArtifactKind.rtl,
            format: url.pathExtension.lowercased() == "json" ? ArtifactFormat.json : ArtifactFormat.text
        )
    }
}
