import Foundation

public enum OpAmpWaveformMetricExtractionError: Error, Equatable, LocalizedError {
    case invalidWaveform(String)
    case missingVariable(String)
    case insufficientPoints(String)
    case noFiniteValues(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWaveform(let reason):
            return "Invalid waveform CSV: \(reason)"
        case .missingVariable(let name):
            return "Waveform variable '\(name)' was not found."
        case .insufficientPoints(let analysis):
            return "Waveform analysis '\(analysis)' does not contain enough points."
        case .noFiniteValues(let variable):
            return "Waveform variable '\(variable)' does not contain finite values."
        }
    }
}
