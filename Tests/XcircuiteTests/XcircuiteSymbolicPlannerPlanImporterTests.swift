import Foundation
import Testing
import CircuiteFoundation
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite symbolic planner plan importer")
struct XcircuiteSymbolicPlannerPlanImporterTests {
    @Test func importerWritesCandidatePlanFromPDDLSolverPlanAndVerifierCoversGoals() async throws {
        let root = try makeTemporaryRoot("symbolic-plan-importer")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(
            root: root,
            runID: "run-pddl",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )

        let result = try await XcircuiteSymbolicPlannerPlanImporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).importSolverPlan(
            request: XcircuiteSymbolicPlannerPlanImportRequest(
                runID: "run-pddl",
                solverPlanText: """
                ; plan from external symbolic planner
                Solution Found
                0.000: (a-fix-m1-width) [1.000]
                cost = 1 (unit cost)
                """
            ),
            projectRoot: root
        )

        #expect(result.diagnostics == [])
        #expect(result.status == "imported")
        #expect(result.importedActionCount == 1)
        #expect(result.solverPlanArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID)
        #expect(result.candidatePlanArtifact.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
        #expect(result.solverPlanArtifact.locator.role == .output)
        #expect(result.pddlExportArtifact.locator.role == .output)
        #expect(result.candidatePlanArtifact.locator.role == .output)
        #expect(result.candidatePlan.planID == "run-pddl-problem-external-symbolic-plan-1")
        #expect(result.candidatePlan.strategy == "external-symbolic-planner-pddl-import")
        #expect(result.candidatePlan.executionReadiness == "ready")
        #expect(result.candidatePlan.blockers == [])
        #expect(result.candidatePlan.unresolvedObjectives == [])
        #expect(result.candidatePlan.assumptions.map(\.assumptionID) == ["drc-symbolic-state-current"])
        #expect(result.candidatePlan.riskClassifications.map(\.riskID) == ["drc-imported-repair-risk"])
        let step = try #require(result.candidatePlan.steps.first)
        #expect(step.actionID == "fix-m1-width")
        #expect(step.domainID == "drc-signoff")
        #expect(step.operationID == "drc.repair-width")
        #expect(step.readiness == "ready")
        #expect(step.requiredInputRefs == ["layout-drc-input"])
        #expect(step.missingInputRefs == [])
        #expect(step.reason.contains("Imported from external symbolic planner action a-fix-m1-width."))

        let verifierResult = try await XcircuiteCandidatePlanVerifier(
            workspaceStore: store,
            artifactStore: artifactStore
        ).verifyCandidatePlan(
            request: XcircuiteCandidatePlanVerificationRequest(runID: "run-pddl"),
            projectRoot: root
        )
        let verification = try await store.readJSON(
            XcircuitePlanVerification.self,
            from: verifierResult.planVerificationArtifact.path
        )
        #expect(verification.stepResults.map(\.status) == ["preflight-passed"])
        #expect(verification.goalCoverageStatus == "covered")
        #expect(verification.missingGoalAtoms == [])
        #expect(verification.finalSymbolicState.contains("drc-width-fixed"))

        let manifest = try await store.loadRunLedger(runID: "run-pddl").runManifest
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID })
        #expect(manifest.artifacts.contains { $0.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID })
    }

    @Test func importSymbolicPlannerPlanCLIWritesCandidatePlan() async throws {
        let root = try makeTemporaryRoot("symbolic-plan-importer-cli")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(
            root: root,
            runID: "run-pddl",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )
        let solverPlanPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/external-plan.txt"
        try await store.writeWorkspaceText("(a-fix-m1-width)\n", to: solverPlanPath)

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "import-symbolic-planner-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-pddl",
                "--solver-plan-path",
                solverPlanPath,
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteSymbolicPlannerPlanImportResult.self, from: data)

        #expect(result.status == "imported")
        #expect(result.candidatePlan.steps.map(\.actionID) == ["fix-m1-width"])
        #expect(result.solverPlanArtifact.path == ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-plan.txt")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: result.candidatePlanArtifact.path).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: result.solverPlanArtifact.path).path(percentEncoded: false)))
    }

    @Test func importerRejectsTamperedPDDLExportArtifact() async throws {
        let root = try makeTemporaryRoot("symbolic-plan-importer-tampered-pddl")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(
            root: root,
            runID: "run-pddl",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )
        let manifest = try await store.loadRunLedger(runID: "run-pddl").runManifest
        let pddlExport = try #require(manifest.artifacts.first {
            $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID
        })
        let pddlExportURL = try pddlExport.locator.location.resolvedFileURL(relativeTo: root)
        let handle = try FileHandle(forWritingTo: pddlExportURL)
        defer {
            do {
                try handle.close()
            } catch {
                Issue.record("Failed to close tampered PDDL export fixture: \(error)")
            }
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))

        await #expect(throws: XcircuiteSymbolicPlannerPlanImportError.artifactIntegrityFailed(
            field: "pddl-export",
            artifactID: XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID,
            path: pddlExport.path,
            status: .byteCountMismatch,
            message: "Artifact byte count does not match the file reference."
        )) {
            _ = try await XcircuiteSymbolicPlannerPlanImporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).importSolverPlan(
                request: XcircuiteSymbolicPlannerPlanImportRequest(
                    runID: "run-pddl",
                    solverPlanText: "(a-fix-m1-width)\n"
                ),
                projectRoot: root
            )
        }
    }

    @Test func importerRejectsExplicitPDDLExportPathOutsideRunManifestReference() async throws {
        let root = try makeTemporaryRoot("symbolic-plan-importer-untracked-pddl")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(
            root: root,
            runID: "run-pddl",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )
        let manifestPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/pddl-export.json"
        let explicitPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/pddl-export-copy.json"
        try FileManager.default.copyItem(
            at: root.appending(path: manifestPath),
            to: root.appending(path: explicitPath)
        )

        await #expect(throws: XcircuiteSymbolicPlannerPlanImportError.manifestReferenceMismatch(
            field: "pddl-export",
            artifactID: XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID,
            path: explicitPath,
            manifestPath: manifestPath,
            reason: "Explicit path does not match the run manifest artifact path."
        )) {
            _ = try await XcircuiteSymbolicPlannerPlanImporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).importSolverPlan(
                request: XcircuiteSymbolicPlannerPlanImportRequest(
                    runID: "run-pddl",
                    pddlExportPath: explicitPath,
                    solverPlanText: "(a-fix-m1-width)\n"
                ),
                projectRoot: root
            )
        }
    }

    @Test func importerRejectsExplicitProblemPathOutsideRunManifestReference() async throws {
        let root = try makeTemporaryRoot("symbolic-plan-importer-untracked-problem")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
        try await prepareRun(
            root: root,
            runID: "run-pddl",
            store: store,
            artifactStore: artifactStore
        )
        _ = try await XcircuiteSymbolicPlannerPDDLExporter(
            workspaceStore: store,
            artifactStore: artifactStore
        ).exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
            projectRoot: root
        )
        let manifestPath = ".xcircuite/runs/run-pddl/planning/problem.json"
        let explicitPath = ".xcircuite/runs/run-pddl/planning/problem-copy.json"
        try FileManager.default.copyItem(
            at: root.appending(path: manifestPath),
            to: root.appending(path: explicitPath)
        )

        await #expect(throws: XcircuiteSymbolicPlannerPlanImportError.manifestReferenceMismatch(
            field: "planning-problem",
            artifactID: XcircuitePlanningArtifactStore.problemArtifactID,
            path: explicitPath,
            manifestPath: manifestPath,
            reason: "Explicit path does not match the run manifest artifact path."
        )) {
            _ = try await XcircuiteSymbolicPlannerPlanImporter(
                workspaceStore: store,
                artifactStore: artifactStore
            ).importSolverPlan(
                request: XcircuiteSymbolicPlannerPlanImportRequest(
                    runID: "run-pddl",
                    problemPath: explicitPath,
                    solverPlanText: "(a-fix-m1-width)\n"
                ),
                projectRoot: root
            )
        }
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
            assumptions: [
                XcircuitePlanningAssumption(
                    assumptionID: "drc-symbolic-state-current",
                    source: "test",
                    statement: "The exported PDDL initial state matches the DRC input.",
                    status: "resolved",
                    confidence: 1,
                    sourceRefIDs: ["layout-drc-input"],
                    requiredBeforeExecution: true
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "drc-imported-repair-risk",
                    category: "external-planner-import",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Imported solver plans must be replayed and verified before acceptance.",
                    affectedActionIDs: ["fix-m1-width"],
                    mitigationActions: ["plan-replay-validation", "native-drc"]
                ),
            ],
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
                    verificationGates: ["native-drc"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "symbolic-planner-import", terms: []),
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
