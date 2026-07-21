import Foundation

public enum XcircuiteRuntimeIdentityError: Error, Sendable, Equatable, LocalizedError {
    case executableUnavailable

    public var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "The current executable could not be resolved for Xcircuite build identification."
        }
    }
}
