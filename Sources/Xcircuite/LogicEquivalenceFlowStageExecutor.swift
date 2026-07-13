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
            try context.checkCancellation()
            try support.validate(stage: stage, stageID: stageID, toolID: toolID)
            let requestURL = try requestInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
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
                    message: "The requested logic equivalence proof scope is not supported by this adapter."
                )
            }

            if let resumed = try loadResumableResult(
                request: request,
                requestURL: requestURL,
                context: context
            ) {
                return resumed
            }

            let verificationRequest = RTLVerificationRequest(
                runID: request.runID,
                inputs: [
                    try materializedReference(
                        request.sourceDesign.artifact,
                        artifactID: "logic-equivalence-source",
                        context: context
                    ),
                    try materializedReference(
                        request.mappedDesign.artifact,
                        artifactID: "logic-equivalence-mapped",
                        context: context
                    ),
                    request.synthesisProvenance,
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
                    reader: FileSystemRTLArtifactReader(projectRoot: context.projectRoot),
                    writer: FileSystemRTLArtifactStore(projectRoot: context.projectRoot)
                )
                verificationEngine = RTLVerificationEngine(environment: environment)
            }
            let result = try await verificationEngine.execute(verificationRequest)
            try context.checkCancellation()

            let resultArtifact = try support.persistResult(
                result,
                fileName: "logic-equivalence-result.json",
                artifactID: "logic-equivalence-result",
                stageID: stageID,
                context: context
            )
            let evidence = makeEvidence(request: request, result: result)
            try evidence.validate()
            let evidenceArtifact = try persistJSON(
                evidence,
                fileName: "logic-equivalence-evidence.json",
                artifactID: "logic-equivalence-evidence",
                stageID: stageID,
                context: context
            )
            let acceptance = NativeLogicSynthesisAcceptanceEvaluator().evaluate(
                request: request,
                evidence: evidence
            )
            let acceptanceArtifact = try persistJSON(
                acceptance,
                fileName: "logic-synthesis-acceptance.json",
                artifactID: "logic-synthesis-acceptance",
                stageID: stageID,
                context: context
            )
            let review = makeReviewArtifact(
                result: result,
                acceptance: acceptance,
                stageID: stageID
            )
            let reviewArtifact = try persistJSON(
                review,
                fileName: "logic-equivalence-review.json",
                artifactID: "logic-equivalence-review",
                stageID: stageID,
                context: context,
                directoryName: "review"
            )
            let requestArtifact = try artifactBuilder.reference(
                for: requestURL,
                projectRoot: context.projectRoot,
                artifactID: "logic-equivalence-request",
                role: .input,
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
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
                    "logic-equivalence-review",
                    "logic-equivalence-audit",
                ]
            )
            let auditArtifact = try persistJSON(
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
            return support.rtlResult(
                result,
                resultArtifact: resultArtifact,
                stageID: stageID,
                gateID: stageID,
                context: context,
                additionalArtifacts: [
                    requestArtifact,
                    evidenceArtifact,
                    acceptanceArtifact,
                    reviewArtifact,
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
                code: "LOGIC_EQUIVALENCE_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        } catch {
            return support.failure(
                stageID: stageID,
                gateID: stageID,
                code: "LOGIC_EQUIVALENCE_ADAPTER_ERROR",
                message: error.localizedDescription
            )
        }
    }

    private func loadResumableResult(
        request: LogicSynthesisEquivalenceRequest,
        requestURL: URL,
        context: FlowExecutionContext
    ) throws -> FlowStageResult? {
        let rawDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
        let reviewDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "review")
        let auditDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "audit")
        let resultURL = rawDirectory.appending(path: "logic-equivalence-result.json")
        let evidenceURL = rawDirectory.appending(path: "logic-equivalence-evidence.json")
        let acceptanceURL = rawDirectory.appending(path: "logic-synthesis-acceptance.json")
        let reviewURL = reviewDirectory.appending(path: "logic-equivalence-review.json")
        let auditURL = auditDirectory.appending(path: "logic-equivalence-audit.json")
        let requiredURLs = [resultURL, evidenceURL, acceptanceURL, reviewURL, auditURL]
        guard requiredURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        let audit = try context.packageStore.readJSON(
            RTLVerificationStageAuditRecord.self,
            from: auditURL
        )
        let requiredArtifactIDs = [
            "logic-equivalence-result",
            "logic-equivalence-request",
            "logic-equivalence-evidence",
            "logic-synthesis-acceptance",
            "logic-equivalence-review",
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

        let result = try context.packageStore.readJSON(
            RTLVerificationResult.self,
            from: resultURL
        )
        guard result.runID == context.runID,
              result.status == audit.status else {
            return nil
        }
        let evidence = try context.packageStore.readJSON(
            LogicSynthesisEquivalenceEvidence.self,
            from: evidenceURL
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
        let acceptance = try context.packageStore.readJSON(
            LogicSynthesisAcceptanceResult.self,
            from: acceptanceURL
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
        let review = try context.packageStore.readJSON(
            RTLVerificationReviewArtifact.self,
            from: reviewURL
        )
        let expectedReview = makeReviewArtifact(
            result: result,
            acceptance: acceptance,
            stageID: stageID
        )
        guard review.schemaVersion == expectedReview.schemaVersion,
              review.stageID == expectedReview.stageID,
              review.runID == expectedReview.runID,
              review.analysis == expectedReview.analysis,
              review.status == expectedReview.status,
              review.findings == expectedReview.findings,
              review.diagnostics == expectedReview.diagnostics,
              review.appliedWaivers == expectedReview.appliedWaivers,
              review.qualification == expectedReview.qualification,
              review.approvalRequired == expectedReview.approvalRequired,
              review.suggestedActions == expectedReview.suggestedActions else {
            throw LogicExecutionError.invalidArtifact(
                "The persisted logic equivalence review does not match the result envelope."
            )
        }
        guard audit.status == result.status,
              audit.qualificationState == result.payload.qualification.state else {
            throw LogicExecutionError.invalidArtifact(
                "The persisted logic equivalence audit does not match the result envelope."
            )
        }

        let resultArtifact = try artifactBuilder.reference(
            for: resultURL,
            projectRoot: context.projectRoot,
            artifactID: "logic-equivalence-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let requestArtifact = try artifactBuilder.reference(
            for: requestURL,
            projectRoot: context.projectRoot,
            artifactID: "logic-equivalence-request",
            role: .input,
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let evidenceArtifact = try artifactBuilder.reference(
            for: evidenceURL,
            projectRoot: context.projectRoot,
            artifactID: "logic-equivalence-evidence",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let acceptanceArtifact = try artifactBuilder.reference(
            for: acceptanceURL,
            projectRoot: context.projectRoot,
            artifactID: "logic-synthesis-acceptance",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let reviewArtifact = try artifactBuilder.reference(
            for: reviewURL,
            projectRoot: context.projectRoot,
            artifactID: "logic-equivalence-review",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let auditArtifact = try artifactBuilder.reference(
            for: auditURL,
            projectRoot: context.projectRoot,
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
        return support.rtlResult(
            result,
            resultArtifact: resultArtifact,
            stageID: stageID,
            gateID: stageID,
            context: context,
            additionalArtifacts: [
                requestArtifact,
                evidenceArtifact,
                acceptanceArtifact,
                reviewArtifact,
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
                : nil
        )
    }

    private func persistJSON<Value: Encodable>(
        _ value: Value,
        fileName: String,
        artifactID: String,
        stageID: String,
        context: FlowExecutionContext,
        directoryName: String = "raw"
    ) throws -> ArtifactReference {
        let directory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: directoryName)
        try context.packageStore.ensureDirectory(at: directory)
        let url = directory.appending(path: fileName)
        try context.packageStore.writeJSON(value, to: url, forProjectAt: context.projectRoot)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
    }

    private func makeReviewArtifact(
        result: RTLVerificationResult,
        acceptance: LogicSynthesisAcceptanceResult,
        stageID: String
    ) -> RTLVerificationReviewArtifact {
        let findingActions = result.payload.findings.flatMap(\.suggestedActions)
        let resultActions = result.diagnostics.flatMap(\.suggestedActions)
        let acceptanceActions = acceptance.diagnostics.flatMap { diagnostic in
            diagnostic.suggestedActions.map(\.code)
        }
        var actionSet = Set(findingActions)
        actionSet.formUnion(resultActions)
        actionSet.formUnion(acceptanceActions)
        if acceptance.state != .accepted {
            actionSet.insert("inspect_logic_synthesis_acceptance")
        }
        let actions = actionSet.sorted()
        return RTLVerificationReviewArtifact(
            stageID: stageID,
            runID: result.runID,
            analysis: result.payload.analysis,
            status: result.status,
            findings: result.payload.findings,
            diagnostics: result.diagnostics + rtlDiagnostics(acceptance.diagnostics),
            appliedWaivers: result.payload.appliedWaivers,
            qualification: result.payload.qualification,
            approvalRequired: acceptance.state != .accepted || result.status != .completed,
            suggestedActions: actions
        )
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
        let acceptanceAction = "acceptance_state_\(acceptance.state.rawValue)"
        return RTLVerificationStageAuditRecord(
            stageID: stageID,
            runID: result.runID,
            requestDigest: requestDigest,
            status: result.status,
            qualificationState: result.payload.qualification.state,
            artifactIDs: artifactIDs + [acceptanceAction],
            resumable: result.status == .completed || result.status == .blocked,
            nextActions: [acceptanceAction]
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
        let url = try locator.location.resolvedFileURL(relativeTo: context.projectRoot)
        return try artifactBuilder.reference(
            for: url,
            projectRoot: context.projectRoot,
            artifactID: artifactID,
            role: .input,
            kind: ArtifactKind.rtl,
            format: url.pathExtension.lowercased() == "json" ? ArtifactFormat.json : ArtifactFormat.text
        )
    }

    private func rtlDiagnostics(_ diagnostics: [DesignDiagnostic]) -> [RTLDiagnostic] {
        diagnostics.map { diagnostic in
            let severity: RTLDiagnosticSeverity
            switch diagnostic.severity {
            case .information: severity = .info
            case .warning: severity = .warning
            case .error: severity = .error
            }
            return RTLDiagnostic(
                severity: severity,
                code: diagnostic.code.rawValue,
                message: diagnostic.summary,
                suggestedActions: diagnostic.suggestedActions.map(\.code)
            )
        }
    }
}
