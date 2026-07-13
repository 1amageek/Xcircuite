import DesignFlowKernel
import Foundation
import LogicIR
import RTLVerificationCore
import RTLVerificationEngine
import TimingCore
import ToolQualification
import XcircuitePackage

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
        engine: (any RTLVerificationExecuting)? = nil
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
                kind: .rtl,
                format: format(for: resolvedRTL),
                producedByRunID: context.runID
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
                    kind: .rtl,
                    format: format(for: resolvedInput),
                    producedByRunID: context.runID
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
                    kind: .rtl,
                    format: format(for: resolvedReference),
                    producedByRunID: context.runID
                )
                referenceDesign = LogicDesignReference(
                    artifact: reference,
                    topDesignName: topModuleName,
                    designDigest: reference.sha256 ?? ""
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
                    kind: .rtl,
                    format: format(for: resolvedInput),
                    producedByRunID: context.runID
                )
            }
            let constraintReference: TimingConstraintReference?
            let constraintArtifact: XcircuiteFileReference?
            if let constraintsInput {
                let resolvedConstraints = try constraintsInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                let artifact = try artifactBuilder.reference(
                    for: resolvedConstraints,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-constraints",
                    kind: .constraint,
                    format: .sdc,
                    producedByRunID: context.runID
                )
                constraintArtifact = artifact
                constraintReference = TimingConstraintReference(
                    artifact: artifact,
                    modeIDs: []
                )
            } else {
                constraintReference = nil
                constraintArtifact = nil
            }
            let qualificationInputValue: RTLVerificationQualificationInput?
            let qualificationArtifact: XcircuiteFileReference?
            if let qualificationInput {
                let resolvedQualification = try qualificationInput.resolveExisting(
                    projectRoot: context.projectRoot,
                    runDirectory: context.runDirectory
                )
                qualificationArtifact = try artifactBuilder.reference(
                    for: resolvedQualification,
                    projectRoot: context.projectRoot,
                    artifactID: "rtl-qualification-input",
                    kind: .report,
                    format: .json,
                    producedByRunID: context.runID
                )
                qualificationInputValue = try loadQualificationInput(from: resolvedQualification)
            } else {
                qualificationInputValue = nil
                qualificationArtifact = nil
            }
            let request = RTLVerificationRequest(
                runID: context.runID,
                inputs: [rtlReference]
                    + additionalRTLReferences
                    + (constraintArtifact.map { [$0] } ?? [])
                    + (qualificationArtifact.map { [$0] } ?? []),
                design: LogicDesignReference(
                    artifact: rtlReference,
                    topDesignName: topModuleName,
                    designDigest: rtlReference.sha256 ?? ""
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
            let envelope = try await verificationEngine.execute(request)
            try context.checkCancellation()
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
        _ envelope: XcircuiteEngineResultEnvelope<RTLVerificationPayload>,
        request: RTLVerificationRequest,
        context: FlowExecutionContext
    ) throws -> [XcircuiteFileReference] {
        let outputDirectory = rawDirectory(context: context)
        let auditDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "audit")
        let reviewDirectory = context.runDirectory
            .appending(path: "stages")
            .appending(path: stageID)
            .appending(path: "review")
        try context.packageStore.ensureDirectory(at: outputDirectory)
        try context.packageStore.ensureDirectory(at: auditDirectory)
        try context.packageStore.ensureDirectory(at: reviewDirectory)
        let outputURL = outputDirectory.appending(path: "rtl-verification-result.json")
        try context.packageStore.writeJSON(envelope, to: outputURL, forProjectAt: context.projectRoot)
        let resultReference = try artifactBuilder.reference(
            for: outputURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-result",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
        let qualificationURL = outputDirectory.appending(path: "qualification.json")
        try context.packageStore.writeJSON(
            envelope.payload.qualification,
            to: qualificationURL,
            forProjectAt: context.projectRoot
        )
        let qualificationReference = try artifactBuilder.reference(
            for: qualificationURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-qualification",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
        )
        let reviewArtifact = makeReviewArtifact(envelope)
        let reviewURL = reviewDirectory.appending(path: "rtl-verification-review.json")
        try context.packageStore.writeJSON(
            reviewArtifact,
            to: reviewURL,
            forProjectAt: context.projectRoot
        )
        let reviewReference = try artifactBuilder.reference(
            for: reviewURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-review",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
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
        try context.packageStore.writeJSON(
            auditRecord,
            to: auditURL,
            forProjectAt: context.projectRoot
        )
        let auditReference = try artifactBuilder.reference(
            for: auditURL,
            projectRoot: context.projectRoot,
            artifactID: "rtl-verification-audit",
            kind: .report,
            format: .json,
            producedByRunID: context.runID
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
    ) throws -> (envelope: XcircuiteEngineResultEnvelope<RTLVerificationPayload>, artifacts: [XcircuiteFileReference])? {
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
        let audit = try context.packageStore.readJSON(
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
        let envelope = try context.packageStore.readJSON(
            XcircuiteEngineResultEnvelope<RTLVerificationPayload>.self,
            from: resultURL
        )
        guard envelope.runID == context.runID, envelope.status == audit.status else {
            return nil
        }
        let qualification = try context.packageStore.readJSON(
            RTLVerificationQualificationReport.self,
            from: qualificationURL
        )
        guard qualification == envelope.payload.qualification,
              audit.qualificationState == envelope.payload.qualification.state else {
            throw RTLVerificationExecutionError.invalidArtifact(
                "The persisted RTL qualification artifact does not match the result envelope."
            )
        }
        let review = try context.packageStore.readJSON(
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
    ) throws -> [XcircuiteFileReference] {
        let definitions: [(URL, String)] = [
            (rawDirectory(context: context).appending(path: "rtl-verification-result.json"), "rtl-verification-result"),
            (rawDirectory(context: context).appending(path: "qualification.json"), "rtl-verification-qualification"),
            (reviewDirectory(context: context).appending(path: "rtl-verification-review.json"), "rtl-verification-review"),
            (auditDirectory(context: context).appending(path: "rtl-verification-audit.json"), "rtl-verification-audit")
        ]
        var references: [XcircuiteFileReference] = []
        for (url, artifactID) in definitions {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            references.append(try artifactBuilder.reference(
                for: url,
                projectRoot: context.projectRoot,
                artifactID: artifactID,
                kind: .report,
                format: .json,
                producedByRunID: context.runID
            ))
        }
        return references
    }

    private func makeReviewArtifact(
        _ envelope: XcircuiteEngineResultEnvelope<RTLVerificationPayload>
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
        return XcircuiteHasher().sha256(data: try encoder.encode(request))
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
        envelope: XcircuiteEngineResultEnvelope<RTLVerificationPayload>,
        resultArtifacts: [XcircuiteFileReference]
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

    private func flowDiagnostic(_ diagnostic: XcircuiteEngineDiagnostic) -> FlowDiagnostic {
        let severity: FlowDiagnosticSeverity
        switch diagnostic.severity {
        case .info: severity = .info
        case .warning: severity = .warning
        case .error: severity = .error
        }
        return FlowDiagnostic(severity: severity, code: diagnostic.code, message: diagnostic.message)
    }

    private func gateStatus(for status: XcircuiteEngineExecutionStatus) -> FlowGateStatus {
        switch status {
        case .completed: return .passed
        case .failed: return .failed
        case .blocked: return .blocked
        case .cancelled: return .incomplete
        }
    }

    private func format(for url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "sv", "svh": return .systemVerilog
        case "v", "vh": return .verilog
        case "sdc": return .sdc
        case "json": return .json
        default: return .text
        }
    }
}
