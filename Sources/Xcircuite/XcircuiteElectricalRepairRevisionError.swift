import Foundation

public enum XcircuiteElectricalRepairRevisionError: Error, Sendable, Hashable, Codable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidRequest(String)
    case invalidPlan(String)
    case candidateNotFound(String)
    case sourceIntegrity(String)
    case noImmutableRevision

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Electrical repair revision request schema version is unsupported: \(version)."
        case let .invalidRequest(message):
            return "Electrical repair revision request is invalid: \(message)"
        case let .invalidPlan(message):
            return "Electrical repair plan is invalid: \(message)"
        case let .candidateNotFound(candidateID):
            return "Electrical repair candidate was not found: \(candidateID)."
        case let .sourceIntegrity(message):
            return "Electrical repair source integrity verification failed: \(message)"
        case .noImmutableRevision:
            return "The repair execution did not produce a changed immutable physical-design revision."
        }
    }
}
