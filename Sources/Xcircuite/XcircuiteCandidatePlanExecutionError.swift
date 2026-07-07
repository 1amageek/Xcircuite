import Foundation
import XcircuitePackage

public enum XcircuiteCandidatePlanExecutionError: Error, LocalizedError, Equatable {
    case missingCandidatePlanReference
    case artifactNotFound(runID: String, artifactID: String)
    case invalidArtifactReference(path: String, reason: String)
    case artifactIntegrityFailed(path: String, status: XcircuiteFileReferenceIntegrityStatus, message: String)
    case artifactProducerRunMismatch(expected: String, actual: String?)
    case runMismatch(expected: String, actual: String)
    case invalidHint(stepID: String, key: String, expected: String)
    case unsupportedOperation(domainID: String, operationID: String)
    case missingNetlistInput(stepID: String)
    case unresolvedParameterAssignment(stepID: String, assignmentName: String)
    case missingLayoutCommandArtifactPath(stepID: String, field: String)
    case layoutCommandStatusFailed(stepID: String, status: String)
    case layoutCommandResultPathMismatch(stepID: String, field: String, expected: String, actual: String)
    case layoutCommandOutputByteCountMismatch(stepID: String, path: String, expected: Int64, actual: Int64)
    case layoutCommandOutputDigestMismatch(stepID: String, path: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingCandidatePlanReference:
            "Candidate plan execution requires a candidate plan artifact ID or path."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .invalidArtifactReference(let path, let reason):
            "Candidate plan execution artifact reference \(path) is invalid: \(reason)"
        case .artifactIntegrityFailed(let path, let status, let message):
            "Candidate plan execution artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .artifactProducerRunMismatch(let expected, let actual):
            "Candidate plan execution artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .runMismatch(let expected, let actual):
            "Candidate plan execution run mismatch: expected \(expected), got \(actual)."
        case .invalidHint(let stepID, let key, let expected):
            "Candidate plan step \(stepID) has invalid hint \(key); expected \(expected)."
        case .unsupportedOperation(let domainID, let operationID):
            "Candidate plan operation \(domainID)/\(operationID) is unsupported by this executor."
        case .missingNetlistInput(let stepID):
            "Candidate plan step \(stepID) requires a netlistPath or resolvable netlist reference."
        case .unresolvedParameterAssignment(let stepID, let assignmentName):
            "Candidate plan step \(stepID) could not resolve parameter assignment \(assignmentName) in the netlist."
        case .missingLayoutCommandArtifactPath(let stepID, let field):
            "Candidate plan step \(stepID) layout command request is missing required artifact path \(field)."
        case .layoutCommandStatusFailed(let stepID, let status):
            "Candidate plan step \(stepID) layout command returned status \(status)."
        case .layoutCommandResultPathMismatch(let stepID, let field, let expected, let actual):
            "Candidate plan step \(stepID) layout command returned \(field) \(actual), expected \(expected)."
        case .layoutCommandOutputByteCountMismatch(let stepID, let path, let expected, let actual):
            "Candidate plan step \(stepID) layout command output \(path) byte count mismatch: expected \(expected), actual \(actual)."
        case .layoutCommandOutputDigestMismatch(let stepID, let path, let expected, let actual):
            "Candidate plan step \(stepID) layout command output \(path) digest mismatch: expected \(expected), actual \(actual)."
        }
    }
}
