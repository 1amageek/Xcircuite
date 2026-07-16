import Foundation
import DesignFlowKernel

public enum XcircuiteSignoffRepairFormulationError: Error, LocalizedError, Equatable {
    case missingRepairHintSource
    case unregisteredRepairHintReport(sourceKind: String, path: String)
    case invalidRepairHintArtifact(sourceKind: String, path: String, reason: String)
    case repairHintProducerRunMismatch(sourceKind: String, expected: String, actual: String?)
    case repairHintArtifactIntegrityFailed(
        sourceKind: String,
        path: String,
        status: FlowArtifactVerificationStatus,
        message: String
    )
    case reportReadFailed(path: String, message: String)
    case noActionableHints

    public var errorDescription: String? {
        switch self {
        case .missingRepairHintSource:
            return "At least one DRC or LVS repair hint report path is required."
        case .unregisteredRepairHintReport(let sourceKind, let path):
            return "\(sourceKind.uppercased()) repair hint report at \(path) is not registered in the run manifest."
        case .invalidRepairHintArtifact(let sourceKind, let path, let reason):
            return "\(sourceKind.uppercased()) repair hint artifact \(path) is invalid: \(reason)"
        case .repairHintProducerRunMismatch(let sourceKind, let expected, let actual):
            return "\(sourceKind.uppercased()) repair hint artifact producer run mismatch: expected \(expected), got \(actual ?? "<missing>")."
        case .repairHintArtifactIntegrityFailed(let sourceKind, let path, let status, let message):
            return "\(sourceKind.uppercased()) repair hint artifact \(path) failed integrity verification with status \(status.rawValue): \(message)"
        case .reportReadFailed(let path, let message):
            return "Unable to read signoff repair hint report at \(path): \(message)"
        case .noActionableHints:
            return "Signoff repair hint reports did not contain actionable repair hints."
        }
    }
}
