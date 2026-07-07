import Foundation

public enum XcircuiteImprovementPlanningArtifactGenerationError: Error, LocalizedError, Equatable, Sendable {
    case missingNumericRepairLoopReference
    case missingProblemReference
    case duplicateManifestArtifact(artifactID: String, paths: [String])
    case runMismatch(expected: String, actual: String)
    case problemMismatch(expected: String, actual: String)
    case planMismatch(expected: String, actual: String)
    case loopIterationCountMismatch(reported: Int, actual: Int)
    case duplicateIterationIndex(Int)
    case acceptedIterationMissing(Int)
    case selectedCandidateMismatch(iterationIndex: Int, expected: String, actual: String)
    case selectedCandidateMissing(iterationIndex: Int, candidateID: String)
    case duplicateSelectionCandidateID(iterationIndex: Int, candidateID: String)
    case duplicateVerificationGateID(iterationIndex: Int, gateID: String)

    public var errorDescription: String? {
        switch self {
        case .missingNumericRepairLoopReference:
            "No numeric repair loop artifact reference was found."
        case .missingProblemReference:
            "No planning problem artifact reference was found."
        case .duplicateManifestArtifact(let artifactID, let paths):
            "Run manifest contains multiple artifact references for \(artifactID): \(paths.joined(separator: ", "))."
        case .runMismatch(let expected, let actual):
            "Expected run ID \(expected), but found \(actual)."
        case .problemMismatch(let expected, let actual):
            "Expected problem ID \(expected), but found \(actual)."
        case .planMismatch(let expected, let actual):
            "Expected plan ID \(expected), but found \(actual)."
        case .loopIterationCountMismatch(let reported, let actual):
            "Numeric repair loop reported \(reported) iterations, but contains \(actual) iteration records."
        case .duplicateIterationIndex(let index):
            "Numeric repair loop contains duplicate iteration index \(index)."
        case .acceptedIterationMissing(let index):
            "Numeric repair loop references accepted iteration \(index), but no such iteration record exists."
        case .selectedCandidateMismatch(let iterationIndex, let expected, let actual):
            "Iteration \(iterationIndex) selected candidate \(expected), but selection trace selected \(actual)."
        case .selectedCandidateMissing(let iterationIndex, let candidateID):
            "Iteration \(iterationIndex) selected candidate \(candidateID), but the selection trace does not rank it."
        case .duplicateSelectionCandidateID(let iterationIndex, let candidateID):
            "Iteration \(iterationIndex) selection trace contains duplicate candidate ID \(candidateID)."
        case .duplicateVerificationGateID(let iterationIndex, let gateID):
            "Iteration \(iterationIndex) plan verification contains duplicate gate ID \(gateID)."
        }
    }
}
