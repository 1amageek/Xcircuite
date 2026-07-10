import Foundation
import LVSEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

@Suite("Xcircuite LVS repair loop")
struct XcircuiteLVSRepairLoopTests {
    @Test func repairHintArtifactDrivesCLIPlanningAndVerifiedPortRepair() async throws {
        let root = try makeTemporaryRoot("repair-hint-artifact-cli-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let runID = "run-lvs-hint-port"
        let layoutPath = "layout/port-layout.json"
        let layoutNetlistPath = "circuits/layout.spice"
        let schematicNetlistPath = "circuits/schematic.spice"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-summary.json"
        let repairHintPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-repair-hints.json"
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeSimpleLayoutDocument(path: layoutPath, root: root)
        try writeMatchingLVSNetlists(
            layoutPath: layoutNetlistPath,
            schematicPath: schematicNetlistPath,
            root: root
        )
        try registerJSONArtifact(
            makePortSummary(),
            artifactID: "lvs-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerJSONArtifact(
            makePortRepairHints(),
            artifactID: "lvs-repair-hints",
            path: repairHintPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerExistingArtifact(
            artifactID: "layout-document",
            path: layoutPath,
            kind: .layout,
            format: .json,
            root: root,
            runID: runID
        )

        let generationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--source",
                "lvs-summary",
                "--layout-artifact-id",
                "layout-document",
                "--repair-hint-artifact-id",
                "lvs-repair-hints",
                "--layout-netlist-path",
                layoutNetlistPath,
                "--schematic-netlist-path",
                schematicNetlistPath,
            ]
        )
        let generationData = try #require(generationJSON.data(using: .utf8))
        let generation = try JSONDecoder().decode(
            XcircuitePlanningProblemGenerationResult.self,
            from: generationData
        )
        #expect(generation.status == "generated")
        #expect(generation.summaryPath == summaryPath)
        #expect(generation.repairHintPath == repairHintPath)

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: generation.problemArtifact.path)
        )
        #expect(problem.sourceRefs.contains {
            $0.refID == "lvs-repair-hints" && $0.path == repairHintPath
        })
        #expect(problem.initialStateRefs.contains {
            $0.refID == "layout-netlist-ref" && $0.path == layoutNetlistPath
        })
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("lvs.export-repair-hints"))
        #expect(problem.candidateActions.map(\.operationID) == ["layout.add-label"])
        #expect(problem.candidateActions.first?.parameterHints["sourceRepairHintID"] == .string("lvs-repair-0-LVS_PORT_MISMATCH"))
        #expect(problem.candidateActions.first?.parameterHints["lvsInputs"] == .object([
            "layoutNetlistRef": .string("layout-netlist-ref"),
            "schematicNetlistRef": .string("schematic-netlist-ref"),
            "topCell": .string("top"),
        ]))

        let candidateJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let candidateData = try #require(candidateJSON.data(using: .utf8))
        let candidateGeneration = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: candidateData
        )
        #expect(candidateGeneration.executionReadiness == "ready")

        let executionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let executionData = try #require(executionJSON.data(using: .utf8))
        let execution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: executionData
        )
        #expect(execution.status == "executed")
        #expect(execution.producedArtifacts.contains { $0.artifactID == "candidate-step-1-layout-document" })

        let verificationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--mode",
                "post-execution",
            ]
        )
        let verificationData = try #require(verificationJSON.data(using: .utf8))
        let verification = try JSONDecoder().decode(
            XcircuiteCandidatePlanVerificationResult.self,
            from: verificationData
        )
        #expect(verification.status == "accepted")
        #expect(verification.accepted)

        let verificationDocument = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: verification.planVerificationArtifact.path)
        )
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verificationDocument.goalCoverageStatus == "covered")
        #expect(verificationDocument.missingGoalAtoms.isEmpty)
        #expect(verificationDocument.finalSymbolicState.contains("label-created"))
        #expect(verificationDocument.finalSymbolicState.contains("artifact:layout-document"))
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
    }

    @Test func approvedPolicyRepairArtifactDrivesNativeLVSVerification() async throws {
        let root = try makeTemporaryRoot("approved-policy-repair-cli-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let runID = "run-lvs-policy-repair"
        let layoutNetlistPath = "circuits/model-layout.spice"
        let schematicNetlistPath = "circuits/model-schematic.spice"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-summary.json"
        let repairHintPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-repair-hints.json"
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeModelMismatchLVSNetlists(
            layoutPath: layoutNetlistPath,
            schematicPath: schematicNetlistPath,
            root: root
        )
        try registerJSONArtifact(
            makeModelPolicySummary(),
            artifactID: "lvs-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerJSONArtifact(
            makeModelPolicyRepairHints(),
            artifactID: "lvs-repair-hints",
            path: repairHintPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )

        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--source",
                "lvs-summary",
                "--repair-hint-artifact-id",
                "lvs-repair-hints",
                "--layout-netlist-path",
                layoutNetlistPath,
                "--schematic-netlist-path",
                schematicNetlistPath,
            ]
        )
        let candidateJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let candidateGeneration = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: try #require(candidateJSON.data(using: .utf8))
        )
        #expect(candidateGeneration.executionReadiness == "ready")

        let blockedExecutionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let blockedExecution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: try #require(blockedExecutionJSON.data(using: .utf8))
        )
        #expect(blockedExecution.status == "blocked")
        #expect(blockedExecution.nextActions == ["request-human-approval:policy-repair-approval"])

        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "approve-candidate-plan-risk",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--approval-id",
                "policy-repair-approval",
                "--reviewer",
                "lvs-policy-reviewer",
            ]
        )
        let executionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let execution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: try #require(executionJSON.data(using: .utf8))
        )
        #expect(execution.status == "executed")
        let policyArtifact = try #require(execution.producedArtifacts.first {
            $0.artifactID == "candidate-step-1-model-equivalence-policy"
        })
        #expect(execution.producedArtifacts.contains {
            $0.artifactID == "candidate-step-1-lvs-policy-repair-report"
        })

        let designDiffArtifact = try #require(execution.designDiffArtifact)
        let designDiff = try store.readJSON(
            XcircuiteDesignDiff.self,
            from: root.appending(path: designDiffArtifact.path)
        )
        #expect(designDiff.changes.first?.domain == .verification)
        #expect(designDiff.changes.first?.operation == .add)

        let policy = try store.readJSON(
            LVSModelEquivalencePolicy.self,
            from: root.appending(path: policyArtifact.path)
        )
        #expect(policy.groups == [
            LVSModelEquivalenceGroup(
                canonicalModel: "nmos",
                aliases: ["sky130_fd_pr__nfet_01v8"]
            ),
        ])

        let verificationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--mode",
                "post-execution",
            ]
        )
        let verification = try JSONDecoder().decode(
            XcircuiteCandidatePlanVerificationResult.self,
            from: try #require(verificationJSON.data(using: .utf8))
        )
        #expect(verification.status == "accepted")
        #expect(verification.accepted)

        let verificationDocument = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: verification.planVerificationArtifact.path)
        )
        #expect(verificationDocument.gateResults.contains { $0.gateID == "approval-gate" && $0.status == "passed" })
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verificationDocument.goalCoverageStatus == "covered")
        #expect(verificationDocument.missingGoalAtoms.isEmpty)
        #expect(verificationDocument.finalSymbolicState.contains("model-or-terminal-equivalence-policy-updated"))
        #expect(verificationDocument.finalSymbolicState.contains("artifact:policy-artifact"))
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
        let correctnessGates = Dictionary(
            uniqueKeysWithValues: verificationDocument.correctnessGateResults.map { ($0.gateID, $0.status) }
        )
        #expect(correctnessGates["action-domain-binding"] == "passed")
        #expect(correctnessGates["post-execution-signoff"] == "passed")
        #expect(correctnessGates["feedback-closure"] == "passed")
    }

    @Test func approvedTerminalPolicyRepairArtifactDrivesNativeLVSVerification() async throws {
        let root = try makeTemporaryRoot("approved-terminal-policy-repair-cli-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        let runID = "run-lvs-terminal-policy-repair"
        let layoutNetlistPath = "circuits/terminal-layout.spice"
        let schematicNetlistPath = "circuits/terminal-schematic.spice"
        let summaryPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-summary.json"
        let repairHintPath = ".xcircuite/runs/\(runID)/stages/native-lvs/lvs-repair-hints.json"
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeTerminalMismatchLVSNetlists(
            layoutPath: layoutNetlistPath,
            schematicPath: schematicNetlistPath,
            root: root
        )
        try registerJSONArtifact(
            makeTerminalPolicySummary(),
            artifactID: "lvs-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerJSONArtifact(
            makeTerminalPolicyRepairHints(),
            artifactID: "lvs-repair-hints",
            path: repairHintPath,
            kind: .report,
            format: .json,
            root: root,
            runID: runID
        )
        try registerExistingArtifact(
            artifactID: "layout-netlist",
            path: layoutNetlistPath,
            kind: .netlist,
            format: .spice,
            root: root,
            runID: runID
        )
        try registerExistingArtifact(
            artifactID: "schematic-netlist",
            path: schematicNetlistPath,
            kind: .netlist,
            format: .spice,
            root: root,
            runID: runID
        )

        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--source",
                "lvs-summary",
                "--repair-hint-artifact-id",
                "lvs-repair-hints",
                "--layout-netlist-path",
                layoutNetlistPath,
                "--schematic-netlist-path",
                schematicNetlistPath,
            ]
        )
        let candidateJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let candidateGeneration = try JSONDecoder().decode(
            XcircuiteCandidatePlanGenerationResult.self,
            from: try #require(candidateJSON.data(using: .utf8))
        )
        #expect(candidateGeneration.executionReadiness == "ready")

        let blockedExecutionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let blockedExecution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: try #require(blockedExecutionJSON.data(using: .utf8))
        )
        #expect(blockedExecution.status == "blocked")
        #expect(blockedExecution.nextActions == ["request-human-approval:policy-repair-approval"])

        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "approve-candidate-plan-risk",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--approval-id",
                "policy-repair-approval",
                "--reviewer",
                "lvs-terminal-policy-reviewer",
            ]
        )
        let executionJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
            ]
        )
        let execution = try JSONDecoder().decode(
            XcircuiteCandidatePlanExecutionResult.self,
            from: try #require(executionJSON.data(using: .utf8))
        )
        #expect(execution.status == "executed")
        let policyArtifact = try #require(execution.producedArtifacts.first {
            $0.artifactID == "candidate-step-1-terminal-equivalence-policy"
        })
        let reportArtifact = try #require(execution.producedArtifacts.first {
            $0.artifactID == "candidate-step-1-lvs-policy-repair-report"
        })

        let policy = try store.readJSON(
            LVSTerminalEquivalencePolicy.self,
            from: root.appending(path: policyArtifact.path)
        )
        #expect(policy.rules == [
            LVSTerminalEquivalenceRule(
                kind: "diode",
                pinCount: 2,
                equivalentPinGroups: [[0, 1]]
            ),
        ])
        let report = try store.readJSON(
            XcircuiteLVSPolicyRepairReport.self,
            from: root.appending(path: reportArtifact.path)
        )
        #expect(report.policyKind == "terminal-equivalence")
        #expect(report.terminalKind == "diode")
        #expect(report.equivalentPinGroups == [[0, 1]])

        let verificationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "verify-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                runID,
                "--mode",
                "post-execution",
            ]
        )
        let verification = try JSONDecoder().decode(
            XcircuiteCandidatePlanVerificationResult.self,
            from: try #require(verificationJSON.data(using: .utf8))
        )
        #expect(verification.status == "accepted")
        #expect(verification.accepted)

        let verificationDocument = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: verification.planVerificationArtifact.path)
        )
        #expect(verificationDocument.gateResults.contains { $0.gateID == "approval-gate" && $0.status == "passed" })
        #expect(verificationDocument.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(verificationDocument.goalCoverageStatus == "covered")
        #expect(verificationDocument.missingGoalAtoms.isEmpty)
        #expect(verificationDocument.finalSymbolicState.contains("model-or-terminal-equivalence-policy-updated"))
        #expect(verificationDocument.finalSymbolicState.contains("artifact:policy-artifact"))
        #expect(verificationDocument.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })
    }

    @Test func closedLVSRepairLoopUsesEditedLayoutNetlistAndAcceptsRepairedCandidate() async throws {
        let root = try makeTemporaryRoot("closed-lvs-repair-loop")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-1")

        try persistCandidatePlan(
            makeLVSPlan(
                runID: "run-1",
                planID: "run-1-lvs-width-failing-plan",
                width: 1.0,
                sourceCandidateID: "lvs-layout-m1-width-1"
            ),
            root: root
        )
        _ = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-1"),
            projectRoot: root
        )

        let rejected = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-1",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(rejected.status == "rejected")
        #expect(rejected.accepted == false)
        #expect(rejected.nextActions.contains("repair-verification-gate:native-lvs"))
        let rejectedVerification = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: rejected.planVerificationArtifact.path)
        )
        #expect(rejectedVerification.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "failed" })
        #expect(rejectedVerification.diagnostics.contains { $0.code == "LVS_PARAMETER_MISMATCH" })

        let rejectedPlansArtifact = try #require(rejected.rejectedPlansArtifact)
        let rejectedRecordsAfterFailure = try readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: root.appending(path: rejectedPlansArtifact.path)
        )
        let rejectedRecord = try #require(rejectedRecordsAfterFailure.last)
        #expect(rejectedRecord.status == "rejected")
        #expect(rejectedRecord.planID == "run-1-lvs-width-failing-plan")
        #expect(rejectedRecord.failedGateIDs.contains("native-lvs"))
        #expect(rejectedRecord.sourceParameterCandidateIDs == ["lvs-layout-m1-width-1"])
        #expect(rejectedRecord.artifactRefs.contains { $0.artifactID == "candidate-step-1-edited-netlist" })
        #expect(rejectedRecord.artifactRefs.contains { $0.artifactID == "candidate-step-1-netlist-parameter-edit-report" })

        try persistCandidatePlan(
            makeLVSPlan(
                runID: "run-1",
                planID: "run-1-lvs-width-repaired-plan",
                width: 2.0,
                sourceCandidateID: "lvs-layout-m1-width-2"
            ),
            root: root
        )
        let repairExecution = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-1"),
            projectRoot: root
        )
        #expect(repairExecution.status == "executed")
        #expect(repairExecution.producedArtifacts.contains { $0.artifactID == "candidate-step-1-edited-netlist" })
        #expect(repairExecution.producedArtifacts.contains { $0.artifactID == "candidate-step-1-netlist-parameter-edit-report" })

        let accepted = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(
                runID: "run-1",
                verificationMode: "post-execution"
            ),
            projectRoot: root
        )

        #expect(accepted.status == "accepted")
        #expect(accepted.accepted)
        #expect(accepted.nextActions.isEmpty)
        let acceptedVerification = try store.readJSON(
            XcircuitePlanVerification.self,
            from: root.appending(path: accepted.planVerificationArtifact.path)
        )
        #expect(acceptedVerification.gateResults.contains { $0.gateID == "native-lvs" && $0.status == "passed" })
        #expect(acceptedVerification.artifactRefs.contains { $0.artifactID == "planning-native-lvs-summary" })

        let rejectedRecordsAfterRepair = try readJSONLines(
            XcircuiteRejectedPlanRecord.self,
            from: root.appending(path: rejectedPlansArtifact.path)
        )
        #expect(rejectedRecordsAfterRepair.count == 1)
        #expect(rejectedRecordsAfterRepair.first?.planID == "run-1-lvs-width-failing-plan")

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains { $0.artifactID == "candidate-step-1-edited-netlist" })
        #expect(manifest.artifacts.contains { $0.artifactID == "candidate-step-1-netlist-parameter-edit-report" })
        #expect(manifest.artifacts.contains { $0.artifactID == "planning-native-lvs-summary" })
        let action = try #require(store.loadRunActions(runID: "run-1", inProjectAt: root).last)
        #expect(action.status == .succeeded)
    }

    private func prepareRun(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText(
            """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=1 L=0.15
            M2 out in vss vss nmos W=1 L=0.15
            .ends inv
            """,
            path: "circuits/layout.spice",
            root: root
        )
        try writeText(
            """
            .subckt inv in out vdd vss
            M1 out in vdd vdd pmos W=2 L=0.15
            M2 out in vss vss nmos W=1 L=0.15
            .ends inv
            """,
            path: "circuits/schematic.spice",
            root: root
        )
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makeLVSProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
    }

    private func makeLVSProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-lvs-repair-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-netlist-ref",
                    kind: "layout-netlist",
                    path: "circuits/layout.spice"
                ),
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/schematic.spice"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-m1-width-equivalence",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "layout-and-schematic-equivalent",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair the layout netlist device width so native LVS passes."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "native-lvs-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The repaired layout netlist must pass native LVS.",
                    sourceRefIDs: []
                ),
            ],
            actionDomainRefs: ["simulation-analysis", "lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "edit-layout-netlist-m1-width",
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    reason: "Materialize a candidate layout netlist edit and rerun native LVS.",
                    sourceObjectiveIDs: ["lvs-m1-width-equivalence"],
                    requiredInputRefs: ["layout-netlist-ref", "schematic-netlist-ref"],
                    verificationGates: ["artifact-integrity", "native-lvs"],
                    parameterHints: [
                        "lvsEditedNetlistRole": .string("layout"),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate netlists must match."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeLVSPlan(
        runID: String,
        planID: String,
        width: Double,
        sourceCandidateID: String
    ) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: planID,
            problemID: "\(runID)-lvs-repair-problem",
            runID: runID,
            strategy: "closed-lvs-layout-netlist-repair",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "edit-layout-netlist-m1-width",
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["lvs-m1-width-equivalence"],
                    requiredInputRefs: ["layout-netlist-ref", "schematic-netlist-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-lvs"],
                    reason: "Edit layout netlist M1 width and verify the resulting LVS equivalence.",
                    parameterHints: [
                        "netlistPath": .string("circuits/layout.spice"),
                        "sourceParameterCandidateID": .string(sourceCandidateID),
                        "lvsEditedNetlistRole": .string("layout"),
                        "assignments": .array([
                            .object([
                                "name": .string("M1.w"),
                                "value": .number(width),
                            ]),
                        ]),
                        "lvsInputs": .object([
                            "layoutNetlistRef": .string("layout-netlist-ref"),
                            "schematicNetlistRef": .string("schematic-netlist-ref"),
                            "topCell": .string("inv"),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate netlists must match."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makePortSummary() -> LVSRunSummaryReport {
        LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "top",
                layoutInputKind: "layout-document-json",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "LVS_PORT_MISMATCH",
                        category: "portMismatch",
                        componentSignature: nil,
                        parameterName: nil,
                        layoutModel: nil,
                        schematicModel: nil,
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: nil,
                        schematicCount: nil,
                        layoutPorts: ["in", "out"],
                        schematicPorts: ["in", "out", "vdd"],
                        suggestedFixes: ["add missing vdd label"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
    }

    private func makePortRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "top",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-LVS_PORT_MISMATCH",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.add-label",
                    confidence: "high",
                    ruleID: "LVS_PORT_MISMATCH",
                    category: "portMismatch",
                    componentSignature: nil,
                    parameterName: nil,
                    layoutModel: nil,
                    schematicModel: nil,
                    layoutValue: nil,
                    schematicValue: nil,
                    layoutPorts: ["in", "out"],
                    schematicPorts: ["in", "out", "vdd"],
                    layoutCount: nil,
                    schematicCount: nil,
                    stringParameters: [
                        "labelText": "vdd",
                        "netName": "vdd",
                        "portName": "vdd",
                    ],
                    verificationGates: ["native-lvs", "artifact-integrity"],
                    rationale: "LVS_PORT_MISMATCH maps to layout.add-label because the layout is missing a schematic-visible port label."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeModelPolicySummary() -> LVSRunSummaryReport {
        LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "top",
                layoutInputKind: "layout-netlist",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "LVS_MODEL_MISMATCH",
                        category: "modelMismatch",
                        componentSignature: "mos|nmos|out,in,vss,vss|",
                        parameterName: nil,
                        layoutModel: "sky130_fd_pr__nfet_01v8",
                        schematicModel: "nmos",
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: 1,
                        schematicCount: 1,
                        layoutPorts: ["D", "G", "S", "B"],
                        schematicPorts: ["D", "G", "S", "B"],
                        suggestedFixes: ["review_model_equivalence_policy"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
    }

    private func makeModelPolicyRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "top",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-LVS_MODEL_MISMATCH",
                    sourceDiagnosticIndex: 0,
                    operationID: "lvs.policy-repair",
                    confidence: "medium",
                    ruleID: "LVS_MODEL_MISMATCH",
                    category: "modelMismatch",
                    componentSignature: "mos|nmos|out,in,vss,vss|",
                    parameterName: nil,
                    layoutModel: "sky130_fd_pr__nfet_01v8",
                    schematicModel: "nmos",
                    layoutValue: nil,
                    schematicValue: nil,
                    layoutPorts: ["D", "G", "S", "B"],
                    schematicPorts: ["D", "G", "S", "B"],
                    layoutCount: 1,
                    schematicCount: 1,
                    stringParameters: [
                        "layoutModel": "sky130_fd_pr__nfet_01v8",
                        "schematicModel": "nmos",
                    ],
                    verificationGates: ["approval-gate", "native-lvs", "artifact-integrity"],
                    rationale: "LVS_MODEL_MISMATCH maps to lvs.policy-repair because model equivalence may need an approved policy update."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeTerminalPolicySummary() -> LVSRunSummaryReport {
        LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "clamp",
                layoutInputKind: "layout-netlist",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "LVS_TERMINAL_EQUIVALENCE_MISMATCH",
                        category: "terminalEquivalence",
                        componentSignature: "diode|diode|in,vss|",
                        parameterName: nil,
                        layoutModel: "diode",
                        schematicModel: "diode",
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: 1,
                        schematicCount: 1,
                        layoutPorts: ["in", "vss"],
                        schematicPorts: ["vss", "in"],
                        suggestedFixes: ["review_terminal_equivalence_policy"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
    }

    private func makeTerminalPolicyRepairHints() -> LVSRepairHintReport {
        LVSRepairHintBuilder().build(result: makeTerminalPolicyExecutionResult())
    }

    private func makeTerminalPolicyExecutionResult() -> LVSExecutionResult {
        LVSExecutionResult(
            request: LVSRequest(
                layoutNetlistURL: URL(filePath: "/tmp/terminal-layout.spice"),
                schematicNetlistURL: URL(filePath: "/tmp/terminal-schematic.spice"),
                topCell: "clamp",
                backendSelection: LVSBackendSelection(backendID: "native")
            ),
            result: LVSResult(
                backendID: "native",
                toolName: "NativeLVS",
                success: true,
                completed: true,
                logPath: "",
                diagnostics: [
                    LVSDiagnostic(
                        severity: .error,
                        message: "Terminal equivalence mismatch",
                        ruleID: "LVS_TERMINAL_EQUIVALENCE_MISMATCH",
                        category: "terminalEquivalence",
                        componentSignature: "diode|diode|in,vss|",
                        layoutCount: 1,
                        schematicCount: 1,
                        layoutModel: "diode",
                        schematicModel: "diode",
                        layoutPorts: ["in", "vss"],
                        schematicPorts: ["vss", "in"],
                        suggestedFix: "Review terminal equivalence policy.",
                        rawLine: "layout_ports=in,vss schematic_ports=vss,in"
                    ),
                ]
            )
        )
    }

    private func writeSimpleLayoutDocument(path: String, root: URL) throws {
        let text = """
        {
          "cells" : [
            {
              "constraints" : [],
              "id" : "10000000-0000-0000-0000-000000020001",
              "instances" : [],
              "labels" : [],
              "name" : "top",
              "nets" : [],
              "pins" : [],
              "properties" : {},
              "shapes" : [],
              "vias" : []
            }
          ],
          "id" : "10000000-0000-0000-0000-000000020000",
          "name" : "lvs-port-layout",
          "topCellID" : "10000000-0000-0000-0000-000000020001",
          "units" : { "dbuPerMicron" : 1000 }
        }
        """
        try writeText(text, path: path, root: root)
    }

    private func persistCandidatePlan(_ plan: XcircuiteCandidatePlan, root: URL) throws {
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            plan,
            runID: plan.runID,
            projectRoot: root
        )
    }

    private func writeText(_ text: String, path: String, root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMatchingLVSNetlists(
        layoutPath: String,
        schematicPath: String,
        root: URL
    ) throws {
        let netlist = """
        .subckt top in out vdd vss
        M1 out in vdd vdd pmos W=1u L=0.15u
        M2 out in vss vss nmos W=1u L=0.15u
        .ends top
        """
        try writeText(netlist, path: layoutPath, root: root)
        try writeText(netlist, path: schematicPath, root: root)
    }

    private func writeModelMismatchLVSNetlists(
        layoutPath: String,
        schematicPath: String,
        root: URL
    ) throws {
        try writeText(
            """
            .subckt top in out vss
            M1 out in vss vss sky130_fd_pr__nfet_01v8 W=1u L=0.15u
            .ends top
            """,
            path: layoutPath,
            root: root
        )
        try writeText(
            """
            .subckt top in out vss
            M1 out in vss vss nmos W=1u L=0.15u
            .ends top
            """,
            path: schematicPath,
            root: root
        )
    }

    private func writeTerminalMismatchLVSNetlists(
        layoutPath: String,
        schematicPath: String,
        root: URL
    ) throws {
        try writeText(
            """
            .subckt clamp in vss
            D1 in vss diode area=1
            .ends clamp
            """,
            path: layoutPath,
            root: root
        )
        try writeText(
            """
            .subckt clamp in vss
            D1 vss in diode area=1
            .ends clamp
            """,
            path: schematicPath,
            root: root
        )
    }

    private func registerJSONArtifact<T: Encodable>(
        _ value: T,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(value, to: url, forProjectAt: root)
        try registerExistingArtifact(
            artifactID: artifactID,
            path: path,
            kind: kind,
            format: format,
            root: root,
            runID: runID
        )
    }

    private func registerExistingArtifact(
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteLVSRepairLoopTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text
            .split(separator: "\n")
            .map { line in
                try decoder.decode(type, from: Data(line.utf8))
            }
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
