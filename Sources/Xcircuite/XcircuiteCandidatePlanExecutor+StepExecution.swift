import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import XcircuitePackage

extension XcircuiteCandidatePlanExecutor {
    func execute(
        step: XcircuiteCandidatePlanStep,
        plan: XcircuiteCandidatePlan,
        projectRoot: URL,
        context: inout CandidatePlanExecutionContext
    ) async throws -> XcircuiteCandidatePlanExecutionStepResult {
        guard step.readiness == "ready" else {
            if step.blockers.contains(where: { $0.hasPrefix("operation-not-implemented:") }) {
                return blockedStepResult(
                    step: step,
                    code: "operation-not-implemented",
                    message: "operation-not-implemented:\(step.domainID)/\(step.operationID)"
                )
            }
            return blockedStepResult(step: step, code: "step-not-ready", message: step.blockers.joined(separator: ","))
        }
        guard step.maturity == "implemented" else {
            return blockedStepResult(
                step: step,
                code: "operation-not-implemented",
                message: "operation-not-implemented:\(step.domainID)/\(step.operationID)"
            )
        }
        switch step.operationID {
        case "layout.create-cell",
             "layout.add-net",
             "layout.add-rect",
             "layout.translate-shape",
             "layout.resize-shape",
             "layout.delete-shape",
             "layout.split-shape",
             "layout.add-label",
             "layout.add-via":
            do {
                return try executeLayoutCommand(step: step, plan: plan, projectRoot: projectRoot, context: &context)
            } catch {
                return failedStepResult(step: step, error: error)
            }
        case "simulation.set-netlist-parameters":
            do {
                return try await executeNetlistParameterEdit(
                    step: step,
                    plan: plan,
                    projectRoot: projectRoot,
                    context: &context
                )
            } catch {
                return failedStepResult(step: step, error: error)
            }
        case "lvs.policy-repair":
            do {
                return try executeLVSPolicyRepair(step: step, plan: plan, projectRoot: projectRoot)
            } catch {
                return failedStepResult(step: step, error: error)
            }
        default:
            let diagnostic = XcircuitePlanVerificationDiagnostic(
                severity: "error",
                code: "unsupported-operation",
                message: "unsupported-operation:\(step.domainID)/\(step.operationID)",
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
                nextActions: ["implement-operation:\(step.domainID)/\(step.operationID)"]
            )
        }
    }
}
