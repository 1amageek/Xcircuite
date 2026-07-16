import Foundation
import CircuiteFoundation
import DesignFlowKernel

extension XcircuiteCandidatePlanGenerator {
    func makeCandidatePlanBuild(
        request: XcircuiteCandidatePlanGenerationRequest,
        projectRoot: URL
    ) async throws -> CandidatePlanBuild {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        let manifest = try await loadRunManifest(runID: request.runID)
        let problemPath = try requiredPath(
            explicitPath: request.problemPath,
            artifactID: request.problemArtifactID ?? XcircuitePlanningArtifactStore.problemArtifactID,
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let problem = try JSONDecoder().decode(
            XcircuiteCircuitPlanningProblem.self,
            from: Data(contentsOf: projectURL(for: problemPath, projectRoot: projectRoot))
        )
        guard problem.runID == request.runID else {
            throw XcircuiteCandidatePlanGenerationError.runMismatch(
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
        let policySelection = try selectPolicy(
            request: request,
            manifest: manifest,
            projectRoot: projectRoot
        )
        var effectiveRequest = request
        effectiveRequest.strategy = policySelection.strategy
        effectiveRequest.metricThresholdProfileArtifactID = policySelection.trace.metricThresholdProfileArtifact?.artifactID
            ?? effectiveRequest.metricThresholdProfileArtifactID
        effectiveRequest.metricThresholdProfilePath = policySelection.trace.metricThresholdProfileArtifact?.path
            ?? effectiveRequest.metricThresholdProfilePath
        effectiveRequest.costCalibrationArtifactID = policySelection.trace.costCalibrationArtifact?.artifactID
            ?? effectiveRequest.costCalibrationArtifactID
        effectiveRequest.costCalibrationPath = policySelection.trace.costCalibrationArtifact?.path
            ?? effectiveRequest.costCalibrationPath
        effectiveRequest.paretoCandidatesArtifactID = policySelection.trace.paretoCandidatesArtifact?.artifactID
            ?? effectiveRequest.paretoCandidatesArtifactID
        effectiveRequest.paretoCandidatesPath = policySelection.trace.paretoCandidatesArtifact?.path
            ?? effectiveRequest.paretoCandidatesPath
        let actionDomainContext = try await loadOrPersistActionDomainSnapshot(
            manifest: manifest,
            runID: request.runID,
            projectRoot: projectRoot
        )
        let feedbackSummary = try loadRejectedPlanFeedback(
            request: effectiveRequest,
            manifest: manifest,
            projectRoot: projectRoot
        )
        let calibrationContext = try loadCalibrationContext(
            request: effectiveRequest,
            manifest: manifest,
            projectRoot: projectRoot
        )

        let draft = try makeCandidatePlanDraft(
            problem: problem,
            problemPath: problemPath,
            strategy: effectiveRequest.strategy,
            actionDomainSnapshot: actionDomainContext.snapshot,
            actionDomainSnapshotRef: actionDomainContext.reference,
            rejectedPlanFeedback: feedbackSummary,
            calibrationContext: calibrationContext,
            policyTrace: policySelection.trace
        )
        return CandidatePlanBuild(
            problem: problem,
            problemPath: problemPath,
            draft: draft,
            problemTranslationAuditArtifact: translationAuditResult.auditArtifact,
            actionDomainSnapshotArtifact: actionDomainContext.reference
        )
    }

    func validateFamilyRequest(_ request: XcircuiteSymbolicPlannerFamilyRunRequest) throws {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        do {
            try FlowIdentifierValidator().validate(request.familyRunID, kind: .artifactID)
        } catch {
            throw XcircuiteCandidatePlanGenerationError.invalidPlannerFamilyRunID(request.familyRunID)
        }
        guard !request.strategies.isEmpty else {
            throw XcircuiteCandidatePlanGenerationError.emptyStrategyFamily
        }
        guard request.selectionPolicy == "prefer-ready-then-goal-coverage-then-score" else {
            throw XcircuiteCandidatePlanGenerationError.unsupportedPlannerFamilySelectionPolicy(request.selectionPolicy)
        }
    }

    func rejectExistingFamilyRunOutputs(
        request: XcircuiteSymbolicPlannerFamilyRunRequest,
        projectRoot: URL
    ) async throws {
        let familyPathPrefix = symbolicPlannerFamilyPathPrefix(
            runID: request.runID,
            familyRunID: request.familyRunID
        )
        let manifest = try await loadRunManifest(runID: request.runID)
        if manifest.artifacts.contains(where: { $0.path.hasPrefix(familyPathPrefix) }) {
            throw XcircuiteCandidatePlanGenerationError.familyRunAlreadyExists(
                runID: request.runID,
                familyRunID: request.familyRunID,
                path: familyPathPrefix
            )
        }

        let familyDirectory = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .runDirectoryURL(for: request.runID)
            .appending(path: "planning")
            .appending(path: "symbolic-planner")
            .appending(path: "family")
            .appending(path: request.familyRunID)
        let filesystemPath = familyDirectory.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filesystemPath, isDirectory: &isDirectory) else {
            return
        }
        guard isDirectory.boolValue else {
            throw XcircuiteCandidatePlanGenerationError.familyRunAlreadyExists(
                runID: request.runID,
                familyRunID: request.familyRunID,
                path: familyPathPrefix
            )
        }

        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: filesystemPath)
        } catch {
            throw XcircuiteCandidatePlanGenerationError.familyRunOutputInspectionFailed(
                path: familyPathPrefix,
                reason: error.localizedDescription
            )
        }
        guard contents.isEmpty else {
            throw XcircuiteCandidatePlanGenerationError.familyRunAlreadyExists(
                runID: request.runID,
                familyRunID: request.familyRunID,
                path: familyPathPrefix
            )
        }
    }

    func persistFamilyCandidateArtifacts(
        build: CandidatePlanBuild,
        requestedStrategy: String,
        candidateIndex: Int,
        familyRunID: String,
        projectRoot: URL
    ) async throws -> FamilyCandidateArtifacts {
        let slotID = familyCandidateSlotID(index: candidateIndex, strategy: requestedStrategy)
        let basePath = symbolicPlannerFamilyPathPrefix(
            runID: build.problem.runID,
            familyRunID: familyRunID
        ) + "candidates/\(slotID)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let planArtifact = try await workspaceStore.persistArtifact(
            content: encoder.encode(build.draft.plan),
            id: ArtifactID(rawValue: familyCandidateArtifactID(
                prefix: "planning-symbolic-planner-family-candidate-plan",
                familyRunID: familyRunID,
                slotID: slotID
            )),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "\(basePath)/candidate-plan.json"),
                role: .output,
                kind: .other,
                format: .json
            ),
            runID: build.problem.runID,
            mode: .immutable
        )
        let traceArtifact = try await workspaceStore.persistArtifact(
            content: encoder.encode(build.draft.trace),
            id: ArtifactID(rawValue: familyCandidateArtifactID(
                prefix: "planning-symbolic-planner-family-candidate-trace",
                familyRunID: familyRunID,
                slotID: slotID
            )),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "\(basePath)/symbolic-planner-trace.json"),
                role: .output,
                kind: .other,
                format: .json
            ),
            runID: build.problem.runID,
            mode: .immutable
        )
        return FamilyCandidateArtifacts(plan: planArtifact, trace: traceArtifact)
    }

    func familySelectionScoreComponents(
        plan: XcircuiteCandidatePlan,
        trace: XcircuiteSymbolicPlannerTrace,
        candidateIndex: Int
    ) -> [XcircuiteSymbolicPlannerFamilySelectionScoreComponent] {
        var components: [XcircuiteSymbolicPlannerFamilySelectionScoreComponent] = []
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "readiness.\(plan.executionReadiness)",
                contribution: readinessContribution(plan.executionReadiness),
                reason: "Prefer candidate plans that are executable without unresolved blockers."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "goal-coverage.\(trace.goalCoverageStatus)",
                contribution: goalCoverageContribution(trace.goalCoverageStatus),
                reason: "Prefer plans whose final symbolic state covers declared objective goals."
            )
        )
        if trace.policyTrace?.usesCalibrationArtifacts == true {
            components.append(
                XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                    termID: "cp7.policy-artifacts-used",
                    contribution: 250,
                    reason: "Prefer strategies that applied CP7 feedback artifacts when calibration is enabled."
                )
            )
        }
        let selectedActionScore = selectedActionScore(from: trace)
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "selected-action-score",
                contribution: selectedActionScore,
                reason: "Use the symbolic planner action score as a secondary quality signal."
            )
        )
        let unresolvedPenalty = -100 * trace.unresolvedObjectiveIDs.count
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "unresolved-objectives",
                contribution: unresolvedPenalty,
                reason: "Demote plans that leave objectives unresolved."
            )
        )
        let missingGoalPenalty = -50 * trace.missingGoalAtoms.count
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "missing-goal-atoms",
                contribution: missingGoalPenalty,
                reason: "Demote plans with missing explicit goal atoms."
            )
        )
        let hardBlockerPenalty = -100 * plan.blockers.filter { isHardBlocker($0) }.count
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "hard-blockers",
                contribution: hardBlockerPenalty,
                reason: "Demote plans that carry hard blockers."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "step-count",
                contribution: -plan.steps.count,
                reason: "Prefer shorter plans after readiness and coverage are equal."
            )
        )
        components.append(
            XcircuiteSymbolicPlannerFamilySelectionScoreComponent(
                termID: "strategy-order",
                contribution: -candidateIndex,
                reason: "Use request order only as a deterministic tie breaker."
            )
        )
        return components
    }

    func selectedFamilyCandidate(
        _ candidates: [FamilyCandidateBuild],
        selectionPolicy: String
    ) throws -> FamilyCandidateBuild {
        guard selectionPolicy == "prefer-ready-then-goal-coverage-then-score" else {
            throw XcircuiteCandidatePlanGenerationError.unsupportedPlannerFamilySelectionPolicy(selectionPolicy)
        }
        guard let selected = candidates.max(by: { lhs, rhs in
            if lhs.selectionScore != rhs.selectionScore {
                return lhs.selectionScore < rhs.selectionScore
            }
            return lhs.candidateIndex > rhs.candidateIndex
        }) else {
            throw XcircuiteCandidatePlanGenerationError.emptyStrategyFamily
        }
        return selected
    }

    func familyCandidateResult(
        from candidate: FamilyCandidateBuild,
        selectedCandidateIndex: Int
    ) throws -> XcircuiteSymbolicPlannerFamilyCandidateResult {
        XcircuiteSymbolicPlannerFamilyCandidateResult(
            candidateIndex: candidate.candidateIndex,
            requestedStrategy: candidate.requestedStrategy,
            effectiveStrategy: candidate.build.draft.trace.strategy,
            status: "generated",
            selected: candidate.candidateIndex == selectedCandidateIndex,
            selectionScore: candidate.selectionScore,
            scoreComponents: candidate.scoreComponents,
            planID: candidate.build.draft.plan.planID,
            executionReadiness: candidate.build.draft.plan.executionReadiness,
            goalCoverageStatus: candidate.build.draft.trace.goalCoverageStatus,
            selectedActionIDs: candidate.build.draft.trace.selectedActionIDs,
            unresolvedObjectiveIDs: candidate.build.draft.trace.unresolvedObjectiveIDs,
            missingGoalAtoms: candidate.build.draft.trace.missingGoalAtoms,
            blockers: candidate.build.draft.plan.blockers,
            candidatePlanArtifact: candidate.candidatePlanArtifact,
            symbolicPlannerTraceArtifact: candidate.symbolicPlannerTraceArtifact,
            policyTrace: candidate.build.draft.trace.policyTrace,
            calibrationTrace: candidate.build.draft.trace.calibrationTrace
        )
    }

    func readinessContribution(_ readiness: String) -> Int {
        switch readiness {
        case "ready":
            return 10_000
        case "requires-implementation":
            return 1_000
        default:
            return 0
        }
    }

    func goalCoverageContribution(_ status: String) -> Int {
        switch status {
        case "covered":
            return 5_000
        case "partial":
            return 1_000
        case "missing":
            return -1_000
        default:
            return 0
        }
    }

    func selectedActionScore(from trace: XcircuiteSymbolicPlannerTrace) -> Int {
        trace.objectiveTraces.reduce(0) { total, objectiveTrace in
            let selectedAction = objectiveTrace.candidateActions.first { $0.selected }
            return total + (selectedAction?.score ?? 0)
        }
    }

    func familyDiagnostics(
        from candidates: [XcircuiteSymbolicPlannerFamilyCandidateResult]
    ) -> [String] {
        let blockedCount = candidates.filter { $0.executionReadiness == "blocked" }.count
        guard blockedCount > 0 else {
            return []
        }
        return ["\(blockedCount) symbolic planner family candidate(s) were blocked."]
    }

    func familyCandidateSlotID(index: Int, strategy: String) -> String {
        "\(index + 1)-\(artifactSlug(from: strategy, limit: 72))"
    }

    func symbolicPlannerFamilyPathPrefix(runID: String, familyRunID: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/runs/\(runID)/planning/symbolic-planner/family/\(familyRunID)/"
    }

    func familyCandidateArtifactID(prefix: String, familyRunID: String, slotID: String) -> String {
        let familyToken = [
            artifactSlug(from: familyRunID, limit: 16),
            artifactDigest(from: familyRunID, limit: 12),
        ].joined(separator: "-")
        let slotToken = [
            artifactSlug(from: slotID, limit: 32),
            artifactDigest(from: slotID, limit: 8),
        ].joined(separator: "-")
        return "\(prefix)-\(familyToken)-\(slotToken)"
    }

    func artifactDigest(from value: String, limit: Int) -> String {
        let derivedID = ArtifactID(stableKey: value).rawValue
        return String(derivedID.dropFirst("derived-".count).prefix(limit))
    }

    func artifactSlug(from value: String, limit: Int) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append("-")
            }
            if scalars.count >= limit {
                break
            }
        }
        let slug = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return slug.isEmpty ? "strategy" : slug
    }
}
