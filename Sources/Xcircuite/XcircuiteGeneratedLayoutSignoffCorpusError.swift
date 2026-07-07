import Foundation

public enum XcircuiteGeneratedLayoutSignoffCorpusError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyCorpus
    case emptyExpectedStages(caseID: String)
    case emptyCoverageTags(caseID: String)
    case duplicateCaseID(String)
    case duplicateExpectedStageID(caseID: String, stageID: String)
    case duplicateOracleReadinessDomain(caseID: String, domain: XcircuiteGeneratedLayoutSignoffStageFamily)
    case invalidOracleReadiness(
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily,
        field: String,
        value: String,
        reason: String
    )
    case invalidOracleEvidenceReference(
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily,
        path: String,
        field: String,
        value: String,
        reason: String
    )
    case duplicateOracleEvidenceReference(
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily,
        role: String,
        path: String
    )
    case missingExpectedStage(caseID: String, stageID: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Generated layout signoff corpus schema version \(version) is not supported."
        case .emptyCorpus:
            return "Generated layout signoff corpus request must include at least one case."
        case .emptyExpectedStages(let caseID):
            return "Generated layout signoff corpus case \(caseID) must declare at least one expected stage."
        case .emptyCoverageTags(let caseID):
            return "Generated layout signoff corpus case \(caseID) must declare at least one coverage tag."
        case .duplicateCaseID(let caseID):
            return "Generated layout signoff corpus contains duplicate case ID \(caseID)."
        case .duplicateExpectedStageID(let caseID, let stageID):
            return "Generated layout signoff corpus case \(caseID) contains duplicate expected stage ID \(stageID)."
        case .duplicateOracleReadinessDomain(let caseID, let domain):
            return "Generated layout signoff corpus case \(caseID) contains duplicate oracle readiness domain \(domain.rawValue)."
        case .invalidOracleReadiness(let caseID, let domain, let field, let value, let reason):
            return "Generated layout signoff corpus case \(caseID) contains invalid \(domain.rawValue) oracle readiness \(field) \(value): \(reason)."
        case .invalidOracleEvidenceReference(let caseID, let domain, let path, let field, let value, let reason):
            return "Generated layout signoff corpus case \(caseID) contains invalid \(domain.rawValue) oracle evidence \(field) \(value) at \(path): \(reason)."
        case .duplicateOracleEvidenceReference(let caseID, let domain, let role, let path):
            return "Generated layout signoff corpus case \(caseID) contains duplicate \(domain.rawValue) oracle evidence reference \(role) at \(path)."
        case .missingExpectedStage(let caseID, let stageID):
            return "Generated layout signoff corpus case \(caseID) expected stage \(stageID), but the run ledger did not contain it."
        }
    }
}
