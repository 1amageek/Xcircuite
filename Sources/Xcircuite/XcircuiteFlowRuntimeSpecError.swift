import Foundation

public enum XcircuiteFlowRuntimeSpecError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case unsupportedEvidenceExportSchemaVersion(Int)
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
    case conflictingExecutorInputs(stageID: String, fields: [String])
    case invalidEvidenceExport(field: String, reason: String)
    case invalidToolEvidence(stageID: String, evidenceID: String, reason: String)
    case missingToolQualificationEvidence(stageID: String, kind: String, level: String)
    case mockExecutorCannotDeclareQualifiedTool(stageID: String, level: String)
    case mockPEXBackendNotAllowed(stageID: String, backendID: String)
    case conflictingRuntimeToolDescriptor(toolID: String, stageIDs: [String])
    case conflictingRuntimeToolHealth(toolID: String, stageIDs: [String])
    case missingRuntimeExecutorForRunStage(String)
    case electricalProcessQualificationRequiresApproval(String)
    case stageNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported runtime spec schema version: \(version)"
        case .unsupportedEvidenceExportSchemaVersion(let version):
            "Unsupported evidence export schema version: \(version)"
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
        case .conflictingExecutorInputs(let stageID, let fields):
            "Runtime spec executor \(stageID) has conflicting inputs: \(fields.joined(separator: ", "))"
        case .invalidEvidenceExport(let field, let reason):
            "Evidence export contains invalid \(field): \(reason)"
        case .invalidToolEvidence(let stageID, let evidenceID, let reason):
            "Runtime spec executor \(stageID) contains invalid tool evidence \(evidenceID): \(reason)"
        case .missingToolQualificationEvidence(let stageID, let kind, let level):
            "Runtime spec executor \(stageID) declares \(level) qualification without qualified \(kind) evidence."
        case .mockExecutorCannotDeclareQualifiedTool(let stageID, let level):
            "Runtime spec executor \(stageID) is mock-only and cannot declare \(level) qualification."
        case .mockPEXBackendNotAllowed(let stageID, let backendID):
            "Runtime spec executor \(stageID) cannot use mock PEX backend \(backendID) through the production PEX executor."
        case .conflictingRuntimeToolDescriptor(let toolID, let stageIDs):
            "Runtime spec contains conflicting descriptors for tool \(toolID) across stages: \(stageIDs.joined(separator: ", "))"
        case .conflictingRuntimeToolHealth(let toolID, let stageIDs):
            "Runtime spec contains conflicting health results for tool \(toolID) across stages: \(stageIDs.joined(separator: ", "))"
        case .missingRuntimeExecutorForRunStage(let stageID):
            "Runtime spec does not contain an executor for run stage: \(stageID)"
        case .electricalProcessQualificationRequiresApproval(let stageID):
            "Electrical process qualification stage must require a human approval gate: \(stageID)"
        case .stageNotFound(let stageID):
            "Runtime spec does not contain an executor for stage: \(stageID)"
        }
    }
}
