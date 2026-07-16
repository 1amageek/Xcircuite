import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteProblemTranslationAuditor: Sendable {
    private struct SourceIntentClause: Sendable, Hashable {
        var sourceRefID: String
        var sourceKind: String
        var clauseID: String
    }

    private let workspaceStore: XcircuiteWorkspaceStore
    private let artifactStore: XcircuitePlanningArtifactStore
    private let artifactVerifier: LocalArtifactVerifier

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = artifactStore
        self.artifactVerifier = artifactVerifier
    }

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        actionDomainSnapshotBuilder: XcircuiteActionDomainSnapshotBuilder,
        artifactVerifier: LocalArtifactVerifier = LocalArtifactVerifier()
    ) {
        self.workspaceStore = workspaceStore
        self.artifactStore = XcircuitePlanningArtifactStore(
            workspaceStore: workspaceStore,
            snapshotBuilder: actionDomainSnapshotBuilder
        )
        self.artifactVerifier = artifactVerifier
    }

    public func auditProblemTranslation(
        request: XcircuiteProblemTranslationAuditRequest,
        projectRoot: URL
    ) async throws -> XcircuiteProblemTranslationAuditResult {
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
            throw XcircuiteProblemTranslationAuditError.runMismatch(
                expected: request.runID,
                actual: problem.runID
            )
        }

        let actionDomainSnapshot = try await loadOrPersistActionDomainSnapshot(
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let audit = makeAudit(
            problem: problem,
            problemPath: problemPath,
            actionDomainSnapshot: actionDomainSnapshot
        )
        let auditRef = try await artifactStore.persistProblemTranslationAudit(
            audit,
            runID: request.runID,
            projectRoot: projectRoot
        )
        return XcircuiteProblemTranslationAuditResult(
            status: audit.status,
            runID: request.runID,
            problemID: problem.problemID,
            problemPath: problemPath,
            audit: audit,
            auditArtifact: auditRef
        )
    }

    public func makeAudit(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String
    ) -> XcircuiteProblemTranslationAudit {
        makeAudit(
            problem: problem,
            problemPath: problemPath,
            actionDomainSnapshot: nil
        )
    }

    public func makeAudit(
        problem: XcircuiteCircuitPlanningProblem,
        problemPath: String,
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot?
    ) -> XcircuiteProblemTranslationAudit {
        let sourceByID = keyedByFirstID(problem.sourceRefs, id: \.refID)
        let objectivesByID = keyedByFirstID(problem.objectives, id: \.objectiveID)
        let operationsByDomain = operationsByDomain(from: actionDomainSnapshot)

        var edges: [XcircuiteProblemTranslationAuditEdge] = []
        edges.append(contentsOf: objectiveEdges(problem: problem, sourceByID: sourceByID))
        edges.append(contentsOf: constraintEdges(problem: problem, sourceByID: sourceByID))
        edges.append(contentsOf: candidateActionEdges(
            problem: problem,
            objectivesByID: objectivesByID,
            sourceByID: sourceByID
        ))
        edges.append(contentsOf: goalAtomEdges(problem: problem, sourceByID: sourceByID))
        edges.append(contentsOf: verificationGateEdges(
            problem: problem,
            objectivesByID: objectivesByID,
            sourceByID: sourceByID,
            operationsByDomain: operationsByDomain
        ))
        let intentClauseEdges = intentClauseEdges(
            problem: problem,
            objectivesByID: objectivesByID,
            sourceByID: sourceByID
        )
        edges.append(contentsOf: intentClauseEdges)
        edges = uniqueEdges(edges)

        let coveredSourceIDs = Set(edges.map(\.sourceRefID))
        let intentClauses = sourceIntentClauses(problem: problem)
        let coveredIntentClauseKeys = Set(intentClauseEdges.compactMap { edge in
            edge.intentClauseID.map { intentClauseKey(sourceRefID: edge.sourceRefID, clauseID: $0) }
        })
        let uncoveredSources = problem.sourceRefs
            .filter { !coveredSourceIDs.contains($0.refID) }
            .map {
                XcircuiteProblemTranslationAuditIssue(
                    id: $0.refID,
                    kind: $0.kind,
                    reason: "Source ref is not connected to any objective, constraint, candidate action, goal atom, or verification gate."
                )
            }
        let uncoveredIntentClauses = intentClauses
            .filter { !coveredIntentClauseKeys.contains(intentClauseKey(sourceRefID: $0.sourceRefID, clauseID: $0.clauseID)) }
            .map {
                XcircuiteProblemTranslationAuditIssue(
                    id: "\($0.sourceRefID):\($0.clauseID)",
                    kind: $0.sourceKind,
                    sourceRefID: $0.sourceRefID,
                    intentClauseID: $0.clauseID,
                    reason: "Source intent clause is not connected to any objective, constraint, or candidate action."
                )
            }
        let sourceDiagnosticCoverage = sourceDiagnosticCoverage(
            problem: problem,
            edges: edges
        )
        let undercoveredSourceDiagnostics = sourceDiagnosticCoverage
            .filter { $0.status != "covered" }
            .map {
                let missingTargets = $0.missingTargetKinds.joined(separator: ", ")
                return XcircuiteProblemTranslationAuditIssue(
                    id: $0.sourceRefID,
                    kind: $0.sourceKind,
                    sourceRefID: $0.sourceRefID,
                    reason: "Source diagnostic is not mapped to required target kinds: \(missingTargets)."
                )
            }
        let orphanObjectives = orphanObjectives(problem: problem, sourceByID: sourceByID)
        let orphanConstraints = orphanConstraints(problem: problem, sourceByID: sourceByID)
        let orphanActions = orphanCandidateActions(
            problem: problem,
            objectivesByID: objectivesByID,
            sourceByID: sourceByID
        )
        let goalAtoms = objectiveGoalAtoms(problem: problem)
        let orphanGoalAtoms = orphanGoalAtoms(problem: problem, sourceByID: sourceByID)
        let unsupportedGoalAtoms = unsupportedGoalAtoms(
            problem: problem,
            operationsByDomain: operationsByDomain
        )

        let diagnostics = diagnostics(
            uncoveredSources: uncoveredSources,
            uncoveredIntentClauses: uncoveredIntentClauses,
            undercoveredSourceDiagnostics: undercoveredSourceDiagnostics,
            orphanObjectives: orphanObjectives,
            orphanConstraints: orphanConstraints,
            orphanCandidateActions: orphanActions,
            orphanGoalAtoms: orphanGoalAtoms,
            unsupportedGoalAtoms: unsupportedGoalAtoms
        )
        let blocking = diagnostics.contains { $0.severity == "error" }
        let status: String
        if blocking {
            status = "failed"
        } else if diagnostics.contains(where: { $0.severity == "warning" }) {
            status = "passed-with-warnings"
        } else {
            status = "passed"
        }

        return XcircuiteProblemTranslationAudit(
            status: status,
            runID: problem.runID,
            problemID: problem.problemID,
            problemPath: problemPath,
            sourceRefs: problem.sourceRefs,
            translationEdges: edges,
            sourceDiagnosticCoverage: sourceDiagnosticCoverage,
            coverageSummary: XcircuiteProblemTranslationAuditCoverageSummary(
                sourceRefCount: problem.sourceRefs.count,
                coveredSourceRefCount: coveredSourceIDs.count,
                uncoveredSourceRefCount: uncoveredSources.count,
                intentClauseCount: intentClauses.count,
                uncoveredIntentClauseCount: uncoveredIntentClauses.count,
                objectiveCount: problem.objectives.count,
                orphanObjectiveCount: orphanObjectives.count,
                constraintCount: problem.constraints.count,
                orphanConstraintCount: orphanConstraints.count,
                candidateActionCount: problem.candidateActions.count,
                orphanCandidateActionCount: orphanActions.count,
                goalAtomCount: goalAtoms.count,
                orphanGoalAtomCount: orphanGoalAtoms.count,
                unsupportedGoalAtomCount: unsupportedGoalAtoms.count,
                translationEdgeCount: edges.count,
                sourceDiagnosticRefCount: sourceDiagnosticCoverage.count,
                fullyCoveredSourceDiagnosticCount: sourceDiagnosticCoverage.filter { $0.status == "covered" }.count,
                undercoveredSourceDiagnosticCount: undercoveredSourceDiagnostics.count
            ),
            uncoveredSources: uncoveredSources,
            uncoveredIntentClauses: uncoveredIntentClauses,
            undercoveredSourceDiagnostics: undercoveredSourceDiagnostics,
            orphanObjectives: orphanObjectives,
            orphanConstraints: orphanConstraints,
            orphanCandidateActions: orphanActions,
            orphanGoalAtoms: orphanGoalAtoms,
            unsupportedGoalAtoms: unsupportedGoalAtoms,
            diagnostics: diagnostics,
            blocking: blocking,
            nextActions: nextActions(blocking: blocking, diagnostics: diagnostics)
        )
    }

    private func objectiveEdges(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        problem.objectives.flatMap { objective in
            objective.sourceRefIDs.compactMap { sourceRefID in
                guard let source = sourceByID[sourceRefID] else {
                    return nil
                }
                return edge(
                    source: source,
                    targetKind: "objective",
                    targetID: objective.objectiveID,
                    relation: "source-to-objective"
                )
            }
        }
    }

    private func constraintEdges(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        problem.constraints.flatMap { constraint in
            constraint.sourceRefIDs.compactMap { sourceRefID in
                guard let source = sourceByID[sourceRefID] else {
                    return nil
                }
                return edge(
                    source: source,
                    targetKind: "constraint",
                    targetID: constraint.constraintID,
                    relation: "source-to-constraint"
                )
            }
        }
    }

    private func candidateActionEdges(
        problem: XcircuiteCircuitPlanningProblem,
        objectivesByID: [String: XcircuitePlanningObjective],
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        problem.candidateActions.flatMap { action in
            action.sourceObjectiveIDs.flatMap { objectiveID in
                guard let objective = objectivesByID[objectiveID] else {
                    return [XcircuiteProblemTranslationAuditEdge]()
                }
                return objective.sourceRefIDs.compactMap { sourceRefID in
                    guard let source = sourceByID[sourceRefID] else {
                        return nil
                    }
                    return edge(
                        source: source,
                        targetKind: "candidate-action",
                        targetID: action.actionID,
                        relation: "source-objective-to-action"
                    )
                }
            }
        }
    }

    private func goalAtomEdges(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        problem.objectives.flatMap { objective in
            let atoms = symbolicGoalAtoms(for: objective)
            return objective.sourceRefIDs.flatMap { sourceRefID in
                guard let source = sourceByID[sourceRefID] else {
                    return [XcircuiteProblemTranslationAuditEdge]()
                }
                return atoms.map { atom in
                    edge(
                        source: source,
                        targetKind: "goal-atom",
                        targetID: atom,
                        relation: "source-objective-to-goal-atom"
                    )
                }
            }
        }
    }

    private func verificationGateEdges(
        problem: XcircuiteCircuitPlanningProblem,
        objectivesByID: [String: XcircuitePlanningObjective],
        sourceByID: [String: XcircuitePlanningReference],
        operationsByDomain: [String: [String: XcircuiteActionDomainOperation]]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        let problemGateIDs = Set(problem.verificationGates.map(\.gateID))
        return problem.candidateActions.flatMap { action in
            let operationGateIDs = Set(
                operationsByDomain[action.domainID]?[action.operationID]?.verificationGates ?? []
            )
            let acceptedGateIDs = problemGateIDs.union(operationGateIDs)
            return action.verificationGates.filter { acceptedGateIDs.contains($0) }.flatMap { gateID in
                action.sourceObjectiveIDs.flatMap { objectiveID in
                    guard let objective = objectivesByID[objectiveID] else {
                        return [XcircuiteProblemTranslationAuditEdge]()
                    }
                    return objective.sourceRefIDs.compactMap { sourceRefID in
                        guard let source = sourceByID[sourceRefID] else {
                            return nil
                        }
                        return edge(
                            source: source,
                            targetKind: "verification-gate",
                            targetID: gateID,
                            relation: "source-objective-action-to-gate"
                        )
                    }
                }
            }
        }
    }

    private func intentClauseEdges(
        problem: XcircuiteCircuitPlanningProblem,
        objectivesByID: [String: XcircuitePlanningObjective],
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        let clausesBySourceRefID = intentClausesBySourceRefID(problem: problem)
        let objectiveEdges = problem.objectives.flatMap { objective in
            intentClauseEdges(
                sourceRefIDs: objective.sourceRefIDs,
                declaredClauseIDs: intentClauseIDs(in: objective.evidence),
                sourceByID: sourceByID,
                clausesBySourceRefID: clausesBySourceRefID,
                targetKind: "objective",
                targetID: objective.objectiveID,
                relation: "source-intent-clause-to-objective"
            )
        }
        let constraintEdges = problem.constraints.flatMap { constraint in
            intentClauseEdges(
                sourceRefIDs: constraint.sourceRefIDs,
                declaredClauseIDs: intentClauseIDs(in: constraint.evidence),
                sourceByID: sourceByID,
                clausesBySourceRefID: clausesBySourceRefID,
                targetKind: "constraint",
                targetID: constraint.constraintID,
                relation: "source-intent-clause-to-constraint"
            )
        }
        let actionEdges = problem.candidateActions.flatMap { action in
            let sourceRefIDs = unique(action.sourceObjectiveIDs.flatMap { objectiveID in
                objectivesByID[objectiveID]?.sourceRefIDs ?? []
            })
            return intentClauseEdges(
                sourceRefIDs: sourceRefIDs,
                declaredClauseIDs: intentClauseIDs(in: action.parameterHints),
                sourceByID: sourceByID,
                clausesBySourceRefID: clausesBySourceRefID,
                targetKind: "candidate-action",
                targetID: action.actionID,
                relation: "source-intent-clause-to-candidate-action"
            )
        }
        return objectiveEdges + constraintEdges + actionEdges
    }

    private func intentClauseEdges(
        sourceRefIDs: [String],
        declaredClauseIDs: [String],
        sourceByID: [String: XcircuitePlanningReference],
        clausesBySourceRefID: [String: Set<String>],
        targetKind: String,
        targetID: String,
        relation: String
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        sourceRefIDs.flatMap { sourceRefID in
            guard let source = sourceByID[sourceRefID],
                  let sourceClauseIDs = clausesBySourceRefID[sourceRefID],
                  !sourceClauseIDs.isEmpty else {
                return [XcircuiteProblemTranslationAuditEdge]()
            }
            return declaredClauseIDs.filter { sourceClauseIDs.contains($0) }.map { clauseID in
                edge(
                    source: source,
                    intentClauseID: clauseID,
                    targetKind: targetKind,
                    targetID: targetID,
                    relation: relation
                )
            }
        }
    }

    private func sourceDiagnosticCoverage(
        problem: XcircuiteCircuitPlanningProblem,
        edges: [XcircuiteProblemTranslationAuditEdge]
    ) -> [XcircuiteProblemTranslationSourceDiagnosticCoverage] {
        let edgesBySourceID = Dictionary(grouping: edges) { $0.sourceRefID }
        return problem.sourceRefs
            .filter(isSourceDiagnostic)
            .map { source in
                let sourceEdges = edgesBySourceID[source.refID, default: []]
                let objectiveIDs = targetIDs(kind: "objective", edges: sourceEdges)
                let constraintIDs = targetIDs(kind: "constraint", edges: sourceEdges)
                let candidateActionIDs = targetIDs(kind: "candidate-action", edges: sourceEdges)
                let verificationGateIDs = targetIDs(kind: "verification-gate", edges: sourceEdges)
                var missingTargetKinds: [String] = []
                if objectiveIDs.isEmpty {
                    missingTargetKinds.append("objective")
                }
                if constraintIDs.isEmpty {
                    missingTargetKinds.append("constraint")
                }
                if candidateActionIDs.isEmpty {
                    missingTargetKinds.append("candidate-action")
                }
                if verificationGateIDs.isEmpty {
                    missingTargetKinds.append("verification-gate")
                }
                return XcircuiteProblemTranslationSourceDiagnosticCoverage(
                    sourceRefID: source.refID,
                    sourceKind: source.kind,
                    status: missingTargetKinds.isEmpty ? "covered" : "undercovered",
                    objectiveIDs: objectiveIDs,
                    constraintIDs: constraintIDs,
                    candidateActionIDs: candidateActionIDs,
                    verificationGateIDs: verificationGateIDs,
                    missingTargetKinds: missingTargetKinds
                )
            }
    }

    private func targetIDs(
        kind: String,
        edges: [XcircuiteProblemTranslationAuditEdge]
    ) -> [String] {
        unique(edges.filter { $0.targetKind == kind }.map(\.targetID)).sorted()
    }

    private func isSourceDiagnostic(_ reference: XcircuitePlanningReference) -> Bool {
        let kind = reference.kind.lowercased()
        if nonDiagnosticReferenceKinds.contains(kind) {
            return false
        }
        let artifactID = reference.artifactID?.lowercased() ?? ""
        let path = reference.path?.lowercased() ?? ""
        let searchable = "\(kind) \(artifactID) \(path)"
        if searchable.contains("diagnostic")
            || searchable.contains("summary")
            || searchable.contains("report")
            || searchable.contains("simulation")
            || searchable.contains("metric")
            || searchable.contains("post-layout")
            || searchable.contains("repair-hint") {
            return true
        }
        if kind.hasPrefix("drc-")
            || kind.hasPrefix("lvs-")
            || kind.hasPrefix("pex-") {
            return true
        }
        return reference.metadata.keys.contains {
            let key = $0.lowercased()
            return key == "diagnosticcodes"
                || key == "sourcediagnosticids"
        }
    }

    private var nonDiagnosticReferenceKinds: Set<String> {
        [
            "action-domain-snapshot",
            "layout",
            "layout-netlist",
            "schematic-netlist",
            "source-netlist",
            "technology",
            "pex-technology",
        ]
    }

    private func orphanObjectives(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditIssue] {
        problem.objectives.compactMap { objective in
            let validSources = objective.sourceRefIDs.filter { sourceByID[$0] != nil }
            guard validSources.isEmpty else {
                return nil
            }
            return XcircuiteProblemTranslationAuditIssue(
                id: objective.objectiveID,
                kind: objective.domain,
                reason: "Objective has no valid source ref."
            )
        }
    }

    private func orphanConstraints(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditIssue] {
        problem.constraints.compactMap { constraint in
            let validSources = constraint.sourceRefIDs.filter { sourceByID[$0] != nil }
            guard validSources.isEmpty else {
                return nil
            }
            return XcircuiteProblemTranslationAuditIssue(
                id: constraint.constraintID,
                kind: constraint.kind,
                reason: "Constraint has no valid source ref."
            )
        }
    }

    private func orphanCandidateActions(
        problem: XcircuiteCircuitPlanningProblem,
        objectivesByID: [String: XcircuitePlanningObjective],
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditIssue] {
        problem.candidateActions.compactMap { action in
            let sourceIDs = action.sourceObjectiveIDs.flatMap { objectiveID -> [String] in
                guard let objective = objectivesByID[objectiveID] else {
                    return []
                }
                return objective.sourceRefIDs
            }
            let validSources = sourceIDs.filter { sourceByID[$0] != nil }
            guard validSources.isEmpty else {
                return nil
            }
            return XcircuiteProblemTranslationAuditIssue(
                id: action.actionID,
                kind: action.operationID,
                reason: "Candidate action has no valid source objective with a source ref."
            )
        }
    }

    private func objectiveGoalAtoms(
        problem: XcircuiteCircuitPlanningProblem
    ) -> [(objective: XcircuitePlanningObjective, atom: String)] {
        problem.objectives.flatMap { objective in
            symbolicGoalAtoms(for: objective).map { atom in
                (objective: objective, atom: atom)
            }
        }
    }

    private func orphanGoalAtoms(
        problem: XcircuiteCircuitPlanningProblem,
        sourceByID: [String: XcircuitePlanningReference]
    ) -> [XcircuiteProblemTranslationAuditIssue] {
        objectiveGoalAtoms(problem: problem).compactMap { item in
            let validSources = item.objective.sourceRefIDs.filter { sourceByID[$0] != nil }
            guard validSources.isEmpty else {
                return nil
            }
            return XcircuiteProblemTranslationAuditIssue(
                id: item.atom,
                kind: item.objective.objectiveID,
                reason: "Goal atom belongs to an objective without a valid source ref."
            )
        }
    }

    private func unsupportedGoalAtoms(
        problem: XcircuiteCircuitPlanningProblem,
        operationsByDomain: [String: [String: XcircuiteActionDomainOperation]]
    ) -> [XcircuiteProblemTranslationAuditIssue] {
        let initialAtoms = Set(initialSymbolicState(for: problem))
        let actionsByObjectiveID = Dictionary(grouping: problem.candidateActions.flatMap { action in
            action.sourceObjectiveIDs.map { objectiveID in
                (objectiveID: objectiveID, action: action)
            }
        }) { $0.objectiveID }

        return objectiveGoalAtoms(problem: problem).compactMap { item in
            if initialAtoms.contains(item.atom) {
                return nil
            }
            let actions = actionsByObjectiveID[item.objective.objectiveID]?.map(\.action) ?? []
            let candidateAtoms = Set(actions.flatMap {
                candidateEffectAtoms(for: $0, operationsByDomain: operationsByDomain)
            })
            guard candidateAtoms.contains(item.atom) == false else {
                return nil
            }
            return XcircuiteProblemTranslationAuditIssue(
                id: item.atom,
                kind: item.objective.objectiveID,
                reason: "Goal atom is not produced by the objective candidate actions or current symbolic state."
            )
        }
    }

    private func diagnostics(
        uncoveredSources: [XcircuiteProblemTranslationAuditIssue],
        uncoveredIntentClauses: [XcircuiteProblemTranslationAuditIssue],
        undercoveredSourceDiagnostics: [XcircuiteProblemTranslationAuditIssue],
        orphanObjectives: [XcircuiteProblemTranslationAuditIssue],
        orphanConstraints: [XcircuiteProblemTranslationAuditIssue],
        orphanCandidateActions: [XcircuiteProblemTranslationAuditIssue],
        orphanGoalAtoms: [XcircuiteProblemTranslationAuditIssue],
        unsupportedGoalAtoms: [XcircuiteProblemTranslationAuditIssue]
    ) -> [XcircuiteProblemTranslationAuditDiagnostic] {
        uncoveredSources.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "source-ref-uncovered",
                message: "Source ref \($0.id) is not translated into the planning problem.",
                sourceRefID: $0.id,
                nextActions: ["map-source-ref-to-objective-or-constraint"]
            )
        } + uncoveredIntentClauses.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "intent-clause-uncovered",
                message: "Source intent clause \($0.intentClauseID ?? $0.id) from \($0.sourceRefID ?? $0.id) is not translated into the planning problem.",
                sourceRefID: $0.sourceRefID,
                intentClauseID: $0.intentClauseID,
                nextActions: ["map-intent-clause-to-objective-constraint-or-action"]
            )
        } + undercoveredSourceDiagnostics.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "source-diagnostic-undercovered",
                message: $0.reason,
                sourceRefID: $0.sourceRefID,
                nextActions: ["map-source-diagnostic-to-objective-constraint-action-and-gate"]
            )
        } + orphanObjectives.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "orphan-objective",
                message: "Objective \($0.id) has no valid source ref.",
                objectiveID: $0.id,
                nextActions: ["attach-objective-source-ref"]
            )
        } + orphanConstraints.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "orphan-constraint",
                message: "Constraint \($0.id) has no valid source ref.",
                constraintID: $0.id,
                nextActions: ["attach-constraint-source-ref"]
            )
        } + orphanCandidateActions.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "orphan-candidate-action",
                message: "Candidate action \($0.id) has no valid source objective.",
                actionID: $0.id,
                nextActions: ["attach-action-source-objective"]
            )
        } + orphanGoalAtoms.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "orphan-goal-atom",
                message: "Goal atom \($0.id) has no valid source objective.",
                goalAtom: $0.id,
                nextActions: ["attach-goal-atom-source-objective"]
            )
        } + unsupportedGoalAtoms.map {
            XcircuiteProblemTranslationAuditDiagnostic(
                severity: "error",
                code: "unsupported-goal-atom",
                message: "Goal atom \($0.id) is not produced by the objective candidate actions or current symbolic state.",
                objectiveID: $0.kind,
                goalAtom: $0.id,
                nextActions: ["add-candidate-action-effect-for-goal-atom"]
            )
        }
    }

    private func nextActions(
        blocking: Bool,
        diagnostics: [XcircuiteProblemTranslationAuditDiagnostic]
    ) -> [String] {
        if !blocking {
            return ["validate-planning-problem"]
        }
        return unique(diagnostics.flatMap(\.nextActions) + ["regenerate-planning-problem"])
    }

    private func symbolicGoalAtoms(for objective: XcircuitePlanningObjective) -> [String] {
        unique(
            stringArrayValue(for: "symbolicGoalAtoms", in: objective.evidence)
                + stringArrayValue(for: "goalAtoms", in: objective.evidence)
                + stringArrayValue(for: "requiredEffects", in: objective.evidence)
        )
    }

    private func sourceIntentClauses(
        problem: XcircuiteCircuitPlanningProblem
    ) -> [SourceIntentClause] {
        problem.sourceRefs.flatMap { source in
            intentClauseIDs(in: source.metadata).map {
                SourceIntentClause(sourceRefID: source.refID, sourceKind: source.kind, clauseID: $0)
            }
        }
    }

    private func intentClausesBySourceRefID(
        problem: XcircuiteCircuitPlanningProblem
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for source in problem.sourceRefs where result[source.refID] == nil {
            result[source.refID] = Set(intentClauseIDs(in: source.metadata))
        }
        return result
    }

    private func intentClauseIDs(
        in values: [String: PlanningParameterValue]
    ) -> [String] {
        unique(
            stringArrayValue(for: "intentClauseIDs", in: values)
                + stringArrayValue(for: "requiredIntentClauseIDs", in: values)
                + stringArrayValue(for: "humanIntentClauseIDs", in: values)
                + stringArrayValue(for: "sourceIntentClauseIDs", in: values)
                + stringArrayValue(for: "coveredIntentClauseIDs", in: values)
        )
    }

    private func initialSymbolicState(for problem: XcircuiteCircuitPlanningProblem) -> [String] {
        unique(
            (problem.sourceRefs + problem.initialStateRefs).flatMap { reference in
                var atoms = ["ref:\(reference.refID)"]
                if let artifactID = reference.artifactID {
                    atoms.append("artifact:\(artifactID)")
                }
                atoms.append(contentsOf: stringArrayValue(for: "symbolicStateAtoms", in: reference.metadata))
                return atoms
            }
        )
    }

    private func candidateEffectAtoms(
        for action: XcircuitePlanningCandidateAction,
        operationsByDomain: [String: [String: XcircuiteActionDomainOperation]]
    ) -> [String] {
        let operation = operationsByDomain[action.domainID]?[action.operationID]
        return unique(
            (operation?.effects ?? [])
                + (operation?.producedArtifacts.map { "artifact:\($0)" } ?? [])
                + stringArrayValue(for: "symbolicEffects", in: action.parameterHints)
                + stringArrayValue(for: "satisfiesGoalAtoms", in: action.parameterHints)
                + stringArrayValue(for: "producedGoalAtoms", in: action.parameterHints)
        )
    }

    private func operationsByDomain(
        from snapshot: XcircuitePlanningActionDomainSnapshot?
    ) -> [String: [String: XcircuiteActionDomainOperation]] {
        guard let snapshot else {
            return [:]
        }
        var result: [String: [String: XcircuiteActionDomainOperation]] = [:]
        for domain in snapshot.domains {
            result[domain.domainID] = keyedByFirstID(domain.operations, id: \.operationID)
        }
        return result
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

    private func edge(
        source: XcircuitePlanningReference,
        intentClauseID: String? = nil,
        targetKind: String,
        targetID: String,
        relation: String
    ) -> XcircuiteProblemTranslationAuditEdge {
        XcircuiteProblemTranslationAuditEdge(
            sourceRefID: source.refID,
            sourceKind: source.kind,
            intentClauseID: intentClauseID,
            targetKind: targetKind,
            targetID: targetID,
            relation: relation
        )
    }

    private func uniqueEdges(
        _ edges: [XcircuiteProblemTranslationAuditEdge]
    ) -> [XcircuiteProblemTranslationAuditEdge] {
        var seen: Set<XcircuiteProblemTranslationAuditEdge> = []
        var result: [XcircuiteProblemTranslationAuditEdge] = []
        for edge in edges where !seen.contains(edge) {
            seen.insert(edge)
            result.append(edge)
        }
        return result
    }

    private func intentClauseKey(sourceRefID: String, clauseID: String) -> String {
        "\(sourceRefID):\(clauseID)"
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

    private func keyedByFirstID<Value>(
        _ values: [Value],
        id: (Value) -> String
    ) -> [String: Value] {
        var result: [String: Value] = [:]
        for value in values where result[id(value)] == nil {
            result[id(value)] = value
        }
        return result
    }

    private func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        return try await workspaceStore.loadRunManifest(runID: runID)
    }

    private func loadOrPersistActionDomainSnapshot(
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> XcircuitePlanningActionDomainSnapshot {
        try await XcircuiteActionDomainSnapshotResolver(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).loadDefaultOrPersist(
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ).snapshot
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
            throw XcircuiteProblemTranslationAuditError.missingProblemReference
        }
        guard let reference = try verifiedManifestProblemReference(
            artifactID: artifactID,
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        ) else {
            throw XcircuiteProblemTranslationAuditError.artifactNotFound(
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
            throw XcircuiteProblemTranslationAuditError.invalidArtifactReference(
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
            throw XcircuiteProblemTranslationAuditError.invalidArtifactReference(
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
            throw XcircuiteProblemTranslationAuditError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuiteProblemTranslationAuditError.invalidArtifactReference(
                path: reference.path,
                reason: "planning problems must be JSON artifacts."
            )
        }
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteProblemTranslationAuditError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }

    private static func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
