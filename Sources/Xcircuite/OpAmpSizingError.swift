import Foundation

public enum OpAmpSizingError: Error, Equatable, LocalizedError {
    case unsupportedTopology(String)
    case invalidSpecification(String)
    case invalidTechnology(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedTopology(let topologyID):
            "Unsupported op-amp topology: \(topologyID)."
        case .invalidSpecification(let reason):
            "Invalid op-amp specification: \(reason)."
        case .invalidTechnology(let reason):
            "Invalid op-amp sizing technology model: \(reason)."
        }
    }
}
