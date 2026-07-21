import Foundation

public enum XcircuiteFlowRuntimeSpecError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case unknownExecutorKind(String)
    case invalidPath(String)
    case emptyRunIntent
    case emptyRunStageList
    case duplicateRunStageID(String)
    case emptyRunStageDisplayName(String)
    case emptyExecutorList
    case duplicateExecutorStageID(String)
    case missingToolchainProfileField(String)
    case invalidToolchainProfileField(String)
    case missingExecutorInput(stageID: String, field: String)
    case invalidExecutorConfiguration(stageID: String, reason: String)
    case conflictingExecutorInputs(stageID: String, fields: [String])
    case conflictingRuntimeToolDescriptor(toolID: String, stageIDs: [String])
    case conflictingRuntimeToolHealth(toolID: String, stageIDs: [String])
    case conflictingQualificationRecord(toolID: String)
    case invalidQualificationRecord(toolID: String, reason: String)
    case qualificationRecordExecutionIdentityMismatch(toolID: String)
    case missingRuntimeExecutorForRunStage(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported runtime spec schema version: \(version)"
        case .unknownExecutorKind(let kind):
            "Unknown runtime executor kind: \(kind)"
        case .invalidPath(let path):
            "Invalid runtime spec path: \(path)"
        case .emptyRunIntent:
            "Run spec intent must not be empty."
        case .emptyRunStageList:
            "Run spec must contain at least one stage."
        case .duplicateRunStageID(let stageID):
            "Run spec contains duplicate stage ID: \(stageID)"
        case .emptyRunStageDisplayName(let stageID):
            "Run spec stage displayName must not be empty for stage: \(stageID)"
        case .emptyExecutorList:
            "Runtime spec must contain at least one executor."
        case .duplicateExecutorStageID(let stageID):
            "Runtime spec contains duplicate executor stage ID: \(stageID)"
        case .missingToolchainProfileField(let field):
            "Runtime spec toolchainProfile is missing required field: \(field)"
        case .invalidToolchainProfileField(let field):
            "Runtime spec toolchainProfile contains invalid field: \(field)"
        case .missingExecutorInput(let stageID, let field):
            "Runtime spec executor \(stageID) is missing required input: \(field)"
        case .invalidExecutorConfiguration(let stageID, let reason):
            "Runtime spec executor \(stageID) has invalid configuration: \(reason)"
        case .conflictingExecutorInputs(let stageID, let fields):
            "Runtime spec executor \(stageID) has conflicting inputs: \(fields.joined(separator: ", "))"
        case .conflictingRuntimeToolDescriptor(let toolID, let stageIDs):
            "Runtime spec contains conflicting descriptors for tool \(toolID) across stages: \(stageIDs.joined(separator: ", "))"
        case .conflictingRuntimeToolHealth(let toolID, let stageIDs):
            "Runtime spec contains conflicting health results for tool \(toolID) across stages: \(stageIDs.joined(separator: ", "))"
        case .conflictingQualificationRecord(let toolID):
            "Runtime spec contains conflicting qualification records for tool \(toolID)."
        case .invalidQualificationRecord(let toolID, let reason):
            "Runtime spec qualification record for tool \(toolID) is invalid: \(reason)"
        case .qualificationRecordExecutionIdentityMismatch(let toolID):
            "Runtime spec qualification record changes the execution identity of tool \(toolID)."
        case .missingRuntimeExecutorForRunStage(let stageID):
            "Runtime spec does not contain an executor for run stage: \(stageID)"
        }
    }
}
