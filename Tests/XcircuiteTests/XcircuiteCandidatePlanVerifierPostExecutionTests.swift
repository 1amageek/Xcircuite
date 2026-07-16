import CircuiteFoundation
import Foundation
import LayoutAutoGen
import LayoutCore
import LayoutIO
import LayoutTech
import PEXEngine
import Testing
@testable import Xcircuite
import XcircuiteFlowCLISupport

extension XcircuiteCandidatePlanVerifierTests {
    @Test func postExecutionVerificationRunsNativeDRCGateAndAcceptsPassingPlan() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-drc-pass")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-3", store: store)
        _ = try await artifactStore.persistCandidatePlan(
            makeExecutableDRCPlan(runID: "run-3", width: 2, requiredWidth: 1),
            runID: "run-3",
            projectRoot: root
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-3"),
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "verify-candidate-plan",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-3",
            "--mode",
            "post-execution",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteCandidatePlanVerificationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "accepted")
        #expect(result.accepted)
        #expect(result.nextActions.isEmpty)

        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.verificationMode == "post-execution")
        #expect(verification.gateResults.contains { $0.gateID == "native-drc" && $0.status == "passed" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-native-drc-summary" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-native-drc-layout" })

        let ledger = try await store.loadRunLedger(runID: "run-3")
        #expect(ledger.artifacts.contains { $0.id.rawValue == "planning-native-drc-summary" })

        let action = try #require((try await store.loadRunActions(runID: "run-3")).last)
        #expect(action.actionKind == "planning.verify-candidate-plan")
        #expect(action.status == .succeeded)
    }

    @Test func postExecutionVerificationRejectsNativeDRCViolation() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-drc-fail")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-4", store: store)
        _ = try await artifactStore.persistCandidatePlan(
            makeExecutableDRCPlan(runID: "run-4", width: 0.5, requiredWidth: 1),
            runID: "run-4",
            projectRoot: root
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-4"),
            projectRoot: root
        )

        let verificationResult = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-4",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(verificationResult.status == "rejected")
        #expect(verificationResult.accepted == false)
        #expect(verificationResult.nextActions.contains("repair-verification-gate:native-drc"))

        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: verificationResult.planVerificationArtifact.path
        )
        #expect(verification.gateResults.contains { $0.gateID == "native-drc" && $0.status == "failed" })
        #expect(verification.diagnostics.contains { $0.code == "M1.width" })
        let action = try #require((try await store.loadRunActions(runID: "run-4")).last)
        #expect(action.status == .failed)
    }

    @Test func postExecutionVerificationRejectsNativeDRCWhenRequestedTopCellIsMissing() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-drc-missing-top")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        let runID = "run-drc-missing-top"
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: store)
        var plan = makeExecutableDRCPlan(runID: runID, width: 2, requiredWidth: 1)
        plan.steps[0].parameterHints["topCell"] = .text("missing_top")
        _ = try await artifactStore.persistCandidatePlan(
            plan,
            runID: runID,
            projectRoot: root
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: runID),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "rejected")
        #expect(result.accepted == false)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        let gate = try #require(verification.gateResults.first { $0.gateID == "native-drc" })
        #expect(gate.status == "failed")
        #expect(gate.diagnostics.contains { $0.code == "native-drc-execution-failed" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-native-drc-summary" } == false)
    }

    @Test func postExecutionVerificationRunsNativeLVSGateAndAcceptsMatchingNetlists() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-lvs-pass")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareExecutableLVSRun(
            root: root,
            runID: "run-5",
            layoutNetlist: """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=1u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends inv
            """,
            schematicNetlist: """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=1u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends inv
            """,
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-5"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-5",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "accepted")
        #expect(result.accepted)
        #expect(result.nextActions.isEmpty)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
        let ledger = try await store.loadRunLedger(runID: "run-5")
        #expect(ledger.artifacts.contains { $0.artifactID == "planning-native-lvs-summary" })
        let action = try #require((try await store.loadRunActions(runID: "run-5")).last)
        #expect(action.status == .succeeded)
    }

    @Test func postExecutionVerificationUsesProducedStandardLayoutCorpusForNativeLVS() async throws {
        for layoutCase in producedLayoutCorpusCases() {
            for circuitCase in producedLVSCircuitCorpusCases() {
                let corpusID = "\(layoutCase.id)/\(circuitCase.id)"
                let root = try makeTemporaryRoot(
                    "candidate-plan-post-execution-lvs-produced-\(layoutCase.id)-\(circuitCase.id)"
                )
                defer { removeTemporaryRoot(root) }
                let store = try XcircuiteWorkspaceStore(projectRoot: root)
                let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
                let runID = "run-produced-lvs-\(layoutCase.id)-\(circuitCase.id)"
                try await prepareProducedStandardLayoutLVSRun(
                    root: root,
                    runID: runID,
                    layoutCase: layoutCase,
                    circuitCase: circuitCase,
                    store: store,
                    artifactStore: artifactStore
                )

                let result = try await XcircuiteCandidatePlanVerifier(
                    workspaceStore: store,
                    artifactStore: artifactStore
                ).verifyCandidatePlan(
                    request: XcircuiteCandidatePlanVerificationRequest(
                        runID: runID,
                        verificationMode: "post-execution"
                    ),
                    projectRoot: root
                )
                #expect(result.status == "accepted", "case=\(corpusID)")
                #expect(result.accepted, "case=\(corpusID)")
                let verification = try await store.readJSON(
                    XcircuitePlanVerification.self,
                    from: result.planVerificationArtifact.path
                )
                #expect(
                    verification.artifactRefs.contains { $0.artifactID == layoutCase.artifactID },
                    "case=\(corpusID)"
                )
                #expect(
                    verification.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" },
                    "case=\(corpusID)"
                )
                #expect(
                    verification.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" },
                    "case=\(corpusID)"
                )
                let action = try #require((try await store.loadRunActions(runID: runID)).last)
                #expect(action.status == .succeeded, "case=\(corpusID)")
            }
        }
    }

    @Test func postExecutionVerificationRejectsNativeLVSMismatch() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-lvs-fail")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareExecutableLVSRun(
            root: root,
            runID: "run-6",
            layoutNetlist: """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=1u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends inv
            """,
            schematicNetlist: """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=2u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends inv
            """,
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-6"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-6",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "rejected")
        #expect(result.accepted == false)
        #expect(result.nextActions.contains("repair-verification-gate:native-lvs"))
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "failed" })
        #expect(verification.diagnostics.contains { $0.code == "LVS_PARAMETER_MISMATCH" })
        let action = try #require((try await store.loadRunActions(runID: "run-6")).last)
        #expect(action.status == .failed)
    }

    @Test func postExecutionVerificationBlocksMockPEXSummaryEvenWhenPlanAllowsMockBackend() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-pex-mock-plan-allow")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareExecutablePEXRun(
            root: root,
            runID: "run-7",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-7"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-7",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.accepted == false)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        let gate = try #require(verification.gateResults.first { $0.gateID == "pex-summary-gate" })
        #expect(gate.status == "blocked")
        #expect(gate.diagnostics.contains { $0.code == "pex-mock-backend-not-approved" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-pex-summary" } == false)
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-pex-manifest" } == false)
        let action = try #require((try await store.loadRunActions(runID: "run-7")).last)
        #expect(action.status == .blocked)
    }

    @Test func postExecutionVerificationBlocksPEXSummaryGateWithoutExplicitBackend() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-pex-missing-backend")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        let runID = "run-pex-missing-backend"
        try await prepareExecutablePEXRun(
            root: root,
            runID: runID,
            store: store,
            artifactStore: artifactStore
        )
        var plan = makeExecutablePEXPlan(runID: runID)
        try updatePEXInputs(in: &plan) { inputs in
            inputs.backendID = ""
            inputs.allowMockBackend = false
        }
        _ = try await artifactStore.persistCandidatePlan(
            plan,
            runID: runID,
            projectRoot: root
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: runID),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.accepted == false)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        let gate = try #require(verification.gateResults.first { $0.gateID == "pex-summary-gate" })
        #expect(gate.status == "blocked")
        #expect(gate.diagnostics.contains { $0.code == "pex-backend-required" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-pex-summary" } == false)
    }

    @Test func postExecutionVerificationBlocksPEXSummaryGateWhenMockBackendIsNotApproved() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-pex-mock-not-approved")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        let runID = "run-pex-mock-not-approved"
        try await prepareExecutablePEXRun(
            root: root,
            runID: runID,
            store: store,
            artifactStore: artifactStore
        )
        var plan = makeExecutablePEXPlan(runID: runID)
        try updatePEXInputs(in: &plan) { inputs in
            inputs.allowMockBackend = false
        }
        _ = try await artifactStore.persistCandidatePlan(
            plan,
            runID: runID,
            projectRoot: root
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: runID),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: runID,
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.accepted == false)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        let gate = try #require(verification.gateResults.first { $0.gateID == "pex-summary-gate" })
        #expect(gate.status == "blocked")
        #expect(gate.diagnostics.contains { $0.code == "pex-mock-backend-not-approved" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-pex-summary" } == false)
    }

    @Test func postExecutionVerificationUsesProducedStandardLayoutCorpusForPEXSummary() async throws {
        for layoutCase in producedLayoutCorpusCases() {
            let root = try makeTemporaryRoot("candidate-plan-post-execution-pex-produced-\(layoutCase.id)")
            defer { removeTemporaryRoot(root) }
            let store = try XcircuiteWorkspaceStore(projectRoot: root)
            let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
            let runID = "run-produced-pex-\(layoutCase.id)"
            try await prepareProducedStandardLayoutPEXRun(
                root: root,
                runID: runID,
                layoutCase: layoutCase,
                store: store,
                artifactStore: artifactStore
            )

            let result = try await XcircuiteCandidatePlanVerifier(
                workspaceStore: store,
                artifactStore: artifactStore
            ).verifyCandidatePlan(
                request: XcircuiteCandidatePlanVerificationRequest(
                    runID: runID,
                    verificationMode: "post-execution"
                ),
                projectRoot: root
            )

            #expect(result.status == "blocked", "format=\(layoutCase.id)")
            #expect(result.accepted == false, "format=\(layoutCase.id)")
            let verification = try await store.readJSON(
                XcircuitePlanVerification.self,
                from: result.planVerificationArtifact.path
            )
            let gate = try #require(
                verification.gateResults.first { $0.gateID == "pex-summary-gate" },
                "format=\(layoutCase.id)"
            )
            #expect(
                gate.status == "blocked",
                "format=\(layoutCase.id)"
            )
            #expect(gate.diagnostics.contains { $0.code == "pex-mock-backend-not-approved" })
            #expect(verification.artifactRefs.contains { $0.artifactID == "planning-pex-manifest" } == false)
            let action = try #require((try await store.loadRunActions(runID: runID)).last)
            #expect(action.status == .blocked, "format=\(layoutCase.id)")
        }
    }

    @Test func postExecutionVerificationRunsSimulationMetricGateAndAcceptsMeasurements() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-sim-pass")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareExecutableSimulationRun(
            root: root,
            runID: "run-8",
            target: 1.0,
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-8"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-8",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "accepted")
        #expect(result.accepted)
        #expect(result.nextActions.isEmpty)
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.gateResults.contains { $0.gateID == "simulation-metric-gate" && $0.status == "passed" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-simulation-summary" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-simulation-measurements" })
        #expect(verification.artifactRefs.contains { $0.artifactID == "planning-simulation-waveform" })
        let summaryRef = try #require(verification.artifactRefs.first { $0.artifactID == "planning-simulation-summary" })
        let summary = try await store.readJSON(
            XcircuiteSimulationMetricReport.self,
            from: summaryRef.path
        )
        #expect(summary.status == "passed")
        #expect(summary.source == "corespice")
        #expect(summary.verdicts.contains { $0.name == "vfinal" && $0.status == "passed" })
        let ledger = try await store.loadRunLedger(runID: "run-8")
        #expect(ledger.artifacts.contains { $0.artifactID == "planning-simulation-summary" })
        let action = try #require((try await store.loadRunActions(runID: "run-8")).last)
        #expect(action.status == .succeeded)
    }

    @Test func postExecutionVerificationRejectsSimulationMetricOutOfTolerance() async throws {
        let root = try makeTemporaryRoot("candidate-plan-post-execution-sim-fail")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareExecutableSimulationRun(
            root: root,
            runID: "run-9",
            target: 0.5,
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteCandidatePlanExecutor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-9"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-9",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "rejected")
        #expect(result.accepted == false)
        #expect(result.nextActions.contains("repair-verification-gate:simulation-metric-gate"))
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: result.planVerificationArtifact.path
        )
        #expect(verification.gateResults.contains { $0.gateID == "simulation-metric-gate" && $0.status == "failed" })
        #expect(verification.diagnostics.contains { $0.code == "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE" })
        let rejectedPlansArtifact = try #require(result.rejectedPlansArtifact)
        #expect(rejectedPlansArtifact.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID)
        #expect(rejectedPlansArtifact.path == ".xcircuite/runs/run-9/planning/rejected-plans.jsonl")
        let rejectedRecords = try await readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: rejectedPlansArtifact.path,
            store: store
        )
        let rejectedRecord = try #require(rejectedRecords.last)
        #expect(rejectedRecord.status == "rejected")
        #expect(rejectedRecord.runID == "run-9")
        #expect(rejectedRecord.planID == "run-9-simulation-metric-plan")
        #expect(rejectedRecord.failedGateIDs.contains("simulation-metric-gate"))
        #expect(rejectedRecord.planVerificationRef.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID)
        #expect(rejectedRecord.diagnostics.contains { $0.code == "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE" })
        #expect(rejectedRecord.diagnosticClassifications.contains {
            $0.diagnosticClass == .failedVerificationGate
                && $0.failedGateIDs.contains("simulation-metric-gate")
        })
        #expect(rejectedRecord.diagnosticClassifications.contains {
            $0.diagnosticClass == .objectiveRegression
                && $0.diagnosticCodes.contains("SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE")
        })
        #expect(rejectedRecord.nextActions.contains("repair-verification-gate:simulation-metric-gate"))
        let ledger = try await store.loadRunLedger(runID: "run-9")
        #expect(ledger.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
                && $0.path == rejectedPlansArtifact.path
        })
        let action = try #require((try await store.loadRunActions(runID: "run-9")).last)
        #expect(action.status == .failed)
        #expect(action.outputs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.rejectedPlansArtifactID
                && $0.path == rejectedPlansArtifact.path
        })
    }

    @Test func postExecutionRejectedPlanRecordsSourceParameterCandidateIDFromEditReport() async throws {
        let root = try makeTemporaryRoot("candidate-plan-rejected-source-candidate")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-10", store: store)
        let plan = XcircuiteCandidatePlan(
            planID: "run-10-parameter-plan",
            problemID: "run-10-parameter-problem",
            runID: "run-10",
            strategy: "parameter-candidate-feedback",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-10/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "parameter-action-1",
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["metric-vfinal"],
                    requiredInputRefs: [],
                    missingInputRefs: [],
                    verificationGates: ["approval-gate"],
                    reason: "Exercise rejected-plan feedback provenance.",
                    parameterHints: [:],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Human approval is required."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
        let candidatePlanRef = try await artifactStore.persistCandidatePlan(
            plan,
            runID: "run-10",
            projectRoot: root
        )
        let reportPath = ".xcircuite/runs/run-10/planning/executions/run-10-parameter-plan/step-1/netlist-parameter-edit-report.json"
        try await store.writeJSON(
            XcircuiteNetlistParameterEditReport(
                runID: "run-10",
                problemID: "run-10-parameter-problem",
                planID: "run-10-parameter-plan",
                stepID: "step-1",
                sourceParameterCandidateID: "candidate-42",
                sourceNetlistPath: "circuits/source.spice",
                outputNetlistPath: ".xcircuite/runs/run-10/planning/executions/run-10-parameter-plan/step-1/netlist.spice",
                outputNetlistArtifactID: "candidate-step-1-edited-netlist",
                edits: []
            ),
            to: reportPath
        )
        let reportRef = try await store.makeArtifactReference(
            forProjectRelativePath: reportPath,
            artifactID: "candidate-step-1-netlist-parameter-edit-report",
            role: .output,
            kind: .report,
            format: .json
        )
        let execution = XcircuiteCandidatePlanExecution(
            runID: "run-10",
            problemID: "run-10-parameter-problem",
            planID: "run-10-parameter-plan",
            status: "executed",
            candidatePlanRef: candidatePlanRef,
            stepResults: [
                XcircuiteCandidatePlanExecutionStepResult(
                    stepID: "step-1",
                    order: 1,
                    actionID: "parameter-action-1",
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    status: "executed",
                    artifactReferences: [reportRef]
                ),
            ],
            artifactReferences: [reportRef],
            diagnostics: [],
            nextActions: []
        )
        _ = try await artifactStore.persistPlanExecution(
            execution,
            runID: "run-10",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-10",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        let rejectedPlansArtifact = try #require(result.rejectedPlansArtifact)
        let rejectedRecords = try await readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: rejectedPlansArtifact.path,
            store: store
        )
        let rejectedRecord = try #require(rejectedRecords.last)
        #expect(rejectedRecord.status == "blocked")
        #expect(rejectedRecord.sourceParameterCandidateIDs == ["candidate-42"])
        #expect(rejectedRecord.failedGateIDs.contains("approval-gate"))
        #expect(rejectedRecord.artifactRefs.contains {
            $0.artifactID == "candidate-step-1-netlist-parameter-edit-report"
        })
    }

}
