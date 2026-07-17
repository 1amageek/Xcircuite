import CircuiteFoundation
import DesignFlowKernel
import Foundation

/// Resolves a reviewed semantic action and projects it at the project-runtime boundary.
public struct XcircuiteSelectedSuggestedActionResolver: XcircuiteSuggestedActionResolving {
    private let workspaceStore: any XcircuiteSuggestedActionSelectionStore

    public init(workspaceStore: any XcircuiteSuggestedActionSelectionStore) {
        self.workspaceStore = workspaceStore
    }

    public func resolve(
        request: XcircuiteSelectedSuggestedActionResolutionRequest
    ) async throws -> XcircuiteResolvedSuggestedAction {
        let selection = try await selectedAction(
            runID: request.runID,
            actionID: request.actionID
        )
        let action = selection.action
        guard selection.nextActionID == action.id else {
            throw XcircuiteSelectedSuggestedActionResolutionError.mismatchedSelectedActionID(
                expected: selection.nextActionID,
                actual: action.id
            )
        }
        guard action.readiness == .ready else {
            throw XcircuiteSelectedSuggestedActionResolutionError.actionRequiresInput(
                actionID: action.id
            )
        }
        guard let actionRunID = action.runID else {
            throw XcircuiteSelectedSuggestedActionResolutionError.actionRunIDMissing(
                actionID: action.id
            )
        }
        guard selection.runID == request.runID else {
            throw XcircuiteSelectedSuggestedActionResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: selection.runID
            )
        }
        guard actionRunID == request.runID else {
            throw XcircuiteSelectedSuggestedActionResolutionError.mismatchedRunID(
                expected: request.runID,
                actual: actionRunID
            )
        }

        let projection = project(operation: action.operation)
        let projectRoot = workspaceStore.projectRoot.path(percentEncoded: false)
        return XcircuiteResolvedSuggestedAction(
            selection: selection,
            command: projection.command,
            dispatchArguments: [
                "--project-root", projectRoot,
                "--run-id", request.runID,
            ] + projection.operationArguments + ["--pretty"]
        )
    }

    private func selectedAction(
        runID: String,
        actionID: String?
    ) async throws -> FlowRunSuggestedActionSelection {
        let selections = try await workspaceStore.loadSuggestedActionSelections(runID: runID)
        let matching = selections.filter { selection in
            guard let actionID else {
                return true
            }
            return selection.action.id == actionID
        }
        guard let selection = matching.last else {
            throw XcircuiteSelectedSuggestedActionResolutionError.noSelection(
                runID: runID,
                actionID: actionID
            )
        }
        guard selection.status == .succeeded else {
            throw XcircuiteSelectedSuggestedActionResolutionError.selectionNotSucceeded(
                actionID: selection.action.id,
                status: selection.status
            )
        }
        return selection
    }

    private func project(
        operation: FlowRunSuggestedOperation
    ) -> (command: XcircuiteFlowActionCommand, operationArguments: [String]) {
        switch operation {
        case .summarizeRunLoop:
            (.summarizeLoop, [])
        case .inspectRun:
            (.inspectRun, [])
        case .reviewRun:
            (.reviewRun, [])
        case .evaluateRunGuard:
            (.evaluateRunGuard, [])
        case .validatePlanningProblem:
            (.validatePlanningProblem, [])
        case .auditProblemTranslation:
            (.auditProblemTranslation, [])
        case .generateCandidatePlan(let rejectedPlansArtifactID):
            if let rejectedPlansArtifactID {
                (
                    .generateCandidatePlan,
                    ["--rejected-plans-artifact-id", rejectedPlansArtifactID.rawValue]
                )
            } else {
                (.generateCandidatePlan, [])
            }
        case .executeCandidatePlan:
            (.executeCandidatePlan, [])
        case .verifyCandidatePlan(let scope):
            switch scope {
            case .preExecution:
                (.verifyCandidatePlan, ["--mode", "preflight"])
            case .postExecution:
                (.verifyCandidatePlan, ["--mode", "post-execution"])
            }
        case .generateParameterCandidates:
            (.generateParameterCandidates, [])
        case .synthesizeParameterCandidatePlan:
            (.synthesizeParameterCandidatePlan, [])
        case .runNumericRepairLoop:
            (.runNumericRepairLoop, [])
        case .buildStageArtifactLadder:
            (.buildStageArtifactLadder, [])
        case .validateDecisionPacket:
            (.validateDecisionPacket, [])
        case .buildReleaseEnvelope:
            (.buildReleaseEnvelope, [])
        }
    }
}
