import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite symbolic planner PDDL exporter")
struct XcircuiteSymbolicPlannerPDDLExporterTests {
    @Test func exporterWritesPDDLArtifactsAndAtomMappings() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-exporter")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)

        let result = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
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
        #expect(result.domainArtifact.sha256.isEmpty == false)
        #expect(result.problemArtifact.sha256.isEmpty == false)
        #expect(result.exportArtifact.sha256.isEmpty == false)
        #expect(result.domainArtifact.byteCount > 0)
        #expect(result.problemArtifact.byteCount > 0)
        #expect(result.exportArtifact.byteCount > 0)

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

        let storedExport = try await store.readJSON(
            XcircuiteSymbolicPlannerPDDLExport.self,
            from: result.exportArtifact.path
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

        let manifest = try await store.loadRunLedger(runID: "run-pddl").runManifest
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLDomainArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLProblemArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID })
    }

    @Test func exportSymbolicPlannerProblemCLIWritesPDDLArtifacts() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-cli")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)

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

    @Test func exportSymbolicPlannerProblemBlocksWhenTranslationAuditBlocks() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-audit-block")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.objectives[0].sourceRefIDs = []
        _ = try await artifactStore.persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }
    }

    @Test func exportSymbolicPlannerProblemRefreshesStalePassedAuditAndBlocksMutatedProblem() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-stale-audit")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)
        let problemPath = ".xcircuite/runs/run-pddl/planning/problem.json"
        let staleAudit = try await XcircuiteProblemTranslationAuditor(
            workspaceStore: store,
            artifactStore: artifactStore
        ).auditProblemTranslation(
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
        _ = try await artifactStore.persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let refreshedAudit = try await store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: staleAudit.auditArtifact.path
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

    @Test func exportSymbolicPlannerProblemRejectsStaleManifestProblemArtifact() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-stale-problem-artifact")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.problemID = "tampered-run-pddl-problem"
        try await store.writeJSON(
            problem,
            to: ".xcircuite/runs/run-pddl/planning/problem.json"
        )

        await #expect(throws: XcircuiteSymbolicPlannerPDDLExportError.self) {
            try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }
    }

    @Test func exportSymbolicPlannerProblemBlocksUnsupportedGoalAtomsBeforePDDL() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-unsupported-goal")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .textList(["unsupported-analog-improvement-goal"]),
        ]
        _ = try await artifactStore.persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let audit = try await store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: ".xcircuite/runs/run-pddl/planning/problem-translation-audit.json"
        )
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.unsupportedGoalAtomCount == 1)
        #expect(audit.diagnostics.contains {
            $0.code == "unsupported-goal-atom"
                && $0.objectiveID == "objective-1"
                && $0.goalAtom == "unsupported-analog-improvement-goal"
        })
    }

    @Test func exportSymbolicPlannerProblemBlocksUncoveredIntentClausesBeforePDDL() async throws {
        let root = try makeTemporaryRoot("symbolic-pddl-uncovered-intent-clause")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(root: root, runID: "run-pddl", store: store, artifactStore: artifactStore)
        var problem = makePlanningProblem(runID: "run-pddl")
        problem.sourceRefs[0] = XcircuitePlanningReference(
            refID: "layout-drc-input",
            kind: "human-intent",
            artifactID: "layout-json",
            metadata: [
                "symbolicStateAtoms": .textList(["drc-width-violation"]),
                "intentClauseIDs": .textList([
                    "repair-width",
                    "preserve-approval-review",
                ]),
            ]
        )
        var objective = problem.objectives[0]
        objective.evidence = [
            "symbolicGoalAtoms": .textList(["drc-width-fixed"]),
            "intentClauseIDs": .textList(["repair-width"]),
        ]
        problem.objectives[0] = objective
        _ = try await artifactStore.persistPlanningProblem(
            problem,
            runID: "run-pddl",
            projectRoot: root
        )

        await #expect(throws: XcircuiteProblemTranslationAuditGateError.self) {
            try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
                projectRoot: root
            )
        }

        let audit = try await store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: ".xcircuite/runs/run-pddl/planning/problem-translation-audit.json"
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

    private func prepareRun(
        root: URL,
        runID: String,
        store: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore
    ) async throws {
        try await prepareTestRun(runID: runID, store: store)
        _ = try await artifactStore.persistPlanningProblem(
            makePlanningProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        _ = try await store.persistArtifact(
            content: encoder.encode(makeActionDomainSnapshot(runID: runID)),
            id: ArtifactID(rawValue: XcircuitePlanningArtifactStore.actionDomainArtifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json"
                ),
                role: .output,
                kind: .other,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
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
                        "symbolicStateAtoms": .textList(["drc-width-violation"]),
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
                    currentValue: .scalar(1),
                    requiredValue: .scalar(0),
                    description: "Repair width violation.",
                    evidence: [
                        "symbolicGoalAtoms": .textList(["drc-width-fixed"]),
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
