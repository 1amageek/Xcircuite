import Foundation

public enum OpAmpTopologyKind: String, Sendable, Hashable, Codable, CaseIterable {
    case twoStageMiller
    case foldedCascode
    case telescopicCascode
}
