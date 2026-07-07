import Foundation

public enum XcircuiteRepairPlanFormulationCompilationError: Error, LocalizedError, Equatable {
    case missingFormulation
    case unsupportedSchemaVersion(Int)
    case runMismatch(expected: String, actual: String)
    case emptyGoals
    case emptyActions
    case duplicateReferenceID(String)
    case duplicateAssumptionID(String)
    case duplicateRiskID(String)
    case duplicateGoalID(String)
    case duplicateGoalSourceReference(goalID: String, refID: String)
    case duplicateConstraintID(String)
    case duplicateActionDomainRef(String)
    case duplicateActionID(String)
    case duplicateActionGoalReference(actionID: String, goalID: String)
    case duplicateActionInputReference(actionID: String, refID: String)
    case duplicateVerificationGateID(String)
    case duplicateActionVerificationGateID(actionID: String, gateID: String)
    case duplicateCostTermID(String)
    case unknownGoalReference(actionID: String, goalID: String)
    case unknownSourceReference(goalID: String, refID: String)
    case unknownInputReference(actionID: String, refID: String)

    public var errorDescription: String? {
        switch self {
        case .missingFormulation:
            return "A repair plan formulation or formulation path is required."
        case .unsupportedSchemaVersion(let version):
            return "Repair plan formulation schemaVersion \(version) is not supported."
        case .runMismatch(let expected, let actual):
            return "Repair plan formulation run mismatch: expected \(expected), got \(actual)."
        case .emptyGoals:
            return "Repair plan formulation must include at least one goal."
        case .emptyActions:
            return "Repair plan formulation must include at least one candidate action."
        case .duplicateReferenceID(let refID):
            return "Repair plan formulation contains duplicate reference ID \(refID)."
        case .duplicateAssumptionID(let assumptionID):
            return "Repair plan formulation contains duplicate assumption ID \(assumptionID)."
        case .duplicateRiskID(let riskID):
            return "Repair plan formulation contains duplicate risk ID \(riskID)."
        case .duplicateGoalID(let goalID):
            return "Repair plan formulation contains duplicate goal ID \(goalID)."
        case .duplicateGoalSourceReference(let goalID, let refID):
            return "Repair plan formulation goal \(goalID) contains duplicate source reference \(refID)."
        case .duplicateConstraintID(let constraintID):
            return "Repair plan formulation contains duplicate constraint ID \(constraintID)."
        case .duplicateActionDomainRef(let domainID):
            return "Repair plan formulation contains duplicate action domain ref \(domainID)."
        case .duplicateActionID(let actionID):
            return "Repair plan formulation contains duplicate action ID \(actionID)."
        case .duplicateActionGoalReference(let actionID, let goalID):
            return "Repair plan formulation action \(actionID) contains duplicate goal reference \(goalID)."
        case .duplicateActionInputReference(let actionID, let refID):
            return "Repair plan formulation action \(actionID) contains duplicate input reference \(refID)."
        case .duplicateVerificationGateID(let gateID):
            return "Repair plan formulation contains duplicate verification gate ID \(gateID)."
        case .duplicateActionVerificationGateID(let actionID, let gateID):
            return "Repair plan formulation action \(actionID) contains duplicate verification gate \(gateID)."
        case .duplicateCostTermID(let termID):
            return "Repair plan formulation cost model contains duplicate term ID \(termID)."
        case .unknownGoalReference(let actionID, let goalID):
            return "Repair plan formulation action \(actionID) references unknown goal \(goalID)."
        case .unknownSourceReference(let goalID, let refID):
            return "Repair plan formulation goal \(goalID) references unknown source ref \(refID)."
        case .unknownInputReference(let actionID, let refID):
            return "Repair plan formulation action \(actionID) references unknown input ref \(refID)."
        }
    }
}
