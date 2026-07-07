import Foundation

public enum XcircuiteGeneratedLayoutFailureLadderError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case missingFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported generated-layout failure ladder schema version: \(version)."
        case let .missingFailure(runID):
            "Run \(runID) has no failed, blocked, incomplete, or integrity-failed ladder node."
        }
    }
}
