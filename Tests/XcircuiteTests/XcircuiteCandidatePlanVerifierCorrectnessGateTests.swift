import Testing
@testable import Xcircuite
import DesignFlowKernel

@Suite("Xcircuite candidate plan verifier correctness gates")
struct XcircuiteCandidatePlanVerifierCorrectnessGateTests {
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
            artifactRefs: [
                XcircuiteFileReference(
                    artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                    path: ".xcircuite/runs/run-evidence/planning/candidate-plan.json",
                    kind: .other,
                    format: .json,
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 2,
                    producedByRunID: "run-evidence"
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
