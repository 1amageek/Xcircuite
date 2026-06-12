import Foundation

public enum XcircuiteRuntimeError: Error, LocalizedError, Equatable {
    case artifactOutsideProject(path: String, projectRoot: String)
    case stageMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .artifactOutsideProject(let path, let projectRoot):
            "Produced artifact is outside the project root: \(path) is not under \(projectRoot)"
        case .stageMismatch(let expected, let actual):
            "Stage executor mismatch: expected \(expected), got \(actual)"
        }
    }
}
