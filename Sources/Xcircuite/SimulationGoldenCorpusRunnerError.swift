import Foundation

public enum SimulationGoldenCorpusRunnerError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptySuite
    case duplicateCaseID(String)
    case invalidExpectedGateStatus(caseID: String, status: String)
    case expectedFailureRequiresDiagnostics(caseID: String)
    case invalidIdentifier(kind: String, value: String)
    case invalidProjectRelativePath(String)
    case pathEscapesProjectRoot(String)
    case artifactDirectoryEscapesRoot(caseID: String, path: String, artifactRoot: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Simulation golden corpus suite schema version \(version) is not supported."
        case .emptySuite:
            "Simulation golden corpus suite must include at least one case."
        case .duplicateCaseID(let caseID):
            "Simulation golden corpus suite contains duplicate case ID \(caseID)."
        case .invalidExpectedGateStatus(let caseID, let status):
            "Simulation golden corpus case \(caseID) has invalid expected gate status \(status)."
        case .expectedFailureRequiresDiagnostics(let caseID):
            "Simulation golden corpus expected-failure case \(caseID) must declare expected diagnostic substrings."
        case .invalidIdentifier(let kind, let value):
            "Simulation golden corpus \(kind) is invalid: \(value)."
        case .invalidProjectRelativePath(let path):
            "Simulation golden corpus path must be project-relative and non-empty: \(path)"
        case .pathEscapesProjectRoot(let path):
            "Simulation golden corpus path escapes project root: \(path)"
        case .artifactDirectoryEscapesRoot(let caseID, let path, let artifactRoot):
            "Simulation golden corpus case \(caseID) artifact path escapes artifact root: \(path) is not under \(artifactRoot)."
        }
    }
}
