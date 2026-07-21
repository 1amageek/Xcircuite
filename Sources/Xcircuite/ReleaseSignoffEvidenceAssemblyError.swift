import Foundation
import ReleaseCore

public enum ReleaseSignoffEvidenceAssemblyError: Error, Sendable, Hashable, LocalizedError {
    case invalidSchemaVersion(Int)
    case invalidRunID(String)
    case duplicateAxis(ReleaseSignoffAxis)
    case unsupportedProducer(ReleaseSignoffEvidenceProducer, ReleaseSignoffAxis)
    case invalidArtifact(String)
    case invalidQualification(String)
    case resultIdentityMismatch(String)
    case resultContractViolation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSchemaVersion(let version):
            "Unsupported release evidence assembly schema version \(version)."
        case .invalidRunID(let runID):
            "Release evidence assembly run ID is invalid: \(runID)."
        case .duplicateAxis(let axis):
            "Release evidence assembly contains duplicate source axis \(axis.rawValue)."
        case .unsupportedProducer(let producer, let axis):
            "Producer \(producer.rawValue) cannot supply release axis \(axis.rawValue)."
        case .invalidArtifact(let message):
            "Release evidence artifact is invalid: \(message)"
        case .invalidQualification(let message):
            "Release evidence qualification is invalid: \(message)"
        case .resultIdentityMismatch(let message):
            "Release evidence result identity does not match: \(message)"
        case .resultContractViolation(let message):
            "Release evidence result contract is not satisfied: \(message)"
        }
    }
}
