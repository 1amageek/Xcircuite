import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuitePlanningProblemValidator: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let makeArtifactReferenceVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        makeArtifactReferenceVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.makeArtifactReferenceVerifier = makeArtifactReferenceVerifier
    }

    public func validatePlanningProblem(
        request: XcircuitePlanningProblemValidationRequest,
        projectRoot: URL
    ) async throws -> XcircuitePlanningProblemValidationResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try await loadRunManifest(runID: request.runID)
        let problemPath = try await requiredPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problem = try await workspaceStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: problemPath
        )
        guard problem.runID == request.runID else {
            throw XcircuitePlanningProblemValidationError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }
        let translationAuditResult = try await XcircuiteProblemTranslationAuditGate(
            auditor: XcircuiteProblemTranslationAuditor(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            )
        ).refreshAudit(
            runID: request.runID,
            problemPath: problemPath,
            projectRoot: projectRoot
        )
        let actionDomainContext = try await loadOrPersistActionDomainSnapshot(
            explicitPath: request.actionDomainPath,
            artifactID: request.actionDomainArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let validation = makeValidation(
            problem: problem,
            problemPath: problemPath,
            actionDomainSnapshot: actionDomainContext.snapshot,
            actionDomainSnapshotRef: actionDomainContext.reference,
            problemTranslationAudit: translationAuditResult.audit,
            problemTranslationAuditRef: translationAuditResult.auditArtifact
        )
        let validationRef = try await artifactStore.persistPlanningProblemValidation(
            validation,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuitePlanningProblemValidationResult(
            status: validation.status,
            runID: request.runID,
            problemID: problem.problemID,
            problemPath: problemPath,
            validation: validation,
            validationArtifact: validationRef,
            problemTranslationAuditArtifact: translationAuditResult.auditArtifact,
            actionDomainSnapshotArtifact: actionDomainContext.reference
        )
    }

    public func makeValidation(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        actionDomainSnapshotRef: ArtifactReference? = nil,
        problemTranslationAudit: XcircuiteProblemTranslationAudit? = nil,
        problemTranslationAuditRef: ArtifactReference? = nil
    ) -> XcircuitePlanningProblemValidation {
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        if let problemTranslationAudit {
            diagnostics.append(contentsOf: XcircuiteProblemTranslationAuditGate.validationDiagnostics(
                for: problemTranslationAudit
            ))
        }
        diagnostics.append(contentsOf: schemaDiagnostics(for: problem))
        diagnostics.append(contentsOf: duplicateDiagnostics(for: problem))
        diagnostics.append(contentsOf: referenceDiagnostics(for: problem))
        diagnostics.append(contentsOf: assumptionDiagnostics(for: problem))
        diagnostics.append(contentsOf: riskDiagnostics(for: problem))
        diagnostics.append(contentsOf: objectiveDiagnostics(for: problem))
        diagnostics.append(contentsOf: actionDiagnostics(for: problem, actionDomainSnapshot: actionDomainSnapshot))
        diagnostics.append(contentsOf: gateDiagnostics(for: problem, actionDomainSnapshot: actionDomainSnapshot))

        let status: String
        if diagnostics.contains(where: { $0.severity == "error" }) {
            status = "invalid"
        } else if diagnostics.contains(where: { $0.severity == "warning" }) {
            status = "valid-with-warnings"
        } else {
            status = "valid"
        }

        return XcircuitePlanningProblemValidation(
            status: status,
            runID: problem.runID,
            problemID: problem.problemID,
            problemPath: problemPath,
            problemTranslationAuditArtifactID: problemTranslationAuditRef?.artifactID,
            problemTranslationAuditPath: problemTranslationAuditRef?.path,
            actionDomainSnapshotArtifactID: actionDomainSnapshotRef?.artifactID,
            actionDomainSnapshotPath: actionDomainSnapshotRef?.path,
            sourceRefCount: problem.sourceRefs.count,
            initialStateRefCount: problem.initialStateRefs.count,
            assumptionCount: problem.assumptions.count,
            riskClassificationCount: problem.riskClassifications.count,
            objectiveCount: problem.objectives.count,
            candidateActionCount: problem.candidateActions.count,
            verificationGateCount: problem.verificationGates.count,
            diagnostics: diagnostics
        )
    }

    private func schemaDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        if problem.schemaVersion != 1 {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "unsupported-schema-version",
                    message: "Planning problem schemaVersion \(problem.schemaVersion) is not supported."
                )
            )
        }
        diagnostics.append(contentsOf: identifierDiagnostics(value: problem.problemID, label: "problemID"))
        diagnostics.append(contentsOf: identifierDiagnostics(value: problem.runID, label: "runID"))
        return diagnostics
    }

    private func duplicateDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        duplicateDiagnostics(values: (problem.sourceRefs + problem.initialStateRefs).map(\.refID), code: "duplicate-reference", label: "reference")
            + duplicateDiagnostics(values: problem.assumptions.map(\.assumptionID), code: "duplicate-assumption", label: "assumption")
            + duplicateDiagnostics(values: problem.riskClassifications.map(\.riskID), code: "duplicate-risk", label: "risk")
            + duplicateDiagnostics(values: problem.objectives.map(\.objectiveID), code: "duplicate-objective", label: "objective")
            + duplicateDiagnostics(values: problem.constraints.map(\.constraintID), code: "duplicate-constraint", label: "constraint")
            + duplicateDiagnostics(values: problem.actionDomainRefs, code: "duplicate-action-domain-ref", label: "action domain ref")
            + duplicateDiagnostics(values: problem.candidateActions.map(\.actionID), code: "duplicate-candidate-action", label: "candidate action")
            + duplicateDiagnostics(values: problem.verificationGates.map(\.gateID), code: "duplicate-verification-gate", label: "verification gate")
    }

    private func referenceDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        let availableRefIDs = Set((problem.sourceRefs + problem.initialStateRefs).map(\.refID))
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        if availableRefIDs.isEmpty {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "no-initial-or-source-refs",
                    message: "Planning problem must declare at least one sourceRef or initialStateRef."
                )
            )
        }
        for objective in problem.objectives {
            for refID in objective.sourceRefIDs where !availableRefIDs.contains(refID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "objective-source-ref-missing",
                        message: "Objective \(objective.objectiveID) references missing source ref \(refID).",
                        refID: refID,
                        objectiveID: objective.objectiveID
                    )
                )
            }
        }
        for constraint in problem.constraints {
            for refID in constraint.sourceRefIDs where !availableRefIDs.contains(refID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "constraint-source-ref-missing",
                        message: "Constraint \(constraint.constraintID) references missing source ref \(refID).",
                        refID: refID
                    )
                )
            }
        }
        return diagnostics
    }

    private func assumptionDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        let availableRefIDs = Set((problem.sourceRefs + problem.initialStateRefs).map(\.refID))
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        for assumption in problem.assumptions {
            diagnostics.append(contentsOf: identifierDiagnostics(
                value: assumption.assumptionID,
                label: "assumptionID",
                assumptionID: assumption.assumptionID
            ))
            if let confidence = assumption.confidence, confidence < 0 || confidence > 1 {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "assumption-confidence-out-of-range",
                        message: "Assumption \(assumption.assumptionID) confidence must be between 0 and 1.",
                        assumptionID: assumption.assumptionID
                    )
                )
            }
            for refID in assumption.sourceRefIDs where !availableRefIDs.contains(refID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "assumption-source-ref-missing",
                        message: "Assumption \(assumption.assumptionID) references missing source ref \(refID).",
                        refID: refID,
                        assumptionID: assumption.assumptionID
                    )
                )
            }
            if assumption.requiredBeforeExecution && assumption.status != "resolved" {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "required-assumption-unresolved",
                        message: "Assumption \(assumption.assumptionID) must be resolved before plan execution.",
                        assumptionID: assumption.assumptionID
                    )
                )
            } else if assumption.status != "resolved" {
                diagnostics.append(
                    diagnostic(
                        severity: "warning",
                        code: "assumption-unresolved",
                        message: "Assumption \(assumption.assumptionID) remains \(assumption.status).",
                        assumptionID: assumption.assumptionID
                    )
                )
            }
        }
        return diagnostics
    }

    private func riskDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        let objectiveIDs = Set(problem.objectives.map(\.objectiveID))
        let actionIDs = Set(problem.candidateActions.map(\.actionID))
        let hasHumanApprovalConstraint = problem.constraints.contains { $0.kind == "human-approval" }
        let validSeverities = Set(["low", "medium", "high", "critical"])
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []

        for risk in problem.riskClassifications {
            diagnostics.append(contentsOf: identifierDiagnostics(
                value: risk.riskID,
                label: "riskID",
                riskID: risk.riskID
            ))
            if !validSeverities.contains(risk.severity) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "risk-severity-invalid",
                        message: "Risk \(risk.riskID) severity \(risk.severity) is not supported.",
                        riskID: risk.riskID
                    )
                )
            }
            for objectiveID in risk.affectedObjectiveIDs where !objectiveIDs.contains(objectiveID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "risk-objective-missing",
                        message: "Risk \(risk.riskID) references missing objective \(objectiveID).",
                        objectiveID: objectiveID,
                        riskID: risk.riskID
                    )
                )
            }
            for actionID in risk.affectedActionIDs where !actionIDs.contains(actionID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "risk-action-missing",
                        message: "Risk \(risk.riskID) references missing candidate action \(actionID).",
                        actionID: actionID,
                        riskID: risk.riskID
                    )
                )
            }
            if (risk.severity == "high" || risk.severity == "critical") && risk.requiredApprovals.isEmpty {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "high-risk-approval-missing",
                        message: "Risk \(risk.riskID) is \(risk.severity) and must declare required approvals.",
                        riskID: risk.riskID
                    )
                )
            }
            if !risk.requiredApprovals.isEmpty && !hasHumanApprovalConstraint {
                diagnostics.append(
                    diagnostic(
                        severity: "warning",
                        code: "risk-approval-constraint-missing",
                        message: "Risk \(risk.riskID) declares approval requirements but the problem has no human-approval constraint.",
                        riskID: risk.riskID
                    )
                )
            }
        }
        return diagnostics
    }

    private func objectiveDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        if problem.objectives.isEmpty {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "no-objectives",
                    message: "Planning problem must declare at least one objective."
                )
            )
        }
        for objective in problem.objectives {
            diagnostics.append(contentsOf: identifierDiagnostics(
                value: objective.objectiveID,
                label: "objectiveID",
                objectiveID: objective.objectiveID
            ))
            if symbolicGoalAtoms(for: objective).isEmpty {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "objective-goal-atoms-missing",
                        message: "Objective \(objective.objectiveID) must declare symbolicGoalAtoms, goalAtoms, or requiredEffects.",
                        objectiveID: objective.objectiveID
                    )
                )
            }
            let actionCount = problem.candidateActions.filter {
                $0.sourceObjectiveIDs.contains(objective.objectiveID)
            }.count
            if actionCount == 0 {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "objective-has-no-candidate-actions",
                        message: "Objective \(objective.objectiveID) has no candidate actions.",
                        objectiveID: objective.objectiveID
                    )
                )
            }
        }
        return diagnostics
    }

    private func actionDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        let objectiveIDs = Set(problem.objectives.map(\.objectiveID))
        let declaredDomainIDs = Set(problem.actionDomainRefs)
        let availableRefIDs = Set((problem.sourceRefs + problem.initialStateRefs).map(\.refID))
        let snapshotDomainIDs = Set(actionDomainSnapshot.domains.map(\.domainID))
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []

        if problem.candidateActions.isEmpty {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "no-candidate-actions",
                    message: "Planning problem must declare at least one candidate action."
                )
            )
        }
        for domainID in declaredDomainIDs where !snapshotDomainIDs.contains(domainID) {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "action-domain-ref-unsupported",
                    message: "Action domain ref \(domainID) is not present in the action-domain snapshot."
                )
            )
        }
        for action in problem.candidateActions {
            diagnostics.append(contentsOf: identifierDiagnostics(
                value: action.actionID,
                label: "actionID",
                actionID: action.actionID
            ))
            if !declaredDomainIDs.contains(action.domainID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "candidate-action-domain-not-declared",
                        message: "Candidate action \(action.actionID) references undeclared action domain \(action.domainID).",
                        actionID: action.actionID
                    )
                )
            }
            for objectiveID in action.sourceObjectiveIDs where !objectiveIDs.contains(objectiveID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "candidate-action-objective-missing",
                        message: "Candidate action \(action.actionID) references missing objective \(objectiveID).",
                        objectiveID: objectiveID,
                        actionID: action.actionID
                    )
                )
            }
            if action.sourceObjectiveIDs.isEmpty {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "candidate-action-has-no-source-objectives",
                        message: "Candidate action \(action.actionID) must reference at least one source objective.",
                        actionID: action.actionID
                    )
                )
            }
            for refID in action.requiredInputRefs where !availableRefIDs.contains(refID) {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "candidate-action-required-ref-missing",
                        message: "Candidate action \(action.actionID) requires missing input ref \(refID).",
                        refID: refID,
                        actionID: action.actionID
                    )
                )
            }
            guard let domain = actionDomainSnapshot.domains.first(where: { $0.domainID == action.domainID }) else {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "unsupported-action-domain",
                        message: "Candidate action \(action.actionID) references unsupported action domain \(action.domainID).",
                        actionID: action.actionID
                    )
                )
                continue
            }
            guard let operation = domain.operations.first(where: { $0.operationID == action.operationID }) else {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "unsupported-operation",
                        message: "Candidate action \(action.actionID) references unsupported operation \(action.domainID)/\(action.operationID).",
                        actionID: action.actionID
                    )
                )
                continue
            }
            if operation.maturity != action.maturity {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "action-domain-maturity-mismatch",
                        message: "Candidate action \(action.actionID) declares maturity \(action.maturity), but \(action.domainID)/\(action.operationID) declares \(operation.maturity).",
                        actionID: action.actionID
                    )
                )
            }
        }
        return diagnostics
    }

    private func gateDiagnostics(
        for problem: XcircuiteCircuitPlanningProblem,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        let problemGateIDs = Set(problem.verificationGates.map(\.gateID))
        let operationGateIDs = Set(actionDomainSnapshot.domains.flatMap { domain in
            domain.operations.flatMap(\.verificationGates)
        })
        var diagnostics: [XcircuitePlanningProblemValidationDiagnostic] = []
        if problem.verificationGates.isEmpty {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "no-verification-gates",
                    message: "Planning problem must declare verification gates."
                )
            )
        }
        for gate in problem.verificationGates {
            diagnostics.append(contentsOf: identifierDiagnostics(
                value: gate.gateID,
                label: "gateID",
                gateID: gate.gateID
            ))
        }
        for action in problem.candidateActions {
            for gateID in action.verificationGates
                where !problemGateIDs.contains(gateID) && !operationGateIDs.contains(gateID)
            {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "candidate-action-gate-not-declared",
                        message: "Candidate action \(action.actionID) references verification gate \(gateID) that is not declared by the problem or action-domain snapshot.",
                        actionID: action.actionID,
                        gateID: gateID
                    )
                )
            }
        }
        return diagnostics
    }

    private func identifierDiagnostics(
        value: String,
        label: String,
        refID: String? = nil,
        objectiveID: String? = nil,
        actionID: String? = nil,
        gateID: String? = nil,
        assumptionID: String? = nil,
        riskID: String? = nil
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        do {
            try FlowIdentifierValidator().validate(value, kind: .artifactID)
            return []
        } catch {
            return [
                diagnostic(
                    severity: "error",
                    code: "invalid-\(label)",
                    message: "\(label) \(value) is not a valid identifier.",
                    refID: refID,
                    objectiveID: objectiveID,
                    actionID: actionID,
                    gateID: gateID,
                    assumptionID: assumptionID,
                    riskID: riskID
                ),
            ]
        }
    }

    private func duplicateDiagnostics(
        values: [String],
        code: String,
        label: String
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for value in values {
            if seen.contains(value) {
                duplicates.append(value)
            } else {
                seen.insert(value)
            }
        }
        return unique(duplicates).map { duplicate in
            diagnostic(
                severity: "error",
                code: code,
                message: "Duplicate \(label) ID \(duplicate)."
            )
        }
    }

    private func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        unique(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    private func stringArrayValue(
        for key: String,
        in values: [String: PlanningParameterValue]
    ) -> [String] {
        guard case .textList(let array)? = values[key] else {
            return []
        }
        return array
    }

    private func diagnostic(
        severity: String,
        code: String,
        message: String,
        refID: String? = nil,
        objectiveID: String? = nil,
        actionID: String? = nil,
        gateID: String? = nil,
        assumptionID: String? = nil,
        riskID: String? = nil
    ) -> XcircuitePlanningProblemValidationDiagnostic {
        XcircuitePlanningProblemValidationDiagnostic(
            severity: severity,
            code: code,
            message: message,
            refID: refID,
            objectiveID: objectiveID,
            actionID: actionID,
            gateID: gateID,
            assumptionID: assumptionID,
            riskID: riskID
        )
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    private func loadOrPersistActionDomainSnapshot(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ActionDomainSnapshotContext {
        let resolved: XcircuiteResolvedActionDomainSnapshot
        do {
            resolved = try await XcircuiteActionDomainSnapshotResolver(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            ).loadExplicitOrDefault(
                explicitPath: explicitPath,
                artifactID: artifactID,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot
            )
        } catch XcircuiteActionDomainSnapshotResolutionError.artifactNotFound(
            let missingRunID,
            let missingArtifactID
        ) {
            throw XcircuitePlanningProblemValidationError.artifactNotFound(
                runID: missingRunID,
                artifactID: missingArtifactID
            )
        } catch XcircuiteActionDomainSnapshotResolutionError.artifactIntegrityFailed(
            let path,
            let status,
            let message
        ) {
            throw XcircuitePlanningProblemValidationError.artifactIntegrityFailed(
                path: path,
                status: status,
                message: message
            )
        } catch XcircuiteActionDomainSnapshotResolutionError.invalidArtifactReference(let path, let reason) {
            throw XcircuitePlanningProblemValidationError.invalidArtifactReference(
                path: path,
                reason: reason
            )
        } catch XcircuiteActionDomainSnapshotResolutionError.runMismatch(let expected, let actual) {
            throw XcircuitePlanningProblemValidationError.runMismatch(expected: expected, actual: actual)
        } catch XcircuiteActionDomainSnapshotResolutionError.producedByRunMismatch(let expected, let actual) {
            throw XcircuitePlanningProblemValidationError.artifactProducerRunMismatch(
                expected: expected,
                actual: actual
            )
        }
        return ActionDomainSnapshotContext(snapshot: resolved.snapshot, reference: resolved.reference)
    }

    private func requiredPath(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> String {
        if let explicitPath {
            return try await verifiedExplicitProblemPath(
                explicitPath,
                artifactID: artifactID,
                manifest: manifest,
                runID: runID,
                projectRoot: projectRoot
            ).path
        }
        guard let artifactID else {
            throw XcircuitePlanningProblemValidationError.missingProblemReference
        }
        guard let reference = try verifiedManifestProblemReference(
            artifactID: artifactID,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ) else {
            throw XcircuitePlanningProblemValidationError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        return reference.path
    }

    private func verifiedExplicitProblemPath(
        _ explicitPath: String,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        let matches = manifest.artifacts.filter { $0.path == explicitPath }
        guard matches.count <= 1 else {
            throw XcircuitePlanningProblemValidationError.invalidArtifactReference(
                path: explicitPath,
                reason: "multiple manifest artifacts reference the same explicit path."
            )
        }
        let reference: ArtifactReference
        if let existing = matches.first {
            reference = existing
        } else {
            reference = try await workspaceStore.makeArtifactReference(
                forProjectRelativePath: explicitPath,
                artifactID: artifactID,
                kind: .other,
                format: .json
            )
        }
        try validateProblemReference(
            reference,
            expectedArtifactID: artifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func verifiedManifestProblemReference(
        artifactID: String,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference? {
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            return nil
        }
        guard matches.count == 1 else {
            throw XcircuitePlanningProblemValidationError.invalidArtifactReference(
                path: artifactID,
                reason: "run manifest contains \(matches.count) artifacts with the same artifact ID."
            )
        }
        let reference = matches[0]
        try validateProblemReference(
            reference,
            expectedArtifactID: artifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func validateProblemReference(
        _ reference: ArtifactReference,
        expectedArtifactID: String?,
        runID: String,
        projectRoot: URL
    ) throws {
        if let expectedArtifactID, reference.artifactID != expectedArtifactID {
            throw XcircuitePlanningProblemValidationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuitePlanningProblemValidationError.invalidArtifactReference(
                path: reference.path,
                reason: "planning problems must be JSON artifacts."
            )
        }
        let integrity = makeArtifactReferenceVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuitePlanningProblemValidationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }

    private struct ActionDomainSnapshotContext {
        var snapshot: XcircuitePlanningActionDomainSnapshot
        var reference: ArtifactReference
    }
}
