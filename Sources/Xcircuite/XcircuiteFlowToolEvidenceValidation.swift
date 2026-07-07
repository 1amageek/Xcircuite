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

            if let sha256 = artifact.sha256 {
                try validateArtifactSHA256(sha256, stageID: stageID)
            }
        }

        if qualification?.qualified == true, !hasPassingQualificationSupport {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "qualified evidence must include artifact, policyID, observedMetrics, or observedCounts"
            )
        }

        guard requiresPassingQualification else {
            return
        }

        guard let qualification else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "\(kind.rawValue) evidence requires a qualification summary"
            )
        }

        guard qualification.qualified else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "\(kind.rawValue) evidence must be qualified before runtime attachment"
            )
        }

        guard qualification.failureCodes.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.invalidToolEvidence(
                stageID: stageID,
                evidenceID: evidenceID,
                reason: "qualified evidence must not include failureCodes"
            )
        }
    }

    private var requiresPassingQualification: Bool {
        switch kind {
        case .corpus, .oracle, .productionApproval:
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
