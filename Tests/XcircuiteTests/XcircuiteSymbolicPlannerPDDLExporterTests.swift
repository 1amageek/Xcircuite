import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite symbolic planner PDDL exporter")
struct XcircuiteSymbolicPlannerPDDLExporterTests {
    @Test func exporterWritesPDDLArtifactsAndAtomMappings() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-exporter")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-pddl")

        let result = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )

        #expect(result.status == "exported")
        #expect(result.problemID == "run-pddl-problem")
        let translationAuditArtifact = try #require(result.problemTranslationAuditArtifact)
        #expect(translationAuditArtifact.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        #expect(result.domainArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLDomainArtifactID)
        #expect(result.problemArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLProblemArtifactID)
        #expect(result.exportArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID)
        #expect(result.domainArtifact.path == ".xcircuite/runs/run-pddl/planning/symbolic-planner/domain.pddl")
        #expect(result.problemArtifact.path == ".xcircuite/runs/run-pddl/planning/symbolic-planner/problem.pddl")
        #expect(result.exportArtifact.path == ".xcircuite/runs/run-pddl/planning/symbolic-planner/pddl-export.json")
        #expect(result.domainArtifact.sha256?.isEmpty == false)
        #expect(result.problemArtifact.sha256?.isEmpty == false)
        #expect(result.exportArtifact.sha256?.isEmpty == false)
        #expect(result.domainArtifact.byteCount != nil)
        #expect(result.problemArtifact.byteCount != nil)
        #expect(result.exportArtifact.byteCount != nil)

        let domainPDDL = try String(contentsOf: root.appending(path: result.domainArtifact.path), encoding: .utf8)
        let problemPDDL = try String(contentsOf: root.appending(path: result.problemArtifact.path), encoding: .utf8)
        #expect(domainPDDL.contains("(define (domain domain-run-pddl-problem)"))
        #expect(domainPDDL.contains("(:requirements :strips :action-costs)"))
        #expect(domainPDDL.contains("(:functions (total-cost))"))
        #expect(domainPDDL.contains("(:action a-fix-m1-width"))
        #expect(domainPDDL.contains("(p-drc-width-violation)"))
        #expect(domainPDDL.contains("(p-ref-layout-drc-input)"))
        #expect(domainPDDL.contains("(p-drc-width-fixed)"))
        #expect(domainPDDL.contains("(increase (total-cost) 3)"))
        #expect(problemPDDL.contains("(define (problem problem-run-pddl-problem)"))
        #expect(problemPDDL.contains("(:domain domain-run-pddl-problem)"))
        #expect(problemPDDL.contains("(p-artifact-layout-json)"))
        #expect(problemPDDL.contains("(= (total-cost) 0)"))
        #expect(problemPDDL.contains("(:goal (and (p-drc-width-fixed)))"))
        #expect(problemPDDL.contains("(:metric minimize (total-cost))"))

        let storedExport = try XcircuitePackageStore().readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: root.appending(path: result.exportArtifact.path)
        )
        #expect(storedExport == result.export)
        #expect(storedExport.atomMappings.contains {
            $0.atom == "drc-width-fixed"
                && $0.predicate == "p-drc-width-fixed"
                && $0.roles.contains("goal")
                && $0.roles.contains("effect")
        })
        let actionMapping = try #require(storedExport.actionMappings.first)
        #expect(actionMapping.actionID == "fix-m1-width")
        #expect(actionMapping.pddlAction == "a-fix-m1-width")
        #expect(actionMapping.included == true)
        #expect(actionMapping.preconditionAtoms == ["ref:layout-drc-input", "drc-width-violation"])
        #expect(actionMapping.effectAtoms == ["drc-width-fixed", "artifact:drc-summary"])
        #expect(actionMapping.actionCost == 3)
        #expect(actionMapping.actionCostUnit == "planner action cost")
        #expect(actionMapping.actionCostSource == "planning-cost-model")

        let manifest = try XcircuitePackageStore().readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
        )
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLDomainArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLProblemArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID })
    }

    @Test func exportSymbolicPlannerProblemCLIWritesPDDLArtifacts() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-cli")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-pddl")

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "export-symbolic-planner-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-pddl",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteSymbolicPlannerPDDLExportResult.self, from: data)

        #expect(result.status == "exported")
        #expect(result.problemTranslationAuditArtifact?.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        #expect(result.export.atomMappings.contains { $0.atom == "drc-width-fixed" })
        #expect(result.export.actionMappings.map(\.pddlAction) == ["a-fix-m1-width"])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: result.domainArtifact.path).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: result.problemArtifact.path).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: result.exportArtifact.path).path(percentEncoded: false)))
    }

    @Test func exportSymbolicPlannerProblemBlocksWhenTranslationAuditBlocks() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-audit-block")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-pddl")
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.objectives[0].sourceRefIDs = []
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }
    }

    @Test func exportSymbolicPlannerProblemRefreshesStalePassedAuditAndBlocksMutatedProblem() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-stale-audit")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-pddl")
        let problemPath = ".xcircuite/runs/run-pddl/planning/problem.json"
        let staleAudit = try XcircuiteProblemTranslationAuditor().auditProblemTranslation(
            request: XcircuiteProblemTranslationAuditRequest(
                runID: "run-pddl",
                problemPath: problemPath
            ),
            projectRoot: root
        )
        #expect(staleAudit.audit.blocking == false)
        #expect(staleAudit.audit.status == "passed")

        var problem = makePlanningProblem(runID: "run-pddl")
        problem.objectives[0].sourceRefIDs = []
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let refreshedAudit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: staleAudit.auditArtifact.path)
        )
        #expect(refreshedAudit.blocking == true)
        #expect(refreshedAudit.status == "failed")
        #expect(refreshedAudit.diagnostics.contains {
            $0.code == "orphan-objective" && $0.objectiveID == "objective-1"
        })
        #expect(refreshedAudit.diagnostics.contains {
            $0.code == "orphan-candidate-action" && $0.actionID == "fix-m1-width"
        })
    }

    @Test func exportSymbolicPlannerProblemRejectsStaleManifestProblemArtifact() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-stale-problem-artifact")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-pddl")
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.problemID = "tampered-run-pddl-problem"
        try store.writeJSON(
            problem,
            to: root.appending(path: ".xcircuite/runs/run-pddl/planning/problem.json"),
            forProjectAt: root
        )

        #expect(throws: XcircuiteSymbolicPlannerPDDLExportError.self) {
            try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }
    }

    @Test func exportSymbolicPlannerProblemBlocksUnsupportedGoalAtomsBeforePDDL() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-unsupported-goal")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-pddl")
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .array([.string("unsupported-analog-improvement-goal")]),
        ]
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: ".xcircuite/runs/run-pddl/planning/problem-translation-audit.json")
        )
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.unsupportedGoalAtomCount == 1)
        #expect(audit.diagnostics.contains {
            $0.code == "unsupported-goal-atom"
                && $0.objectiveID == "objective-1"
                && $0.goalAtom == "unsupported-analog-improvement-goal"
        })
    }

    @Test func exportSymbolicPlannerProblemBlocksUncoveredIntentClausesBeforePDDL() throws {
        let root = try makeTemporaryRoot("symbolic-pddl-uncovered-intent-clause")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try prepareRun(root: root, runID: "run-pddl")
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.sourceRefs[0] = XcircuitePlanningReference(
            refID: "layout-drc-input",
            kind: "human-intent",
            artifactID: "layout-json",
            metadata: [
                "symbolicStateAtoms": .array([.string("drc-width-violation")]),
                "intentClauseIDs": .array([
                    .string("repair-width"),
                    .string("preserve-approval-review"),
                ]),
            ]
        )
        var objective = problem.objectives[0]
        objective.evidence = [
            "symbolicGoalAtoms": .array([.string("drc-width-fixed")]),
            "intentClauseIDs": .array([.string("repair-width")]),
        ]
        problem.objectives[0] = objective
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let audit = try store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: root.appending(path: ".xcircuite/runs/run-pddl/planning/problem-translation-audit.json")
        )
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.intentClauseCount == 2)
        #expect(audit.coverageSummary.uncoveredIntentClauseCount == 1)
        #expect(audit.diagnostics.contains {
            $0.code == "intent-clause-uncovered"
                && $0.sourceRefID == "layout-drc-input"
                && $0.intentClauseID == "preserve-approval-review"
        })
    }

    private func prepareRun(root: URL, runID: String) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makePlanningProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
        let snapshotURL = root.appending(path: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json")
        try store.writeJSON(makeActionDomainSnapshot(runID: runID), to: snapshotURL, forProjectAt: root)
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

    private func makePlanningProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-problem",
            runID: runID,
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "layout-drc-input",
                    kind: "layout",
                    artifactID: "layout-json",
                    metadata: [
                        "symbolicStateAtoms": .array([.string("drc-width-violation")]),
                    ]
                ),
            ],
            initialStateRefs: [],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "objective-1",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["layout-drc-input"],
                    target: "no-width-violation",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair width violation.",
                    evidence: [
                        "symbolicGoalAtoms": .array([.string("drc-width-fixed")]),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["drc-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "fix-m1-width",
                    domainID: "drc-signoff",
                    operationID: "drc.repair-width",
                    maturity: "implemented",
                    reason: "Repair M1 width.",
                    sourceObjectiveIDs: ["objective-1"],
                    requiredInputRefs: ["layout-drc-input"],
                    verificationGates: ["native-drc", "approval-gate"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(
                strategy: "symbolic-planner-export",
                terms: [
                    XcircuitePlanningCostTerm(
                        termID: "approval-cost",
                        weight: 2,
                        direction: "minimize",
                        description: "Prefer actions that avoid approval gates."
                    ),
                ]
            ),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate must pass DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeActionDomainSnapshot(runID: String) -> XcircuitePlanningActionDomainSnapshot {
        XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: "2026-06-20T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "drc-signoff",
                    ownerPackages: ["DRCEngine", "Xcircuite"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "drc.repair-width",
                            maturity: "implemented",
                            inputRefs: ["layout-drc-input"],
                            preconditions: ["drc-width-violation"],
                            effects: ["drc-width-fixed"],
                            producedArtifacts: ["drc-summary"],
                            verificationGates: ["native-drc"],
                            reversible: true
                        ),
                    ]
                ),
            ]
        )
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
