import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPDDLExporter: Sendable {
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

    public func exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest,
        projectRoot: URL
    ) async throws -> XcircuiteSymbolicPlannerPDDLExportResult {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try await loadRunManifest(runID: request.runID)
        let problemReference = try await requiredProblemReference(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problemPath = problemReference.path
        let problem = try await workspaceStore.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: problemPath
        )
        guard problem.runID == request.runID else {
            throw XcircuiteSymbolicPlannerPDDLExportError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }
        let translationAuditResult = try await XcircuiteProblemTranslationAuditGate(
            auditor: XcircuiteProblemTranslationAuditor(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            )
        ).requireFreshNonBlockingAudit(
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

        let export = makePDDLExport(
            problem: problem,
            actionDomainSnapshot: actionDomainContext.snapshot
        )
        let artifacts = try await artifactStore.persistSymbolicPlannerPDDLExport(
            export,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteSymbolicPlannerPDDLExportResult(
            status: export.diagnostics.contains(where: { $0.severity == "error" }) ? "exported-with-errors" : "exported",
            runID: request.runID,
            problemID: problem.problemID,
            domainName: export.domainName,
            problemName: export.problemName,
            problemPath: problemPath,
            problemTranslationAuditArtifact: translationAuditResult.auditArtifact,
            actionDomainSnapshotArtifact: actionDomainContext.reference,
            domainArtifact: artifacts.domainArtifact,
            problemArtifact: artifacts.problemArtifact,
            exportArtifact: artifacts.exportArtifact,
            export: export
        )
    }

    public func makePDDLExport(
        problem: XcircuiteCircuitPlanningProblem,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot
    ) -> XcircuiteSymbolicPlannerPDDLExport {
        let domainName = pddlName(prefix: "domain", rawValue: problem.problemID)
        let problemName = pddlName(prefix: "problem", rawValue: problem.problemID)
        var atomRoles = AtomRoleAccumulator()
        var diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic] = []

        let initialAtoms = initialSymbolicState(for: problem)
        for atom in initialAtoms {
            atomRoles.add(role: "initial", for: atom)
        }

        let goalAtoms = unique(problem.objectives.flatMap { objective in
            let atoms = symbolicGoalAtoms(for: objective)
            if atoms.isEmpty {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPDDLDiagnostic(
                        severity: "warning",
                        code: "objective-has-no-symbolic-goal-atoms",
                        message: "Objective \(objective.objectiveID) does not declare symbolic goal atoms.",
                        objectiveID: objective.objectiveID
                    )
                )
            }
            return atoms
        })
        for atom in goalAtoms {
            atomRoles.add(role: "goal", for: atom)
        }

        let actionDrafts = actionDrafts(
            for: problem.candidateActions,
            actionDomainSnapshot: actionDomainSnapshot,
            costModel: problem.costModel
        )
        var actionMappings: [XcircuiteSymbolicPlannerPDDLActionMapping] = []
        for draft in actionDrafts {
            for atom in draft.preconditionAtoms {
                atomRoles.add(role: "precondition", for: atom)
            }
            for atom in draft.effectAtoms {
                atomRoles.add(role: "effect", for: atom)
            }
            diagnostics.append(contentsOf: draft.diagnostics)
            actionMappings.append(draft.mapping)
        }
        if actionDrafts.allSatisfy({ !$0.mapping.included }) {
            diagnostics.append(
                XcircuiteSymbolicPlannerPDDLDiagnostic(
                    severity: "error",
                    code: "no-included-pddl-actions",
                    message: "No candidate actions could be exported as PDDL actions."
                )
            )
        }

        let atomNameMap = pddlNameMap(for: atomRoles.atoms, prefix: "p")
        let actionNameMap = pddlNameMap(for: actionDrafts.map(\.mapping.actionID), prefix: "a")
        let atomMappings = atomRoles.atoms.map { atom in
            XcircuiteSymbolicPlannerPDDLAtomMapping(
                atom: atom,
                predicate: atomNameMap[atom] ?? pddlName(prefix: "p", rawValue: atom),
                roles: atomRoles.roles(for: atom)
            )
        }
        let mappedActionDrafts = actionDrafts.map { draft in
            ActionDraft(
                mapping: XcircuiteSymbolicPlannerPDDLActionMapping(
                    actionID: draft.mapping.actionID,
                    domainID: draft.mapping.domainID,
                    operationID: draft.mapping.operationID,
                    pddlAction: actionNameMap[draft.mapping.actionID]
                        ?? pddlName(prefix: "a", rawValue: draft.mapping.actionID),
                    included: draft.mapping.included,
                    preconditionAtoms: draft.mapping.preconditionAtoms,
                    effectAtoms: draft.mapping.effectAtoms,
                    actionCost: draft.mapping.actionCost,
                    actionCostUnit: draft.mapping.actionCostUnit,
                    actionCostSource: draft.mapping.actionCostSource,
                    diagnostics: draft.mapping.diagnostics
                ),
                preconditionAtoms: draft.preconditionAtoms,
                effectAtoms: draft.effectAtoms,
                diagnostics: draft.diagnostics
            )
        }
        let domainPDDL = makeDomainPDDL(
            domainName: domainName,
            atomMappings: atomMappings,
            actionDrafts: mappedActionDrafts,
            atomNameMap: atomNameMap
        )
        let problemPDDL = makeProblemPDDL(
            problemName: problemName,
            domainName: domainName,
            initialAtoms: initialAtoms,
            goalAtoms: goalAtoms,
            atomNameMap: atomNameMap
        )
        return XcircuiteSymbolicPlannerPDDLExport(
            runID: problem.runID,
            problemID: problem.problemID,
            domainName: domainName,
            problemName: problemName,
            requirements: [":strips", ":action-costs"],
            domainPDDL: domainPDDL,
            problemPDDL: problemPDDL,
            atomMappings: atomMappings,
            actionMappings: mappedActionDrafts.map(\.mapping),
            diagnostics: diagnostics
        )
    }

    private func actionDrafts(
        for actions: [XcircuitePlanningCandidateAction],
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        costModel: XcircuitePlanningCostModel
    ) -> [ActionDraft] {
        actions.sorted { $0.actionID < $1.actionID }.map { action in
            let domain = actionDomainSnapshot.domains.first { $0.domainID == action.domainID }
            let operation = domain?.operations.first { $0.operationID == action.operationID }
            var diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic] = []
            if domain == nil {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPDDLDiagnostic(
                        severity: "error",
                        code: "unsupported-action-domain",
                        message: "Candidate action \(action.actionID) references unsupported action domain \(action.domainID).",
                        actionID: action.actionID
                    )
                )
            } else if operation == nil {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPDDLDiagnostic(
                        severity: "error",
                        code: "unsupported-operation",
                        message: "Candidate action \(action.actionID) references unsupported operation \(action.domainID)/\(action.operationID).",
                        actionID: action.actionID
                    )
                )
            }
            if let operation, operation.maturity != action.maturity {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPDDLDiagnostic(
                        severity: "error",
                        code: "action-domain-maturity-mismatch",
                        message: "Candidate action \(action.actionID) declares \(action.maturity), but the action domain declares \(operation.maturity).",
                        actionID: action.actionID
                    )
                )
            }

            let preconditionAtoms = unique(
                action.requiredInputRefs.map { "ref:\($0)" }
                    + (operation?.preconditions ?? [])
            )
            let effectAtoms = unique(
                (operation?.effects ?? [])
                    + (operation?.producedArtifacts.map { "artifact:\($0)" } ?? [])
                    + candidateEffectAtoms(for: action)
            )
            if effectAtoms.isEmpty {
                diagnostics.append(
                    XcircuiteSymbolicPlannerPDDLDiagnostic(
                        severity: "error",
                        code: "action-has-no-symbolic-effects",
                        message: "Candidate action \(action.actionID) has no symbolic effects to export.",
                        actionID: action.actionID
                    )
                )
            }
            let included = diagnostics.allSatisfy { $0.severity != "error" }
            let actionCost = pddlActionCost(
                for: action,
                operation: operation,
                costModel: costModel
            )
            let mapping = XcircuiteSymbolicPlannerPDDLActionMapping(
                actionID: action.actionID,
                domainID: action.domainID,
                operationID: action.operationID,
                pddlAction: "",
                included: included,
                preconditionAtoms: preconditionAtoms,
                effectAtoms: effectAtoms,
                actionCost: actionCost.value,
                actionCostUnit: "planner action cost",
                actionCostSource: actionCost.source,
                diagnostics: diagnostics
            )
            return ActionDraft(
                mapping: mapping,
                preconditionAtoms: preconditionAtoms,
                effectAtoms: effectAtoms,
                diagnostics: diagnostics
            )
        }
    }

    private func makeDomainPDDL(
        domainName: String,
        atomMappings: [XcircuiteSymbolicPlannerPDDLAtomMapping],
        actionDrafts: [ActionDraft],
        atomNameMap: [String: String]
    ) -> String {
        var lines: [String] = [
            "(define (domain \(domainName))",
            "  (:requirements :strips :action-costs)",
            "  (:predicates",
        ]
        for mapping in atomMappings.sorted(by: { $0.predicate < $1.predicate }) {
            lines.append("    (\(mapping.predicate))")
        }
        lines.append("  )")
        lines.append("  (:functions (total-cost))")
        for draft in actionDrafts where draft.mapping.included {
            lines.append("  (:action \(draft.mapping.pddlAction)")
            lines.append("    :precondition \(pddlAnd(draft.preconditionAtoms, atomNameMap: atomNameMap))")
            lines.append("    :effect \(pddlEffect(draft.effectAtoms, atomNameMap: atomNameMap, actionCost: draft.mapping.actionCost ?? 1))")
            lines.append("  )")
        }
        lines.append(")")
        return lines.joined(separator: "\n") + "\n"
    }

    private func makeProblemPDDL(
        problemName: String,
        domainName: String,
        initialAtoms: [String],
        goalAtoms: [String],
        atomNameMap: [String: String]
    ) -> String {
        var lines: [String] = [
            "(define (problem \(problemName))",
            "  (:domain \(domainName))",
            "  (:init",
        ]
        for atom in initialAtoms.sorted() {
            if let predicate = atomNameMap[atom] {
                lines.append("    (\(predicate))")
            }
        }
        lines.append("    (= (total-cost) 0)")
        lines.append("  )")
        lines.append("  (:goal \(pddlAnd(goalAtoms, atomNameMap: atomNameMap)))")
        lines.append("  (:metric minimize (total-cost))")
        lines.append(")")
        return lines.joined(separator: "\n") + "\n"
    }

    private func pddlAnd(
        _ atoms: [String],
        atomNameMap: [String: String]
    ) -> String {
        let predicates = atoms.compactMap { atomNameMap[$0] }.sorted()
        guard !predicates.isEmpty else {
            return "(and)"
        }
        return "(and \(predicates.map { "(\($0))" }.joined(separator: " ")))"
    }

    private func pddlEffect(
        _ atoms: [String],
        atomNameMap: [String: String],
        actionCost: Double
    ) -> String {
        let predicates = atoms.compactMap { atomNameMap[$0] }.sorted()
        let effects = predicates.map { "(\($0))" } + ["(increase (total-cost) \(pddlNumber(actionCost)))"]
        return "(and \(effects.joined(separator: " ")))"
    }

    private func pddlNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) <= 0.000_001 {
            return String(Int(rounded))
        }
        return String(value)
    }

    private func pddlActionCost(
        for action: XcircuitePlanningCandidateAction,
        operation: XcircuiteActionDomainOperation?,
        costModel: XcircuitePlanningCostModel
    ) -> (value: Double, source: String) {
        if let explicitCost = explicitActionCost(from: action.parameterHints) {
            return (explicitCost, "candidate-action-parameter-hint")
        }

        var cost = 1
        if action.verificationGates.contains("approval-gate") {
            cost += weightedPenalty(for: "approval-cost", in: costModel, defaultValue: 0)
        }
        if action.domainID == "layout-edit" {
            cost += weightedPenalty(for: "layout-churn", in: costModel, defaultValue: 0)
        }
        if action.verificationGates.contains("simulation-metric-gate") {
            cost += weightedPenalty(for: "simulation-regression-risk", in: costModel, defaultValue: 0)
        }
        if operation?.reversible == false {
            cost += weightedPenalty(for: "irreversible-risk", in: costModel, defaultValue: 0)
        }
        return (Double(max(1, cost)), "planning-cost-model")
    }

    private func explicitActionCost(from hints: [String: PlanningParameterValue]) -> Double? {
        for key in ["plannerActionCost", "symbolicPlannerCost", "pddlActionCost"] {
            guard case .scalar(let value)? = hints[key],
                  value.isFinite,
                  value > 0 else {
                continue
            }
            return value.rounded(.up)
        }
        return nil
    }

    private func initialSymbolicState(for problem: XcircuiteCircuitPlanningProblem) -> [String] {
        unique(
            (problem.sourceRefs + problem.initialStateRefs).flatMap { reference in
                var atoms = ["ref:\(reference.refID)"]
                if let artifactID = reference.artifactID {
                    atoms.append("artifact:\(artifactID)")
                }
                atoms.append(contentsOf: stringArrayValue(for: "symbolicStateAtoms", in: reference.metadata))
                atoms.append(contentsOf: stringArrayValue(for: "satisfiedPreconditions", in: reference.metadata))
                return atoms
            }
        )
    }

    private func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        unique(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    private func candidateEffectAtoms(for action: XcircuitePlanningCandidateAction) -> [String] {
        unique(
            stringArrayValue(for: "symbolicEffects", in: action.parameterHints)
                + stringArrayValue(for: "satisfiesGoalAtoms", in: action.parameterHints)
                + stringArrayValue(for: "producedGoalAtoms", in: action.parameterHints)
        )
    }

    private func stringArrayValue(
        for key: String,
        in values: [String: PlanningParameterValue]
    ) -> [String] {
        guard case .textList(let items)? = values[key] else {
            return []
        }
        return items
    }

    private func pddlNameMap(
        for rawValues: [String],
        prefix: String
    ) -> [String: String] {
        var usedNames: Set<String> = []
        var result: [String: String] = [:]
        for rawValue in rawValues {
            var candidate = pddlName(prefix: prefix, rawValue: rawValue)
            var suffix = 2
            while usedNames.contains(candidate) {
                candidate = "\(pddlName(prefix: prefix, rawValue: rawValue))-\(suffix)"
                suffix += 1
            }
            usedNames.insert(candidate)
            result[rawValue] = candidate
        }
        return result
    }

    private func pddlName(prefix: String, rawValue: String) -> String {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let lowercased = rawValue.lowercased()
        let sanitized = lowercased.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = sanitized.joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(96)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(prefix)-\(trimmed.isEmpty ? "item" : trimmed)"
    }

    private func weightedPenalty(
        for termID: String,
        in costModel: XcircuitePlanningCostModel,
        defaultValue: Int
    ) -> Int {
        guard let term = costModel.terms.first(where: { $0.termID == termID }) else {
            return defaultValue
        }
        guard term.weight.isFinite, term.weight >= 0 else {
            return defaultValue
        }
        let rounded = Int(term.weight.rounded(.toNearestOrAwayFromZero))
        if term.direction == "maximize" {
            return -rounded
        }
        return rounded
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
        try await workspaceStore.loadRunManifest(runID: runID)
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
            throw XcircuiteSymbolicPlannerPDDLExportError.artifactNotFound(
                runID: missingRunID,
                artifactID: missingArtifactID
            )
        } catch XcircuiteActionDomainSnapshotResolutionError.runMismatch(let expected, let actual) {
            throw XcircuiteSymbolicPlannerPDDLExportError.runMismatch(expected: expected, actual: actual)
        }
        return ActionDomainSnapshotContext(snapshot: resolved.snapshot, reference: resolved.reference)
    }

    private func requiredProblemReference(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        if let explicitPath {
            let reference = try await workspaceStore.makeArtifactReference(
                forProjectRelativePath: explicitPath,
                artifactID: artifactID,
                kind: .other,
                format: .json
            )
            try validateProblemReferenceShape(reference, field: "planning-problem", runID: runID)
            return reference
        }
        guard let artifactID else {
            throw XcircuiteSymbolicPlannerPDDLExportError.missingProblemReference
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuiteSymbolicPlannerPDDLExportError.artifactNotFound(
                runID: runID,
                artifactID: artifactID
            )
        }
        guard matches.count == 1 else {
            throw XcircuiteSymbolicPlannerPDDLExportError.duplicateArtifactReference(
                runID: runID,
                artifactID: artifactID,
                count: matches.count
            )
        }
        let reference = matches[0]
        try validateProblemReferenceShape(reference, field: "planning-problem", runID: runID)
        try validateArtifactIntegrity(reference, field: "planning-problem", projectRoot: projectRoot)
        return reference
    }

    private func validateProblemReferenceShape(
        _ reference: ArtifactReference,
        field: String,
        runID: String
    ) throws {
        guard reference.kind == .other else {
            throw XcircuiteSymbolicPlannerPDDLExportError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected file kind \(ArtifactKind.other.rawValue), got \(reference.kind.rawValue)"
            )
        }
        guard reference.format == .json else {
            throw XcircuiteSymbolicPlannerPDDLExportError.invalidArtifactReference(
                field: field,
                path: reference.path,
                reason: "expected format \(ArtifactFormat.json.rawValue), got \(reference.format.rawValue)"
            )
        }
    }

    private func validateArtifactIntegrity(
        _ reference: ArtifactReference,
        field: String,
        projectRoot: URL
    ) throws {
        let integrity = makeArtifactReferenceVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteSymbolicPlannerPDDLExportError.artifactIntegrityFailed(
                field: field,
                artifactID: reference.artifactID,
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }

    private struct ActionDraft {
        var mapping: XcircuiteSymbolicPlannerPDDLActionMapping
        var preconditionAtoms: [String]
        var effectAtoms: [String]
        var diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic]
    }

    private struct ActionDomainSnapshotContext {
        var snapshot: XcircuitePlanningActionDomainSnapshot
        var reference: ArtifactReference
    }

    private struct AtomRoleAccumulator {
        private(set) var atoms: [String] = []
        private var roleMap: [String: [String]] = [:]

        mutating func add(role: String, for atom: String) {
            if roleMap[atom] == nil {
                atoms.append(atom)
                roleMap[atom] = []
            }
            if roleMap[atom]?.contains(role) == false {
                roleMap[atom]?.append(role)
            }
        }

        func roles(for atom: String) -> [String] {
            roleMap[atom] ?? []
        }
    }
}
