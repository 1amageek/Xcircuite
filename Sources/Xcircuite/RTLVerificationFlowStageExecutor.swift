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
    private let qualificationInput: XcircuiteFlowInputReference?
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
        qualificationInput: XcircuiteFlowInputReference? = nil,
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
        self.qualificationInput = qualificationInput
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
        qualificationInput: XcircuiteFlowInputReference? = nil,
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
            qualificationInput: qualificationInput,
            topModuleName: topModuleName
        )
    }

    public func execute(
        stage: FlowStageDefinition,
        context: FlowExecutionContext
    ) async throws -> FlowStageResult {
        do {
            try context.checkCancellation()
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
            let qualificationInputValue: RTLVerificationQualificationInput?
            let qualificationArtifact: ArtifactReference?
            if let qualificationInput {
                let resolvedQualification = try qualificationInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                qualificationArtifact = try artifactBuilder.reference(
                    for: resolvedQualification,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-qualification-input",
                    role: .input,
                    kind: ArtifactKind.report,
                    format: ArtifactFormat.json
                )
                let loadedQualification = try loadQualificationInput(from: resolvedQualification)
                do {
                    try RTLVerificationQualificationInputArtifactAuditor().audit(
                        loadedQualification,
                        reader: FileSystemRTLArtifactReader(projectRoot: context.projectRoot)
                    )
                } catch {
                    return blockedResult(
                        code: "RTL_QUALIFICATION_ARTIFACT_INTEGRITY_FAILED",
                        message: error.localizedDescription
                    )
                }
                qualificationInputValue = loadedQualification
            } else {
                qualificationInputValue = nil
                qualificationArtifact = nil
            }
            var requestInputs = [rtlReference] + additionalRTLReferences
            if let constraintArtifact {
                requestInputs.append(constraintArtifact)
            }
            if let qualificationArtifact {
                requestInputs.append(qualificationArtifact)
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
                qualificationInput: qualificationInputValue
            )
            if let blocked = toolQualificationBlocker(request: request, context: context) {
                return blocked
            }
            if let blocked = oracleToolQualificationBlocker(request: request, context: context) {
                return blocked
            }
            if let resumable = try loadResumableResult(request: request, context: context) {
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
            try context.checkCancellation()
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
                    let resultArtifacts = try persistEnvelope(
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
            let resultArtifacts = try persistEnvelope(
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
        try XcircuiteIdentifierValidator().validate(stageID, kind: .stageID)
        try XcircuiteIdentifierValidator().validate(toolID, kind: .toolID)
        guard stageID == analysis.stageID else {
            throw XcircuiteRuntimeError.stageMismatch(expected: analysis.stageID, actual: stageID)
        }
    }

    private func toolQualificationBlocker(
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) -> FlowStageResult? {
        guard toolID != RTLVerificationExecutionSupport.implementationID else {
            return nil
        }
        guard let descriptor = context.toolRegistry.descriptor(toolID: toolID) else {
            return blockedResult(
                code: "RTL_TOOL_DESCRIPTOR_MISSING",
                message: "No ToolQualification descriptor is registered for \(toolID)."
            )
        }
        let minimumLevel: ToolQualificationLevel
        switch request.policy.minimumQualification {
        case .unassessed:
            minimumLevel = .unknown
        case .smokeChecked:
            minimumLevel = .smokeChecked
        case .corpusChecked:
            minimumLevel = .corpusChecked
        case .oracleCorrelated:
            minimumLevel = .oracleChecked
        case .processQualified, .releaseEligible:
            minimumLevel = .productionEligible
        }
        let decision = RTLVerificationToolQualificationAdapter().evaluate(
            descriptor: descriptor,
            request: request,
            health: context.healthResults[toolID],
            minimumLevel: minimumLevel,
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
    ) -> FlowStageResult? {
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
        let decision = RTLVerificationToolQualificationAdapter().evaluate(
            descriptor: descriptor,
            request: request,
            health: context.healthResults[oracleToolID],
            minimumLevel: .oracleChecked,
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
            qualified: true,
            qualification: oracleQualification(for: descriptor),
            limitations: descriptor.trustProfile.knownLimitations,
            timeoutSeconds: oracleTimeoutSeconds
        )
        let executor = ExternalRTLVerificationOracleExecutor(
            descriptor: externalDescriptor,
            additionalArguments: oracleAdditionalArguments
        )
        return try await executor.execute(request, native: native)
    }

    private func oracleQualification(for descriptor: ToolDescriptor) -> RTLVerificationQualificationReport {
        let evidence = descriptor.trustProfile.evidence.map { item in
            RTLVerificationQualificationEvidence(
                evidenceID: "toolqualification:\(item.evidenceID)",
                kind: qualificationEvidenceKind(for: item.kind),
                artifactIDs: item.artifact.map { [$0.artifactID].compactMap { $0 } } ?? [],
                summary: "ToolQualification evidence \(item.evidenceID) admitted the independent RTL oracle.",
                checkedAt: item.checkedAt ?? Date()
            )
        }
        return RTLVerificationQualificationReport(
            implementationID: descriptor.toolID,
            implementationVersion: descriptor.version,
            state: .oracleCorrelated,
            evidence: evidence,
            blockers: [],
            limitations: descriptor.trustProfile.knownLimitations
        )
    }

    private func qualificationEvidenceKind(
        for kind: ToolEvidenceKind
    ) -> RTLVerificationQualificationEvidenceKind {
        switch kind {
        case .smoke:
            return .smoke
        case .corpus:
            return .corpus
        case .oracle:
            return .oracleCorrelation
        case .healthCheck:
            return .healthCheck
        case .productionApproval:
            return .releaseApproval
        }
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
        var qualificationInput = request.qualificationInput ?? RTLVerificationQualificationInput()
        if !qualificationInput.oracleReports.contains(evidence.evidence.report) {
            qualificationInput.oracleReports.append(evidence.evidence.report)
        }
        if !qualificationInput.oracleEvidence.contains(evidence.evidence) {
            qualificationInput.oracleEvidence.append(evidence.evidence)
        }
        let requestDigest = try RTLVerificationRequestDigest.make(request)
        let qualification = RTLVerificationQualificationEvaluator().evaluate(
            implementationID: native.payload.qualification.implementationID,
            implementationVersion: native.payload.qualification.implementationVersion,
            healthEvidence: qualificationInput.healthEvidence,
            corpusEvaluations: qualificationInput.corpusEvaluations,
            oracleReports: qualificationInput.oracleReports,
            oracleEvidence: qualificationInput.oracleEvidence,
            processQualification: qualificationInput.processQualification,
            processEvidence: qualificationInput.processEvidence,
            releaseApproval: qualificationInput.releaseApproval,
            expectedRequestDigest: requestDigest,
            actualRequestDigest: requestDigest,
            analysis: request.analysis,
            proofView: request.proofView
        )
        var payload = native.payload
        payload.qualification = qualification
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
                qualification: qualification
            )
            : .blocked
        if status == .blocked,
           !qualification.satisfies(request.policy.minimumQualification),
           !diagnostics.contains(where: { $0.code == "RTL_QUALIFICATION_INSUFFICIENT" }) {
            diagnostics.append(RTLDiagnostic(
                severity: .error,
                code: "RTL_QUALIFICATION_INSUFFICIENT",
                message: "The correlated RTL result does not satisfy the requested qualification policy.",
                suggestedActions: ["attach_qualification_evidence", "select_qualified_backend", "lower_policy_for_exploration"]
            ))
        }
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
            metadata: native.metadata,
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
            metadata: native.metadata,
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
    ) throws -> [ArtifactReference] {
        let outputDirectory = rawDirectory(context: context)
        let auditDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "audit")
        let reviewDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "review")
        try context.storage.ensureDirectory(at: outputDirectory)
        try context.storage.ensureDirectory(at: auditDirectory)
        try context.storage.ensureDirectory(at: reviewDirectory)
        let outputURL = outputDirectory.appending(path: "rtl-verification-result.json")
        try context.storage.writeJSON(envelope, to: outputURL, forProjectAt: context.projectRoot)
        let resultReference = try artifactBuilder.reference(
            for: outputURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-result",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let qualificationURL = outputDirectory.appending(path: "qualification.json")
        try context.storage.writeJSON(
            envelope.payload.qualification,
            to: qualificationURL,
            forProjectAt: context.projectRoot
        )
        let qualificationReference = try artifactBuilder.reference(
            for: qualificationURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-qualification",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let reviewArtifact = makeReviewArtifact(envelope)
        let reviewURL = reviewDirectory.appending(path: "rtl-verification-review.json")
        try context.storage.writeJSON(
            reviewArtifact,
            to: reviewURL,
            forProjectAt: context.projectRoot
        )
        let reviewReference = try artifactBuilder.reference(
            for: reviewURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-review",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        let requestDigest = try digest(for: request)
        let auditArtifactIDs = envelope.artifacts.compactMap(\.artifactID)
            + [
                "rtl-verification-result",
                "rtl-verification-qualification",
                "rtl-verification-review",
                "rtl-verification-audit"
            ]
        let auditRecord = RTLVerificationStageAuditRecord(
            stageID: stageID,
            runID: context.runID,
            requestDigest: requestDigest,
            status: envelope.status,
            qualificationState: envelope.payload.qualification.state,
            artifactIDs: auditArtifactIDs,
            resumable: envelope.status == .completed || envelope.status == .blocked,
            nextActions: reviewArtifact.suggestedActions
        )
        let auditURL = auditDirectory.appending(path: "rtl-verification-audit.json")
        try context.storage.writeJSON(
            auditRecord,
            to: auditURL,
            forProjectAt: context.projectRoot
        )
        let auditReference = try artifactBuilder.reference(
            for: auditURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-audit",
            kind: ArtifactKind.report,
            format: ArtifactFormat.json
        )
        return [resultReference, qualificationReference, reviewReference, auditReference]
    }

    private func loadQualificationInput(from url: URL) throws -> RTLVerificationQualificationInput {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RTLVerificationExecutionError.invalidArtifact(
                "Could not read qualification input \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
        do {
            return try JSONDecoder().decode(RTLVerificationQualificationInput.self, from: data)
        } catch {
            throw RTLVerificationExecutionError.invalidArtifact(
                "Could not decode qualification input \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
    }

    private func loadResumableResult(
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) throws -> (envelope: RTLVerificationResult, artifacts: [ArtifactReference])? {
        let resultURL = rawDirectory(context: context)
            .appending(path: "rtl-verification-result.json")
        let auditURL = auditDirectory(context: context)
            .appending(path: "rtl-verification-audit.json")
        let qualificationURL = rawDirectory(context: context)
            .appending(path: "qualification.json")
        let reviewURL = reviewDirectory(context: context)
            .appending(path: "rtl-verification-review.json")
        guard FileManager.default.fileExists(atPath: resultURL.path),
              FileManager.default.fileExists(atPath: auditURL.path),
              FileManager.default.fileExists(atPath: qualificationURL.path),
              FileManager.default.fileExists(atPath: reviewURL.path) else {
            return nil
        }
        let audit = try context.storage.readJSON(
            RTLVerificationStageAuditRecord.self,
            from: auditURL
        )
        guard audit.stageID == stageID,
              audit.runID == context.runID,
              audit.resumable,
              audit.status == .completed || audit.status == .blocked,
              audit.artifactIDs.contains("rtl-verification-result"),
              audit.artifactIDs.contains("rtl-verification-qualification"),
              audit.artifactIDs.contains("rtl-verification-review"),
              audit.artifactIDs.contains("rtl-verification-audit"),
              audit.requestDigest == (try digest(for: request)) else {
            return nil
        }
        let envelope = try context.storage.readJSON(
            RTLVerificationResult.self,
            from: resultURL
        )
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
        let qualification = try context.storage.readJSON(
            RTLVerificationQualificationReport.self,
            from: qualificationURL
        )
        guard qualification == envelope.payload.qualification,
              audit.qualificationState == envelope.payload.qualification.state else {
            throw RTLVerificationExecutionError.invalidArtifact(
                "The persisted RTL qualification artifact does not match the result envelope."
            )
        }
        let review = try context.storage.readJSON(
            RTLVerificationReviewArtifact.self,
            from: reviewURL
        )
        guard review.stageID == stageID,
              review.runID == context.runID,
              review.analysis == envelope.payload.analysis,
              review.status == envelope.status,
              review.findings == envelope.payload.findings,
              review.diagnostics == envelope.diagnostics,
              review.appliedWaivers == envelope.payload.appliedWaivers,
              review.qualification == envelope.payload.qualification else {
            throw RTLVerificationExecutionError.invalidArtifact(
                "The persisted RTL review artifact does not match the result envelope."
            )
        }
        return (
            envelope: envelope,
            artifacts: try persistedStageReferences(context: context)
        )
    }

    private func persistedStageReferences(
        context: FlowExecutionContext
    ) throws -> [ArtifactReference] {
        let definitions: [(URL, String)] = [
            (rawDirectory(context: context).appending(path: "rtl-verification-result.json"), "rtl-verification-result"),
            (rawDirectory(context: context).appending(path: "qualification.json"), "rtl-verification-qualification"),
            (reviewDirectory(context: context).appending(path: "rtl-verification-review.json"), "rtl-verification-review"),
            (auditDirectory(context: context).appending(path: "rtl-verification-audit.json"), "rtl-verification-audit")
        ]
        var references: [ArtifactReference] = []
        for (url, artifactID) in definitions {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            references.append(try artifactBuilder.reference(
                for: url,
                projectRoot: context.projectRoot,
                artifactID: artifactID,
                kind: ArtifactKind.report,
                format: ArtifactFormat.json
            ))
        }
        return references
    }

    private func makeReviewArtifact(
        _ envelope: RTLVerificationResult
    ) -> RTLVerificationReviewArtifact {
        let findingActions = envelope.payload.findings.flatMap(\.suggestedActions)
        let diagnosticActions = envelope.diagnostics.flatMap(\.suggestedActions)
        let suggestedActions = Array(Set(findingActions + diagnosticActions)).sorted()
        let approvalRequired = envelope.status != .completed
            || !envelope.payload.findings.isEmpty
            || !envelope.payload.qualification.blockers.isEmpty
        return RTLVerificationReviewArtifact(
            stageID: stageID,
            runID: envelope.runID,
            analysis: envelope.payload.analysis,
            status: envelope.status,
            findings: envelope.payload.findings,
            diagnostics: envelope.diagnostics,
            appliedWaivers: envelope.payload.appliedWaivers,
            qualification: envelope.payload.qualification,
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

    private func rawDirectory(context: FlowExecutionContext) -> URL {
        context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "raw")
    }

    private func auditDirectory(context: FlowExecutionContext) -> URL {
        context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "audit")
    }

    private func reviewDirectory(context: FlowExecutionContext) -> URL {
        context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "review")
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
