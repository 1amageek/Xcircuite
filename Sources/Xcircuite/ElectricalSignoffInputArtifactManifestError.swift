import Foundation

public enum ElectricalSignoffInputArtifactManifestError: Error, LocalizedError, Sendable, Hashable {
    case unsupportedSchemaVersion(Int)
    case invalidIdentity
    case emptyInputArtifacts
    case duplicatePath(String)
    case missingIntegrity(String)
    case digestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Electrical signoff input artifact manifest schema version is unsupported: \(version)."
        case .invalidIdentity:
            "Electrical signoff input artifact manifest requires non-empty run and stage identifiers."
        case .emptyInputArtifacts:
            "Electrical signoff input artifact manifest must contain at least one artifact."
        case .duplicatePath(let path):
            "Electrical signoff input artifact manifest contains a duplicate path: \(path)."
        case .missingIntegrity(let path):
            "Electrical signoff input artifact is missing SHA-256 or byte count: \(path)."
        case .digestMismatch(let expected, let actual):
            "Electrical signoff input artifact manifest digest mismatch: expected \(expected), got \(actual)."
        }
    }
}
