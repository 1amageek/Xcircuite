import Foundation

public enum OpAmpSimulationDeckValidationMode: String, Sendable, Hashable, Codable {
    case parseOnly
    case executeCoreSpice
}
