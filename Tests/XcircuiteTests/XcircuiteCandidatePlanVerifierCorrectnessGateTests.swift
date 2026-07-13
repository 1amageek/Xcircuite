import Testing
@testable import Xcircuite
import CircuiteFoundation
import DesignFlowKernel

@Suite("Xcircuite candidate plan verifier correctness gates")
struct XcircuiteCandidatePlanVerifierCorrectnessGateTests {
    @Test func foundationArtifactReferencesPreserveIdentityAndIntegrityMetadata() throws {
        let legacyReference = XcircuiteFileReference(
            artifactID: "planning-native-drc-result",
            path: ".xcircuite/runs/run-evidence/planning/native-drc/result.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 7,
            producedByRunID: "run-evidence"
        )

        let artifact = try #require(
            foundationArtifactReferences([legacyReference], field: "correctness-gate-test").first
        )

        #expect(artifact.id.rawValue == "planning-native-drc-result")
        #expect(artifact.locator.role == .output)
        #expect(artifact.digest.hexadecimalValue == String(repeating: "a", count: 64))
        #expect(artifact.byteCount == 7)
        #expect(uniqueArtifactReferences([artifact, artifact]) == [artifact])
    }

    @Test func postExecutionSignoffRejectsPassedNativeGateWithoutEvidenceArtifact() throws {
        let gate = XcircuiteCandidatePlanVerifier().postExecutionSignoffCorrectnessGate(
            verificationMode: "post-execution",
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: "native-drc",
                    required: true,
                    status: "passed",
                    sourceStepIDs: ["step-1"]
                ),
            ],
            artifactReferences: try foundationArtifactReferences([
                XcircuiteFileReference(
                    artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                    path: ".xcircuite/runs/run-evidence/planning/candidate-plan.json",
                    kind: .other,
                    format: .json,
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 2,
                    producedByRunID: "run-evidence"
                ),
            ], field: "correctness-gate-test")
        )

        #expect(gate.status == "failed")
        #expect(gate.diagnostics.contains {
            $0.code == "post-execution-signoff-evidence-missing"
                && $0.gateID == "native-drc"
        })
        #expect(gate.nextActions.contains("rerun-verification-gate:native-drc"))
    }

    @Test func verificationStatusRejectsFailedCorrectnessGateEvenWhenAcceptedFlagIsStale() throws {
        let verification = XcircuitePlanVerification(
            problemID: "problem",
            planID: "plan",
            runID: "run-evidence",
            verificationMode: "post-execution",
            candidatePlanRef: XcircuiteFileReference(
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

        #expect(XcircuiteCandidatePlanVerifier().verificationStatus(for: verification) == "rejected")
    }
}
