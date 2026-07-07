import Foundation

public enum XcircuiteParetoCandidateSetValidationError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case invalidIdentifier(field: String, value: String)
    case duplicateIdentifier(field: String, value: String)
    case nonFiniteMetricValue(metricID: String, field: String)
    case invalidFrontierRank(candidateID: String, rank: Int)
    case candidateRunMismatch(candidateID: String, expected: String, actual: String)
    case candidateProblemMismatch(candidateID: String, expected: String, actual: String)
    case candidateProblemUnexpected(candidateID: String, actual: String)
    case selfDominatedCandidateID(String)
    case invalidGateStatus(candidateID: String, gateID: String, status: String)
    case unknownSelectedCandidateID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Pareto candidate set schema version \(version) is not supported."
        case .emptyField(let field):
            return "Pareto candidate set field \(field) must not be empty."
        case .invalidIdentifier(let field, let value):
            return "Pareto candidate set field \(field) contains an invalid identifier: \(value)."
        case .duplicateIdentifier(let field, let value):
            return "Pareto candidate set field \(field) contains a duplicate identifier: \(value)."
        case .nonFiniteMetricValue(let metricID, let field):
            return "Pareto candidate metric \(metricID) contains a non-finite \(field)."
        case .invalidFrontierRank(let candidateID, let rank):
            return "Pareto candidate \(candidateID) has invalid frontier rank \(rank)."
        case .candidateRunMismatch(let candidateID, let expected, let actual):
            return "Pareto candidate \(candidateID) belongs to run \(actual), expected \(expected)."
        case .candidateProblemMismatch(let candidateID, let expected, let actual):
            return "Pareto candidate \(candidateID) belongs to problem \(actual), expected \(expected)."
        case .candidateProblemUnexpected(let candidateID, let actual):
            return "Pareto candidate \(candidateID) belongs to problem \(actual), but the candidate set has no problem identifier."
        case .selfDominatedCandidateID(let candidateID):
            return "Pareto candidate \(candidateID) cannot dominate itself."
        case .invalidGateStatus(let candidateID, let gateID, let status):
            return "Pareto candidate \(candidateID) has invalid gate status \(status) for gate \(gateID)."
        case .unknownSelectedCandidateID(let candidateID):
            return "Pareto candidate set selected candidate \(candidateID) is not present in candidates."
        }
    }
}
