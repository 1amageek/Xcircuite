import Foundation
import DesignFlowKernel
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

extension XcircuiteSymbolicPlannerSolverRunnerTests {
@Test func qualifySymbolicPlannerSolverCorpusCLIProducesAggregatePassingHealth() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-corpus-pass")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl-a")
    try prepareRun(root: root, runID: "run-pddl-b")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-a"),
        projectRoot: root
    )
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-b"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "corpus-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--suite-id",
            "basic-symbolic-corpus",
            "--tool-id",
            "mock-corpus-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--case",
            "run-pddl-a:fix-m1-width",
            "--case",
            "run-pddl-b:fix-m1-width",
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverCorpusQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.qualifiedCaseCount == 2)
    #expect(result.failedCaseCount == 0)
    #expect(result.toolHealth.status == .passed)
    #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
    #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusArtifactID)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["caseCount"] == 2)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["passRate"] == 1)

    let projectManifest = try XcircuiteWorkspaceStore().loadManifest(forProjectAt: root)
    #expect(projectManifest.files.contains {
        $0.path == ".xcircuite/qualification/symbolic-planner/basic-symbolic-corpus/solver-qualification-corpus-suite.json"
    })
    #expect(projectManifest.files.contains {
        $0.path == ".xcircuite/qualification/symbolic-planner/basic-symbolic-corpus/solver-qualification-corpus.json"
    })
    let persisted = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverCorpusQualificationResult.self,
        from: root.appending(path: ".xcircuite/qualification/symbolic-planner/basic-symbolic-corpus/solver-qualification-corpus.json")
    )
    #expect(persisted.status == "qualified")
    #expect(persisted.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
    #expect(persisted.corpusArtifact == nil)
}

@Test func qualifySymbolicPlannerSolverCorpusRejectsEmptyCaseList() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-empty-corpus")
    defer { removeTemporaryRoot(root) }
    try XcircuiteWorkspaceStore().createWorkspace(at: root)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
                suiteID: "empty-symbolic-corpus",
                toolID: "mock-empty-planner",
                executablePath: "/bin/false",
                cases: []
            ),
            projectRoot: root
        )
        Issue.record("Expected empty corpus qualification to fail.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .emptyQualificationCorpus = error else {
            Issue.record("Expected emptyQualificationCorpus, got \(error).")
            return
        }
    }
}

@Test func qualifySymbolicPlannerSolverCorpusCLIReadsSuiteSpec() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-corpus-suite-spec")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl-a")
    try prepareRun(root: root, runID: "run-pddl-b")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-a"),
        projectRoot: root
    )
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-b"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "suite-spec-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let suiteSpecURL = root.appending(path: "symbolic-planner-suite.json")
    try XcircuiteWorkspaceStore().writeJSON(
        XcircuiteSymbolicPlannerSolverCorpusSuiteSpec(
            suiteID: "suite-spec-corpus",
            toolID: "mock-suite-spec-planner",
            executablePath: solverURL.path(percentEncoded: false),
            requiredCoverageTags: [
                "symbolic.expected-action-coverage",
                "symbolic.multi-case",
            ],
            cases: [
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "case-a",
                    runID: "run-pddl-a",
                    expectedActionIDs: ["fix-m1-width"],
                    coverageTags: ["symbolic.expected-action-coverage"]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "case-b",
                    runID: "run-pddl-b",
                    expectedActionIDs: ["fix-m1-width"],
                    coverageTags: ["symbolic.multi-case"]
                ),
            ]
        ),
        to: suiteSpecURL,
        forProjectAt: root
    )

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--suite-spec",
            suiteSpecURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverCorpusQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.suiteID == "suite-spec-corpus")
    #expect(result.toolID == "mock-suite-spec-planner")
    #expect(result.requiredCoverageTags == ["symbolic.expected-action-coverage", "symbolic.multi-case"])
    #expect(result.missingRequiredCoverageTags == [])
    #expect(result.coverageTagCounts["symbolic.expected-action-coverage"] == 1)
    #expect(result.coverageTagCounts["symbolic.multi-case"] == 1)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["coverageRate"] == 1)
    #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
    #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusArtifactID)
    let persistedSuiteSpec = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverCorpusSuiteSpec.self,
        from: root.appending(path: ".xcircuite/qualification/symbolic-planner/suite-spec-corpus/solver-qualification-corpus-suite.json")
    )
    #expect(persistedSuiteSpec.suiteID == "suite-spec-corpus")
    #expect(persistedSuiteSpec.requiredCoverageTags == ["symbolic.expected-action-coverage", "symbolic.multi-case"])
    #expect(persistedSuiteSpec.cases.map(\.caseID) == ["case-a", "case-b"])
}

@Test func qualifySymbolicPlannerSolverCorpusCoversDRCRepairDomain() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-drc-repair-domain-corpus")
    defer { removeTemporaryRoot(root) }
    let fixtures: [DRCRepairFixture] = [
        .width,
        .spacing,
        .enclosure,
        .overlapShort,
        .minimumDensity,
        .antenna,
        .routing,
        .notch,
        .grid,
        .cut,
    ]
    for fixture in fixtures {
        try prepareRun(root: root, runID: fixture.runID, repair: fixture)
        _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
            request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: fixture.runID),
            projectRoot: root
        )
    }
    let solverURL = root.appending(path: "drc-repair-domain-symbolic-planner.sh")
    try writeDRCRepairMockPlanner(to: solverURL)

    let result = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
            suiteID: "drc-repair-domain-corpus",
            toolID: "mock-drc-repair-planner",
            executablePath: solverURL.path(percentEncoded: false),
            arguments: ["{problem}"],
            requiredCoverageTags: [
                "symbolic.drc-repair-domain",
                "symbolic.expected-action-coverage",
                "symbolic.goal-coverage",
                "symbolic.multi-case",
                "symbolic.drc-overlap-repair-domain",
                "symbolic.drc-density-repair-domain",
                "symbolic.drc-antenna-repair-domain",
                "symbolic.drc-routing-repair-domain",
                "symbolic.drc-notch-repair-domain",
                "symbolic.drc-grid-repair-domain",
                "symbolic.drc-cut-repair-domain",
            ],
            cases: [
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-width",
                    runID: DRCRepairFixture.width.runID,
                    expectedActionIDs: [DRCRepairFixture.width.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.expected-action-coverage",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-spacing",
                    runID: DRCRepairFixture.spacing.runID,
                    expectedActionIDs: [DRCRepairFixture.spacing.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.goal-coverage",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-enclosure",
                    runID: DRCRepairFixture.enclosure.runID,
                    expectedActionIDs: [DRCRepairFixture.enclosure.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.multi-case",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-overlap-short",
                    runID: DRCRepairFixture.overlapShort.runID,
                    expectedActionIDs: [DRCRepairFixture.overlapShort.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-overlap-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-minimum-density",
                    runID: DRCRepairFixture.minimumDensity.runID,
                    expectedActionIDs: [DRCRepairFixture.minimumDensity.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-density-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-antenna",
                    runID: DRCRepairFixture.antenna.runID,
                    expectedActionIDs: [DRCRepairFixture.antenna.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-antenna-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-routing",
                    runID: DRCRepairFixture.routing.runID,
                    expectedActionIDs: [DRCRepairFixture.routing.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-routing-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-notch",
                    runID: DRCRepairFixture.notch.runID,
                    expectedActionIDs: [DRCRepairFixture.notch.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-notch-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-grid",
                    runID: DRCRepairFixture.grid.runID,
                    expectedActionIDs: [DRCRepairFixture.grid.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-grid-repair-domain",
                    ]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "drc-cut",
                    runID: DRCRepairFixture.cut.runID,
                    expectedActionIDs: [DRCRepairFixture.cut.actionID],
                    coverageTags: [
                        "symbolic.drc-repair-domain",
                        "symbolic.drc-cut-repair-domain",
                    ]
                ),
            ]
        ),
        projectRoot: root
    )

    #expect(result.status == "qualified")
    #expect(result.qualifiedCaseCount == 10)
    #expect(result.failedCaseCount == 0)
    #expect(result.missingRequiredCoverageTags == [])
    #expect(result.coverageTagCounts["symbolic.drc-repair-domain"] == 10)
    #expect(result.coverageTagCounts["symbolic.drc-overlap-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-density-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-antenna-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-routing-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-notch-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-grid-repair-domain"] == 1)
    #expect(result.coverageTagCounts["symbolic.drc-cut-repair-domain"] == 1)
    #expect(result.caseResults.map(\.observedActionIDs) == fixtures.map { [$0.actionID] })
    #expect(result.caseResults.allSatisfy { $0.goalCoverageStatus == "covered" })
    #expect(result.toolHealth.status == .passed)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["coverageRate"] == 1)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["passRate"] == 1)
    #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
    #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusArtifactID)
}

@Test func qualifySymbolicPlannerSolverCorpusFailsWhenRequiredCoverageIsMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-corpus-missing-coverage")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl-a")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-a"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "coverage-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let result = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
            suiteID: "missing-coverage-corpus",
            toolID: "mock-coverage-planner",
            executablePath: solverURL.path(percentEncoded: false),
            requiredCoverageTags: [
                "symbolic.expected-action-coverage",
                "symbolic.goal-coverage",
            ],
            cases: [
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "case-a",
                    runID: "run-pddl-a",
                    expectedActionIDs: ["fix-m1-width"],
                    coverageTags: ["symbolic.expected-action-coverage"]
                ),
            ]
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.qualifiedCaseCount == 1)
    #expect(result.failedCaseCount == 0)
    #expect(result.coverageTagCounts["symbolic.expected-action-coverage"] == 1)
    #expect(result.missingRequiredCoverageTags == ["symbolic.goal-coverage"])
    #expect(result.failureCodes == ["required-coverage-missing"])
    #expect(result.toolHealth.status == .failed)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["coverageRate"] == 0.5)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["missingRequiredCoverageTagCount"] == 1)
}

@Test func qualifySymbolicPlannerSolverCorpusRejectsUnknownCoverageTags() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-corpus-unknown-coverage")
    defer { removeTemporaryRoot(root) }
    try XcircuiteWorkspaceStore().createWorkspace(at: root)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
                suiteID: "unknown-coverage-corpus",
                toolID: "mock-coverage-planner",
                executablePath: "/bin/false",
                requiredCoverageTags: [
                    "symbolic.external-solver-invocation",
                ],
                cases: [
                    XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                        caseID: "case-unknown",
                        runID: "run-pddl-a",
                        expectedActionIDs: ["fix-m1-width"],
                        coverageTags: ["symbolic.unregistered-domain"]
                    ),
                ]
            ),
            projectRoot: root
        )
        Issue.record("Expected unknown coverage tag validation to fail.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .unknownCoverageTags(let tags, let knownTags) = error else {
            Issue.record("Expected unknownCoverageTags, got \(error).")
            return
        }
        #expect(tags == ["symbolic.unregistered-domain"])
        #expect(knownTags.contains("symbolic.external-solver-invocation"))
        #expect(knownTags.contains("symbolic.drc-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-overlap-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-density-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-antenna-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-routing-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-notch-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-grid-repair-domain"))
        #expect(knownTags.contains("symbolic.drc-cut-repair-domain"))
    }
}

@Test func qualifySymbolicPlannerSolverCorpusAcceptsNativeCertificateCoverageTags() throws {
    let implementedTags = XcircuiteSymbolicPlannerFeatureMatrixProvider()
        .currentMatrix()
        .implementedCoverageTags
    #expect(implementedTags.contains("symbolic.solver-native-certificate-parsing"))

    try XcircuiteSymbolicPlannerCoverageTagValidator().validateImplementedCoverageTags([
        "symbolic.external-solver-invocation",
        "symbolic.solver-native-certificate-parsing",
    ])
}

@Test func qualifySymbolicPlannerSolverCorpusFailsWhenAnyCaseFails() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-corpus-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl-a")
    try prepareRun(root: root, runID: "run-pddl-b")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-a"),
        projectRoot: root
    )
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl-b"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "corpus-failing-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let result = try await XcircuiteSymbolicPlannerSolverCorpusQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverCorpusQualificationRequest(
            suiteID: "mixed-symbolic-corpus",
            toolID: "mock-corpus-planner",
            executablePath: solverURL.path(percentEncoded: false),
            cases: [
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "case-pass",
                    runID: "run-pddl-a",
                    expectedActionIDs: ["fix-m1-width"]
                ),
                XcircuiteSymbolicPlannerSolverCorpusCaseRequest(
                    caseID: "case-fail",
                    runID: "run-pddl-b",
                    expectedActionIDs: ["fix-lvs-mismatch"]
                ),
            ]
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.qualifiedCaseCount == 1)
    #expect(result.failedCaseCount == 1)
    #expect(result.toolHealth.status == .failed)
    #expect(result.failureCodes == ["expected-actions-missing"])
    #expect(result.caseResults.map(\.status) == ["qualified", "failed"])
    #expect(result.toolHealth.evidence.first?.qualification?.qualified == false)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["passRate"] == 0.5)
    #expect(result.suiteSpecArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusSuiteSpecArtifactID)
    #expect(result.corpusArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationCorpusArtifactID)
}
}
