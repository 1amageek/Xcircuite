import Foundation

public enum DFTProcessQualificationEvidenceValidationError: Error, LocalizedError, Sendable, Hashable {
    case structurallyInvalid
    case notQualified(reasons: [String])
    case toolMismatch(expected: String, actual: String)
    case implementationMismatch(expected: String, actual: String)
    case processMismatch(expected: String, actual: String)
    case pdkMismatch(expected: String, actual: String)
    case modelMismatch(required: [String], qualified: [String])

    public var code: String {
        switch self {
        case .structurallyInvalid:
            return "DFT_PROCESS_QUALIFICATION_STRUCTURALLY_INVALID"
        case .notQualified:
            return "DFT_PROCESS_QUALIFICATION_NOT_QUALIFIED"
        case .toolMismatch:
            return "DFT_PROCESS_QUALIFICATION_TOOL_MISMATCH"
        case .implementationMismatch:
            return "DFT_PROCESS_QUALIFICATION_IMPLEMENTATION_MISMATCH"
        case .processMismatch:
            return "DFT_PROCESS_QUALIFICATION_PROCESS_MISMATCH"
        case .pdkMismatch:
            return "DFT_PROCESS_QUALIFICATION_PDK_MISMATCH"
        case .modelMismatch:
            return "DFT_PROCESS_QUALIFICATION_MODEL_MISMATCH"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .structurallyInvalid:
            return "qualification identity, scope and evidence references are incomplete"
        case .notQualified(let reasons):
            return "qualification is not currently eligible (\(reasons.joined(separator: ", ")))"
        case .toolMismatch(let expected, let actual):
            return "tool ID \(actual) does not match release engine \(expected)"
        case .implementationMismatch(let expected, let actual):
            return "implementation ID \(actual) does not match release result \(expected)"
        case .processMismatch(let expected, let actual):
            return "process profile \(actual) does not match request process \(expected)"
        case .pdkMismatch(let expected, let actual):
            return "PDK digest \(actual) does not match request PDK \(expected)"
        case .modelMismatch(let required, let qualified):
            return "process-specific models \(required.joined(separator: ", ")) are used by the DFT result but are not qualified; qualified models are \(qualified.joined(separator: ", "))"
        }
    }
}
