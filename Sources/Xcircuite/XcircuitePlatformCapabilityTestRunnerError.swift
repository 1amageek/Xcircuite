import Foundation

public enum XcircuitePlatformCapabilityTestRunnerError: Error, Sendable, Equatable, LocalizedError {
    case invalidEvidenceID(String)
    case invalidCommand
    case declarationContainsExecutionResults
    case packageDirectoryUnavailable(String)
    case packageDirectoryEscapesRoot(String)
    case xcodebuildExecutableUnavailable(path: String, reason: String)
    case xcodebuildVersionProbeFailed(path: String, exitStatus: Int32)
    case xcodebuildExecutableChangedDuringExecution(String)
    case persistenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEvidenceID(let value):
            "Platform capability test evidence ID is invalid: \(value)."
        case .invalidCommand:
            "Platform capability tests must use the bounded /usr/bin/perl xcodebuild command contract."
        case .declarationContainsExecutionResults:
            "Platform capability test declarations cannot supply retained outputs, provenance, result artifacts, or exit status."
        case .packageDirectoryUnavailable(let path):
            "Platform capability test package directory is unavailable: \(path)."
        case .packageDirectoryEscapesRoot(let path):
            "Platform capability test package directory escapes the evidence root: \(path)."
        case .xcodebuildExecutableUnavailable(let path, let reason):
            "The selected xcodebuild executable is unavailable at \(path): \(reason)."
        case .xcodebuildVersionProbeFailed(let path, let exitStatus):
            "The selected xcodebuild version could not be measured at \(path); exit status \(exitStatus)."
        case .xcodebuildExecutableChangedDuringExecution(let path):
            "The selected xcodebuild executable changed during execution: \(path)."
        case .persistenceFailure(let message):
            "Platform capability test evidence could not be persisted: \(message)."
        }
    }
}
