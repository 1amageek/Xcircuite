import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func pexSummaryMissingInputGateResult(
        required: Bool,
        sourceStepIDs: [String],
        message: String = "pex-summary-gate requires layout, source netlist, and PEX technology inputs before execution."
    ) -> XcircuitePlanVerificationGateResult {
        XcircuitePlanVerificationGateResult(
            gateID: "pex-summary-gate",
            required: required,
            status: "blocked",
            sourceStepIDs: sourceStepIDs,
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "gate-input-missing",
                    message: message,
                    gateID: "pex-summary-gate"
                ),
            ]
        )
    }

    func pexSummaryGateResult(
        required: Bool,
        sourceStepIDs: [String],
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        manifest: XcircuiteRunManifest,
        projectRoot: URL
    ) async throws -> GateExecutionEvaluation {
        guard let problem = try sourcePlanningProblem(
            for: plan,
            manifest: manifest,
            projectRoot: projectRoot
        ) else {
            return GateExecutionEvaluation(
                gateResult: pexSummaryMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    message: "pex-summary-gate requires a readable source planning problem reference."
                ),
                artifactRefs: []
            )
        }
        let hint = try pexInputHint(from: plan)
        let summaryRef = pexSummaryPlanningReference(
            references: problem.sourceRefs + problem.initialStateRefs
        )
        if let backendPolicyGate = pexBackendPolicyGateResult(
            required: required,
            sourceStepIDs: sourceStepIDs,
            hint: hint,
            summaryRef: summaryRef
        ) {
            return GateExecutionEvaluation(
                gateResult: backendPolicyGate,
                artifactRefs: []
            )
        }
        guard let spec = try pexExecutionSpec(from: plan, problem: problem) else {
            return GateExecutionEvaluation(
                gateResult: pexSummaryMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactRefs: []
            )
        }
        let executionSpec = try pexExecutionSpecByApplyingExecutionArtifacts(
            to: spec,
            plan: plan,
            execution: execution,
            sourceStepIDs: sourceStepIDs
        )
        guard let layoutRef = executionSpec.layoutRef,
              let layoutFormat = executionSpec.layoutFormat else {
            return GateExecutionEvaluation(
                gateResult: pexSummaryMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactRefs: []
            )
        }

        do {
            let verificationDirectory = try XcircuitePackage(projectRoot: projectRoot)
                .runDirectoryURL(for: plan.runID)
                .appending(path: "planning")
                .appending(path: "verification")
                .appending(path: "pex-summary")
            try packageStore.ensureDirectory(at: verificationDirectory)
            let executionResult = try await DefaultPEXEngine.withDefaults().run(PEXRunRequest(
                layoutURL: try url(
                    for: layoutRef,
                    manifest: manifest,
                    projectRoot: projectRoot
                ),
                layoutFormat: layoutFormat,
                sourceNetlistURL: try url(
                    for: executionSpec.sourceNetlistRef,
                    manifest: manifest,
                    projectRoot: projectRoot
                ),
                sourceNetlistFormat: executionSpec.sourceNetlistFormat,
                topCell: executionSpec.topCell,
                corners: executionSpec.corners,
                technology: .jsonFile(try url(
                    for: executionSpec.technologyRef,
                    manifest: manifest,
                    projectRoot: projectRoot
                )),
                backendSelection: executionSpec.backendSelection,
                options: executionSpec.options,
                workingDirectory: verificationDirectory
            ))
            let completeness = try PEXArtifactResolver(
                manifestURL: executionResult.manifestURL
            ).completenessReport()
            let summary = try PEXRunSummaryBuilder().build(
                manifestURL: executionResult.manifestURL,
                topNets: executionSpec.topNets
            )
            let summaryURL = verificationDirectory.appending(path: "pex-summary.json")
            try packageStore.writeJSON(summary, to: summaryURL, forProjectAt: projectRoot)
            let artifacts = try pexSummaryArtifactRefs(
                summaryURL: summaryURL,
                executionResult: executionResult,
                runID: plan.runID,
                projectRoot: projectRoot
            )
            for artifact in artifacts {
                try packageStore.upsertRunArtifact(artifact, runID: plan.runID, inProjectAt: projectRoot)
            }
            let status = pexSummaryGateStatus(
                runStatus: executionResult.status,
                completenessStatus: completeness.status
            )
            let diagnostics = pexSummaryDiagnostics(
                executionResult: executionResult,
                completeness: completeness,
                summary: summary,
                gateStatus: status
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "pex-summary-gate",
                    required: required,
                    status: status,
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: diagnostics
                ),
                artifactRefs: artifacts
            )
        } catch {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "pex-summary-gate-execution-failed",
                message: error.localizedDescription,
                gateID: "pex-summary-gate"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "pex-summary-gate",
                    required: required,
                    status: "failed",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactRefs: []
            )
        }
    }

    func pexSummaryArtifactRefs(
        summaryURL: URL,
        executionResult: PEXRunResult,
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteFileReference] {
        let pexRunDirectory = executionResult.manifestURL.deletingLastPathComponent()
        var artifacts = [
            try artifactBuilder.reference(
                for: executionResult.manifestURL,
                projectRoot: projectRoot,
                artifactID: "planning-pex-manifest",
                kind: .report,
                format: .json,
                producedByRunID: runID
            ),
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: projectRoot,
                artifactID: "planning-pex-summary",
                kind: .report,
                format: .json,
                producedByRunID: runID
            ),
        ]

        for artifact in executionResult.artifacts.artifacts where artifact.status == .available {
            let url = pexRunDirectory.appending(path: artifact.relativePath.value)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            artifacts.append(try artifactBuilder.reference(
                for: url,
                projectRoot: projectRoot,
                artifactID: planningPEXArtifactID(for: artifact),
                kind: pexFileKind(for: artifact.kind),
                format: pexFileFormat(for: artifact, url: url),
                producedByRunID: runID
            ))
        }
        return uniqueArtifactRefs(artifacts)
    }

    func pexExecutionSpec(
        from plan: XcircuiteCandidatePlan,
        problem: XcircuiteCircuitPlanningProblem
    ) throws -> PEXExecutionSpec? {
        let hint = try pexInputHint(from: plan)
        let references = problem.sourceRefs + problem.initialStateRefs
        let layoutRef = resolvableReference(planningReference(
            explicitID: hint.layoutRefID ?? hint.layoutRef,
            fallbackIDs: ["layout-ref", "layout-gds-ref", "layout-oasis-ref"],
            fallbackKinds: ["layout", "layout-gds", "layout-oasis"],
            references: references
        ))
        guard let sourceNetlistRef = resolvableReference(planningReference(
            explicitID: hint.sourceNetlistRefID ?? hint.sourceNetlistRef,
            fallbackIDs: ["source-netlist-ref", "schematic-netlist-ref"],
            fallbackKinds: ["source-netlist", "schematic-netlist", "netlist"],
            references: references
        )) else {
            return nil
        }
        guard let technologyRef = resolvableReference(planningReference(
            explicitID: hint.technologyRefID ?? hint.technologyRef,
            fallbackIDs: ["pex-technology-ref", "technology-ref"],
            fallbackKinds: ["pex-technology", "technology"],
            references: references
        )) else {
            return nil
        }
        let summaryRef = pexSummaryPlanningReference(references: references)
        guard let backendID = pexBackendID(from: hint, summaryRef: summaryRef) else {
            return nil
        }
        return PEXExecutionSpec(
            layoutRef: layoutRef,
            layoutFormat: try pexLayoutFormat(from: hint.layoutFormat, reference: layoutRef),
            sourceNetlistRef: sourceNetlistRef,
            sourceNetlistFormat: try pexNetlistFormat(from: hint.sourceNetlistFormat, reference: sourceNetlistRef),
            topCell: hint.topCell ?? "top",
            corners: pexCorners(from: hint.cornerIDs ?? hint.corners),
            technologyRef: technologyRef,
            backendSelection: PEXBackendSelection(
                backendID: backendID,
                executablePath: hint.executablePath,
                environmentOverrides: hint.environmentOverrides ?? [:]
            ),
            options: hint.options ?? .default,
            topNets: max(1, hint.topNets ?? 10)
        )
    }

    func pexExecutionSpecByApplyingExecutionArtifacts(
        to spec: PEXExecutionSpec,
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String]
    ) throws -> PEXExecutionSpec {
        var updated = spec
        let hint = try pexInputHint(from: plan)
        if let standardLayout = postExecutionStandardLayoutReference(
            from: execution,
            sourceStepIDs: sourceStepIDs,
            explicitArtifactID: hint.layoutRefID ?? hint.layoutRef,
            supportedFormats: .pex
        ) {
            updated.layoutRef = standardLayout
            updated.layoutFormat = try pexLayoutFormat(from: hint.layoutFormat, reference: standardLayout)
        }
        return updated
    }

    func pexInputHint(from plan: XcircuiteCandidatePlan) throws -> CandidatePlanPEXInputHint {
        var hint = CandidatePlanPEXInputHint()
        for step in plan.steps.sorted(by: { $0.order < $1.order })
            where step.verificationGates.contains("pex-summary-gate") {
            if let decoded: CandidatePlanPEXInputHint = try decodedHint("pexInputs", from: step) {
                hint.merge(decoded)
            }
            var stepHint = CandidatePlanPEXInputHint(
                layoutRef: stringHint("layoutRef", step: step),
                layoutRefID: stringHint("layoutRefID", step: step),
                sourceNetlistRef: stringHint("sourceNetlistRef", step: step),
                sourceNetlistRefID: stringHint("sourceNetlistRefID", step: step),
                technologyRef: stringHint("technologyRef", step: step),
                technologyRefID: stringHint("technologyRefID", step: step),
                topCell: stringHint("topCell", step: step),
                layoutFormat: stringHint("layoutFormat", step: step),
                sourceNetlistFormat: stringHint("sourceNetlistFormat", step: step),
                backendID: stringHint("backendID", step: step),
                pexBackendID: stringHint("pexBackendID", step: step),
                allowMockBackend: boolHint("allowMockBackend", step: step),
                executablePath: stringHint("pexExecutablePath", step: step) ?? stringHint("executablePath", step: step),
                cornerIDs: stringArrayHint("cornerIDs", step: step) ?? stringArrayHint("corners", step: step),
                topNets: intHint("topNets", step: step)
            )
            if let options: PEXRunOptions = try decodedHint("pexOptions", from: step) {
                stepHint.options = options
            }
            if let environmentOverrides: [String: String] = try decodedHint("pexEnvironmentOverrides", from: step) {
                stepHint.environmentOverrides = environmentOverrides
            }
            hint.merge(stepHint)
        }
        return hint
    }

    func pexSummaryPlanningReference(
        references: [XcircuitePlanningReference]
    ) -> XcircuitePlanningReference? {
        planningReference(
            explicitID: "pex-summary",
            fallbackIDs: ["pex-summary"],
            fallbackKinds: ["pex-summary"],
            references: references
        )
    }

    func pexBackendID(
        from hint: CandidatePlanPEXInputHint,
        summaryRef: XcircuitePlanningReference?
    ) -> String? {
        let rawBackendID = hint.backendID
            ?? hint.pexBackendID
            ?? stringMetadata("backendID", reference: summaryRef)
        let backendID = rawBackendID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return backendID?.isEmpty == false ? backendID : nil
    }

    func pexBackendPolicyGateResult(
        required: Bool,
        sourceStepIDs: [String],
        hint: CandidatePlanPEXInputHint,
        summaryRef: XcircuitePlanningReference?
    ) -> XcircuitePlanVerificationGateResult? {
        guard let backendID = pexBackendID(from: hint, summaryRef: summaryRef) else {
            return pexSummaryBackendPolicyGateResult(
                required: required,
                sourceStepIDs: sourceStepIDs,
                code: "pex-backend-required",
                message: "pex-summary-gate requires an explicit PEX backendID. The verifier does not fall back to a mock backend for signoff acceptance."
            )
        }
        guard !isMockPEXBackend(backendID) || !required else {
            return pexSummaryBackendPolicyGateResult(
                required: required,
                sourceStepIDs: sourceStepIDs,
                code: "pex-mock-backend-not-approved",
                message: "PEX backend \(backendID) is a mock backend and cannot satisfy a required PEX signoff gate. Use a qualified extraction backend."
            )
        }
        return nil
    }

    func pexSummaryBackendPolicyGateResult(
        required: Bool,
        sourceStepIDs: [String],
        code: String,
        message: String
    ) -> XcircuitePlanVerificationGateResult {
        XcircuitePlanVerificationGateResult(
            gateID: "pex-summary-gate",
            required: required,
            status: "blocked",
            sourceStepIDs: sourceStepIDs,
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: code,
                    message: message,
                    gateID: "pex-summary-gate"
                ),
            ]
        )
    }

    func isMockPEXBackend(_ backendID: String) -> Bool {
        backendID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("mock")
    }

    func pexLayoutFormat(
        from value: String?,
        reference: XcircuitePlanningReference?
    ) throws -> LayoutFormat? {
        if let value {
            guard let format = LayoutFormat(rawValue: value) else {
                throw CandidatePlanGateExecutionError.unsupportedPEXLayoutFormat(value)
            }
            return format
        }
        guard let reference else {
            return nil
        }
        switch reference.path?.split(separator: ".").last?.lowercased() {
        case "gds":
            return .gds
        case "oas", "oasis":
            return .oas
        default:
            throw CandidatePlanGateExecutionError.unsupportedPEXLayoutFormat(reference.path ?? reference.refID)
        }
    }

    func pexNetlistFormat(
        from value: String?,
        reference: XcircuitePlanningReference
    ) throws -> NetlistFormat {
        if let value {
            guard let format = NetlistFormat(rawValue: value) else {
                throw CandidatePlanGateExecutionError.unsupportedPEXNetlistFormat(value)
            }
            return format
        }
        switch reference.path?.split(separator: ".").last?.lowercased() {
        case "cdl":
            return .cdl
        case "v", "sv", "verilog":
            return .verilog
        default:
            return .spice
        }
    }

    func pexCorners(from values: [String]?) -> [PEXCorner] {
        let rawValues = values?.filter { !$0.isEmpty } ?? []
        let cornerIDs = rawValues.isEmpty ? ["tt"] : rawValues
        return cornerIDs.map { PEXCorner(id: $0) }
    }

    func resolvableReference(
        _ reference: XcircuitePlanningReference?
    ) -> XcircuitePlanningReference? {
        guard let reference else {
            return nil
        }
        guard reference.path != nil || reference.artifactID != nil else {
            return nil
        }
        return reference
    }

    func stringMetadata(
        _ key: String,
        reference: XcircuitePlanningReference?
    ) -> String? {
        guard case .string(let value) = reference?.metadata[key] else {
            return nil
        }
        return value
    }

    func pexSummaryGateStatus(
        runStatus: PEXRunStatus,
        completenessStatus: PEXArtifactCompletenessStatus
    ) -> String {
        runStatus == .success && completenessStatus == .complete ? "passed" : "failed"
    }

    func pexSummaryDiagnostics(
        executionResult: PEXRunResult,
        completeness: PEXArtifactCompletenessReport,
        summary: PEXRunSummaryReport,
        gateStatus: String
    ) -> [XcircuitePlanVerificationDiagnostic] {
        var diagnostics = executionResult.warnings.map { warning in
            XcircuitePlanVerificationDiagnostic(
                severity: "warning",
                code: "PEX_WARNING",
                message: warning.message,
                gateID: "pex-summary-gate"
            )
        }
        for corner in executionResult.cornerResults where corner.status == .failed {
            diagnostics.append(XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "PEX_CORNER_FAILED",
                message: "PEX failed for corner \(corner.cornerID.value).",
                gateID: "pex-summary-gate"
            ))
        }
        if executionResult.status != .success {
            diagnostics.append(XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "PEX_RUN_NOT_SUCCESS",
                message: "PEX run finished with status \(executionResult.status.rawValue).",
                gateID: "pex-summary-gate"
            ))
        }
        diagnostics.append(contentsOf: pexArtifactDiagnostics(from: completeness))
        diagnostics.append(contentsOf: summary.summary.corners.flatMap { corner in
            corner.diagnostics.map { diagnostic in
                XcircuitePlanVerificationDiagnostic(
                    severity: diagnostic.severity,
                    code: diagnostic.code,
                    message: diagnostic.message,
                    gateID: "pex-summary-gate"
                )
            }
        })
        if gateStatus == "failed" && diagnostics.isEmpty {
            diagnostics.append(XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "PEX_SUMMARY_GATE_FAILED",
                message: "PEX summary gate failed without backend diagnostics.",
                gateID: "pex-summary-gate"
            ))
        }
        return diagnostics
    }

    func pexArtifactDiagnostics(
        from report: PEXArtifactCompletenessReport
    ) -> [XcircuitePlanVerificationDiagnostic] {
        report.issues.map { issue in
            XcircuitePlanVerificationDiagnostic(
                severity: pexArtifactSeverity(for: issue, reportStatus: report.status),
                code: "PEX_ARTIFACT_\(issue.kind.rawValue)",
                message: artifactDiagnosticMessage(for: issue),
                gateID: "pex-summary-gate"
            )
        }
    }

    func pexArtifactSeverity(
        for issue: PEXArtifactCompletenessIssue,
        reportStatus: PEXArtifactCompletenessStatus
    ) -> String {
        switch reportStatus {
        case .complete:
            return "info"
        case .incomplete:
            return issue.kind == .failedCorner ? "error" : "warning"
        case .invalid:
            return "error"
        }
    }

    func artifactDiagnosticMessage(for issue: PEXArtifactCompletenessIssue) -> String {
        var parts = [issue.message]
        if let artifactID = issue.artifactID {
            parts.append("artifact=\(artifactID)")
        }
        if let cornerID = issue.cornerID {
            parts.append("corner=\(cornerID.value)")
        }
        if let path = issue.path {
            parts.append("path=\(path.value)")
        }
        return parts.joined(separator: " ")
    }

    func pexFileKind(for kind: PEXArtifactKind) -> XcircuiteFileKind {
        switch kind {
        case .layoutInput:
            return .layout
        case .netlistInput:
            return .netlist
        case .technologyInput, .processProfileDeckInput:
            return .technology
        case .request, .log, .report, .sourceConnectivityReport:
            return .report
        case .rawOutput, .spefRoundTrip, .spiceBackannotation, .parasiticIR:
            return .parasitic
        }
    }

    func pexFileFormat(
        for artifact: PEXArtifactRecord,
        url: URL
    ) -> XcircuiteFileFormat {
        switch artifact.kind {
        case .rawOutput, .spefRoundTrip:
            return .spef
        case .parasiticIR, .request, .technologyInput, .sourceConnectivityReport:
            return .json
        case .spiceBackannotation:
            return .spice
        case .log, .report, .processProfileDeckInput:
            return .text
        case .layoutInput:
            return layoutFileFormat(from: url)
        case .netlistInput:
            return netlistFileFormat(from: url)
        }
    }

    func layoutFileFormat(from url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "oas", "oasis":
            return .oasis
        case "gds":
            return .gdsii
        default:
            return .unknown
        }
    }

    func netlistFileFormat(from url: URL) -> XcircuiteFileFormat {
        switch url.pathExtension.lowercased() {
        case "sp", "spi", "cir", "net", "spice":
            return .spice
        default:
            return .unknown
        }
    }

    func planningPEXArtifactID(for artifact: PEXArtifactRecord) -> String {
        sanitizedArtifactID(raw: artifact.id, prefix: "planning-pex-")
    }

    func sanitizedArtifactID(raw: String, prefix: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let body = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let fallback = body.isEmpty ? "artifact" : body
        let maximumBodyLength = max(1, 128 - prefix.count)
        return prefix + String(fallback.prefix(maximumBodyLength))
    }
}
