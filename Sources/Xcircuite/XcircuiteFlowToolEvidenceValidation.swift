import Foundation
import ToolQualification

extension ToolEvidence {
    func validateForRuntimeToolSpec(stageID: String) throws {
        let trimmedEvidenceID = evidenceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEvidenceID.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "evidenceID must not be empty"
            )
        }

        if let artifact {
            let trimmedPath = artifact.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                    stageID: stageID,
                    evidenceID: evidenceID,
                    reason: "artifact.path must not be empty"
                )
            }

            try validateArtifactSHA256(artifact.sha256, stageID: stageID)
        }

        guard requiresVerifiableArtifact else {
            return
        }
        guard hasVerifiableArtifactBinding else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "\(kind.rawValue) evidence requires a verifiable artifact binding"
            )
        }
    }

    private var requiresVerifiableArtifact: Bool {
        switch kind {
        case .corpus, .oracle:
            true
        case .smoke, .healthCheck:
            false
        }
    }

    private func validateArtifactSHA256(_ sha256: String, stageID: String) throws {
        let trimmedSHA256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSHA256.count == 64,
              trimmedSHA256.allSatisfy({ character in
                  character.isNumber || ("a"..."f").contains(character.lowercased())
              }) else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "artifact.sha256 must be a 64-character hex digest"
            )
        }
    }
}
