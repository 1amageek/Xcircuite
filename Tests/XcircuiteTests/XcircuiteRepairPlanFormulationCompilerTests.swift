import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite repair plan formulation compiler")
struct XcircuiteRepairPlanFormulationCompilerTests {
    @Test func formulateRepairPlanningProblemCLICompilesAuditableProblemAndPDDLExport() async throws {
        let root = try makeTemporaryRoot("repair-formulation")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-formulation", inProjectAt: root)
        try persistActionDomainSnapshot(root: root, runID: "run-formulation")
        let formulation = makeFormulation(runID: "run-formulation")
        let formulationURL = root.appending(path: "agent-repair-formulation.json")
        try store.writeJSON(formulation, to: formulationURL, forProjectAt: root)

        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "formulate-repair-planning-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-formulation",
            "--formulation-path",
            "agent-repair-formulation.json",
            "--problem-id",
            "agent-compiled-repair-problem",
            "--pretty",
        ])
        let result = try JSONDecoder().decode(
            XcircuiteRepairPlanFormulationCompilationResult.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(result.status == "compiled")
        #expect(result.formulationArtifact.path == ".xcircuite/runs/run-formulation/planning/repair-formulation.json")
        #expect(result.problemArtifact.path == ".xcircuite/runs/run-formulation/planning/problem.json")
        #expect(result.diagnosticCodes.contains("verification-gates-generated"))

        let persistedFormulation = try store.readJSON(
            XcircuiteRepairPlanFormulation.self,
            from: root.appending(path: result.formulationArtifact.path)
        )
        #expect(persistedFormulation.formulationID == "agent-sizing-repair")

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: result.problemArtifact.path)
        )
        #expect(problem.problemID == "agent-compiled-repair-problem")
        #expect(problem.sourceRefs.first?.kind == "repair-plan-formulation")
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([.string("gain-restored")]))
        #expect(problem.candidateActions.first?.operationID == "simulation.set-netlist-parameters")
        #expect(problem.verificationGates.map(\.gateID).contains("simulation-metric-gate"))
        #expect(problem.resumeContract.requiredArtifacts.contains("planning/repair-formulation.json"))

        let validationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-planning-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-formulation",
            "--pretty",
        ])
        let validation = try JSONDecoder().decode(
            XcircuitePlanningProblemValidationResult.self,
            from: try #require(validationJSON.data(using: .utf8))
        )
        #expect(validation.validation.status == "valid")

        let pddlJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "export-symbolic-planner-problem",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-formulation",
            "--pretty",
        ])
        let pddlResult = try JSONDecoder().decode(
            XcircuiteSymbolicPlannerPDDLExportResult.self,
            from: try #require(pddlJSON.data(using: .utf8))
        )
        #expect(pddlResult.export.atomMappings.contains {
            $0.atom == "gain-restored" && $0.roles.contains("goal")
        })
        #expect(pddlResult.export.actionMappings.map(\.operationID) == ["simulation.set-netlist-parameters"])

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-formulation/manifest.json")
        )
        let artifactIDs = Set(manifest.artifacts.map(\.artifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.repairPlanFormulationArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.problemArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.planningProblemValidationArtifactID))
        #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID))
    }

    @Test func compilerRejectsActionReferencingUnknownGoal() throws {
        let root = try makeTemporaryRoot("repair-formulation-unknown-goal")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-formulation", inProjectAt: root)
        var formulation = makeFormulation(runID: "run-formulation")
        formulation.actions[0].sourceGoalIDs = ["missing-goal"]

        do {
            _ = try XcircuiteRepairPlanFormulationCompiler().compile(
                request: XcircuiteRepairPlanFormulationCompilationRequest(
                    runID: "run-formulation",
                    formulation: formulation
                ),
                projectRoot: root
            )
            Issue.record("Expected formulation compilation to reject an unknown goal reference.")
        } catch let error as XcircuiteRepairPlanFormulationCompilationError {
            #expect(error == .unknownGoalReference(
                actionID: "set-bias-current",
                goalID: "missing-goal"
            ))
        }
    }

    @Test func compilerRejectsUnsupportedSchemaVersion() throws {
        var formulation = makeFormulation(runID: "run-formulation")
        formulation.schemaVersion = 2

        try expectCompilationError(
            .unsupportedSchemaVersion(2),
            formulation: formulation,
            rootName: "repair-formulation-schema-version"
        )
    }

    @Test func compilerRejectsDuplicateReferenceIDs() throws {
        var formulation = makeFormulation(runID: "run-formulation")
        formulation.sourceRefs.append(formulation.initialStateRefs[0])

        try expectCompilationError(
            .duplicateReferenceID("source-netlist"),
            formulation: formulation,
            rootName: "repair-formulation-duplicate-ref"
        )
    }

    @Test func compilerRejectsDuplicateGoalIDs() throws {
        var formulation = makeFormulation(runID: "run-formulation")
        formulation.goals.append(formulation.goals[0])

        try expectCompilationError(
            .duplicateGoalID("restore-gain"),
            formulation: formulation,
            rootName: "repair-formulation-duplicate-goal"
        )
    }

    @Test func compilerRejectsDuplicateActionIDs() throws {
        var formulation = makeFormulation(runID: "run-formulation")
        formulation.actions.append(formulation.actions[0])

        try expectCompilationError(
            .duplicateActionID("set-bias-current"),
            formulation: formulation,
            rootName: "repair-formulation-duplicate-action"
        )
    }

    @Test func compilerRejectsDuplicateCopiedPlanningEntityIDs() throws {
        let assumption = XcircuitePlanningAssumption(
            assumptionID: "review-assumption",
            source: "agent",
            statement: "A review assumption must stay uniquely addressable.",
            status: "resolved",
            confidence: 1,
            sourceRefIDs: ["simulation-summary"]
        )
        var assumptionFormulation = makeFormulation(runID: "run-formulation")
        assumptionFormulation.assumptions = [assumption, assumption]
        try expectCompilationError(
            .duplicateAssumptionID("review-assumption"),
            formulation: assumptionFormulation,
            rootName: "repair-formulation-duplicate-assumption"
        )

        let risk = XcircuitePlanningRiskClassification(
            riskID: "approval-risk",
            category: "human-review",
            severity: "low",
            scope: "candidate-action",
            description: "A risk must stay uniquely addressable.",
            affectedObjectiveIDs: ["restore-gain"],
            affectedActionIDs: ["set-bias-current"]
        )
        var riskFormulation = makeFormulation(runID: "run-formulation")
        riskFormulation.riskClassifications = [risk, risk]
        try expectCompilationError(
            .duplicateRiskID("approval-risk"),
            formulation: riskFormulation,
            rootName: "repair-formulation-duplicate-risk"
        )

        let constraint = XcircuitePlanningConstraint(
            constraintID: "human-approval-required",
            kind: "human-approval",
            severity: "warning",
            description: "A constraint must stay uniquely addressable.",
            sourceRefIDs: ["simulation-summary"]
        )
        var constraintFormulation = makeFormulation(runID: "run-formulation")
        constraintFormulation.constraints = [constraint, constraint]
        try expectCompilationError(
            .duplicateConstraintID("human-approval-required"),
            formulation: constraintFormulation,
            rootName: "repair-formulation-duplicate-constraint"
        )

        var actionDomainFormulation = makeFormulation(runID: "run-formulation")
        actionDomainFormulation.actionDomainRefs.append("simulation-analysis")
        try expectCompilationError(
            .duplicateActionDomainRef("simulation-analysis"),
            formulation: actionDomainFormulation,
            rootName: "repair-formulation-duplicate-action-domain"
        )

        let gate = XcircuitePlanningVerificationGate(
            gateID: "simulation-metric-gate",
            required: true,
            description: "A verification gate must stay uniquely addressable."
        )
        var gateFormulation = makeFormulation(runID: "run-formulation")
        gateFormulation.verificationGates = [gate, gate]
        try expectCompilationError(
            .duplicateVerificationGateID("simulation-metric-gate"),
            formulation: gateFormulation,
            rootName: "repair-formulation-duplicate-gate"
        )

        let costTerm = XcircuitePlanningCostTerm(
            termID: "repair.action-count",
            weight: 1,
            direction: "minimize",
            description: "A cost term must stay uniquely addressable."
        )
        var costFormulation = makeFormulation(runID: "run-formulation")
        costFormulation.costModel = XcircuitePlanningCostModel(
            strategy: "test",
            terms: [costTerm, costTerm]
        )
        try expectCompilationError(
            .duplicateCostTermID("repair.action-count"),
            formulation: costFormulation,
            rootName: "repair-formulation-duplicate-cost-term"
        )
    }

    @Test func compilerRejectsDuplicateNestedActionReferences() throws {
        var goalSourceFormulation = makeFormulation(runID: "run-formulation")
        goalSourceFormulation.goals[0].sourceRefIDs = ["simulation-summary", "simulation-summary"]
        try expectCompilationError(
            .duplicateGoalSourceReference(goalID: "restore-gain", refID: "simulation-summary"),
            formulation: goalSourceFormulation,
            rootName: "repair-formulation-duplicate-goal-source"
        )

        var actionGoalFormulation = makeFormulation(runID: "run-formulation")
        actionGoalFormulation.actions[0].sourceGoalIDs = ["restore-gain", "restore-gain"]
        try expectCompilationError(
            .duplicateActionGoalReference(actionID: "set-bias-current", goalID: "restore-gain"),
            formulation: actionGoalFormulation,
            rootName: "repair-formulation-duplicate-action-goal"
        )

        var actionInputFormulation = makeFormulation(runID: "run-formulation")
        actionInputFormulation.actions[0].requiredInputRefs = ["source-netlist", "source-netlist"]
        try expectCompilationError(
            .duplicateActionInputReference(actionID: "set-bias-current", refID: "source-netlist"),
            formulation: actionInputFormulation,
            rootName: "repair-formulation-duplicate-action-input"
        )

        var actionGateFormulation = makeFormulation(runID: "run-formulation")
        actionGateFormulation.actions[0].verificationGates = ["simulation-metric-gate", "simulation-metric-gate"]
        try expectCompilationError(
            .duplicateActionVerificationGateID(actionID: "set-bias-current", gateID: "simulation-metric-gate"),
            formulation: actionGateFormulation,
            rootName: "repair-formulation-duplicate-action-gate"
        )
    }

    private func expectCompilationError(
        _ expectedError: XcircuiteRepairPlanFormulationCompilationError,
        formulation: XcircuiteRepairPlanFormulation,
        rootName: String
    ) throws {
        let root = try makeTemporaryRoot(rootName)
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: formulation.runID, inProjectAt: root)

        do {
            _ = try XcircuiteRepairPlanFormulationCompiler().compile(
                request: XcircuiteRepairPlanFormulationCompilationRequest(
                    runID: formulation.runID,
                    formulation: formulation
                ),
                projectRoot: root
            )
            Issue.record("Expected formulation compilation to reject \(expectedError).")
        } catch let error as XcircuiteRepairPlanFormulationCompilationError {
            #expect(error == expectedError)
        }
    }

    private func makeFormulation(runID: String) -> XcircuiteRepairPlanFormulation {
        XcircuiteRepairPlanFormulation(
            formulationID: "agent-sizing-repair",
            runID: runID,
            intentID: "recover-gain-after-simulation",
            intent: "Recover the failed gain metric by applying a bounded netlist parameter edit and re-running simulation verification.",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "simulation-summary",
                    kind: "simulation-metric-report",
                    path: ".xcircuite/runs/\(runID)/planning/verification/simulation-metric/simulation-summary.json",
                    artifactID: "planning-simulation-summary",
                    metadata: [
                        "symbolicStateAtoms": .array([.string("gain-low")]),
                    ]
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist",
                    kind: "source-netlist",
                    path: "circuits/amplifier.spice"
                ),
                XcircuitePlanningReference(
                    refID: "action-domain-snapshot",
                    kind: "action-domain-snapshot",
                    path: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json",
                    artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID
                ),
            ],
            goals: [
                XcircuiteRepairPlanFormulation.Goal(
                    goalID: "restore-gain",
                    kind: "improve",
                    domain: "simulation",
                    priority: "error",
                    sourceRefIDs: ["simulation-summary"],
                    target: "gain-within-spec",
                    currentValue: .number(8),
                    requiredValue: .number(10),
                    unit: "V/V",
                    description: "Recovered gain must meet the design specification.",
                    symbolicGoalAtoms: ["gain-restored"]
                ),
            ],
            actionDomainRefs: ["simulation-analysis"],
            actions: [
                XcircuiteRepairPlanFormulation.Action(
                    actionID: "set-bias-current",
                    domainID: "simulation-analysis",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    reason: "Adjust bias current within declared bounds before simulation verification.",
                    sourceGoalIDs: ["restore-gain"],
                    requiredInputRefs: ["source-netlist"],
                    verificationGates: ["simulation-metric-gate"],
                    parameterHints: [
                        "parameterName": .string("IBIAS"),
                        "candidateValue": .number(0.0012),
                    ]
                ),
            ]
        )
    }

    private func persistActionDomainSnapshot(root: URL, runID: String) throws {
        let snapshot = XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: "2026-06-23T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "simulation-analysis",
                    ownerPackages: ["CoreSpice", "Xcircuite"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "simulation.set-netlist-parameters",
                            maturity: "implemented",
                            inputRefs: ["source-netlist"],
                            preconditions: ["gain-low"],
                            effects: ["gain-restored"],
                            producedArtifacts: ["netlist.spice", "netlist-parameter-edit-report.json"],
                            verificationGates: ["simulation-metric-gate"],
                            reversible: true
                        ),
                    ]
                ),
            ]
        )
        let store = XcircuitePackageStore()
        let snapshotURL = root.appending(path: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json")
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(snapshot, to: snapshotURL, forProjectAt: root)
        let reference = try store.fileReference(
            forProjectRelativePath: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json",
            artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
