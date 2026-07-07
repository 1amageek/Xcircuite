import Foundation
import Testing
import Xcircuite
import XcircuitePackage

@Suite("Xcircuite symbolic planner PEX repair-domain corpus")
struct XcircuiteSymbolicPlannerPEXRepairDomainCorpusTests {
    @Test func qualifySymbolicPlannerSolverCorpusCoversPEXRepairDomain() async throws {
        let root = try makeTemporaryRoot("symbolic-planner-pex-repair-domain-corpus")
        defer { removeTemporaryRoot(root) }
        let fixtures: [PEXRepairFixture] = [
            .capacitanceBudget,
            .couplingBudget,
            .metricDegradation,
            .multiCornerRegression,
            .rcNetworkMismatch,
            .postLayoutSimulationRegression,
        ]
        for fixture in fixtures {
            try prepareRun(root: root, runID: fixture.runID, repair: fixture)
            _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: fixture.runID),
                projectRoot: root
            )
        }
        let solverURL = root.appending(path: "pex-repair-domain-symbolic-planner.sh")
        try writePEXRepairMockPlanner(to: solverURL)

        let result = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
                suiteID: "pex-repair-domain-corpus",
                toolID: "mock-pex-repair-planner",
                executablePath: solverURL.path(percentEncoded: false),
                arguments: ["{problem}"],
                requiredCoverageTags: [
                    "symbolic.pex-repair-domain",
                    "symbolic.expected-action-coverage",
                    "symbolic.goal-coverage",
                    "symbolic.multi-case",
                    "symbolic.pex-multi-corner-repair-domain",
                    "symbolic.pex-rc-network-repair-domain",
                    "symbolic.pex-post-layout-simulation-repair-domain",
                ],
                cases: [
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-capacitance",
                        runID: PEXRepairFixture.capacitanceBudget.runID,
                        expectedActionIDs: [PEXRepairFixture.capacitanceBudget.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.expected-action-coverage",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-coupling",
                        runID: PEXRepairFixture.couplingBudget.runID,
                        expectedActionIDs: [PEXRepairFixture.couplingBudget.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.goal-coverage",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-metric",
                        runID: PEXRepairFixture.metricDegradation.runID,
                        expectedActionIDs: [PEXRepairFixture.metricDegradation.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.multi-case",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-multi-corner",
                        runID: PEXRepairFixture.multiCornerRegression.runID,
                        expectedActionIDs: [PEXRepairFixture.multiCornerRegression.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.pex-multi-corner-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-rc-network",
                        runID: PEXRepairFixture.rcNetworkMismatch.runID,
                        expectedActionIDs: [PEXRepairFixture.rcNetworkMismatch.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.pex-rc-network-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "pex-post-layout-simulation",
                        runID: PEXRepairFixture.postLayoutSimulationRegression.runID,
                        expectedActionIDs: [PEXRepairFixture.postLayoutSimulationRegression.actionID],
                        coverageTags: [
                            "symbolic.pex-repair-domain",
                            "symbolic.pex-post-layout-simulation-repair-domain",
                        ]
                    ),
                ]
            ),
            projectRoot: root
        )

        #expect(result.status == "qualified")
        #expect(result.qualifiedCaseCount == 6)
        #expect(result.failedCaseCount == 0)
        #expect(result.missingRequiredCoverageTags == [])
        #expect(result.coverageTagCounts["symbolic.pex-repair-domain"] == 6)
        #expect(result.coverageTagCounts["symbolic.pex-multi-corner-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.pex-rc-network-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.pex-post-layout-simulation-repair-domain"] == 1)
        #expect(result.caseResults.map(\.observedActionIDs) == fixtures.map { [$0.actionID] })
        #expect(result.caseResults.allSatisfy { $0.goalCoverageStatus == "covered" })
        #expect(result.toolHealth.status == .passed)
        #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["coverageRate"] == 1)
        #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["passRate"] == 1)
        #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
        #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusArtifactID)
    }

    private func prepareRun(
        root: URL,
        runID: String,
        repair: PEXRepairFixture
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makePlanningProblem(runID: runID, repair: repair),
            runID: runID,
            projectRoot: root
        )
        let snapshotURL = root.appending(path: ".xcircuite/runs/\(runID)/planning/action-domain-snapshot.json")
        try store.writeJSON(makeActionDomainSnapshot(runID: runID, repair: repair), to: snapshotURL, forProjectAt: root)
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

    private func makePlanningProblem(
        runID: String,
        repair: PEXRepairFixture
    ) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-problem",
            runID: runID,
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "layout-input",
                    kind: "layout",
                    artifactID: "layout-gds",
                    metadata: [
                        "symbolicStateAtoms": .array([.string(repair.mismatchAtom)]),
                    ]
                ),
                XcircuitePlanningReference(
                    refID: "source-netlist-input",
                    kind: "source-netlist",
                    artifactID: "source-netlist",
                    metadata: [:]
                ),
                XcircuitePlanningReference(
                    refID: "technology-input",
                    kind: "technology",
                    artifactID: "pex-technology",
                    metadata: [:]
                ),
            ],
            initialStateRefs: [],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "objective-1",
                    kind: "satisfy",
                    domain: "pex",
                    priority: "error",
                    sourceRefIDs: [
                        "layout-input",
                        "source-netlist-input",
                        "technology-input",
                    ],
                    target: repair.target,
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: repair.objectiveDescription,
                    evidence: [
                        "symbolicGoalAtoms": .array([.string(repair.goalAtom)]),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["pex-extraction"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: repair.actionID,
                    domainID: "pex-extraction",
                    operationID: repair.operationID,
                    maturity: "implemented",
                    reason: repair.actionReason,
                    sourceObjectiveIDs: ["objective-1"],
                    requiredInputRefs: [
                        "layout-input",
                        "source-netlist-input",
                        "technology-input",
                    ],
                    verificationGates: [
                        "pex-summary",
                        "simulation-metric",
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "symbolic-planner-solver", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary",
                    required: true,
                    description: "Candidate must improve extracted parasitic evidence."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric",
                    required: true,
                    description: "Candidate must recover post-layout metrics."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    private func makeActionDomainSnapshot(
        runID: String,
        repair: PEXRepairFixture
    ) -> XcircuitePlanningActionDomainSnapshot {
        XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: "2026-06-20T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "pex-extraction",
                    ownerPackages: ["PEXEngine", "CoreSpice", "Xcircuite"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: repair.operationID,
                            maturity: "implemented",
                            inputRefs: [
                                "layout-input",
                                "source-netlist-input",
                                "technology-input",
                            ],
                            preconditions: [repair.mismatchAtom],
                            effects: [repair.goalAtom],
                            producedArtifacts: [
                                "pex-summary",
                                "simulation-summary",
                            ],
                            verificationGates: [
                                "pex-summary",
                                "simulation-metric",
                            ],
                            reversible: true
                        ),
                    ]
                ),
            ]
        )
    }

    private struct PEXRepairFixture: Sendable, Hashable {
        var runID: String
        var actionID: String
        var operationID: String
        var mismatchAtom: String
        var goalAtom: String
        var target: String
        var objectiveDescription: String
        var actionReason: String

        static let capacitanceBudget = PEXRepairFixture(
            runID: "run-pex-capacitance",
            actionID: "fix-pex-capacitance",
            operationID: "pex.repair-capacitance-budget",
            mismatchAtom: "pex-capacitance-exceeds-budget",
            goalAtom: "pex-capacitance-within-budget",
            target: "capacitance-budget",
            objectiveDescription: "Repair extracted capacitance that exceeds the post-layout budget.",
            actionReason: "Reduce extracted capacitance through layout or routing repair."
        )

        static let couplingBudget = PEXRepairFixture(
            runID: "run-pex-coupling",
            actionID: "fix-pex-coupling",
            operationID: "pex.repair-coupling-budget",
            mismatchAtom: "pex-coupling-exceeds-budget",
            goalAtom: "pex-coupling-within-budget",
            target: "coupling-budget",
            objectiveDescription: "Repair coupling parasitic risk after extraction.",
            actionReason: "Reduce coupling exposure before accepting post-layout evidence."
        )

        static let metricDegradation = PEXRepairFixture(
            runID: "run-pex-metric",
            actionID: "fix-pex-post-layout-metric",
            operationID: "pex.repair-post-layout-metric",
            mismatchAtom: "pex-post-layout-metric-degraded",
            goalAtom: "pex-post-layout-metric-recovered",
            target: "post-layout-metric",
            objectiveDescription: "Repair a post-layout simulation metric degraded by parasitics.",
            actionReason: "Recover the post-layout metric through parasitic-aware repair."
        )

        static let multiCornerRegression = PEXRepairFixture(
            runID: "run-pex-multi-corner",
            actionID: "fix-pex-multi-corner-regression",
            operationID: "pex.repair-multi-corner-regression",
            mismatchAtom: "pex-multi-corner-regression",
            goalAtom: "pex-multi-corner-covered",
            target: "multi-corner-parasitic-consistency",
            objectiveDescription: "Repair a multi-corner parasitic regression.",
            actionReason: "Choose a repair that keeps parasitic evidence within limits across corners."
        )

        static let rcNetworkMismatch = PEXRepairFixture(
            runID: "run-pex-rc-network",
            actionID: "fix-pex-rc-network",
            operationID: "pex.repair-rc-network",
            mismatchAtom: "pex-rc-network-mismatch",
            goalAtom: "pex-rc-network-covered",
            target: "rc-network-consistency",
            objectiveDescription: "Repair an extracted RC-network mismatch.",
            actionReason: "Reduce or restructure the extracted RC network before accepting post-layout evidence."
        )

        static let postLayoutSimulationRegression = PEXRepairFixture(
            runID: "run-pex-post-layout-simulation",
            actionID: "fix-pex-post-layout-simulation",
            operationID: "pex.repair-post-layout-simulation-regression",
            mismatchAtom: "pex-post-layout-simulation-regression",
            goalAtom: "pex-post-layout-simulation-recovered",
            target: "post-layout-simulation-regression",
            objectiveDescription: "Repair a post-layout simulation regression caused by extracted parasitics.",
            actionReason: "Recover post-layout simulation behavior with parasitic-aware design changes."
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

    private func writePEXRepairMockPlanner(to solverURL: URL) throws {
        try XcircuitePackageStore().writeText(
            """
            #!/bin/sh
            case "$1" in
              *run-pex-capacitance*) printf '0.000: (a-fix-pex-capacitance) [1.000]\\n' ;;
              *run-pex-coupling*) printf '0.000: (a-fix-pex-coupling) [1.000]\\n' ;;
              *run-pex-metric*) printf '0.000: (a-fix-pex-post-layout-metric) [1.000]\\n' ;;
              *run-pex-multi-corner*) printf '0.000: (a-fix-pex-multi-corner-regression) [1.000]\\n' ;;
              *run-pex-rc-network*) printf '0.000: (a-fix-pex-rc-network) [1.000]\\n' ;;
              *run-pex-post-layout-simulation*) printf '0.000: (a-fix-pex-post-layout-simulation) [1.000]\\n' ;;
              *) exit 2 ;;
            esac
            """,
            to: solverURL
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: solverURL.path(percentEncoded: false)
        )
    }
}
