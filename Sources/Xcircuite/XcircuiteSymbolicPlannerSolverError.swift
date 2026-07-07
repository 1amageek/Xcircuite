import Foundation
import XcircuitePackage

public enum XcircuiteSymbolicPlannerSolverError: Error, LocalizedError, Equatable {
    case invalidTimeout(Double)
    case invalidProofCheckerTimeout(Double)
    case invalidMaximumSolverCost(Double)
    case missingDomainReference
    case missingProblemReference
    case missingPDDLExportReference
    case emptyQualificationCorpus
    case emptySolverFamilyComparison
    case invalidSolverFamilyCandidateID(index: Int, candidateID: String)
    case invalidSolverFamilyCandidateToolID(index: Int, toolID: String)
    case duplicateSolverFamilyCandidateToolID(toolID: String)
    case invalidSolverFamilyCandidateExecutablePath(index: Int)
    case invalidSolverFamilyCandidateTimeout(index: Int, timeoutSeconds: Double)
    case invalidSolverFamilyCandidateReference(index: Int, field: String, value: String)
    case qualificationRunMismatch(expected: String, actual: String)
    case invalidSolverFamilyCandidateIndex(index: Int, candidateCount: Int)
    case missingSelectedSolverFamilyQualificationArtifact
    case selectedSolverFamilyQualificationNotQualified(toolID: String, status: String)
    case missingSelectedSolverFamilyImportedPlan(toolID: String)
    case solverFamilyComparisonIDMismatch(expected: String, actual: String)
    case duplicateArtifactReference(runID: String, artifactID: String, count: Int)
    case invalidArtifactReference(field: String, path: String, reason: String)
    case artifactReferenceMismatch(field: String, artifactID: String?, path: String, manifestPath: String)
    case artifactProducerRunMismatch(field: String, expected: String, actual: String?)
    case artifactIntegrityFailed(
        field: String,
        artifactID: String?,
        path: String,
        status: XcircuiteFileReferenceIntegrityStatus,
        message: String
    )
    case invalidSolverQualificationReference(field: String, value: String)
    case invalidSolverQualificationPath(field: String, value: String)
    case invalidSolverQualificationExecutablePath(field: String, value: String)
    case unknownCoverageTags(tags: [String], knownTags: [String])
    case unimplementedCoverageTags(tags: [String], implementedTags: [String])
    case artifactNotFound(runID: String, artifactID: String)
    case conflictingSolverPlanOutputPath(path: String, conflictingArtifactID: String?, conflictingPath: String)
    case solverPlanOutputOutsideWorkingDirectory(path: String, workingDirectoryPath: String)
    case existingSolverPlanOutput(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimeout(let timeoutSeconds):
            "Symbolic planner solver timeout must be positive finite seconds, got \(timeoutSeconds)."
        case .invalidProofCheckerTimeout(let timeoutSeconds):
            "Symbolic planner proof checker timeout must be positive finite seconds, got \(timeoutSeconds)."
        case .invalidMaximumSolverCost(let maximumSolverCost):
            "Symbolic planner solver maximum cost must be finite and non-negative, got \(maximumSolverCost)."
        case .missingDomainReference:
            "Symbolic planner solver requires a PDDL domain artifact ID or path."
        case .missingProblemReference:
            "Symbolic planner solver requires a PDDL problem artifact ID or path."
        case .missingPDDLExportReference:
            "Symbolic planner solver import requires a PDDL export artifact ID or path."
        case .emptyQualificationCorpus:
            "Symbolic planner solver qualification corpus requires at least one case."
        case .emptySolverFamilyComparison:
            "Symbolic planner solver family comparison requires at least one qualification artifact ID or path."
        case .invalidSolverFamilyCandidateID(let index, let candidateID):
            "Symbolic planner solver family candidate \(index) has invalid candidate ID \(candidateID)."
        case .invalidSolverFamilyCandidateToolID(let index, let toolID):
            "Symbolic planner solver family candidate \(index) has invalid tool ID \(toolID)."
        case .duplicateSolverFamilyCandidateToolID(let toolID):
            "Symbolic planner solver family candidate tool ID \(toolID) is duplicated."
        case .invalidSolverFamilyCandidateExecutablePath(let index):
            "Symbolic planner solver family candidate \(index) requires a non-empty executable path."
        case .invalidSolverFamilyCandidateTimeout(let index, let timeoutSeconds):
            "Symbolic planner solver family candidate \(index) timeout must be positive finite seconds, got \(timeoutSeconds)."
        case .invalidSolverFamilyCandidateReference(let index, let field, let value):
            "Symbolic planner solver family candidate \(index) has invalid \(field) reference \(value)."
        case .qualificationRunMismatch(let expected, let actual):
            "Symbolic planner solver family comparison expected qualification for run \(expected), got \(actual)."
        case .invalidSolverFamilyCandidateIndex(let index, let candidateCount):
            "Symbolic planner solver family candidate index \(index) is outside 0..<\(candidateCount)."
        case .missingSelectedSolverFamilyQualificationArtifact:
            "Selected symbolic planner solver family candidate does not reference a qualification artifact."
        case .selectedSolverFamilyQualificationNotQualified(let toolID, let status):
            "Selected symbolic planner solver family qualification for \(toolID) has status \(status), but promotion requires a qualified certificate."
        case .missingSelectedSolverFamilyImportedPlan(let toolID):
            "Selected symbolic planner solver family qualification for \(toolID) does not contain an imported candidate plan to promote."
        case .solverFamilyComparisonIDMismatch(let expected, let actual):
            "Symbolic planner solver family promotion expected comparison ID \(expected), got \(actual)."
        case .duplicateArtifactReference(let runID, let artifactID, let count):
            "Run \(runID) contains \(count) artifacts with artifactID \(artifactID); symbolic planner solver artifact reads require a unique artifact reference."
        case .invalidArtifactReference(let field, let path, let reason):
            "Symbolic planner solver artifact reference \(field) at \(path) is invalid: \(reason)"
        case .artifactReferenceMismatch(let field, let artifactID, let path, let manifestPath):
            "Symbolic planner solver artifact reference \(field) \(artifactID ?? path) points to \(path), but the run manifest records \(manifestPath)."
        case .artifactProducerRunMismatch(let field, let expected, let actual):
            "Symbolic planner solver artifact reference \(field) expected producer run \(expected), got \(actual ?? "nil")."
        case .artifactIntegrityFailed(let field, let artifactID, let path, let status, let message):
            "Symbolic planner solver artifact reference \(field) \(artifactID ?? path) failed integrity verification at \(path) with status \(status.rawValue): \(message)"
        case .invalidSolverQualificationReference(let field, let value):
            "Symbolic planner solver qualification request has invalid \(field) reference \(value)."
        case .invalidSolverQualificationPath(let field, let value):
            "Symbolic planner solver qualification request has unsafe project-relative \(field) path \(value)."
        case .invalidSolverQualificationExecutablePath(let field, let value):
            "Symbolic planner solver qualification request requires a non-empty \(field), got \(value)."
        case .unknownCoverageTags(let tags, let knownTags):
            "Symbolic planner solver corpus references unknown coverage tags \(tags.joined(separator: ", ")). Known tags: \(knownTags.joined(separator: ", "))."
        case .unimplementedCoverageTags(let tags, let implementedTags):
            "Symbolic planner solver corpus references coverage tags that are not implemented \(tags.joined(separator: ", ")). Implemented tags: \(implementedTags.joined(separator: ", "))."
        case .artifactNotFound(let runID, let artifactID):
            "Run \(runID) does not contain artifact \(artifactID)."
        case .conflictingSolverPlanOutputPath(let path, let conflictingArtifactID, let conflictingPath):
            if let conflictingArtifactID {
                "Symbolic planner solver plan output path \(path) conflicts with input artifact \(conflictingArtifactID) at \(conflictingPath)."
            } else {
                "Symbolic planner solver plan output path \(path) conflicts with input artifact at \(conflictingPath)."
            }
        case .solverPlanOutputOutsideWorkingDirectory(let path, let workingDirectoryPath):
            "Symbolic planner solver plan output path \(path) must be inside working directory \(workingDirectoryPath)."
        case .existingSolverPlanOutput(let path):
            "Symbolic planner solver plan output path \(path) already exists. Use a fresh output path to avoid importing stale solver output."
        }
    }
}
