import Foundation
import CircuiteFoundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite problem translation auditor")
struct XcircuiteProblemTranslationAuditorTests {
    private func makeAuditor(root: URL = FileManager.default.temporaryDirectory) throws -> XcircuiteProblemTranslationAuditor {
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        return XcircuiteProblemTranslationAuditor(
            workspaceStore: store,
            artifactStore: XcircuitePlanningArtifactStore(workspaceStore: store)
        )
    }

    @Test func auditProblemTranslationCLIPersistsAuditArtifact() async throws {
        let root = try makeTemporaryRoot("problem-translation-audit-cli")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-audit", store: store)
        let problem = makePlanningProblem()
        let problemRef = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            problem,
            runID: "run-audit",
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "audit-problem-translation",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-audit",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteProblemTranslationAuditResult.self, from: data)

        #expect(result.status == "passed")
        #expect(result.problemID == "run-audit-drc-repair-problem")
        #expect(result.problemPath == problemRef.path)
        #expect(result.audit.status == "passed")
        #expect(result.audit.blocking == false)
        #expect(result.audit.coverageSummary.sourceRefCount == 1)
        #expect(result.audit.coverageSummary.coveredSourceRefCount == 1)
        #expect(result.audit.coverageSummary.uncoveredSourceRefCount == 0)
        #expect(result.audit.coverageSummary.sourceDiagnosticRefCount == 1)
        #expect(result.audit.coverageSummary.fullyCoveredSourceDiagnosticCount == 1)
        #expect(result.audit.coverageSummary.undercoveredSourceDiagnosticCount == 0)
        #expect(result.audit.coverageSummary.orphanObjectiveCount == 0)
        #expect(result.audit.coverageSummary.orphanCandidateActionCount == 0)
        #expect(result.audit.sourceDiagnosticCoverage == [
            XcircuiteProblemTranslationSourceDiagnosticCoverage(
                sourceRefID: "drc-summary",
                sourceKind: "drc-summary",
                status: "covered",
                objectiveIDs: ["drc-width-fixed"],
                constraintIDs: ["drc-must-pass"],
                candidateActionIDs: ["layout-fix-width"],
                verificationGateIDs: ["artifact-integrity", "native-drc"]
            ),
        ])
        #expect(result.audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary" && $0.targetKind == "objective" && $0.targetID == "drc-width-fixed"
        })
        #expect(result.audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary" && $0.targetKind == "candidate-action" && $0.targetID == "layout-fix-width"
        })
        #expect(result.audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary" && $0.targetKind == "goal-atom" && $0.targetID == "rect-shape-created"
        })
        #expect(result.audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary" && $0.targetKind == "verification-gate" && $0.targetID == "native-drc"
        })
        #expect(result.audit.nextActions == ["validate-planning-problem"])
        #expect(result.auditArtifact.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        #expect(result.auditArtifact.path == ".xcircuite/runs/run-audit/planning/problem-translation-audit.json")
        #expect(!result.auditArtifact.digest.hexadecimalValue.isEmpty)
        #expect(result.auditArtifact.byteCount > 0)

        let persisted = try await store.readJSON(
            XcircuiteProblemTranslationAudit.self,
            from: result.auditArtifact.path
        )
        #expect(persisted == result.audit)

        let ledger = try await store.loadRunLedger(runID: "run-audit")
        #expect(ledger.runManifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID
                && $0.path == result.auditArtifact.path
        })
    }

    @Test func runSelectedSuggestedActionDispatchesProblemTranslationAudit() async throws {
        let root = try makeTemporaryRoot("selected-problem-translation-audit")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-audit", store: store)
        let problem = makePlanningProblem()
        let problemRef = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            problem,
            runID: "run-audit",
            projectRoot: root
        )
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-audit-problem-translation",
                runID: "run-audit",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(suggestedAction: .init(
                    nextActionID: "audit-problem-translation",
                    nextActionKind: "auditProblemTranslation",
                    action: FlowRunSuggestedAction(
                        id: "audit-problem-translation",
                        readiness: .ready,
                        operation: .auditProblemTranslation,
                        runID: "run-audit",
                        reason: "Audit source-to-problem translation coverage."
                    )
                ))
            ),
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run-selected-suggested-action",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-audit",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteProblemTranslationAuditResult.self, from: data)

        #expect(result.status == "passed")
        #expect(result.problemPath == problemRef.path)
        #expect(result.auditArtifact.artifactID == XcircuitePlanningArtifactStore.problemTranslationAuditArtifactID)
        let actions = try await store.loadRunActions(runID: "run-audit")
        #expect(actions.contains { $0.actionID == "selection-audit-problem-translation" })
    }

    @Test func auditProblemTranslationRejectsStaleProblemArtifact() async throws {
        let root = try makeTemporaryRoot("problem-translation-audit-stale-artifact")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-audit", store: store)
        let problemRef = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-audit",
            projectRoot: root
        )
        let problemURL = root.appending(path: problemRef.path)
        let original = try String(contentsOf: problemURL, encoding: .utf8)
        try "\(original)\n".write(to: problemURL, atomically: true, encoding: .utf8)

        do {
            _ = try await makeAuditor(root: root).auditProblemTranslation(
                request: XcircuiteProblemTranslationAuditRequest(runID: "run-audit"),
                projectRoot: root
            )
            Issue.record("Expected stale problem artifact rejection.")
        } catch let error as XcircuiteProblemTranslationAuditError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected audit error: \(error)")
                return
            }
            #expect(path == problemRef.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func auditProblemTranslationRejectsExplicitPathForDifferentManifestArtifact() async throws {
        let root = try makeTemporaryRoot("problem-translation-audit-explicit-artifact-mismatch")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await store.ensureWorkspace()
        try await prepareTestRun(runID: "run-audit", store: store)
        _ = try await XcircuitePlanningArtifactStore(workspaceStore: store).persistPlanningProblem(
            makePlanningProblem(),
            runID: "run-audit",
            projectRoot: root
        )
        let alternatePath = ".xcircuite/runs/run-audit/planning/alternate-problem.json"
        try await store.writeJSON(
            makePlanningProblem(),
            to: alternatePath
        )
        let alternateRef = try await store.makeArtifactReference(
            forProjectRelativePath: alternatePath,
            artifactID: "alternate-planning-problem",
            kind: .other,
            format: .json,
        )
        _ = try await retainTestArtifact(alternateRef, runID: "run-audit", store: store, projectRoot: root)

        do {
            _ = try await makeAuditor(root: root).auditProblemTranslation(
                request: XcircuiteProblemTranslationAuditRequest(
                    runID: "run-audit",
                    problemArtifactID: XcircuitePlanningArtifactStore.problemArtifactID,
                    problemPath: alternatePath
                ),
                projectRoot: root
            )
            Issue.record("Expected explicit path artifact mismatch rejection.")
        } catch let error as XcircuiteProblemTranslationAuditError {
            guard case .invalidArtifactReference(let path, let reason) = error else {
                Issue.record("Unexpected audit error: \(error)")
                return
            }
            #expect(path == alternatePath)
            #expect(reason == "artifactID does not match requested \(XcircuitePlanningArtifactStore.problemArtifactID).")
        }
    }

    @Test func auditorBlocksUncoveredSourcesAndOrphanProblemElements() async throws {
        var problem = makePlanningProblem()
        problem.sourceRefs.append(
            XcircuitePlanningReference(
                refID: "unused-drc-diagnostic",
                kind: "drc-summary",
                path: ".xcircuite/runs/run-audit/stages/drc/raw/unused-drc-summary.json"
            )
        )
        problem.objectives[0].sourceRefIDs = []

        let audit = try makeAuditor().makeAudit(
            problem: problem,
            problemPath: ".xcircuite/runs/run-audit/planning/problem.json"
        )

        #expect(audit.status == "failed")
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.uncoveredSourceRefCount == 1)
        #expect(audit.coverageSummary.sourceDiagnosticRefCount == 2)
        #expect(audit.coverageSummary.undercoveredSourceDiagnosticCount == 2)
        #expect(audit.coverageSummary.orphanObjectiveCount == 1)
        #expect(audit.coverageSummary.orphanCandidateActionCount == 1)
        #expect(audit.coverageSummary.orphanGoalAtomCount == 2)
        #expect(audit.diagnostics.contains {
            $0.code == "source-ref-uncovered" && $0.sourceRefID == "unused-drc-diagnostic"
        })
        #expect(audit.diagnostics.contains {
            $0.code == "source-diagnostic-undercovered" && $0.sourceRefID == "drc-summary"
        })
        #expect(audit.diagnostics.contains {
            $0.code == "orphan-objective" && $0.objectiveID == "drc-width-fixed"
        })
        #expect(audit.diagnostics.contains {
            $0.code == "orphan-candidate-action" && $0.actionID == "layout-fix-width"
        })
        #expect(audit.diagnostics.contains {
            $0.code == "orphan-goal-atom" && $0.goalAtom == "rect-shape-created"
        })
        #expect(audit.nextActions.contains("regenerate-planning-problem"))
    }

    @Test func auditorRequiresDiagnosticSourcesToReachObjectiveConstraintActionAndGate() async throws {
        var problem = makePlanningProblem()
        problem.constraints.removeAll()
        problem.verificationGates.removeAll()
        problem.candidateActions[0].verificationGates.removeAll()

        let audit = try makeAuditor().makeAudit(
            problem: problem,
            problemPath: ".xcircuite/runs/run-audit/planning/problem.json"
        )

        #expect(audit.status == "failed")
        #expect(audit.blocking)
        #expect(audit.coverageSummary.sourceDiagnosticRefCount == 1)
        #expect(audit.coverageSummary.fullyCoveredSourceDiagnosticCount == 0)
        #expect(audit.coverageSummary.undercoveredSourceDiagnosticCount == 1)
        #expect(audit.sourceDiagnosticCoverage == [
            XcircuiteProblemTranslationSourceDiagnosticCoverage(
                sourceRefID: "drc-summary",
                sourceKind: "drc-summary",
                status: "undercovered",
                objectiveIDs: ["drc-width-fixed"],
                constraintIDs: [],
                candidateActionIDs: ["layout-fix-width"],
                verificationGateIDs: [],
                missingTargetKinds: ["constraint", "verification-gate"]
            ),
        ])
        #expect(audit.undercoveredSourceDiagnostics == [
            XcircuiteProblemTranslationAuditIssue(
                id: "drc-summary",
                kind: "drc-summary",
                sourceRefID: "drc-summary",
                reason: "Source diagnostic is not mapped to required target kinds: constraint, verification-gate."
            ),
        ])
        #expect(audit.diagnostics.contains {
            $0.code == "source-diagnostic-undercovered"
                && $0.sourceRefID == "drc-summary"
        })
        #expect(audit.nextActions.contains("map-source-diagnostic-to-objective-constraint-action-and-gate"))
    }

    @Test func auditorCountsActionDomainVerificationGatesAsDiagnosticCoverage() async throws {
        var problem = makePlanningProblem()
        problem.verificationGates = [
            XcircuitePlanningVerificationGate(
                gateID: "artifact-integrity",
                required: true,
                description: "Edited artifacts must be registered and hashed."
            ),
        ]
        var action = problem.candidateActions[0]
        action.verificationGates = ["operation-native-drc"]
        problem.candidateActions[0] = action
        let snapshot = XcircuitePlanningActionDomainSnapshot(
            runID: "run-audit",
            generatedAt: "2026-07-02T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "layout-edit",
                    ownerPackages: ["LayoutCommands"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "layout.add-rect",
                            maturity: "implemented",
                            inputRefs: ["layout-ref"],
                            preconditions: [],
                            effects: ["rect-shape-created"],
                            producedArtifacts: ["layout-document"],
                            verificationGates: ["operation-native-drc"],
                            reversible: false
                        ),
                    ]
                ),
            ]
        )

        let audit = try makeAuditor().makeAudit(
            problem: problem,
            problemPath: ".xcircuite/runs/run-audit/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(audit.status == "passed")
        #expect(audit.blocking == false)
        #expect(audit.sourceDiagnosticCoverage == [
            XcircuiteProblemTranslationSourceDiagnosticCoverage(
                sourceRefID: "drc-summary",
                sourceKind: "drc-summary",
                status: "covered",
                objectiveIDs: ["drc-width-fixed"],
                constraintIDs: ["drc-must-pass"],
                candidateActionIDs: ["layout-fix-width"],
                verificationGateIDs: ["operation-native-drc"]
            ),
        ])
        #expect(audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary"
                && $0.targetKind == "verification-gate"
                && $0.targetID == "operation-native-drc"
        })
    }

    @Test func problemTranslationAuditRejectsMissingCoverageFields() async throws {
        let payload = Data("""
        {
          "schemaVersion": 1,
          "status": "passed",
          "runID": "run-audit",
          "problemID": "problem-1",
          "problemPath": ".xcircuite/runs/run-audit/planning/problem.json",
          "sourceRefs": [],
          "translationEdges": [],
          "coverageSummary": {
            "sourceRefCount": 0,
            "coveredSourceRefCount": 0,
            "uncoveredSourceRefCount": 0,
            "objectiveCount": 0,
            "orphanObjectiveCount": 0,
            "constraintCount": 0,
            "orphanConstraintCount": 0,
            "candidateActionCount": 0,
            "orphanCandidateActionCount": 0,
            "goalAtomCount": 0,
            "orphanGoalAtomCount": 0,
            "translationEdgeCount": 0
          },
          "uncoveredSources": [],
          "orphanObjectives": [],
          "orphanConstraints": [],
          "orphanCandidateActions": [],
          "orphanGoalAtoms": [],
          "diagnostics": [],
          "blocking": false,
          "nextActions": []
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(XcircuiteProblemTranslationAudit.self, from: payload)
        }
    }

    @Test func auditorBlocksUnsupportedGoalAtomsWithoutCandidateEffects() async throws {
        var problem = makePlanningProblem()
        problem.objectives[0].evidence = [
            "symbolicGoalAtoms": .textList(["unsupported-analog-improvement-goal"]),
        ]

        let audit = try makeAuditor().makeAudit(
            problem: problem,
            problemPath: ".xcircuite/runs/run-audit/planning/problem.json"
        )

        #expect(audit.status == "failed")
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.unsupportedGoalAtomCount == 1)
        #expect(audit.unsupportedGoalAtoms == [
            XcircuiteProblemTranslationAuditIssue(
                id: "unsupported-analog-improvement-goal",
                kind: "drc-width-fixed",
                reason: "Goal atom is not produced by the objective candidate actions or current symbolic state."
            ),
        ])
        #expect(audit.diagnostics.contains {
            $0.code == "unsupported-goal-atom"
                && $0.objectiveID == "drc-width-fixed"
                && $0.goalAtom == "unsupported-analog-improvement-goal"
        })
        #expect(audit.nextActions.contains("add-candidate-action-effect-for-goal-atom"))
    }

    @Test func auditorBlocksUncoveredIntentClausesWithinCoveredSourceRef() async throws {
        var problem = makePlanningProblem()
        problem.sourceRefs[0] = XcircuitePlanningReference(
            refID: "drc-summary",
            kind: "human-intent",
            path: ".xcircuite/runs/run-audit/stages/drc/raw/drc-summary.json",
            artifactID: "drc-summary",
            metadata: [
                "intentClauseIDs": .textList(["fix-width", "preserve-lvs"]),
            ]
        )
        var objective = problem.objectives[0]
        objective.evidence["intentClauseIDs"] = .textList(["fix-width"])
        problem.objectives[0] = objective
        var constraint = problem.constraints[0]
        constraint.evidence = [
            "intentClauseIDs": .textList(["fix-width"]),
        ]
        problem.constraints[0] = constraint
        var action = problem.candidateActions[0]
        action.parameterHints["intentClauseIDs"] = .textList(["fix-width"])
        problem.candidateActions[0] = action

        let audit = try makeAuditor().makeAudit(
            problem: problem,
            problemPath: ".xcircuite/runs/run-audit/planning/problem.json"
        )

        #expect(audit.status == "failed")
        #expect(audit.blocking == true)
        #expect(audit.coverageSummary.coveredSourceRefCount == 1)
        #expect(audit.coverageSummary.uncoveredSourceRefCount == 0)
        #expect(audit.coverageSummary.intentClauseCount == 2)
        #expect(audit.coverageSummary.uncoveredIntentClauseCount == 1)
        #expect(audit.uncoveredIntentClauses == [
            XcircuiteProblemTranslationAuditIssue(
                id: "drc-summary:preserve-lvs",
                kind: "human-intent",
                sourceRefID: "drc-summary",
                intentClauseID: "preserve-lvs",
                reason: "Source intent clause is not connected to any objective, constraint, or candidate action."
            ),
        ])
        #expect(audit.translationEdges.contains {
            $0.sourceRefID == "drc-summary"
                && $0.intentClauseID == "fix-width"
                && $0.targetKind == "objective"
                && $0.targetID == "drc-width-fixed"
        })
        #expect(audit.diagnostics.contains {
            $0.code == "intent-clause-uncovered"
                && $0.sourceRefID == "drc-summary"
                && $0.intentClauseID == "preserve-lvs"
        })
        #expect(audit.nextActions.contains("map-intent-clause-to-objective-constraint-or-action"))
    }

    private func makePlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-audit-drc-repair-problem",
            runID: "run-audit",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "drc-summary",
                    kind: "drc-summary",
                    path: ".xcircuite/runs/run-audit/stages/drc/raw/drc-summary.json",
                    artifactID: "drc-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: ".xcircuite/runs/run-audit/stages/layout/raw/layout.gds"
                ),
            ],
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "summary-current",
                    source: "test",
                    statement: "The DRC summary matches the layout state.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["drc-summary"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "layout-edit-risk",
                    category: "layout-regression",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Layout edits must preserve DRC and artifact integrity.",
                    affectedObjectiveIDs: ["drc-width-fixed"],
                    affectedActionIDs: ["layout-fix-width"],
                    mitigationActions: ["native-drc", "artifact-integrity"]
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-width-fixed",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["drc-summary"],
                    target: "no-active-violations-for-bucket",
                    currentValue: .scalar(1),
                    requiredValue: .scalar(0),
                    description: "Repair DRC width violation.",
                    evidence: [
                        "symbolicGoalAtoms": .textList([
                            "rect-shape-created",
                            "artifact:layout-document",
                        ]),
                    ]
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The repaired candidate must pass DRC.",
                    sourceRefIDs: ["drc-summary"]
                ),
            ],
            actionDomainRefs: ["layout-edit"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-fix-width",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Use a concrete layout edit to repair width.",
                    sourceObjectiveIDs: ["drc-width-fixed"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-drc"],
                    parameterHints: [
                        "symbolicEffects": .textList([
                            "rect-shape-created",
                            "artifact:layout-document",
                        ]),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Edited artifacts must be registered and hashed."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "The candidate must pass native DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
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
            Issue.record("Failed to remove temporary root \(root.path(percentEncoded: false)): \(error)")
        }
    }
}
