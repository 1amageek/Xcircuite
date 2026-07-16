import Foundation
import Testing
@testable import Xcircuite
import CircuiteFoundation
import DesignFlowKernel

@Suite("Xcircuite candidate plan verifier correctness gates")
struct XcircuiteCandidatePlanVerifierCorrectnessGateTests {
    private func makeVerifier() throws -> XcircuiteCandidatePlanVerifier {
        let store = try XcircuiteWorkspaceStore(projectRoot: FileManager.default.temporaryDirectory)
        return XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: store)
        )
    }

    @Test func artifactReferencesPreserveIdentityAndIntegrityMetadata() async throws {
        let canonicalReference = try fixtureArtifactReference(
            artifactID: "planning-native-drc-result",
            path: ".xcircuite/runs/run-evidence/planning/native-drc/result.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 7,
        )

        let artifact = canonicalReference

        #expect(artifact.id.rawValue == "planning-native-drc-result")
        #expect(artifact.locator.role == .input)
        #expect(artifact.digest.hexadecimalValue == String(repeating: "a", count: 64))
        #expect(artifact.byteCount == 7)
        #expect(uniqueArtifactReferences([artifact, artifact]) == [artifact])
    }

    @Test func postExecutionSignoffRejectsPassedNativeGateWithoutEvidenceArtifact() async throws {
        let gate = try makeVerifier().postExecutionSignoffCorrectnessGate(
            verificationMode: "post-execution",
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: true,
                    status: "passed",
                    sourceStepIDs: ["step-1"]
                ),
            ],
            artifactReferences: [
                try fixtureArtifactReference(
                    artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                    path: ".xcircuite/runs/run-evidence/planning/candidate-plan.json",
                    kind: .other,
                    format: .json,
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 2,
                ),
            ]
        )

        #expect(gate.status == "failed")
        #expect(gate.diagnostics.contains {
            $0.code == "post-execution-signoff-evidence-missing"
                && $0.gateID == "native-drc"
        })
        #expect(gate.nextActions.contains("rerun-verification-gate:native-drc"))
    }

    @Test func verificationStatusRejectsFailedCorrectnessGateEvenWhenAcceptedFlagIsStale() async throws {
        let verification = XcircuitePlanVerification(
            problemID: "problem",
            planID: "plan",
            runID: "run-evidence",
            verificationMode: "post-execution",
            candidatePlanRef: try fixtureArtifactReference(
                artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                path: ".xcircuite/runs/run-evidence/planning/candidate-plan.json",
                kind: .other,
                format: .json
            ),
            stepResults: [
                XcircuitePlanVerificationStepResult(
                    stepID: "step-1",
                    order: 1,
                    actionID: "action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    status: "executed",
                    gateIDs: ["native-drc"]
                ),
            ],
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: true,
                    status: "passed"
                ),
            ],
            correctnessGateResults: [
                XcircuitePlanningCorrectnessGateResult(
                    gateID: "post-execution-signoff",
                    status: "failed",
                    summary: "Missing signoff evidence."
                ),
            ],
            artifactRefs: [],
            diagnostics: [],
            accepted: true,
            nextActions: []
        )

        #expect(try makeVerifier().verificationStatus(for: verification) == "rejected")
    }
}
