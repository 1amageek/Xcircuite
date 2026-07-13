import Foundation

public enum ElectricalStandardLayoutImportError: Error, Sendable, Hashable, Codable, LocalizedError {
    case stageMismatch
    case missingTechnology
    case unsupportedLayoutFormat(String)
    case invalidTopCell
    case missingElectricalConnectivity
    case malformedGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .stageMismatch:
            return "Electrical standard-layout import stage does not match the requested stage."
        case .missingTechnology:
            return "A verified LEF or equivalent layout technology input is required for standard-layout import."
        case let .unsupportedLayoutFormat(format):
            return "Standard layout format is unsupported for electrical import: \(format)."
        case .invalidTopCell:
            return "The standard layout does not contain a usable top cell."
        case .missingElectricalConnectivity:
            return "The standard layout contains no recoverable electrical nets and routed connectivity."
        case let .malformedGeometry(message):
            return "Standard layout geometry is malformed: \(message)"
        }
    }
}
