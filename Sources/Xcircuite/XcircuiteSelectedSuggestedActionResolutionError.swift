import DesignFlowKernel
import Foundation

public enum XcircuiteSelectedSuggestedActionResolutionError: Error, LocalizedError, Equatable {
    case noSelection(runID: String, actionID: String?)
    case selectionNotSucceeded(actionID: String, status: FlowRunActionStatus)
    case actionRequiresInput(actionID: String)
    case actionRunIDMissing(actionID: String)
    case mismatchedSelectedActionID(expected: String, actual: String)
    case mismatchedRunID(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .noSelection(let runID, let actionID):
            if let actionID {
                "No selected suggested action was found for run \(runID) and action \(actionID)."
            } else {
                "No selected suggested action was found for run \(runID)."
            }
        case .selectionNotSucceeded(let actionID, let status):
            "Selected suggested action \(actionID) has status \(status.rawValue), not succeeded."
        case .actionRequiresInput(let actionID):
            "Selected suggested action \(actionID) requires input before it can run."
        case .actionRunIDMissing(let actionID):
            "Selected suggested action \(actionID) does not identify a run."
        case .mismatchedSelectedActionID(let expected, let actual):
            "Selected suggested action ID mismatch. Expected \(expected), got \(actual)."
        case .mismatchedRunID(let expected, let actual):
            "Selected suggested action run ID mismatch. Expected \(expected), got \(actual)."
        }
    }
}
