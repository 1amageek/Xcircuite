import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import XcircuitePackage

extension XcircuiteCandidatePlanExecutor {
    func blockedStepResult(
        step: XcircuiteCandidatePlanStep,
        code: String,
        message: String
    ) -> XcircuiteCandidatePlanExecutionStepResult {
        let diagnostic = XcircuitePlanVerificationDiagnostic(
            severity: code == "operation-not-implemented" ? "warning" : "error",
            code: code,
            message: message.isEmpty ? code : message,
            stepID: step.stepID
        )
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "blocked",
            diagnostics: [diagnostic],
            nextActions: nextActions(for: diagnostic, step: step)
        )
    }

    func failedStepResult(
        step: XcircuiteCandidatePlanStep,
        error: any Error
    ) -> XcircuiteCandidatePlanExecutionStepResult {
        let diagnostic = XcircuitePlanVerificationDiagnostic(
            severity: "error",
            code: executionDiagnosticCode(for: error),
            message: error.localizedDescription,
            stepID: step.stepID
        )
        return XcircuiteCandidatePlanExecutionStepResult(
            stepID: step.stepID,
            order: step.order,
            actionID: step.actionID,
            domainID: step.domainID,
            operationID: step.operationID,
            status: "failed",
            diagnostics: [diagnostic],
            nextActions: ["inspect-execution-diagnostic:\(step.stepID)"]
        )
    }

    func executionDiagnosticCode(for error: any Error) -> String {
        guard let executionError = error as? XcircuiteCandidatePlanExecutionError else {
            return "execution-failed"
        }
        switch executionError {
        case .missingLayoutCommandArtifactPath:
            return "layout-command-artifact-path-missing"
        case .layoutCommandStatusFailed:
            return "layout-command-status-failed"
        case .layoutCommandResultPathMismatch:
            return "layout-command-result-path-mismatch"
        case .layoutCommandOutputByteCountMismatch:
            return "layout-command-output-byte-count-mismatch"
        case .layoutCommandOutputDigestMismatch:
            return "layout-command-output-digest-mismatch"
        default:
            return "execution-failed"
        }
    }

    func policyBlockedStepResults(
        plan: XcircuiteCandidatePlan,
        riskReviews: [XcircuitePlanRiskReview],
        diagnostics: [XcircuitePlanVerificationDiagnostic]
    ) -> [XcircuiteCandidatePlanExecutionStepResult] {
        let riskReviewer = XcircuiteCandidatePlanRiskReviewer()
        let blockedStepIDs = Set(riskReviewer.blockingStepIDs(from: riskReviews, plan: plan))
        return plan.steps
            .filter { blockedStepIDs.contains($0.stepID) }
            .sorted { $0.order < $1.order }
            .map { step in
                XcircuiteCandidatePlanExecutionStepResult(
                    stepID: step.stepID,
                    order: step.order,
                    actionID: step.actionID,
                    domainID: step.domainID,
                    operationID: step.operationID,
                    status: "blocked",
                    diagnostics: diagnostics.map { diagnostic in
                        XcircuitePlanVerificationDiagnostic(
                            severity: diagnostic.severity,
                            code: diagnostic.code,
                            message: diagnostic.message,
                            stepID: step.stepID,
                            gateID: diagnostic.gateID
                        )
                    },
                    nextActions: riskReviewer.nextActions(from: riskReviews)
                )
            }
    }

    func nextActions(
        for diagnostic: XcircuitePlanVerificationDiagnostic,
        step: XcircuiteCandidatePlanStep
    ) -> [String] {
        switch diagnostic.code {
        case "operation-not-implemented":
            return ["implement-operation:\(step.domainID)/\(step.operationID)"]
        case "step-not-ready":
            return step.missingInputRefs.map { "provide-input-ref:\($0)" }
        default:
            return []
        }
    }

    func writeDesignDiff(
        plan: XcircuiteCandidatePlan,
        stepResults: [XcircuiteCandidatePlanExecutionStepResult],
        actor: String,
        projectRoot: URL
    ) throws -> XcircuiteFileReference? {
        let executed = stepResults.filter { $0.status == "executed" }
        guard !executed.isEmpty else {
            return nil
        }
        let changes = executed.map { result in
            XcircuiteDesignDiffChange(
                changeID: "candidate-step-\(result.order)",
                domain: designDiffDomain(for: result.operationID),
                operation: designDiffOperation(for: result.operationID),
                path: "/planning/candidate-plan/steps/\(result.stepID)",
                after: .object([
                    "operationID": .string(result.operationID),
                    "artifactIDs": .array(result.artifactRefs.compactMap { reference in
                        reference.artifactID.map { .string($0) }
                    }),
                ]),
                artifacts: result.artifactRefs,
                summary: "Executed candidate plan step \(result.stepID) with operation \(result.operationID)."
            )
        }
        return try packageStore.writeDesignDiff(
            XcircuiteDesignDiff(
                runID: plan.runID,
                title: "Candidate plan \(plan.planID) execution",
                actor: actor,
                changes: changes
            ),
            inProjectAt: projectRoot
        )
    }

    func designDiffDomain(for operationID: String) -> XcircuiteDesignDiffDomain {
        if operationID == "simulation.set-netlist-parameters" {
            return .netlist
        }
        if operationID.hasPrefix("layout.") {
            return .layout
        }
        if operationID.hasPrefix("lvs.") {
            return .verification
        }
        if operationID.hasPrefix("pex.") {
            return .pex
        }
        if operationID.hasPrefix("simulation.") {
            return .simulation
        }
        if operationID.contains("netlist") {
            return .netlist
        }
        return .other
    }

    func executionCoverage(
        stepResults: [XcircuiteCandidatePlanExecutionStepResult],
        artifactRefs: [XcircuiteFileReference]
    ) -> XcircuiteCandidatePlanExecutionCoverage {
        let requiredFamilyIDs = ["layout", "netlist", "parameter", "policy"]
        let families = requiredFamilyIDs.map { familyID in
            familyCoverage(familyID: familyID, stepResults: stepResults)
        }
        let coveredFamilyIDs = families
            .filter { $0.status == "covered" }
            .map(\.familyID)
        let missingFamilyIDs = requiredFamilyIDs.filter { !coveredFamilyIDs.contains($0) }
        let producedArtifactIDs = unique(artifactRefs.compactMap(\.artifactID)).sorted()
        return XcircuiteCandidatePlanExecutionCoverage(
            status: missingFamilyIDs.isEmpty ? "covered" : "partial",
            requiredFamilyIDs: requiredFamilyIDs,
            coveredFamilyIDs: coveredFamilyIDs,
            missingFamilyIDs: missingFamilyIDs,
            familyCoverage: families,
            producedArtifactIDs: producedArtifactIDs
        )
    }

    func familyCoverage(
        familyID: String,
        stepResults: [XcircuiteCandidatePlanExecutionStepResult]
    ) -> XcircuiteCandidatePlanExecutionFamilyCoverage {
        let familyStepResults = stepResults
            .filter { $0.status == "executed" && operationFamilies(for: $0.operationID).contains(familyID) }
        let artifactIDs = unique(familyStepResults.flatMap(\.artifactRefs).compactMap(\.artifactID)).sorted()
        return XcircuiteCandidatePlanExecutionFamilyCoverage(
            familyID: familyID,
            status: artifactIDs.isEmpty ? "missing" : "covered",
            stepIDs: unique(familyStepResults.map(\.stepID)).sorted(),
            domainIDs: unique(familyStepResults.map(\.domainID)).sorted(),
            operationIDs: unique(familyStepResults.map(\.operationID)).sorted(),
            artifactIDs: artifactIDs
        )
    }

    func operationFamilies(for operationID: String) -> [String] {
        if operationID.hasPrefix("layout.") {
            return ["layout"]
        }
        if operationID == "simulation.set-netlist-parameters" {
            return ["netlist", "parameter"]
        }
        if operationID == "lvs.policy-repair" {
            return ["policy"]
        }
        return []
    }

    func designDiffOperation(for operationID: String) -> XcircuiteDesignDiffOperation {
        switch operationID {
        case "layout.translate-shape":
            return .move
        case "layout.resize-shape":
            return .replace
        case "layout.delete-shape":
            return .remove
        case "layout.split-shape":
            return .replace
        default:
            return .add
        }
    }

    func appendActionRecord(
        execution: XcircuiteCandidatePlanExecution,
        candidatePlanRef: XcircuiteFileReference,
        executionRef: XcircuiteFileReference,
        designDiffRef: XcircuiteFileReference?,
        projectRoot: URL
    ) throws {
        let status: XcircuiteRunActionStatus
        switch execution.status {
        case "executed":
            status = .succeeded
        case "partial":
            status = .partial
        case "failed":
            status = .failed
        default:
            status = .blocked
        }
        let outputs = [executionRef] + execution.artifactRefs + [designDiffRef].compactMap { $0 }
        try packageStore.appendRunAction(
            XcircuiteRunActionRecord(
                actionID: "\(execution.planID)-execution",
                runID: execution.runID,
                actor: XcircuiteRunActionActor(kind: .cli, identifier: "xcircuite-flow"),
                actionKind: "planning.execute-candidate-plan",
                status: status,
                inputs: [candidatePlanRef],
                outputs: outputs,
                diagnostics: execution.diagnostics.map {
                    XcircuiteRunActionDiagnostic(
                        severity: runActionSeverity($0.severity),
                        code: $0.code,
                        message: $0.message
                    )
                }
            ),
            inProjectAt: projectRoot
        )
    }

    func executionStatus(
        _ stepResults: [XcircuiteCandidatePlanExecutionStepResult]
    ) -> String {
        if stepResults.isEmpty {
            return "blocked"
        }
        if stepResults.allSatisfy({ $0.status == "executed" }) {
            return "executed"
        }
        if stepResults.contains(where: { $0.status == "executed" }) {
            return "partial"
        }
        if stepResults.contains(where: { $0.status == "failed" }) {
            return "failed"
        }
        return "blocked"
    }

    func signoffNextActions(for plan: XcircuiteCandidatePlan) -> [String] {
        unique(plan.verificationGates.filter(\.required).map { "run-verification-gate:\($0.gateID)" })
    }

    func signoffNextActions(for step: XcircuiteCandidatePlanStep) -> [String] {
        unique(step.verificationGates.filter {
            !["artifact-integrity", "schema-validation", "precondition-validation"].contains($0)
        }.map { "run-verification-gate:\($0)" })
    }

    func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }
}
