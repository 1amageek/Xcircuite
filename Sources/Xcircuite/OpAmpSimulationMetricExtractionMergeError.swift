import Foundation

public enum OpAmpSimulationMetricExtractionMergeError: Error, Equatable, LocalizedError {
    case emptyInputs

    public var errorDescription: String? {
        switch self {
        case .emptyInputs:
            return "At least one op-amp metric extraction is required for merging."
        }
    }
}
