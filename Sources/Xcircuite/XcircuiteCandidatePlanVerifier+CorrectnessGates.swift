import Foundation
import CircuiteFoundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func makeCorrectnessGateResults(
        plan: XcircuiteCandidatePlan,
        verificationMode: String,
        planningProblem: XcircuiteCircuitPlanningProblem?,
        planningProblemValidationArtifact: ArtifactReference?,
        actionDomainSnapshotArtifact: ArtifactReference?,
        stepResults: [XcircuitePlanVerificationStepResult],
        gateResults: [XcircuitePlanVerificationGateResult],
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage],
        artifactReferences: [ArtifactReference],
        diagnostics: [XcircuitePlanVerificationDiagnostic],
        accepted: Bool,
        nextActions: [String]
    ) -> [XcircuitePlanningCorrectnessGateResult] {
        [
            problemValidationCorrectnessGate(
                planningProblem: planningProblem,
                planningProblemValidationArtifact: planningProblemValidationArtifact
            ),
            actionDomainBindingCorrectnessGate(
                actionDomainSnapshotArtifact: actionDomainSnapshotArtifact,
                stepResults: stepResults
            ),
            plannerReplayCorrectnessGate(
                stepResults: stepResults,
                goalCoverage: goalCoverage,
                diagnostics: diagnostics
            ),
            postExecutionSignoffCorrectnessGate(
                verificationMode: verificationMode,
                gateResults: gateResults,
                artifactReferences: artifactReferences
            ),
            feedbackClosureCorrectnessGate(
                plan: plan,
                stepResults: stepResults,
                gateResults: gateResults,
                goalCoverage: goalCoverage,
                accepted: accepted,
                nextActions: nextActions
            ),
        ]
    }

    func problemValidationCorrectnessGate(
        planningProblem: XcircuiteCircuitPlanningProblem?,
        planningProblemValidationArtifact: ArtifactReference?
    ) -> XcircuitePlanningCorrectnessGateResult {
        if let planningProblemValidationArtifact {
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "problem-validation",
                status: "passed",
                summary: "Translated planning problem has a persisted validation artifact.",
                evidenceArtifactIDs: artifactIDs([planningProblemValidationArtifact])
            )
        }
        if planningProblem != nil {
            let diagnostic = correctnessGateDiagnostic(
                severity: "warning",
                code: "planning-problem-validation-missing",
                message: "Plan verification loaded a planning problem, but planning/problem-validation.json was not registered in the run manifest."
            )
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "problem-validation",
                status: "not-evaluated",
                summary: "Planning problem exists, but validation evidence is missing.",
                evidenceArtifactIDs: [XcircuitePlanningArtifactStore.problemArtifactID],
                diagnostics: [diagnostic],
                nextActions: ["validate-planning-problem"]
            )
        }
        let diagnostic = correctnessGateDiagnostic(
            severity: "warning",
            code: "planning-problem-missing",
            message: "Plan verification could not load the source planning problem, so translation correctness was not evaluated."
        )
        return XcircuitePlanningCorrectnessGateResult(
            gateID: "problem-validation",
            status: "not-evaluated",
            summary: "No source planning problem was available for translation validation.",
            diagnostics: [diagnostic],
            nextActions: ["generate-or-attach-planning-problem"]
        )
    }

    func actionDomainBindingCorrectnessGate(
        actionDomainSnapshotArtifact: ArtifactReference?,
        stepResults: [XcircuitePlanVerificationStepResult]
    ) -> XcircuitePlanningCorrectnessGateResult {
        let bindingCodes: Set<String> = [
            "unsupported-action-domain",
            "unsupported-operation",
            "operation-not-implemented",
            "action-domain-maturity-mismatch",
            "unbound-operation-input-refs",
            "unproven-operation-preconditions",
        ]
        let bindingDiagnostics = stepResults.flatMap(\.diagnostics).filter {
            bindingCodes.contains($0.code)
        }
        if bindingDiagnostics.isEmpty {
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "action-domain-binding",
                status: "passed",
                summary: "Candidate steps bind to declared action-domain operations.",
                evidenceArtifactIDs: artifactIDs([actionDomainSnapshotArtifact].compactMap { $0 })
            )
        }
        return XcircuitePlanningCorrectnessGateResult(
            gateID: "action-domain-binding",
            status: "blocked",
            summary: "At least one candidate step does not bind to an implemented action-domain operation.",
            evidenceArtifactIDs: artifactIDs([actionDomainSnapshotArtifact].compactMap { $0 }),
            diagnostics: bindingDiagnostics,
            nextActions: unique(bindingDiagnostics.flatMap { nextActions(for: $0) })
        )
    }

    func plannerReplayCorrectnessGate(
        stepResults: [XcircuitePlanVerificationStepResult],
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage],
        diagnostics: [XcircuitePlanVerificationDiagnostic]
    ) -> XcircuitePlanningCorrectnessGateResult {
        let missingGoalDiagnostics = diagnostics.filter { $0.code == "missing-goal-atom" }
        if !missingGoalDiagnostics.isEmpty {
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "planner-replay",
                status: "blocked",
                summary: "Symbolic replay did not cover all declared objective goal atoms.",
                evidenceArtifactIDs: [XcircuitePlanningArtifactStore.candidatePlanArtifactID],
                diagnostics: missingGoalDiagnostics,
                nextActions: unique(missingGoalDiagnostics.flatMap { nextActions(for: $0) })
            )
        }
        if stepResults.isEmpty || goalCoverage.isEmpty || goalCoverage.allSatisfy({ $0.status == "not-declared" }) {
            let diagnostic = correctnessGateDiagnostic(
                severity: "warning",
                code: "planner-replay-goals-not-declared",
                message: "Symbolic replay could not prove objective coverage because explicit goal atoms were not available."
            )
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "planner-replay",
                status: "not-evaluated",
                summary: "No explicit symbolic goals were available for replay coverage.",
                evidenceArtifactIDs: [XcircuitePlanningArtifactStore.candidatePlanArtifactID],
                diagnostics: [diagnostic],
                nextActions: ["add-objective-goal-atoms"]
            )
        }
        return XcircuitePlanningCorrectnessGateResult(
            gateID: "planner-replay",
            status: "passed",
            summary: "Symbolic replay covered declared objective goal atoms.",
            evidenceArtifactIDs: [XcircuitePlanningArtifactStore.candidatePlanArtifactID]
        )
    }

    func postExecutionSignoffCorrectnessGate(
        verificationMode: String,
        gateResults: [XcircuitePlanVerificationGateResult],
        artifactReferences: [ArtifactReference]
    ) -> XcircuitePlanningCorrectnessGateResult {
        guard verificationMode == "post-execution" else {
            let diagnostic = correctnessGateDiagnostic(
                severity: "warning",
                code: "post-execution-verification-required",
                message: "Candidate plan has not been verified against executed artifacts yet."
            )
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "post-execution-signoff",
                status: "pending",
                summary: "Post-execution signoff gates still need to run.",
                diagnostics: [diagnostic],
                nextActions: ["execute-candidate-plan", "verify-candidate-plan:post-execution"]
            )
        }
        let requiredResults = gateResults.filter(\.required)
        if requiredResults.isEmpty {
            let diagnostic = correctnessGateDiagnostic(
                severity: "warning",
                code: "post-execution-signoff-gates-missing",
                message: "Post-execution verification did not include required signoff gates."
            )
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "post-execution-signoff",
                status: "not-evaluated",
                summary: "No required post-execution signoff gates were declared.",
                diagnostics: [diagnostic],
                nextActions: ["add-verification-gates"]
            )
        }
        let status: String
        let missingEvidenceDiagnostics = missingPostExecutionSignoffEvidenceDiagnostics(
            requiredResults: requiredResults,
            artifactReferences: artifactReferences
        )
        if requiredResults.contains(where: { $0.status == "failed" }) || !missingEvidenceDiagnostics.isEmpty {
            status = "failed"
        } else if requiredResults.contains(where: { $0.status == "blocked" }) {
            status = "blocked"
        } else if requiredResults.contains(where: { $0.status == "pending" }) {
            status = "pending"
        } else {
            status = "passed"
        }
        return XcircuitePlanningCorrectnessGateResult(
            gateID: "post-execution-signoff",
            status: status,
            summary: "Required post-execution gate status is \(status).",
            evidenceArtifactIDs: signoffEvidenceArtifactIDs(from: artifactReferences),
            diagnostics: requiredResults.flatMap(\.diagnostics) + missingEvidenceDiagnostics,
            nextActions: unique(
                requiredResults.flatMap { nextActions(for: $0) }
                    + missingEvidenceDiagnostics.flatMap { nextActions(for: $0) }
            )
        )
    }

    func missingPostExecutionSignoffEvidenceDiagnostics(
        requiredResults: [XcircuitePlanVerificationGateResult],
        artifactReferences: [ArtifactReference]
    ) -> [XcircuitePlanVerificationDiagnostic] {
        let artifactIDs = Set(artifactReferences.map(\.id.rawValue))
        return requiredResults.compactMap { result in
            guard result.status == "passed" else {
                return nil
            }
            let prefixes = requiredSignoffArtifactPrefixes(for: result.gateID)
            guard !prefixes.isEmpty else {
                return nil
            }
            guard artifactIDs.contains(where: { artifactID in
                prefixes.contains(where: { artifactID.hasPrefix($0) })
            }) else {
                let expectedPrefixes = prefixes.joined(separator: ",")
                return XcircuitePlanVerificationDiagnostic(
                    severity: "error",
                    code: "post-execution-signoff-evidence-missing",
                    message: "Required post-execution gate \(result.gateID) passed without matching evidence artifacts. expectedArtifactPrefixes=\(expectedPrefixes)",
                    gateID: result.gateID
                )
            }
            return nil
        }
    }

    func requiredSignoffArtifactPrefixes(for gateID: String) -> [String] {
        switch gateID {
        case "native-drc":
            return ["planning-native-drc"]
        case "native-lvs":
            return ["planning-native-lvs"]
        case "pex-summary-gate":
            return ["planning-pex"]
        case "simulation-metric-gate":
            return ["planning-simulation"]
        default:
            return []
        }
    }

    func feedbackClosureCorrectnessGate(
        plan: XcircuiteCandidatePlan,
        stepResults: [XcircuitePlanVerificationStepResult],
        gateResults: [XcircuitePlanVerificationGateResult],
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage],
        accepted: Bool,
        nextActions: [String]
    ) -> XcircuitePlanningCorrectnessGateResult {
        if accepted {
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "feedback-closure",
                status: "passed",
                summary: "Plan is accepted, so no rejected-plan feedback is required.",
                evidenceArtifactIDs: [XcircuitePlanningArtifactStore.planVerificationArtifactID]
            )
        }
        let hasRejectedOrBlockedEvidence = stepResults.contains { $0.status == "failed" || $0.status == "blocked" }
            || gateResults.contains { $0.status == "failed" || $0.status == "blocked" }
            || goalCoverage.contains { $0.status == "missing" }
            || !plan.unresolvedObjectives.isEmpty
        if hasRejectedOrBlockedEvidence {
            let status = nextActions.isEmpty ? "blocked" : "passed"
            let diagnostic = correctnessGateDiagnostic(
                severity: status == "passed" ? "info" : "warning",
                code: "rejected-plan-feedback-captured",
                message: "Verification captured rejected or blocked plan evidence for feedback-aware candidate generation."
            )
            return XcircuitePlanningCorrectnessGateResult(
                gateID: "feedback-closure",
                status: status,
                summary: "Rejected or blocked plan evidence is available for the next planning iteration.",
                evidenceArtifactIDs: [
                    XcircuitePlanningArtifactStore.planVerificationArtifactID,
                    XcircuitePlanningArtifactStore.rejectedPlansArtifactID,
                ],
                diagnostics: [diagnostic],
                nextActions: nextActions
            )
        }
        return XcircuitePlanningCorrectnessGateResult(
            gateID: "feedback-closure",
            status: "pending",
            summary: "Plan is not accepted yet, but no rejected feedback is available.",
            evidenceArtifactIDs: [XcircuitePlanningArtifactStore.planVerificationArtifactID],
            nextActions: nextActions
        )
    }

    func correctnessGateDiagnostic(
        severity: String,
        code: String,
        message: String
    ) -> XcircuitePlanVerificationDiagnostic {
        XcircuitePlanVerificationDiagnostic(
            severity: severity,
            code: code,
            message: message
        )
    }

    func artifactIDs(_ references: [ArtifactReference]) -> [String] {
        uniqueStrings(references.map(\.id.rawValue))
    }

    func signoffEvidenceArtifactIDs(from artifactReferences: [ArtifactReference]) -> [String] {
        let prefixes = [
            "planning-native-drc",
            "planning-native-lvs",
            "planning-pex",
            "planning-simulation",
            "planning-plan-execution",
        ]
        return uniqueStrings(
            artifactReferences.map(\.id.rawValue).filter { artifactID in
                prefixes.contains(where: { artifactID.hasPrefix($0) })
            }
        )
    }

    func makeNextActions(
        plan: XcircuiteCandidatePlan,
        stepResults: [XcircuitePlanVerificationStepResult],
        gateResults: [XcircuitePlanVerificationGateResult],
        riskReviews: [XcircuitePlanRiskReview] = [],
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage] = []
    ) -> [String] {
        var actions: [String] = []
        actions.append(contentsOf: plan.unresolvedObjectives.map { "add-candidate-action:\($0)" })
        actions.append(contentsOf: XcircuiteCandidatePlanRiskReviewer().nextActions(from: riskReviews))
        actions.append(contentsOf: goalCoverage.filter { !$0.missingGoalAtoms.isEmpty }.map {
            "revise-plan-to-cover-goals:\($0.objectiveID)"
        })
        actions.append(contentsOf: stepResults.flatMap { step in
            step.diagnostics.flatMap { nextActions(for: $0) }
        })
        actions.append(contentsOf: gateResults.flatMap { nextActions(for: $0) })

        var seen: Set<String> = []
        return actions.filter { action in
            guard !seen.contains(action) else {
                return false
            }
            seen.insert(action)
            return true
        }
    }

    func nextActions(
        for diagnostic: XcircuitePlanVerificationDiagnostic
    ) -> [String] {
        switch diagnostic.code {
        case "operation-not-implemented":
            return [diagnostic.message.replacingOccurrences(
                of: "operation-not-implemented:",
                with: "implement-operation:"
            )]
        case "unsupported-action-domain", "unsupported-operation":
            return ["revise-plan-to-supported-action"]
        case "action-domain-maturity-mismatch":
            return ["refresh-action-domain-snapshot"]
        case "unbound-operation-input-refs":
            let refs = diagnostic.message
                .split(separator: ":")
                .last?
                .split(separator: ",") ?? []
            return refs.map { "bind-operation-input-ref:\($0)" }
        case "unproven-operation-preconditions":
            let preconditions = diagnostic.message
                .split(separator: ":")
                .last?
                .split(separator: ",") ?? []
            return preconditions.map { "prove-operation-precondition:\($0)" }
        case "missing-input-refs":
            let refs = diagnostic.message
                .replacingOccurrences(of: "missing-input-refs:", with: "")
                .split(separator: ",")
            return refs.map { "provide-input-ref:\($0)" }
        case "invalid-artifact-reference":
            return ["provide-valid-artifact-reference"]
        case "missing-goal-atom":
            let parts = diagnostic.message.split(separator: ":")
            guard parts.count >= 2 else {
                return ["revise-plan-to-cover-goals"]
            }
            return ["revise-plan-to-cover-goals:\(parts[1])"]
        case "post-execution-signoff-evidence-missing":
            guard let gateID = diagnostic.gateID else {
                return ["rerun-post-execution-verification"]
            }
            return ["rerun-verification-gate:\(gateID)"]
        default:
            return []
        }
    }

    func nextActions(
        for gateResult: XcircuitePlanVerificationGateResult
    ) -> [String] {
        guard gateResult.required else {
            return []
        }
        switch gateResult.status {
        case "pending":
            return ["run-verification-gate:\(gateResult.gateID)"]
        case "blocked" where gateResult.gateID == "approval-gate":
            return ["request-human-approval:\(gateResult.gateID)"]
        case "blocked":
            if gateResult.diagnostics.contains(where: { $0.code == "gate-input-missing" }) {
                return ["provide-gate-input:\(gateResult.gateID)"]
            }
            return ["unblock-verification-gate:\(gateResult.gateID)"]
        case "failed":
            return ["repair-verification-gate:\(gateResult.gateID)"]
        default:
            return []
        }
    }

    func verificationStatus(for verification: XcircuitePlanVerification) -> String {
        if verification.correctnessGateResults.contains(where: { $0.status == "blocked" }) {
            return "blocked"
        }
        if verification.correctnessGateResults.contains(where: { $0.status == "failed" }) {
            return "rejected"
        }
        if verification.accepted {
            return "accepted"
        }
        if verification.stepResults.contains(where: { $0.status == "blocked" })
            || verification.gateResults.contains(where: { $0.status == "blocked" })
            || verification.diagnostics.contains(where: { $0.code == "missing-goal-atom" }) {
            return "blocked"
        }
        if verification.stepResults.contains(where: { $0.status == "failed" })
            || verification.gateResults.contains(where: { $0.status == "failed" }) {
            return "rejected"
        }
        return "requires-verification"
    }
}
