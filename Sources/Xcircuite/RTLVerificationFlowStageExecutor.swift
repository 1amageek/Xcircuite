import Foundation
import CircuiteFoundation
import DesignFlowKernel
import LogicIR
import RTLVerificationCore
import RTLVerificationEngine
import TimingCore
import ToolQualification

public struct RTLVerificationFlowStageExecutor: FlowStageExecutor {
    public let stageID: String
    public let toolID: String
    private let analysis: RTLVerificationAnalysis
    private let rtlInput: XcircuiteFlowInputReference
    private let additionalRTLInputs: [XcircuiteFlowInputReference]
    private let referenceInput: XcircuiteFlowInputReference?
    private let additionalReferenceInputs: [XcircuiteFlowInputReference]
    private let constraintsInput: XcircuiteFlowInputReference?
    private let evidenceInput: XcircuiteFlowInputReference?
    private let topModuleName: String
    private let policy: RTLVerificationPolicy
    private let frontend: RTLVerificationFrontendOptions
    private let proofView: RTLVerificationProofView
    private let assumptions: [RTLVerificationAssumption]
    private let engine: (any RTLVerificationExecuting)?
    private let oracleToolID: String?
    private let oracleAdditionalArguments: [String]
    private let oracleTimeoutSeconds: TimeInterval
    private let oracleExecutor: (any RTLVerificationOracleExecuting)?
    private let oracleEvidenceBuilder: (any RTLVerificationOracleEvidenceBuilding)?
    private let artifactBuilder: StageArtifactReferenceBuilder

    public init(
        stageID: String,
        toolID: String = "native-rtl-verification",
        analysis: RTLVerificationAnalysis,
        rtlInput: XcircuiteFlowInputReference,
        additionalRTLInputs: [XcircuiteFlowInputReference] = [],
        referenceInput: XcircuiteFlowInputReference? = nil,
        additionalReferenceInputs: [XcircuiteFlowInputReference] = [],
        constraintsInput: XcircuiteFlowInputReference? = nil,
        evidenceInput: XcircuiteFlowInputReference? = nil,
        topModuleName: String,
        policy: RTLVerificationPolicy = RTLVerificationPolicy(),
        frontend: RTLVerificationFrontendOptions = RTLVerificationFrontendOptions(),
        proofView: RTLVerificationProofView = .rtlToRtlStructural,
        assumptions: [RTLVerificationAssumption] = [],
        engine: (any RTLVerificationExecuting)? = nil,
        oracleToolID: String? = nil,
        oracleAdditionalArguments: [String] = [],
        oracleTimeoutSeconds: TimeInterval = 60,
        oracleExecutor: (any RTLVerificationOracleExecuting)? = nil,
        oracleEvidenceBuilder: (any RTLVerificationOracleEvidenceBuilding)? = nil
    ) {
        self.stageID = stageID
        self.toolID = toolID
        self.analysis = analysis
        self.rtlInput = rtlInput
        self.additionalRTLInputs = additionalRTLInputs
        self.referenceInput = referenceInput
        self.additionalReferenceInputs = additionalReferenceInputs
        self.constraintsInput = constraintsInput
        self.evidenceInput = evidenceInput
        self.topModuleName = topModuleName
        self.policy = policy
        self.frontend = frontend
        self.proofView = proofView
        self.assumptions = assumptions
        self.engine = engine
        self.oracleToolID = oracleToolID
        self.oracleAdditionalArguments = oracleAdditionalArguments
        self.oracleTimeoutSeconds = oracleTimeoutSeconds
        self.oracleExecutor = oracleExecutor
        self.oracleEvidenceBuilder = oracleEvidenceBuilder
        self.artifactBuilder = StageArtifactReferenceBuilder()
    }

    public static func native(
        analysis: RTLVerificationAnalysis,
        rtlInput: XcircuiteFlowInputReference,
        additionalRTLInputs: [XcircuiteFlowInputReference] = [],
        referenceInput: XcircuiteFlowInputReference? = nil,
        additionalReferenceInputs: [XcircuiteFlowInputReference] = [],
        constraintsInput: XcircuiteFlowInputReference? = nil,
        evidenceInput: XcircuiteFlowInputReference? = nil,
        topModuleName: String
    ) -> RTLVerificationFlowStageExecutor {
        RTLVerificationFlowStageExecutor(
            stageID: analysis.stageID,
            analysis: analysis,
            rtlInput: rtlInput,
            additionalRTLInputs: additionalRTLInputs,
            referenceInput: referenceInput,
            additionalReferenceInputs: additionalReferenceInputs,
            constraintsInput: constraintsInput,
            evidenceInput: evidenceInput,
            topModuleName: topModuleName
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try await context.checkCancellation()
            try validate(stage: stage)
            let resolvedRTL = try rtlInput.resolveExisting(
                projectRoot: context.projectRoot,
                runDirectory: context.runDirectory
            )
            let rtlReference = try artifactBuilder.reference(
                for: resolvedRTL,
                projectRoot: context.projectRoot,
                artifactID: "rtl-input",
                role: .input,
                kind: ArtifactKind.rtl,
                format: format(for: resolvedRTL)
            )
            let additionalRTLReferences = try additionalRTLInputs.enumerated().map { index, input in
                let resolvedInput = try input.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                return try artifactBuilder.reference(
                    for: resolvedInput,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-input-\(index + 1)",
                    role: .input,
                    kind: ArtifactKind.rtl,
                    format: format(for: resolvedInput)
                )
            }
            let referenceDesign: LogicDesignReference?
            if let referenceInput {
                let resolvedReference = try referenceInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let reference = try artifactBuilder.reference(
                    for: resolvedReference,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-reference",
                    role: .input,
                    kind: ArtifactKind.rtl,
                    format: format(for: resolvedReference)
                )
                referenceDesign = LogicDesignReference(
                    artifact: reference.locator,
                    topDesignName: topModuleName,
                    designDigest: reference.sha256
                )
            } else {
                referenceDesign = nil
            }
            let additionalReferenceReferences = try additionalReferenceInputs.enumerated().map { index, input in
                let resolvedInput = try input.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                return try artifactBuilder.reference(
                    for: resolvedInput,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-reference-\(index + 1)",
                    role: .input,
                    kind: ArtifactKind.rtl,
                    format: format(for: resolvedInput)
                )
            }
            let constraintReference: RTLConstraintReference?
            let constraintArtifact: ArtifactReference?
            if let constraintsInput {
                let resolvedConstraints = try constraintsInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let artifact = try artifactBuilder.reference(
                    for: resolvedConstraints,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-constraints",
                    role: .input,
                    kind: ArtifactKind.constraint,
                    format: ArtifactFormat.sdc
                )
                constraintArtifact = artifact
                constraintReference = RTLConstraintReference(
                    artifact: artifact,
                    modeIDs: []
                )
            } else {
                constraintReference = nil
                constraintArtifact = nil
            }
            let evidenceInputValue: RTLVerificationEvidenceInput?
            let evidenceArtifact: ArtifactReference?
            if let evidenceInput {
                let resolvedEvidence = try evidenceInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                evidenceArtifact = try artifactBuilder.reference(
                    for: resolvedEvidence,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-evidence-input",
                    role: .input,
                    kind: ArtifactKind.report,
                    format: ArtifactFormat.json
                )
                let loadedEvidence = try loadEvidenceInput(from: resolvedEvidence)
                do {
                    try RTLVerificationEvidenceInputArtifactAuditor().audit(
                        loadedEvidence,
                        reader: FileSystemRTLArtifactReader(projectRoot: context.projectRoot)
                    )
                } catch {
                    return blockedResult(
                        code: "RTL_QUALIFICATION_ARTIFACT_INTEGRITY_FAILED",
                        message: error.localizedDescription
                    )
                }
                evidenceInputValue = loadedEvidence
            } else {
                evidenceInputValue = nil
                evidenceArtifact = nil
            }
            var requestInputs = [rtlReference] + additionalRTLReferences
            if let constraintArtifact {
                requestInputs.append(constraintArtifact)
            }
            if let evidenceArtifact {
                requestInputs.append(evidenceArtifact)
            }
            let request = RTLVerificationRequest(
                runID: context.runID,
                inputs: requestInputs,
                design: LogicDesignReference(
                    artifact: rtlReference.locator,
                    topDesignName: topModuleName,
                    designDigest: rtlReference.sha256
                ),
                referenceDesign: referenceDesign,
                referenceInputs: additionalReferenceReferences,
                constraints: constraintReference,
                analysis: analysis,
                policy: policy,
                frontend: frontend,
                proofView: proofView,
                assumptions: assumptions,
                evidenceInput: evidenceInputValue
            )
            if let blocked = await toolQualificationBlocker(request: request, context: context) {
                return blocked
            }
            if let blocked = await oracleToolQualificationBlocker(request: request, context: context) {
                return blocked
            }
            if let resumable = try await loadResumableResult(request: request, context: context) {
                return stageResult(
                    envelope: resumable.envelope,
                    resultArtifacts: resumable.artifacts
                )
            }
            let verificationEngine: any RTLVerificationExecuting
            if let engine {
                verificationEngine = engine
            } else {
                let environment = RTLVerificationEnvironment(
                    reader: FileSystemRTLArtifactReader(projectRoot: context.projectRoot),
                    writer: FileSystemRTLArtifactStore(projectRoot: context.projectRoot)
                )
                verificationEngine = RTLVerificationEngine(environment: environment)
            }
            let nativeEnvelope = try await verificationEngine.execute(request)
            try await context.checkCancellation()
            let envelope: RTLVerificationResult
            if oracleToolID != nil {
                do {
                    let oracle = try await executeOracle(
                        request: request,
                        native: nativeEnvelope,
                        context: context
                    )
                    let requestDigest = try RTLVerificationRequestDigest.make(request)
                    let builder = oracleEvidenceBuilder ?? RTLVerificationOracleEvidenceBuilder(
                        writer: FileSystemRTLArtifactStore(projectRoot: context.projectRoot)
                    )
                    let evidence = try await builder.build(
                        caseID: analysis.stageID,
                        requestDigest: requestDigest,
                        native: nativeEnvelope,
                        oracle: oracle,
                        oracleProvenance: oracleProvenance(context: context),
                        runID: context.runID
                    )
                    envelope = try makeOracleEnvelope(
                        native: nativeEnvelope,
                        request: request,
                        evidence: evidence
                    )
                } catch {
                    let failedEnvelope = makeOracleFailureEnvelope(
                        native: nativeEnvelope,
                        error: error
                    )
                    let resultArtifacts = try await persistEnvelope(
                        failedEnvelope,
                        request: request,
                        context: context
                    )
                    return stageResult(
                        envelope: failedEnvelope,
                        resultArtifacts: resultArtifacts
                    )
                }
            } else {
                envelope = nativeEnvelope
            }
            let resultArtifacts = try await persistEnvelope(
                envelope,
                request: request,
                context: context
            )
            return stageResult(envelope: envelope, resultArtifacts: resultArtifacts)
        } catch let cancellationError as FlowRunCancellationError {
            throw cancellationError
        } catch {
            return failureResult(code: "RTL_VERIFICATION_EXECUTION_ERROR", message: error.localizedDescription)
        }
    }

    private func validate(stage: FlowStageDefinition) throws {
        guard stage.stageID == stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: stageID, actual: stage.stageID)
        }
        try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        try FlowIdentifierValidator().validate(toolID, kind: .toolID)
        guard stageID == analysis.stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: analysis.stageID, actual: stageID)
        }
    }

    private func toolQualificationBlocker(
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) async -> FlowStageResult? {
        guard toolID != RTLVerificationExecutionSupport.implementationID else {
            return nil
        }
        guard let descriptor = context.toolRegistry.descriptor(toolID: toolID) else {
            return blockedResult(
                code: "RTL_TOOL_DESCRIPTOR_MISSING",
                message: "No ToolQualification descriptor is registered for \(toolID)."
            )
        }
        let decision = await RTLVerificationToolTrustPolicy().evaluate(
            descriptor: descriptor,
            request: request,
            health: context.healthResults[toolID],
            minimumLevel: .productionEligible,
            artifactReader: context.infrastructure,
            evaluatedAt: Date()
        )
        guard decision.status == .eligible else {
            let diagnostics = decision.diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: flowSeverity(for: diagnostic.severity),
                    code: diagnostic.code,
                    message: diagnostic.message
                )
            }
            return blockedResult(
                code: "RTL_TOOL_QUALIFICATION_REJECTED",
                message: "ToolQualification rejected \(toolID) for \(request.analysis.stageID).",
                additionalDiagnostics: diagnostics
            )
        }
        return nil
    }

    private func oracleToolQualificationBlocker(
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) async -> FlowStageResult? {
        guard let oracleToolID else {
            return nil
        }
        if oracleToolID == toolID || oracleToolID == RTLVerificationExecutionSupport.implementationID {
            return blockedResult(
                code: "RTL_ORACLE_TOOL_NOT_INDEPENDENT",
                message: "The RTL oracle must use an implementation independent from the native or execution tool."
            )
        }
        guard let descriptor = context.toolRegistry.descriptor(toolID: oracleToolID) else {
            return blockedResult(
                code: "RTL_ORACLE_TOOL_DESCRIPTOR_MISSING",
                message: "No ToolQualification descriptor is registered for RTL oracle \(oracleToolID)."
            )
        }
        guard descriptor.kind == .rtlVerification else {
            return blockedResult(
                code: "RTL_ORACLE_TOOL_KIND_INVALID",
                message: "RTL oracle \(oracleToolID) must be registered as an RTL verification tool."
            )
        }
        guard let executablePath = descriptor.environment.executablePath,
              !executablePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
            executablePath != "in-process" else {
            return blockedResult(
                code: "RTL_ORACLE_EXECUTABLE_MISSING",
                message: "RTL oracle \(oracleToolID) must declare an executable path."
            )
        }
        let decision = await RTLVerificationToolTrustPolicy().evaluate(
            descriptor: descriptor,
            request: request,
            health: context.healthResults[oracleToolID],
            minimumLevel: .oracleChecked,
            artifactReader: context.infrastructure,
            evaluatedAt: Date()
        )
        guard decision.status == .eligible else {
            let diagnostics = decision.diagnostics.map { diagnostic in
                FlowDiagnostic(
                    severity: flowSeverity(for: diagnostic.severity),
                    code: diagnostic.code,
                    message: diagnostic.message
                )
            }
            return blockedResult(
                code: "RTL_ORACLE_TOOL_QUALIFICATION_REJECTED",
                message: "ToolQualification rejected RTL oracle \(oracleToolID) for \(request.analysis.stageID).",
                additionalDiagnostics: diagnostics
            )
        }
        return nil
    }

    private func executeOracle(
        request: RTLVerificationRequest,
        native: RTLVerificationResult,
        context: FlowExecutionContext
    ) async throws -> RTLVerificationResult {
        if let oracleExecutor {
            return try await oracleExecutor.execute(request, native: native)
        }
        guard let oracleToolID,
              let descriptor = context.toolRegistry.descriptor(toolID: oracleToolID),
              let executablePath = descriptor.environment.executablePath else {
            throw RTLVerificationExecutionError.invalidRequest(
                "An RTL oracle tool descriptor is required when oracle execution is enabled."
            )
        }
        let resolvedExecutablePath = try XcircuiteFlowRuntimeSpec.resolvePath(
            executablePath,
            projectRoot: context.projectRoot
        ).path(percentEncoded: false)
        let externalDescriptor = RTLExternalToolDescriptor(
            toolID: descriptor.toolID,
            executablePath: resolvedExecutablePath,
            version: descriptor.version,
            supportedAnalyses: [request.analysis],
            supportedProofViews: [request.proofView],
            limitations: descriptor.trustProfile.knownLimitations,
            timeoutSeconds: oracleTimeoutSeconds
        )
        let trustDecision = await RTLVerificationToolTrustPolicy().evaluate(
            descriptor: descriptor,
            request: request,
            health: context.healthResults[oracleToolID],
            minimumLevel: .oracleChecked,
            artifactReader: context.infrastructure
        )
        let executor = ExternalRTLVerificationOracleExecutor(
            descriptor: externalDescriptor,
            trustDecision: trustDecision,
            additionalArguments: oracleAdditionalArguments
        )
        return try await executor.execute(request, native: native)
    }

    private func oracleProvenance(context: FlowExecutionContext) -> String {
        guard let oracleToolID,
              let descriptor = context.toolRegistry.descriptor(toolID: oracleToolID) else {
            return "unregistered-rtl-oracle"
        }
        return "tool:\(descriptor.toolID)@\(descriptor.version)"
    }

    private func makeOracleEnvelope(
        native: RTLVerificationResult,
        request: RTLVerificationRequest,
        evidence: RTLVerificationOracleEvidenceBuildResult
    ) throws -> RTLVerificationResult {
        var evidenceInput = request.evidenceInput ?? RTLVerificationEvidenceInput()
        if !evidenceInput.oracleReports.contains(evidence.evidence.report) {
            evidenceInput.oracleReports.append(evidence.evidence.report)
        }
        if !evidenceInput.oracleEvidence.contains(evidence.evidence) {
            evidenceInput.oracleEvidence.append(evidence.evidence)
        }
        let requestDigest = try RTLVerificationRequestDigest.make(request)
        let assessment = RTLVerificationEvidenceEvaluator().evaluate(
            implementationID: native.payload.record.implementationID,
            implementationVersion: native.payload.record.implementationVersion,
            corpusEvaluations: evidenceInput.corpusEvaluations,
            oracleReports: evidenceInput.oracleReports,
            oracleEvidence: evidenceInput.oracleEvidence,
            expectedRequestDigest: requestDigest,
            checkedAt: Date()
        )
        var payload = native.payload
        payload.record = assessment
        var diagnostics = native.diagnostics
        let correlationPassed = evidence.evidence.report.matched
            && evidence.evidence.report.independenceVerified
        if !correlationPassed {
            diagnostics.append(RTLDiagnostic(
                severity: .error,
                code: "RTL_ORACLE_CORRELATION_FAILED",
                message: "The independent RTL oracle did not match the native verification result.",
                suggestedActions: ["inspect_oracle_evidence", "fix_backend_divergence", "rerun_qualified_oracle"]
            ))
        }
        let status = correlationPassed
            ? RTLVerificationExecutionSupport.status(
                requested: native.status,
                findings: payload.findings,
                coverage: payload.coverage,
                policy: request.policy,
                proofStatus: payload.proofStatus,
                assessment: assessment
            )
            : .blocked
        return RTLVerificationResult(
            schemaVersion: native.schemaVersion,
            runID: native.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: uniqueArtifactReferences(
                native.artifacts + [
                    evidence.nativeArtifact,
                    evidence.oracleArtifact,
                    evidence.evidenceArtifact,
                ]
            ),
            provenance: native.provenance,
            payload: payload
        )
    }

    private func makeOracleFailureEnvelope(
        native: RTLVerificationResult,
        error: Error
    ) -> RTLVerificationResult {
        var diagnostics = native.diagnostics
        diagnostics.append(RTLDiagnostic(
            severity: .error,
            code: "RTL_ORACLE_CORRELATION_EXECUTION_FAILED",
            message: error.localizedDescription,
            suggestedActions: ["inspect_external_tool_log", "verify_oracle_artifacts", "retry_run"]
        ))
        return RTLVerificationResult(
            schemaVersion: native.schemaVersion,
            runID: native.runID,
            status: .blocked,
            diagnostics: diagnostics,
            artifacts: native.artifacts,
            provenance: native.provenance,
            payload: native.payload
        )
    }

    private func uniqueArtifactReferences(
        _ references: [ArtifactReference]
    ) -> [ArtifactReference] {
        var keys: Set<ArtifactReference> = []
        var unique: [ArtifactReference] = []
        unique.reserveCapacity(references.count)
        for reference in references {
            if keys.insert(reference).inserted {
                unique.append(reference)
            }
        }
        return unique
    }

    private func blockedResult(
        code: String,
        message: String,
        additionalDiagnostics: [FlowDiagnostic] = []
    ) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        let diagnostics = [diagnostic] + additionalDiagnostics
        return FlowStageResult(
            stageID: stageID,
            status: .blocked,
            diagnostics: diagnostics,
            gates: [FlowGateResult(gateID: stageID, status: .blocked, diagnostics: diagnostics)]
        )
    }

    private func flowSeverity(for severity: ToolDiagnosticSeverity) -> FlowDiagnosticSeverity {
        switch severity {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }

    private func persistEnvelope(
        _ envelope: RTLVerificationResult,
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) async throws -> [ArtifactReference] {
        let resultReference = try await context.persistJSONArtifact(
            envelope,
            artifactID: "rtl-verification-result",
            stageID: stageID,
            fileName: "rtl-verification-result.json",
            kind: ArtifactKind.report,
            mode: .replaceable
        )
        let assessmentReference = try await context.persistJSONArtifact(
            envelope.payload.record,
            artifactID: "rtl-verification-evidence-assessment",
            stageID: stageID,
            fileName: "evidence-assessment.json",
            kind: ArtifactKind.report,
            mode: .replaceable
        )
        let reviewArtifact = makeReviewArtifact(envelope)
        let reviewReference = try await context.persistJSONArtifact(
            reviewArtifact,
            artifactID: "rtl-verification-review",
            stageID: stageID,
            directory: "review",
            fileName: "rtl-verification-review.json",
            kind: ArtifactKind.report,
            mode: .replaceable
        )
        let requestDigest = try digest(for: request)
        let auditArtifactIDs = envelope.artifacts.map(\.artifactID)
            + [
                "rtl-verification-result",
                "rtl-verification-evidence-assessment",
                "rtl-verification-review",
                "rtl-verification-audit"
            ]
        let auditRecord = RTLVerificationStageAuditRecord(
            stageID: stageID,
            runID: context.runID,
            requestDigest: requestDigest,
            status: envelope.status,
            evidenceMaturity: envelope.payload.record.maturity,
            artifactIDs: auditArtifactIDs,
            resumable: envelope.status == .completed || envelope.status == .blocked,
            nextActions: reviewArtifact.suggestedActions
        )
        let auditReference = try await context.persistJSONArtifact(
            auditRecord,
            artifactID: "rtl-verification-audit",
            stageID: stageID,
            directory: "audit",
            fileName: "rtl-verification-audit.json",
            kind: ArtifactKind.report,
            mode: .replaceable
        )
        return [resultReference, assessmentReference, reviewReference, auditReference]
    }

    private func loadEvidenceInput(from url: URL) throws -> RTLVerificationEvidenceInput {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RTLVerificationExecutionError.invalidArtifact(
                "Could not read RTL evidence input \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(RTLVerificationEvidenceInput.self, from: data)
        } catch {
            throw RTLVerificationExecutionError.invalidArtifact(
                "Could not decode RTL evidence input \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
    }

    private func loadResumableResult(
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) async throws -> (envelope: RTLVerificationResult, artifacts: [ArtifactReference])? {
        let definitions = try persistedArtifactDefinitions(context: context)
        var contents: [String: Data] = [:]
        for definition in definitions {
            guard let data = try await context.infrastructure.loadArtifactContent(at: definition.locator) else {
                return nil
            }
            contents[definition.artifactID] = data
        }
        guard let auditData = contents["rtl-verification-audit"],
              let resultData = contents["rtl-verification-result"],
              let assessmentData = contents["rtl-verification-evidence-assessment"],
              let reviewData = contents["rtl-verification-review"] else {
            return nil
        }
        let audit = try JSONDecoder().decode(RTLVerificationStageAuditRecord.self, from: auditData)
        guard audit.stageID == stageID,
              audit.runID == context.runID,
              audit.resumable,
              audit.status == .completed || audit.status == .blocked,
              audit.artifactIDs.contains("rtl-verification-result"),
              audit.artifactIDs.contains("rtl-verification-evidence-assessment"),
              audit.artifactIDs.contains("rtl-verification-review"),
              audit.artifactIDs.contains("rtl-verification-audit"),
              audit.requestDigest == (try digest(for: request)) else {
            return nil
        }
        let envelope = try JSONDecoder().decode(RTLVerificationResult.self, from: resultData)
        guard envelope.runID == context.runID, envelope.status == audit.status else {
            return nil
        }
        if oracleToolID != nil,
           !envelope.artifacts.contains(where: { reference in
               reference.artifactID.hasSuffix("-evidence")
                   && reference.artifactID.hasPrefix("oracle-")
           }) {
            return nil
        }
        let assessment = try JSONDecoder().decode(RTLVerificationEvidenceAssessment.self, from: assessmentData)
        guard assessment == envelope.payload.record,
              audit.evidenceMaturity == envelope.payload.record.maturity else {
            throw RTLVerificationExecutionError.invalidArtifact(
                "The persisted RTL evidence assessment does not match the result envelope."
            )
        }
        let review = try JSONDecoder().decode(RTLVerificationReviewArtifact.self, from: reviewData)
        guard review.stageID == stageID,
              review.runID == context.runID,
              review.analysis == envelope.payload.analysis,
              review.status == envelope.status,
              review.findings == envelope.payload.findings,
              review.diagnostics == envelope.diagnostics,
              review.appliedWaivers == envelope.payload.appliedWaivers,
              review.record == envelope.payload.record else {
            throw RTLVerificationExecutionError.invalidArtifact(
                "The persisted RTL review artifact does not match the result envelope."
            )
        }
        return (
            envelope: envelope,
            artifacts: try definitions.compactMap { definition in
                guard let data = contents[definition.artifactID] else { return nil }
                return try artifactReference(definition: definition, content: data)
            }
        )
    }

    private struct PersistedArtifactDefinition {
        var artifactID: String
        var locator: ArtifactLocator
    }

    private func persistedArtifactDefinitions(
        context: FlowExecutionContext
    ) throws -> [PersistedArtifactDefinition] {
        let definitions: [(String, String, String)] = [
            ("raw", "rtl-verification-result.json", "rtl-verification-result"),
            ("raw", "evidence-assessment.json", "rtl-verification-evidence-assessment"),
            ("review", "rtl-verification-review.json", "rtl-verification-review"),
            ("audit", "rtl-verification-audit.json", "rtl-verification-audit")
        ]
        return try definitions.map { directory, fileName, artifactID in
            PersistedArtifactDefinition(
                artifactID: artifactID,
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath: ".xcircuite/runs/\(context.runID)/stages/\(stageID)/\(directory)/\(fileName)"
                    ),
                    role: .output,
                    kind: ArtifactKind.report,
                    format: ArtifactFormat.json
                )
            )
        }
    }

    private func artifactReference(
        definition: PersistedArtifactDefinition,
        content: Data
    ) throws -> ArtifactReference {
        ArtifactReference(
            id: try ArtifactID(rawValue: definition.artifactID),
            locator: definition.locator,
            digest: try SHA256ContentDigester().digest(data: content),
            byteCount: UInt64(content.count)
        )
    }

    private func makeReviewArtifact(
        _ envelope: RTLVerificationResult
    ) -> RTLVerificationReviewArtifact {
        let findingActions = envelope.payload.findings.flatMap(\.suggestedActions)
        let diagnosticActions = envelope.diagnostics.flatMap(\.suggestedActions)
        let suggestedActions = Array(Set(findingActions + diagnosticActions)).sorted()
        let approvalRequired = envelope.status != .completed
            || !envelope.payload.findings.isEmpty
            || !envelope.payload.record.limitations.isEmpty
        return RTLVerificationReviewArtifact(
            stageID: stageID,
            runID: envelope.runID,
            analysis: envelope.payload.analysis,
            status: envelope.status,
            findings: envelope.payload.findings,
            diagnostics: envelope.diagnostics,
            appliedWaivers: envelope.payload.appliedWaivers,
            record: envelope.payload.record,
            approvalRequired: approvalRequired,
            suggestedActions: suggestedActions
        )
    }

    private func digest(for request: RTLVerificationRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try SHA256ContentDigester()
            .digest(data: try encoder.encode(request))
            .hexadecimalValue
    }

    private func stageResult(
        envelope: RTLVerificationResult,
        resultArtifacts: [ArtifactReference]
    ) -> FlowStageResult {
        let diagnostics = envelope.diagnostics.map(flowDiagnostic)
        let gate = FlowGateResult(
            gateID: stageID,
            status: gateStatus(for: envelope.status),
            diagnostics: diagnostics
        )
        let stageStatus: FlowStageStatus
        switch envelope.status {
        case .completed: stageStatus = .succeeded
        case .blocked: stageStatus = .blocked
        case .failed, .cancelled: stageStatus = .failed
        }
        return FlowStageResult(
            stageID: stageID,
            status: stageStatus,
            diagnostics: diagnostics,
            gates: [gate],
            artifacts: envelope.artifacts + resultArtifacts
        )
    }

    private func failureResult(code: String, message: String) -> FlowStageResult {
        let diagnostic = FlowDiagnostic(severity: .error, code: code, message: message)
        return FlowStageResult(
            stageID: stageID,
            status: .failed,
            diagnostics: [diagnostic],
            gates: [FlowGateResult(gateID: stageID, status: .failed, diagnostics: [diagnostic])]
        )
    }

    private func flowDiagnostic(_ diagnostic: RTLDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .info: severity = .info
        case .warning: severity = .warning
        case .error: severity = .error
        }
        return FlowDiagnostic(severity: severity, code: diagnostic.code, message: diagnostic.message)
    }

    private func gateStatus(for status: RTLExecutionStatus) -> FlowGateStatus {
        switch status {
        case .completed: return .passed
        case .failed: return .failed
        case .blocked: return .blocked
        case .cancelled: return .incomplete
        }
    }

    private func format(for url: URL) -> ArtifactFormat {
        switch url.pathExtension.lowercased() {
        case "sv", "svh": return .systemVerilog
        case "v", "vh": return .verilog
        case "sdc": return .sdc
        case "json": return .json
        default: return .text
        }
    }
}
