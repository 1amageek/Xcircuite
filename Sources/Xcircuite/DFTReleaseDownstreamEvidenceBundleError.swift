import Foundation

public enum DFTReleaseDownstreamEvidenceBundleError: Error, LocalizedError, Sendable, Hashable {
    case stageMismatch(expected: String, actual: String)
    case invalidRole
    case duplicateDomain(String)
    case missingDomain(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .stageMismatch(let expected, let actual):
            return "DFT downstream evidence stage \(actual) does not match expected stage \(expected)."
        case .invalidRole:
            return "DFT downstream evidence roles must be non-empty."
        case .duplicateDomain(let domain):
            return "DFT downstream evidence domain \(domain) was supplied more than once."
        case .missingDomain(let domain):
            return "DFT downstream evidence domain \(domain) is required."
        case .invalidInput(let message):
            return "DFT downstream evidence input is invalid: \(message)."
        }
    }
}
