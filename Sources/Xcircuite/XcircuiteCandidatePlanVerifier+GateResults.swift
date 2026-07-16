import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel
import CircuiteFoundation

extension XcircuiteCandidatePlanVerifier {
    func makeGateResults(
        plan: XcircuiteCandidatePlan,
        stepResults: [XcircuitePlanVerificationStepResult],
        riskReviews: [XcircuitePlanRiskReview],
        artifactRefs: [ArtifactReference],
        projectRoot: URL?
    ) -> [XcircuitePlanVerificationGateResult] {
        let gateSpecs = gateSpecifications(plan: plan, stepResults: stepResults, riskReviews: riskReviews)
        return gateSpecs.map { gate in
            gateResult(
                gateID: gate.gateID,
                required: gate.required,
                sourceStepIDs: stepResults.filter { $0.gateIDs.contains(gate.gateID) }.map(\.stepID),
                stepResults: stepResults,
                riskReviews: riskReviews,
                artifactRefs: artifactRefs,
                projectRoot: projectRoot
            )
        }
    }

    func gateSpecifications(
        plan: XcircuiteCandidatePlan,
        stepResults: [XcircuitePlanVerificationStepResult],
        riskReviews: [XcircuitePlanRiskReview]
    ) -> [XcircuitePlanningVerificationGate] {
        var gates: [String: XcircuitePlanningVerificationGate] = [:]
        for gate in plan.verificationGates {
            gates[gate.gateID] = gate
        }
        for gateID in stepResults.flatMap(\.gateIDs) where gates[gateID] == nil {
            gates[gateID] = XcircuitePlanningVerificationGate(
                gateID: gateID,
                required: true,
                description: "Step-level verification gate."
            )
        }
        if XcircuiteCandidatePlanRiskReviewer().requiresApprovalGate(riskReviews) && gates["approval-gate"] == nil {
            gates["approval-gate"] = XcircuitePlanningVerificationGate(
                gateID: "approval-gate",
                required: true,
                description: "Candidate plan risk requires human approval."
            )
        }
        return gates.values.sorted { $0.gateID < $1.gateID }
    }

    func gateResult(
        gateID: String,
        required: Bool,
        sourceStepIDs: [String],
        stepResults: [XcircuitePlanVerificationStepResult],
        riskReviews: [XcircuitePlanRiskReview],
        artifactRefs: [ArtifactReference],
        projectRoot: URL?
    ) -> XcircuitePlanVerificationGateResult {
        if stepResults.contains(where: { $0.status == "blocked" && $0.gateIDs.contains(gateID) }) {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "blocked",
                sourceStepIDs: sourceStepIDs,
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "gate-blocked-by-step",
                        message: "Gate \(gateID) cannot run because at least one source step is blocked.",
                        gateID: gateID
                    ),
                ]
            )
        }

        switch gateID {
        case "artifact-integrity", "schema-validation", "precondition-validation":
            return artifactIntegrityGateResult(
                gateID: gateID,
                required: required,
                sourceStepIDs: sourceStepIDs,
                artifactRefs: artifactRefs,
                projectRoot: projectRoot
            )
        case "approval-gate":
            return approvalGateResult(
                gateID: gateID,
                required: required,
                sourceStepIDs: sourceStepIDs,
                riskReviews: riskReviews
            )
        default:
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "pending",
                sourceStepIDs: sourceStepIDs,
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "warning",
                        code: "gate-execution-required",
                        message: "Gate \(gateID) requires a stage executor result before plan acceptance.",
                        gateID: gateID
                    ),
                ]
            )
        }
    }

    func approvalGateResult(
        gateID: String,
        required: Bool,
        sourceStepIDs: [String],
        riskReviews: [XcircuitePlanRiskReview]
    ) -> XcircuitePlanVerificationGateResult {
        let approvalRiskReviews = riskReviews.filter { !$0.requiredApprovals.isEmpty }
        guard !approvalRiskReviews.isEmpty else {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "blocked",
                sourceStepIDs: sourceStepIDs,
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "warning",
                        code: "human-approval-required",
                        message: "Human approval is required before this plan can be accepted.",
                        gateID: gateID
                    ),
                ]
            )
        }
        if approvalRiskReviews.contains(where: { $0.status == "approval-rejected" }) {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "failed",
                sourceStepIDs: sourceStepIDs,
                diagnostics: XcircuiteCandidatePlanRiskReviewer()
                    .blockingDiagnostics(from: approvalRiskReviews)
            )
        }
        if approvalRiskReviews.contains(where: { $0.status == "approval-required" }) {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "blocked",
                sourceStepIDs: sourceStepIDs,
                diagnostics: XcircuiteCandidatePlanRiskReviewer()
                    .blockingDiagnostics(from: approvalRiskReviews)
            )
        }
        return XcircuitePlanVerificationGateResult(
            gateID: gateID,
            required: required,
            status: "passed",
            sourceStepIDs: sourceStepIDs,
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "info",
                    code: "risk-approval-recorded",
                    message: "Required risk approvals are recorded for this candidate plan.",
                    gateID: gateID
                ),
            ]
        )
    }

    func artifactIntegrityGateResult(
        gateID: String,
        required: Bool,
        sourceStepIDs: [String],
        artifactRefs: [ArtifactReference],
        projectRoot: URL?
    ) -> XcircuitePlanVerificationGateResult {
        guard let projectRoot else {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "blocked",
                sourceStepIDs: sourceStepIDs,
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "artifact-integrity-project-root-required",
                        message: "Artifact integrity verification requires a project root so artifact paths can be resolved and hashed.",
                        gateID: gateID
                    ),
                ]
            )
        }
        guard !artifactRefs.isEmpty else {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "failed",
                sourceStepIDs: sourceStepIDs,
                diagnostics: [
                    XcircuitePlanVerificationDiagnostic(
                        severity: "error",
                        code: "artifact-integrity-no-artifacts",
                        message: "Artifact integrity verification requires at least one artifact reference.",
                        gateID: gateID
                    ),
                ]
            )
        }

        let diagnostics = artifactRefs.compactMap { artifact -> XcircuitePlanVerificationDiagnostic? in
            let integrity = artifactVerifier.verify(artifact, relativeTo: projectRoot)
            guard !integrity.isVerified else {
                return nil
            }
            return artifactIntegrityDiagnostic(
                gateID: gateID,
                artifact: artifact,
                integrity: integrity
            )
        }
        if diagnostics.isEmpty {
            return XcircuitePlanVerificationGateResult(
                gateID: gateID,
                required: required,
                status: "passed",
                sourceStepIDs: sourceStepIDs
            )
        }
        return XcircuitePlanVerificationGateResult(
            gateID: gateID,
            required: required,
            status: "failed",
            sourceStepIDs: sourceStepIDs,
            diagnostics: diagnostics
        )
    }

    func artifactIntegrityDiagnostic(
        gateID: String,
        artifact: ArtifactReference,
        integrity: ArtifactIntegrity
    ) -> XcircuitePlanVerificationDiagnostic {
        let status = integrity.flowVerificationStatus
        var messageParts = [
            "Artifact integrity verification failed.",
            "artifactID=\(artifact.artifactID)",
            "path=\(artifact.path)",
            "status=\(status.rawValue)",
            integrity.diagnosticMessage,
        ]
        for issue in integrity.issues {
            if let expectedByteCount = issue.expectedByteCount {
                messageParts.append("expectedByteCount=\(expectedByteCount)")
            }
            if let actualByteCount = issue.actualByteCount {
                messageParts.append("actualByteCount=\(actualByteCount)")
            }
            if let expectedDigest = issue.expectedDigest {
                messageParts.append("expectedDigest=\(expectedDigest.hexadecimalValue)")
            }
            if let actualDigest = issue.actualDigest {
                messageParts.append("actualDigest=\(actualDigest.hexadecimalValue)")
            }
        }
        return XcircuitePlanVerificationDiagnostic(
            severity: "error",
            code: artifactIntegrityDiagnosticCode(for: status),
            message: messageParts.joined(separator: " "),
            gateID: gateID
        )
    }

    func artifactIntegrityDiagnosticCode(for status: FlowArtifactVerificationStatus) -> String {
        switch status {
        case .verified:
            "artifact-integrity-verified"
        case .missingArtifact:
            "artifact-integrity-missing-artifact"
        case .missingDigest:
            "artifact-integrity-missing-digest"
        case .missingByteCount:
            "artifact-integrity-missing-byte-count"
        case .invalidDigest:
            "artifact-integrity-invalid-digest"
        case .invalidByteCount:
            "artifact-integrity-invalid-byte-count"
        case .byteCountMismatch:
            "artifact-integrity-byte-count-mismatch"
        case .sha256Mismatch:
            "artifact-integrity-sha256-mismatch"
        case .invalidPath:
            "artifact-integrity-invalid-path"
        case .unreadableArtifact:
            "artifact-integrity-unreadable-artifact"
        }
    }

    func nativeDRCGateResult(
        required: Bool,
        sourceStepIDs: [String],
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        projectRoot: URL
    ) async throws -> GateExecutionEvaluation {
        guard let spec = try nativeDRCExportSpec(from: plan) else {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "gate-input-missing",
                message: "native-drc requires a drcExportSpec or drcRules parameter hint.",
                gateID: "native-drc"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: required,
                    status: "blocked",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactReferences: []
            )
        }
        guard let layoutRef = latestLayoutDocumentRef(from: execution) else {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "gate-input-missing",
                message: "native-drc requires an executed layout document artifact.",
                gateID: "native-drc"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: required,
                    status: "blocked",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactReferences: []
            )
        }

        do {
            let verificationDirectory = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
                .runDirectoryURL(for: plan.runID)
                .appending(path: "planning")
                .appending(path: "verification")
                .appending(path: "native-drc")
            try await ensureWorkspaceDirectory(at: verificationDirectory, projectRoot: projectRoot)
            let layoutURL = try projectURL(for: layoutRef.path, projectRoot: projectRoot)
            let documentData = try Data(contentsOf: layoutURL)
            let document = try layoutDocumentSerializer.decodeDocument(documentData)
            let drcLayout = try nativeDRCLayout(from: document, spec: spec)
            let drcLayoutURL = verificationDirectory.appending(path: "drc-layout.json")
            try await writeWorkspaceJSON(drcLayout, to: drcLayoutURL, projectRoot: projectRoot)

            let executionResult = try await DefaultDRCEngine(backend: nil).run(DRCRequest(
                layoutURL: drcLayoutURL,
                topCell: spec.topCell,
                workingDirectory: verificationDirectory,
                backendSelection: DRCBackendSelection(backendID: "native")
            ))
            let summaryURL = verificationDirectory.appending(path: "drc-summary.json")
            try await writeWorkspaceJSON(
                DRCRunSummaryBuilder().build(result: executionResult),
                to: summaryURL,
                projectRoot: projectRoot
            )
            let artifacts = try await retainRunArtifacts(nativeDRCArtifactReferences(
                drcLayoutURL: drcLayoutURL,
                summaryURL: summaryURL,
                executionResult: executionResult,
                projectRoot: projectRoot
            ), runID: plan.runID, projectRoot: projectRoot)
            let diagnostics = executionResult.result.diagnostics.map { diagnostic in
                XcircuitePlanVerificationDiagnostic(
                    severity: diagnostic.severity.rawValue,
                    code: diagnostic.ruleID ?? "native-drc-diagnostic",
                    message: diagnostic.message,
                    gateID: "native-drc"
                )
            }
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: required,
                    status: executionResult.result.passed ? "passed" : "failed",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: diagnostics
                ),
                artifactReferences: artifacts
            )
        } catch {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "native-drc-execution-failed",
                message: error.localizedDescription,
                gateID: "native-drc"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: required,
                    status: "failed",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactReferences: []
            )
        }
    }

    func nativeLVSMissingInputGateResult(
        required: Bool,
        sourceStepIDs: [String],
        message: String = "native-lvs requires layout netlist or layout GDS plus schematic netlist inputs before execution."
    ) -> XcircuitePlanVerificationGateResult {
        XcircuitePlanVerificationGateResult(
            gateID: "native-lvs",
            required: required,
            status: "blocked",
            sourceStepIDs: sourceStepIDs,
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "gate-input-missing",
                    message: message,
                    gateID: "native-lvs"
                ),
            ]
        )
    }

    func nativeLVSGateResult(
        required: Bool,
        sourceStepIDs: [String],
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> GateExecutionEvaluation {
        guard let problem = try sourcePlanningProblem(
            for: plan,
            manifest: manifest,
            projectRoot: projectRoot
        ) else {
            return GateExecutionEvaluation(
                gateResult: nativeLVSMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    message: "native-lvs requires a readable source planning problem reference."
                ),
                artifactReferences: []
            )
        }
        guard let spec = try nativeLVSExecutionSpec(from: plan, problem: problem) else {
            return GateExecutionEvaluation(
                gateResult: nativeLVSMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactReferences: []
            )
        }
        let executionSpec = try nativeLVSExecutionSpecByApplyingExecutionArtifacts(
            to: spec,
            plan: plan,
            execution: execution,
            sourceStepIDs: sourceStepIDs
        )
        guard executionSpec.layoutNetlistRef != nil || executionSpec.layoutGDSRef != nil else {
            return GateExecutionEvaluation(
                gateResult: nativeLVSMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactReferences: []
            )
        }
        guard executionSpec.layoutNetlistRef != nil || executionSpec.technologyRef != nil else {
            return GateExecutionEvaluation(
                gateResult: nativeLVSMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    message: "native-lvs requires a technology reference when using a standard layout artifact."
                ),
                artifactReferences: []
            )
        }

        do {
            let verificationDirectory = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
                .runDirectoryURL(for: plan.runID)
                .appending(path: "planning")
                .appending(path: "verification")
                .appending(path: "native-lvs")
            try await ensureWorkspaceDirectory(at: verificationDirectory, projectRoot: projectRoot)
            let executionResult = try await DefaultLVSEngine(
                backend: nil,
                layoutNetlistExtractor: nil
            ).run(LVSRequest(
                layoutNetlistURL: try executionSpec.layoutNetlistRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                layoutGDSURL: try executionSpec.layoutGDSRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                layoutFormat: executionSpec.layoutFormat,
                schematicNetlistURL: try url(
                    for: executionSpec.schematicNetlistRef,
                    manifest: manifest,
                    projectRoot: projectRoot
                ),
                topCell: executionSpec.topCell,
                technologyURL: try executionSpec.technologyRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                extractionDeckURL: try executionSpec.extractionDeckRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                processProfileID: executionSpec.processProfileID,
                waiverURL: try executionSpec.waiverRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                modelEquivalenceURL: try executionSpec.modelEquivalenceRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                terminalEquivalenceURL: try executionSpec.terminalEquivalenceRef.map {
                    try url(for: $0, manifest: manifest, projectRoot: projectRoot)
                },
                workingDirectory: verificationDirectory,
                backendSelection: LVSBackendSelection(backendID: executionSpec.backendID)
            ))
            let summaryURL = verificationDirectory.appending(path: "lvs-summary.json")
            try await writeWorkspaceJSON(
                LVSRunSummaryBuilder().build(result: executionResult),
                to: summaryURL,
                projectRoot: projectRoot
            )
            let artifacts = try await retainRunArtifacts(nativeLVSArtifactReferences(
                summaryURL: summaryURL,
                executionResult: executionResult,
                projectRoot: projectRoot
            ), runID: plan.runID, projectRoot: projectRoot)
            let diagnostics = executionResult.result.diagnostics.map { diagnostic in
                XcircuitePlanVerificationDiagnostic(
                    severity: diagnostic.severity.rawValue,
                    code: diagnostic.ruleID ?? "native-lvs-diagnostic",
                    message: diagnostic.message,
                    gateID: "native-lvs"
                )
            }
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-lvs",
                    required: required,
                    status: nativeLVSGateStatus(from: executionResult.result),
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: diagnostics
                ),
                artifactReferences: artifacts
            )
        } catch {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "native-lvs-execution-failed",
                message: error.localizedDescription,
                gateID: "native-lvs"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "native-lvs",
                    required: required,
                    status: "failed",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactReferences: []
            )
        }
    }

    func nativeLVSGateStatus(from result: LVSResult) -> String {
        guard result.executionStatus == .completed else {
            return "blocked"
        }
        guard result.readiness == .ready else {
            return "blocked"
        }
        switch result.verdict {
        case .match:
            return result.passed ? "passed" : "failed"
        case .mismatch:
            return "failed"
        case .blocked:
            return "blocked"
        }
    }

    func nativeLVSExecutionSpecByApplyingExecutionArtifacts(
        to spec: NativeLVSExecutionSpec,
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String]
    ) throws -> NativeLVSExecutionSpec {
        var updated = spec
        if let editedLayout = editedLVSNetlistReference(
            from: execution,
            plan: plan,
            sourceStepIDs: sourceStepIDs,
            role: "layout"
        ) {
            updated.layoutNetlistRef = editedLayout
            updated.layoutGDSRef = nil
            updated.layoutFormat = nil
            updated.backendID = "native"
        } else {
            let hint = try nativeLVSInputHint(from: plan)
            if let standardLayout = postExecutionStandardLayoutReference(
                from: execution,
                sourceStepIDs: sourceStepIDs,
                explicitArtifactID: hint.layoutGDSRefID ?? hint.layoutGDSRef,
                supportedFormats: .lvs
            ) {
                updated.layoutNetlistRef = nil
                updated.layoutGDSRef = standardLayout
                updated.layoutFormat = try lvsLayoutFormat(from: standardLayout)
                updated.backendID = "native-gds"
            }
        }
        if let editedSchematic = editedLVSNetlistReference(
            from: execution,
            plan: plan,
            sourceStepIDs: sourceStepIDs,
            role: "schematic"
        ) {
            updated.schematicNetlistRef = editedSchematic
        }
        if let modelEquivalence = postExecutionModelEquivalenceReference(
            from: execution,
            sourceStepIDs: sourceStepIDs
        ) {
            updated.modelEquivalenceRef = modelEquivalence
        }
        if let terminalEquivalence = postExecutionTerminalEquivalenceReference(
            from: execution,
            sourceStepIDs: sourceStepIDs
        ) {
            updated.terminalEquivalenceRef = terminalEquivalence
        }
        return updated
    }

    func editedLVSNetlistReference(
        from execution: XcircuiteCandidatePlanExecution,
        plan: XcircuiteCandidatePlan,
        sourceStepIDs: [String],
        role: String
    ) -> XcircuitePlanningReference? {
        let sourceStepIDSet = Set(sourceStepIDs)
        let role = role.lowercased()
        let stepsByID = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.stepID, $0) })
        let stepResults = execution.stepResults.sorted { $0.order < $1.order }
        for stepResult in stepResults where sourceStepIDSet.isEmpty || sourceStepIDSet.contains(stepResult.stepID) {
            guard let step = stepsByID[stepResult.stepID],
                  stringHint("lvsEditedNetlistRole", step: step)?.lowercased() == role,
                  let reference = stepResult.artifactReferences
                      .first(where: isEditedNetlistArtifact) else {
                continue
            }
            return planningReference(from: reference)
        }
        return nil
    }

    func simulationMetricMissingInputGateResult(
        required: Bool,
        sourceStepIDs: [String],
        message: String = "simulation-metric-gate requires simulation expectations with a netlist reference or a post-layout metric report."
    ) -> XcircuitePlanVerificationGateResult {
        XcircuitePlanVerificationGateResult(
            gateID: "simulation-metric-gate",
            required: required,
            status: "blocked",
            sourceStepIDs: sourceStepIDs,
            diagnostics: [
                XcircuitePlanVerificationDiagnostic(
                    severity: "warning",
                    code: "gate-input-missing",
                    message: message,
                    gateID: "simulation-metric-gate"
                ),
            ]
        )
    }

    func simulationMetricGateResult(
        required: Bool,
        sourceStepIDs: [String],
        plan: XcircuiteCandidatePlan,
        execution: XcircuiteCandidatePlanExecution,
        manifest: FlowRunManifest,
        projectRoot: URL
    ) async throws -> GateExecutionEvaluation {
        guard let problem = try sourcePlanningProblem(
            for: plan,
            manifest: manifest,
            projectRoot: projectRoot
        ) else {
            return GateExecutionEvaluation(
                gateResult: simulationMetricMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    message: "simulation-metric-gate requires a readable source planning problem reference."
                ),
                artifactReferences: []
            )
        }
        guard let spec = try simulationMetricExecutionSpec(from: plan, problem: problem) else {
            return GateExecutionEvaluation(
                gateResult: simulationMetricMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactReferences: []
            )
        }

        do {
            let verificationDirectory = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
                .runDirectoryURL(for: plan.runID)
                .appending(path: "planning")
                .appending(path: "verification")
                .appending(path: "simulation-metric")
            try await ensureWorkspaceDirectory(at: verificationDirectory, projectRoot: projectRoot)

            if !spec.expectations.isEmpty, let netlistRef = spec.netlistRef {
                let executionNetlistRef = editedNetlistReference(
                    from: execution,
                    sourceStepIDs: sourceStepIDs
                )
                return try await runSimulationMetricGate(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    spec: spec,
                    netlistRef: executionNetlistRef ?? netlistRef,
                    manifest: manifest,
                    verificationDirectory: verificationDirectory,
                    runID: plan.runID,
                    projectRoot: projectRoot
                )
            }

            if let metricReportRef = spec.metricReportRef {
                return try await evaluatePostLayoutMetricReportGate(
                    required: required,
                    sourceStepIDs: sourceStepIDs,
                    metricReportRef: metricReportRef,
                    manifest: manifest,
                    verificationDirectory: verificationDirectory,
                    runID: plan.runID,
                    projectRoot: projectRoot
                )
            }

            return GateExecutionEvaluation(
                gateResult: simulationMetricMissingInputGateResult(
                    required: required,
                    sourceStepIDs: sourceStepIDs
                ),
                artifactReferences: []
            )
        } catch {
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "simulation-metric-gate-execution-failed",
                message: error.localizedDescription,
                gateID: "simulation-metric-gate"
            )
            return GateExecutionEvaluation(
                gateResult: XcircuitePlanVerificationGateResult(
                    gateID: "simulation-metric-gate",
                    required: required,
                    status: "failed",
                    sourceStepIDs: sourceStepIDs,
                    diagnostics: [diagnostic]
                ),
                artifactReferences: []
            )
        }
    }

    func editedNetlistReference(
        from execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String]
    ) -> XcircuitePlanningReference? {
        let sourceStepIDSet = Set(sourceStepIDs)
        let stepResults = execution.stepResults.sorted { $0.order < $1.order }
        for stepResult in stepResults where sourceStepIDSet.isEmpty || sourceStepIDSet.contains(stepResult.stepID) {
            if let reference = stepResult.artifactReferences
                .first(where: isEditedNetlistArtifact) {
                return planningReference(from: reference)
            }
        }
        if let reference = execution.artifactReferences
            .first(where: isEditedNetlistArtifact) {
            return planningReference(from: reference)
        }
        return nil
    }

    func isEditedNetlistArtifact(_ reference: ArtifactReference) -> Bool {
        guard reference.kind == .netlist else {
            return false
        }
        return reference.artifactID.contains("edited-netlist")
    }

    func postExecutionStandardLayoutReference(
        from execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String],
        explicitArtifactID: String?,
        supportedFormats: StandardLayoutSupport
    ) -> XcircuitePlanningReference? {
        let sourceStepIDSet = Set(sourceStepIDs)
        let stepArtifactRefs = execution.stepResults
            .sorted { $0.order > $1.order }
            .filter { sourceStepIDSet.isEmpty || sourceStepIDSet.contains($0.stepID) }
            .flatMap { $0.artifactReferences }
        let executionArtifactRefs = Array(execution.artifactReferences.reversed())
        let artifactRefs = stepArtifactRefs + executionArtifactRefs
        if let explicitArtifactID,
           let reference = artifactRefs.first(where: {
               ($0.artifactID == explicitArtifactID || $0.path == explicitArtifactID)
                   && isStandardLayoutArtifact($0, supportedFormats: supportedFormats)
           }) {
            return planningReference(
                from: reference,
                kind: standardLayoutPlanningKind(for: reference)
            )
        }
        guard let reference = artifactRefs.first(where: {
            isStandardLayoutArtifact($0, supportedFormats: supportedFormats)
        }) else {
            return nil
        }
        return planningReference(
            from: reference,
            kind: standardLayoutPlanningKind(for: reference)
        )
    }

    func postExecutionModelEquivalenceReference(
        from execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String]
    ) -> XcircuitePlanningReference? {
        guard let reference = postExecutionArtifactReference(
            from: execution,
            sourceStepIDs: sourceStepIDs,
            matching: isModelEquivalencePolicyArtifact
        ) else {
            return nil
        }
        return planningReference(
            from: reference,
            kind: "model-equivalence"
        )
    }

    func postExecutionTerminalEquivalenceReference(
        from execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String]
    ) -> XcircuitePlanningReference? {
        guard let reference = postExecutionArtifactReference(
            from: execution,
            sourceStepIDs: sourceStepIDs,
            matching: isTerminalEquivalencePolicyArtifact
        ) else {
            return nil
        }
        return planningReference(
            from: reference,
            kind: "terminal-equivalence"
        )
    }

    func postExecutionArtifactReference(
        from execution: XcircuiteCandidatePlanExecution,
        sourceStepIDs: [String],
        matching predicate: (ArtifactReference) -> Bool
    ) -> ArtifactReference? {
        let sourceStepIDSet = Set(sourceStepIDs)
        let stepArtifactRefs = execution.stepResults
            .sorted { $0.order > $1.order }
            .filter { sourceStepIDSet.isEmpty || sourceStepIDSet.contains($0.stepID) }
            .flatMap { $0.artifactReferences }
        let executionArtifactRefs = Array(execution.artifactReferences.reversed())
        return (stepArtifactRefs + executionArtifactRefs).first(where: predicate)
    }

    func isStandardLayoutArtifact(
        _ reference: ArtifactReference,
        supportedFormats: StandardLayoutSupport
    ) -> Bool {
        guard reference.kind == .layout else {
            return false
        }
        switch supportedFormats {
        case .lvs:
            return lvsLayoutFormatForArtifact(reference) != nil
        case .pex:
            return pexLayoutFormatForArtifact(reference) != nil
        }
    }

    func isModelEquivalencePolicyArtifact(_ reference: ArtifactReference) -> Bool {
        guard reference.format == .json else {
            return false
        }
        let artifactID = reference.artifactID.lowercased()
        let path = reference.path.lowercased()
        return artifactID.contains("model-equivalence-policy")
            || path.hasSuffix("model-equivalence-policy.json")
    }

    func isTerminalEquivalencePolicyArtifact(_ reference: ArtifactReference) -> Bool {
        guard reference.format == .json else {
            return false
        }
        let artifactID = reference.artifactID.lowercased()
        let path = reference.path.lowercased()
        return artifactID.contains("terminal-equivalence-policy")
            || path.hasSuffix("terminal-equivalence-policy.json")
    }

    func standardLayoutPlanningKind(for reference: ArtifactReference) -> String {
        switch reference.format {
        case .gdsii:
            return "layout-gds"
        case .oasis:
            return "layout-oasis"
        default:
            return "layout"
        }
    }

    func standardLayoutPathExtension(for reference: ArtifactReference) -> String? {
        reference.path.split(separator: ".").last.map { String($0).lowercased() }
    }

    func lvsLayoutFormatForArtifact(_ reference: ArtifactReference) -> LVSLayoutFormat? {
        switch reference.format {
        case .gdsii:
            return .gds
        case .oasis:
            return .oasis
        default:
            break
        }
        switch standardLayoutPathExtension(for: reference) {
        case "gds", "gdsii":
            return .gds
        case "oas", "oasis":
            return .oasis
        case "cif":
            return .cif
        case "dxf":
            return .dxf
        default:
            return nil
        }
    }

    func pexLayoutFormatForArtifact(_ reference: ArtifactReference) -> LayoutFormat? {
        switch reference.format {
        case .gdsii:
            return .gds
        case .oasis:
            return .oas
        default:
            break
        }
        switch standardLayoutPathExtension(for: reference) {
        case "gds", "gdsii":
            return .gds
        case "oas", "oasis":
            return .oas
        default:
            return nil
        }
    }

    func planningReference(
        from reference: ArtifactReference,
        kind: String = "edited-netlist"
    ) -> XcircuitePlanningReference {
        XcircuitePlanningReference(
            refID: reference.artifactID,
            kind: kind,
            path: reference.path,
            artifactID: reference.artifactID
        )
    }
}
