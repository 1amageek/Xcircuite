import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import Xcircuite

@Suite("Xcircuite symbolic planner LVS repair-domain corpus")
struct XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests {
    @Test func assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain() async throws {
        let root = try makeTemporaryRoot("symbolic-planner-lvs-repair-domain-corpus")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        let fixtures: [LVSRepairFixture] = [
            .portMismatch,
            .modelMismatch,
            .parameterMismatch,
            .deviceMismatch,
            .terminalEquivalence,
            .hierarchyMismatch,
            .globalNetMismatch,
            .policyMutation,
            .blackBoxHierarchy,
            .arrayedDevice,
            .parasiticDevice,
        ]
        for fixture in fixtures {
            try await prepareRun(
                root: root,
                runID: fixture.runID,
                repair: fixture,
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            )
            _ = try await XcircuiteSymbolicPlannerPDDLExporter(
                workspaceStore: workspaceStore,
                artifactStore: artifactStore
            ).exportSymbolicPlannerProblem(
                request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: fixture.runID),
                projectRoot: root
            )
        }
        let solverURL = root.appending(path: "lvs-repair-domain-symbolic-planner.sh")
        try writeLVSRepairMockPlanner(to: solverURL)

        let result = try await XcircuiteSymbolicPlannerSolverCorpusAssessor(
            artifactStore: artifactStore
        ).assess(
            request: XcircuiteSymbolicPlannerSolverCorpusAssessmentRequest(
                suiteID: "lvs-repair-domain-corpus",
                toolID: "mock-lvs-repair-planner",
                executablePath: solverURL.path(percentEncoded: false),
                arguments: ["{problem}"],
                requiredCoverageTags: [
                    "symbolic.lvs-repair-domain",
                    "symbolic.expected-action-coverage",
                    "symbolic.goal-coverage",
                    "symbolic.multi-case",
                    "symbolic.lvs-device-repair-domain",
                    "symbolic.lvs-terminal-equivalence-repair-domain",
                    "symbolic.lvs-hierarchy-repair-domain",
                    "symbolic.lvs-global-net-repair-domain",
                    "symbolic.lvs-policy-mutation-repair-domain",
                    "symbolic.lvs-black-box-hierarchy-repair-domain",
                    "symbolic.lvs-arrayed-device-repair-domain",
                    "symbolic.lvs-parasitic-device-repair-domain",
                ],
                cases: [
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-port",
                        runID: LVSRepairFixture.portMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.portMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.expected-action-coverage",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-model",
                        runID: LVSRepairFixture.modelMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.modelMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.goal-coverage",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-parameter",
                        runID: LVSRepairFixture.parameterMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.parameterMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.multi-case",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-device",
                        runID: LVSRepairFixture.deviceMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.deviceMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-device-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-terminal-equivalence",
                        runID: LVSRepairFixture.terminalEquivalence.runID,
                        expectedActionIDs: [LVSRepairFixture.terminalEquivalence.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-terminal-equivalence-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-hierarchy",
                        runID: LVSRepairFixture.hierarchyMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.hierarchyMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-hierarchy-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-global-net",
                        runID: LVSRepairFixture.globalNetMismatch.runID,
                        expectedActionIDs: [LVSRepairFixture.globalNetMismatch.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-global-net-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-policy-mutation",
                        runID: LVSRepairFixture.policyMutation.runID,
                        expectedActionIDs: [LVSRepairFixture.policyMutation.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-policy-mutation-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-black-box-hierarchy",
                        runID: LVSRepairFixture.blackBoxHierarchy.runID,
                        expectedActionIDs: [LVSRepairFixture.blackBoxHierarchy.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-black-box-hierarchy-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-arrayed-device",
                        runID: LVSRepairFixture.arrayedDevice.runID,
                        expectedActionIDs: [LVSRepairFixture.arrayedDevice.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-arrayed-device-repair-domain",
                        ]
                    ),
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "lvs-parasitic-device",
                        runID: LVSRepairFixture.parasiticDevice.runID,
                        expectedActionIDs: [LVSRepairFixture.parasiticDevice.actionID],
                        coverageTags: [
                            "symbolic.lvs-repair-domain",
                            "symbolic.lvs-parasitic-device-repair-domain",
                        ]
                    ),
                ]
            ),
            projectRoot: root
        )

        #expect(result.status == "passed")
        #expect(result.passedCaseCount == 11)
        #expect(result.failedCaseCount == 0)
        #expect(result.missingRequiredCoverageTags == [])
        #expect(result.coverageTagCounts["symbolic.lvs-repair-domain"] == 11)
        #expect(result.coverageTagCounts["symbolic.lvs-device-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-terminal-equivalence-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-hierarchy-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-global-net-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-policy-mutation-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-black-box-hierarchy-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-arrayed-device-repair-domain"] == 1)
        #expect(result.coverageTagCounts["symbolic.lvs-parasitic-device-repair-domain"] == 1)
        #expect(result.caseResults.map(\.observedActionIDs) == fixtures.map { [$0.actionID] })
        #expect(result.caseResults.allSatisfy { $0.goalCoverageStatus == "covered" })
        #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverCorpusAssessmentSuiteSpecArtifactID)
        #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverCorpusAssessmentArtifactID)
    }

    private func prepareRun(
        root: URL,
        runID: String,
        repair: LVSRepairFixture,
        workspaceStore: XcircuiteWorkspaceStore,
        artifactStore: XcircuitePlanningArtifactStore
    ) async throws {
        try await prepareTestRun(runID: runID, store: workspaceStore)
        _ = try await artifactStore.persistPlanningProblem(
            makePlanningProblem(runID: runID, repair: repair),
            runID: runID,
            projectRoot: root
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        _ = try await workspaceStore.persistArtifact(
            content: encoder.encode(makeActionDomainSnapshot(runID: runID, repair: repair)),
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

    private func makePlanningProblem(
        runID: String,
        repair: LVSRepairFixture
    ) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-problem",
            runID: runID,
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "layout-netlist-input",
                    kind: "layout-netlist",
                    artifactID: "layout-netlist",
                    metadata: [
                        "symbolicStateAtoms": .textList([repair.mismatchAtom]),
                    ]
                ),
                XcircuitePlanningReference(
                    refID: "schematic-netlist-input",
                    kind: "schematic-netlist",
                    artifactID: "schematic-netlist",
                    metadata: [:]
                ),
            ],
            initialStateRefs: [],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "objective-1",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: [
                        "layout-netlist-input",
                        "schematic-netlist-input",
                    ],
                    target: repair.target,
                    currentValue: .scalar(1),
                    requiredValue: .scalar(0),
                    description: repair.objectiveDescription,
                    evidence: [
                        "symbolicGoalAtoms": .textList([repair.goalAtom]),
                    ]
                ),
            ],
            constraints: [],
            actionDomainRefs: ["lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: repair.actionID,
                    domainID: "lvs-signoff",
                    operationID: repair.operationID,
                    maturity: "implemented",
                    reason: repair.actionReason,
                    sourceObjectiveIDs: ["objective-1"],
                    requiredInputRefs: [
                        "layout-netlist-input",
                        "schematic-netlist-input",
                    ],
                    verificationGates: ["native-lvs"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "symbolic-planner-solver", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate must pass LVS."
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
        repair: LVSRepairFixture
    ) -> XcircuitePlanningActionDomainSnapshot {
        XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: "2026-06-20T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "lvs-signoff",
                    ownerPackages: ["LVSEngine", "Xcircuite"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: repair.operationID,
                            maturity: "implemented",
                            inputRefs: [
                                "layout-netlist-input",
                                "schematic-netlist-input",
                            ],
                            preconditions: [repair.mismatchAtom],
                            effects: [repair.goalAtom],
                            producedArtifacts: ["lvs-summary"],
                            verificationGates: ["native-lvs"],
                            reversible: true
                        ),
                    ]
                ),
            ]
        )
    }

    private struct LVSRepairFixture: Sendable, Hashable {
        var runID: String
        var actionID: String
        var operationID: String
        var mismatchAtom: String
        var goalAtom: String
        var target: String
        var objectiveDescription: String
        var actionReason: String

        static let portMismatch = LVSRepairFixture(
            runID: "run-lvs-port",
            actionID: "fix-lvs-port-map",
            operationID: "lvs.repair-port-map",
            mismatchAtom: "lvs-port-mismatch",
            goalAtom: "lvs-port-fixed",
            target: "no-port-mismatch",
            objectiveDescription: "Repair LVS port mismatch.",
            actionReason: "Align LVS port mapping."
        )

        static let modelMismatch = LVSRepairFixture(
            runID: "run-lvs-model",
            actionID: "fix-lvs-model-alias",
            operationID: "lvs.repair-model-alias",
            mismatchAtom: "lvs-model-mismatch",
            goalAtom: "lvs-model-fixed",
            target: "no-model-mismatch",
            objectiveDescription: "Repair LVS model mismatch.",
            actionReason: "Align LVS model alias policy."
        )

        static let parameterMismatch = LVSRepairFixture(
            runID: "run-lvs-parameter",
            actionID: "fix-lvs-parameter",
            operationID: "lvs.repair-parameter",
            mismatchAtom: "lvs-parameter-mismatch",
            goalAtom: "lvs-parameter-fixed",
            target: "no-parameter-mismatch",
            objectiveDescription: "Repair LVS parameter mismatch.",
            actionReason: "Align LVS extracted parameter."
        )

        static let deviceMismatch = LVSRepairFixture(
            runID: "run-lvs-device",
            actionID: "fix-lvs-device-extraction",
            operationID: "lvs.repair-device-extraction",
            mismatchAtom: "lvs-device-mismatch",
            goalAtom: "lvs-device-fixed",
            target: "no-device-mismatch",
            objectiveDescription: "Repair LVS device mismatch.",
            actionReason: "Adjust device extraction or schematic device mapping."
        )

        static let terminalEquivalence = LVSRepairFixture(
            runID: "run-lvs-terminal-equivalence",
            actionID: "fix-lvs-terminal-equivalence",
            operationID: "lvs.repair-terminal-equivalence",
            mismatchAtom: "lvs-terminal-equivalence-mismatch",
            goalAtom: "lvs-terminal-equivalence-fixed",
            target: "terminal-equivalence-covered",
            objectiveDescription: "Repair LVS terminal equivalence mismatch.",
            actionReason: "Apply terminal equivalence policy for symmetric devices."
        )

        static let hierarchyMismatch = LVSRepairFixture(
            runID: "run-lvs-hierarchy",
            actionID: "fix-lvs-hierarchy-binding",
            operationID: "lvs.repair-hierarchy-binding",
            mismatchAtom: "lvs-hierarchy-mismatch",
            goalAtom: "lvs-hierarchy-fixed",
            target: "hierarchy-binding-covered",
            objectiveDescription: "Repair LVS hierarchy mismatch.",
            actionReason: "Align hierarchical cell binding and flattening policy."
        )

        static let globalNetMismatch = LVSRepairFixture(
            runID: "run-lvs-global-net",
            actionID: "fix-lvs-global-net",
            operationID: "lvs.repair-global-net",
            mismatchAtom: "lvs-global-net-mismatch",
            goalAtom: "lvs-global-net-fixed",
            target: "global-net-covered",
            objectiveDescription: "Repair LVS global-net mismatch.",
            actionReason: "Align global supply net recognition."
        )

        static let policyMutation = LVSRepairFixture(
            runID: "run-lvs-policy-mutation",
            actionID: "fix-lvs-policy-mutation",
            operationID: "lvs.repair-policy-mutation",
            mismatchAtom: "lvs-policy-mutation-mismatch",
            goalAtom: "lvs-policy-mutation-fixed",
            target: "policy-mutation-covered",
            objectiveDescription: "Repair LVS policy mutation mismatch.",
            actionReason: "Select a validated LVS matching policy mutation."
        )

        static let blackBoxHierarchy = LVSRepairFixture(
            runID: "run-lvs-black-box-hierarchy",
            actionID: "fix-lvs-black-box-hierarchy",
            operationID: "lvs.repair-black-box-hierarchy",
            mismatchAtom: "lvs-black-box-hierarchy-mismatch",
            goalAtom: "lvs-black-box-hierarchy-fixed",
            target: "black-box-hierarchy-covered",
            objectiveDescription: "Repair LVS black-box hierarchy mismatch.",
            actionReason: "Align black-box hierarchy boundaries and comparison policy."
        )

        static let arrayedDevice = LVSRepairFixture(
            runID: "run-lvs-arrayed-device",
            actionID: "fix-lvs-arrayed-device",
            operationID: "lvs.repair-arrayed-device",
            mismatchAtom: "lvs-arrayed-device-mismatch",
            goalAtom: "lvs-arrayed-device-fixed",
            target: "arrayed-device-covered",
            objectiveDescription: "Repair LVS arrayed-device mismatch.",
            actionReason: "Align arrayed device expansion and multiplicity policy."
        )

        static let parasiticDevice = LVSRepairFixture(
            runID: "run-lvs-parasitic-device",
            actionID: "fix-lvs-parasitic-device",
            operationID: "lvs.repair-parasitic-device",
            mismatchAtom: "lvs-parasitic-device-mismatch",
            goalAtom: "lvs-parasitic-device-fixed",
            target: "parasitic-device-covered",
            objectiveDescription: "Repair LVS parasitic-device mismatch.",
            actionReason: "Classify or suppress extracted parasitic devices under policy."
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

    private func writeLVSRepairMockPlanner(to solverURL: URL) throws {
        let script = """
            #!/bin/sh
            case "$1" in
              *run-lvs-port*) printf '0.000: (a-fix-lvs-port-map) [1.000]\\n' ;;
              *run-lvs-model*) printf '0.000: (a-fix-lvs-model-alias) [1.000]\\n' ;;
              *run-lvs-parameter*) printf '0.000: (a-fix-lvs-parameter) [1.000]\\n' ;;
              *run-lvs-device*) printf '0.000: (a-fix-lvs-device-extraction) [1.000]\\n' ;;
              *run-lvs-terminal-equivalence*) printf '0.000: (a-fix-lvs-terminal-equivalence) [1.000]\\n' ;;
              *run-lvs-hierarchy*) printf '0.000: (a-fix-lvs-hierarchy-binding) [1.000]\\n' ;;
              *run-lvs-global-net*) printf '0.000: (a-fix-lvs-global-net) [1.000]\\n' ;;
              *run-lvs-policy-mutation*) printf '0.000: (a-fix-lvs-policy-mutation) [1.000]\\n' ;;
              *run-lvs-black-box-hierarchy*) printf '0.000: (a-fix-lvs-black-box-hierarchy) [1.000]\\n' ;;
              *run-lvs-arrayed-device*) printf '0.000: (a-fix-lvs-arrayed-device) [1.000]\\n' ;;
              *run-lvs-parasitic-device*) printf '0.000: (a-fix-lvs-parasitic-device) [1.000]\\n' ;;
              *) exit 2 ;;
            esac
            """
        try Data(script.utf8).write(to: solverURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: solverURL.path(percentEncoded: false)
        )
    }
}
