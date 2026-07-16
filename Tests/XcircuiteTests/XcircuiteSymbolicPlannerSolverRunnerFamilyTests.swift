import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

extension XcircuiteSymbolicPlannerSolverRunnerTests {
@Test func runSymbolicPlannerSolverFamilyBatchPersistsPlannerFamilyCertificateFixtures() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-certificate-fixtures")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(
        root: root,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let fastDownwardSolverURL = root.appending(path: "fast-downward-family-symbolic-planner.sh")
    try writeMockPlanner(to: fastDownwardSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")
    let metricFFSolverURL = root.appending(path: "metric-ff-family-symbolic-planner.sh")
    try writeMockPlanner(to: metricFFSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")

    let certificateDirectory = root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates")
    try FileManager.default.createDirectory(at: certificateDirectory, withIntermediateDirectories: true)
    let fastDownwardCertificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates/fast-downward.txt"
    try await store.writeWorkspaceText(
        """
        Fast Downward 24.06
        Solution found.
        Search status: solved optimally
        Plan length: 1 step(s).
        Plan cost: 1
        Best solution cost so far: 1
        Actual search time: 0.01s
        """,
        to: fastDownwardCertificatePath
    )
    let metricFFCertificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates/metric-ff.txt"
    try await store.writeWorkspaceText(
        """
        Metric-FF v2.1
        ff: found legal plan as follows
        step    0: A-FIX-M1-WIDTH
        plan length: 1
        plan cost: 1
        """,
        to: metricFFCertificatePath
    )

    let spec = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "solver-family-certificate-fixtures",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                candidateID: "fast-downward",
                toolID: "fast-downward-fixture-planner",
                executablePath: fastDownwardSolverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"],
                requireOptimality: true,
                requireNativeCertificate: true,
                certificatePath: fastDownwardCertificatePath,
                certificateFormat: "fast-downward-text"
            ),
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                candidateID: "metric-ff",
                toolID: "metric-ff-fixture-planner",
                executablePath: metricFFSolverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"],
                requireNativeCertificate: true,
                certificatePath: metricFFCertificatePath,
                certificateFormat: "metric-ff-text"
            ),
        ],
        promoteSelectedPlan: false
    )
    let specURL = root.appending(path: "solver-family-certificate-fixtures.json")
    try writeJSONFile(spec, to: specURL)

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "run-symbolic-planner-solver-family",
            "--project-root",
            root.path(percentEncoded: false),
            "--spec",
            specURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyBatchResult.self,
        from: data
    )

    #expect(result.batchRun.status == "completed-with-passing-selection")
    #expect(result.batchRun.passedCandidateCount == 2)
    #expect(result.comparisonResult.comparison.selectedToolID == "fast-downward-fixture-planner")
    #expect(result.comparisonResult.comparison.candidates[0].nativeCertificateArtifact?.path.contains("/candidates/candidate-0-fast-downward/solver-certificate.json") == true)
    #expect(result.comparisonResult.comparison.candidates[1].nativeCertificateArtifact?.path.contains("/candidates/candidate-1-metric-ff/solver-certificate.json") == true)
    #expect(result.comparisonResult.comparison.candidates[0].scoreComponents.contains {
        $0.termID == "optimality" && $0.contribution > 0
    })
    #expect(result.comparisonResult.comparison.candidates[0].selectionScore > result.comparisonResult.comparison.candidates[1].selectionScore)

    let fastDownwardSnapshot = try await store.readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-certificate-fixtures/candidates/candidate-0-fast-downward/solver-certificate.json"
    )
    #expect(fastDownwardSnapshot.certificate?.solverFamily == "fast-downward")
    #expect(fastDownwardSnapshot.certificate?.optimalityStatus == "optimal")
    #expect(fastDownwardSnapshot.certificate?.lowerBound == 1)
    #expect(fastDownwardSnapshot.certificate?.upperBound == 1)

    let metricFFSnapshot = try await store.readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-certificate-fixtures/candidates/candidate-1-metric-ff/solver-certificate.json"
    )
    #expect(metricFFSnapshot.certificate?.solverFamily == "metric-ff")
    #expect(metricFFSnapshot.certificate?.optimalityStatus == nil)
    #expect(metricFFSnapshot.certificate?.goalCoverageStatus == "covered")
}

@Test func discoverInstalledSymbolicPlannerSolversCLIWritesLaneArtifactAndBatchSpec() async throws {
    let root = try makeTemporaryRoot("installed-symbolic-planner-lane")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let binURL = root.appending(path: "bin")
    try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
    let fastDownwardURL = binURL.appending(path: "fast-downward.py")
    try writeMockPlanner(to: fastDownwardURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")
    let batchSpecURL = root.appending(path: "installed-solver-batch.json")

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "discover-installed-symbolic-planner-solvers",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--lane-id",
            "installed-fixture-lane",
            "--search-path",
            binURL.path(percentEncoded: false),
            "--batch-spec-output-path",
            batchSpecURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult.self,
        from: data
    )

    #expect(result.lane.status == "available")
    #expect(result.lane.availableCandidateCount == 1)
    #expect(result.lane.unavailableCandidateCount == 3)
    #expect(result.lane.candidates.first { $0.solverFamily == "fast-downward" }?.status == "available")
    #expect(result.lane.candidates.first { $0.solverFamily == "metric-ff" }?.status == "missing")
    #expect(result.lane.batchRequest?.candidates.map(\.toolID) == ["fast-downward"])
    #expect(result.lane.batchRequest?.candidates.first?.certificateFormat == "fast-downward-text")
    #expect(result.lane.batchRequest?.candidates.first?.requireNativeCertificate == true)
    #expect(result.laneArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerInstalledSolverLaneArtifactID)-installed-fixture-lane")

    let persistedLane = try await store.readJSON(
        XcircuiteSymbolicPlannerInstalledSolverLane.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/installed-solver-lane.json"
    )
    #expect(persistedLane.batchRequest?.candidates.count == 1)

    let writtenBatchSpec = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyBatchRequest.self,
        from: Data(contentsOf: batchSpecURL)
    )
    #expect(writtenBatchSpec.comparisonID == "installed-fixture-lane")
    #expect(writtenBatchSpec.candidates.map(\.toolID) == ["fast-downward"])
}

@Test func discoverInstalledSymbolicPlannerSolversPrefersLaterExecutableOverEarlierNonExecutableFile() async throws {
    let root = try makeTemporaryRoot("installed-symbolic-planner-lane-path-priority")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let staleBinURL = root.appending(path: "stale-bin")
    let workingBinURL = root.appending(path: "working-bin")
    try FileManager.default.createDirectory(at: staleBinURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workingBinURL, withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 1\n".write(
        to: staleBinURL.appending(path: "fast-downward.py"),
        atomically: true,
        encoding: .utf8
    )
    let fastDownwardURL = workingBinURL.appending(path: "fast-downward.py")
    try writeMockPlanner(to: fastDownwardURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "discover-installed-symbolic-planner-solvers",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--lane-id",
            "installed-path-priority-lane",
            "--search-path",
            staleBinURL.path(percentEncoded: false),
            "--search-path",
            workingBinURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerInstalledSolverLaneDiscoveryResult.self,
        from: try #require(json.data(using: .utf8))
    )
    let fastDownward = try #require(result.lane.candidates.first { $0.solverFamily == "fast-downward" })

    #expect(result.lane.status == "available")
    #expect(fastDownward.status == "available")
    #expect(fastDownward.executablePath == fastDownwardURL.path(percentEncoded: false))
    #expect(result.lane.batchRequest?.candidates.map(\.executablePath) == [fastDownwardURL.path(percentEncoded: false)])
}

@Test func runSymbolicPlannerSolverFamilyBatchRejectsDuplicateCandidateToolID() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-duplicate-tool-id")
    defer { removeTemporaryRoot(root) }
    let request = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "duplicate-tool-id",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                toolID: "duplicate-solver",
                executablePath: "/bin/echo"
            ),
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                toolID: "duplicate-solver",
                executablePath: "/bin/echo"
            ),
        ],
        promoteSelectedPlan: false
    )
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner(
            workspaceStore: store,
            artifactStore: artifactStore
        ).run(
            request: request,
            projectRoot: root
        )
        Issue.record("Expected duplicateSolverFamilyCandidateToolID.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .duplicateSolverFamilyCandidateToolID(toolID: "duplicate-solver"))
    }
}

@Test func runSymbolicPlannerSolverFamilyBatchRejectsEmptyCandidateExecutablePath() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-empty-executable")
    defer { removeTemporaryRoot(root) }
    let request = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "empty-executable",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                toolID: "empty-executable-solver",
                executablePath: ""
            ),
        ],
        promoteSelectedPlan: false
    )
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner(
            workspaceStore: store,
            artifactStore: artifactStore
        ).run(
            request: request,
            projectRoot: root
        )
        Issue.record("Expected invalidSolverFamilyCandidateExecutablePath.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .invalidSolverFamilyCandidateExecutablePath(index: 0))
    }
}

@Test func runSymbolicPlannerSolverFamilyBatchRejectsInvalidCandidateArtifactIDReference() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-invalid-artifact-id")
    defer { removeTemporaryRoot(root) }
    let request = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "invalid-artifact-id",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                toolID: "invalid-artifact-solver",
                executablePath: "/bin/echo",
                domainArtifactID: "../domain"
            ),
        ],
        promoteSelectedPlan: false
    )
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner(
            workspaceStore: store,
            artifactStore: artifactStore
        ).run(
            request: request,
            projectRoot: root
        )
        Issue.record("Expected invalidSolverFamilyCandidateReference.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .invalidSolverFamilyCandidateReference(
            index: 0,
            field: "domainArtifactID",
            value: "../domain"
        ))
    }
}

@Test func compareAndPromoteSymbolicPlannerSolverFamilyCLISelectsValidatedCertificate() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-comparison")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(
        root: root,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let solverURL = root.appending(path: "family-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let failedSolverURL = root.appending(path: "failed-family-symbolic-planner.sh")
    try writeMockPlanner(to: failedSolverURL, planText: "0.000: (a-unmapped-action) [1.000]\\n")

    let validatedJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "validate-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-validated-family-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
        ]
    )
    let validatedData = try #require(validatedJSON.data(using: .utf8))
    var validated = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverValidationResult.self,
        from: validatedData
    )
    validated.validationArtifact = nil
    let validatedSolverPlanPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/validated-solver-plan.txt"
    let validatedSolverPlanRef = try await store.persistArtifact(
        content: Data("0.000: (a-fix-m1-width) [1.000]\n".utf8),
        id: try ArtifactID(rawValue: "validated-family-solver-plan-input"),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: validatedSolverPlanPath),
            role: .output,
            kind: .other,
            format: .text
        ),
        runID: "run-pddl",
        mode: .replaceable
    )
    validated.solverResult.solverPlanArtifact = validatedSolverPlanRef
    if var importResult = validated.solverResult.importResult {
        importResult.solverPlanArtifact = validatedSolverPlanRef
        validated.solverResult.importResult = importResult
    }

    let failedJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "validate-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-failed-family-planner",
            "--executable-path",
            failedSolverURL.path(percentEncoded: false),
            "--expected-action-id",
            "missing-action",
        ]
    )
    let failedData = try #require(failedJSON.data(using: .utf8))
    var failed = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverValidationResult.self,
        from: failedData
    )
    failed.validationArtifact = nil

    let inputDirectory = root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs")
    try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    let validatedPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/validated.json"
    let failedPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/failed.json"
    try await store.writeJSON(validated, to: validatedPath)
    try await store.writeJSON(failed, to: failedPath)

    let comparisonJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "compare-symbolic-planner-solver-family",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--comparison-id",
            "solver-family-regression",
            "--validation-path",
            validatedPath,
            "--validation-path",
            failedPath,
            "--pretty",
        ]
    )
    let comparisonData = try #require(comparisonJSON.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyComparisonResult.self,
        from: comparisonData
    )

    #expect(result.comparison.status == "selected-passing")
    #expect(result.comparison.selectedCandidateIndex == 0)
    #expect(result.comparison.selectedToolID == "mock-validated-family-planner")
    #expect(result.comparison.candidateCount == 2)
    #expect(result.comparison.passedCandidateCount == 1)
    #expect(result.comparison.failedCandidateCount == 1)
    #expect(result.comparison.candidates[0].selected == true)
    #expect(result.comparison.candidates[1].selected == false)
    #expect(result.comparison.candidates[1].missingExpectedActionIDs == ["missing-action"])
    #expect(result.comparison.candidates[0].selectionScore > result.comparison.candidates[1].selectionScore)
    #expect(result.comparisonArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyComparisonArtifactID)-solver-family-regression")

    let persisted = try await store.readJSON(
        XcircuiteSymbolicPlannerSolverFamilyComparison.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-regression/solver-family-comparison.json"
    )
    #expect(persisted.selectedToolID == "mock-validated-family-planner")
    let manifest = (try await store.loadRunLedger(runID: "run-pddl")).runManifest
    #expect(manifest.artifacts.contains {
        $0.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyComparisonArtifactID)-solver-family-regression"
    })

    let promotionJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "promote-symbolic-planner-solver-family-selection",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--comparison-id",
            "solver-family-regression",
            "--pretty",
        ]
    )
    let promotionData = try #require(promotionJSON.data(using: .utf8))
    let promotionResult = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyPromotionResult.self,
        from: promotionData
    )
    #expect(promotionResult.promotion.status == "promoted-with-verification-diagnostics")
    #expect(promotionResult.promotion.selectedToolID == "mock-validated-family-planner")
    #expect(promotionResult.promotion.promotedCandidatePlanArtifact.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
    #expect(promotionResult.promotion.promotedSolverPlanArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID)
    #expect(promotionResult.promotion.promotedPlanReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
    #expect(promotionResult.promotion.promotedPlanVerificationArtifact?.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID)
    #expect(promotionResult.promotion.verificationAccepted == false)
    #expect(promotionResult.promotion.diagnostics.map(\.code) == ["promoted-plan-verification-not-accepted"])
    #expect(promotionResult.promotionArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyPromotionArtifactID)-solver-family-regression")

    let promotedPlan = try await store.readJSON(
        XcircuiteCandidatePlan.self,
        from: ".xcircuite/runs/run-pddl/planning/candidate-plan.json"
    )
    #expect(promotedPlan.steps.map(\.actionID) == ["fix-m1-width"])
    let promotedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(promotedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")
    let promotedManifest = (try await store.loadRunLedger(runID: "run-pddl")).runManifest
    #expect(promotedManifest.artifacts.contains {
        $0.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyPromotionArtifactID)-solver-family-regression"
    })
}

@Test func runSymbolicPlannerSolverFamilyBatchCLIValidatesComparesAndPromotes() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-batch")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(
        root: root,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let validatedSolverURL = root.appending(path: "batch-validated-symbolic-planner.sh")
    try writeMockPlanner(to: validatedSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")
    let failedSolverURL = root.appending(path: "batch-failed-symbolic-planner.sh")
    try writeMockPlanner(to: failedSolverURL, planText: "0.000: (a-unmapped-action) [1.000]\n")
    let spec = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "solver-family-batch-regression",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                candidateID: "passed",
                toolID: "mock-validated-batch-planner",
                executablePath: validatedSolverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"]
            ),
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                candidateID: "failed",
                toolID: "mock-failed-batch-planner",
                executablePath: failedSolverURL.path(percentEncoded: false),
                expectedActionIDs: ["missing-action"]
            ),
        ]
    )
    let specURL = root.appending(path: "solver-family-batch-spec.json")
    try writeJSONFile(spec, to: specURL)

    let batchJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "run-symbolic-planner-solver-family",
            "--project-root",
            root.path(percentEncoded: false),
            "--spec",
            specURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let batchData = try #require(batchJSON.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyBatchResult.self,
        from: batchData
    )

    #expect(result.batchRun.status == "completed-with-promotion-diagnostics")
    #expect(result.batchRun.candidateCount == 2)
    #expect(result.batchRun.passedCandidateCount == 1)
    #expect(result.batchRun.failedCandidateCount == 1)
    #expect(result.comparisonResult.comparison.status == "selected-passing")
    #expect(result.comparisonResult.comparison.selectedToolID == "mock-validated-batch-planner")
    #expect(result.promotionResult?.promotion.selectedToolID == "mock-validated-batch-planner")
    #expect(result.batchArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyBatchArtifactID)-solver-family-batch-regression")

    let validatedCandidate = result.batchRun.candidates[0]
    #expect(validatedCandidate.candidateID == "candidate-0-passed")
    #expect(validatedCandidate.validationStatus == "passed")
    #expect(validatedCandidate.validationArtifact.path.contains("/candidates/candidate-0-passed/solver-validation.json"))
    #expect(validatedCandidate.solverPlanArtifact?.path.contains("/candidates/candidate-0-passed/solver-plan.txt") == true)
    let failedCandidate = result.batchRun.candidates[1]
    #expect(failedCandidate.candidateID == "candidate-1-failed")
    #expect(failedCandidate.validationStatus == "failed")

    let selectedValidation = result.comparisonResult.comparison.selectedValidationArtifact
    #expect(selectedValidation?.path.contains("/candidates/candidate-0-passed/solver-validation.json") == true)
    let validatedSnapshot = try await store.readJSON(
        XcircuiteSymbolicPlannerSolverValidationResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-batch-regression/candidates/candidate-0-passed/solver-validation.json"
    )
    #expect(validatedSnapshot.validationArtifact == nil)
    #expect(validatedSnapshot.solverResult.solverPlanArtifact?.artifactID == validatedCandidate.solverPlanArtifact?.artifactID)
    let validatedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-batch-regression/candidates/candidate-0-passed/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(validatedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")

    let promotedPlan = try await store.readJSON(
        XcircuiteCandidatePlan.self,
        from: ".xcircuite/runs/run-pddl/planning/candidate-plan.json"
    )
    #expect(promotedPlan.steps.map(\.actionID) == ["fix-m1-width"])
    let promotedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(promotedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")

    let manifest = (try await store.loadRunLedger(runID: "run-pddl")).runManifest
    let promotionArtifactID = try #require(result.promotionResult?.promotionArtifact.artifactID)
    let validatedSolverPlanArtifactID = try #require(validatedCandidate.solverPlanArtifact?.artifactID)
    #expect(manifest.artifacts.contains { $0.artifactID == result.batchArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == result.comparisonResult.comparisonArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == promotionArtifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == validatedCandidate.validationArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == validatedSolverPlanArtifactID })
}

@Test func validateSymbolicPlannerSolverValidatesProofArtifactWithExternalChecker() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-proof-validation")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(
        root: root,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let solverURL = root.appending(path: "proof-validated-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\n")
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try await store.writeWorkspaceText(
        "proof-ok\n",
        to: proofPath
    )
    let checkerURL = root.appending(path: "proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "proof-ok", success: true)

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "validate-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-proof-validated-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
            "--require-proof-validation",
            "--proof-path",
            proofPath,
            "--proof-checker-executable-path",
            checkerURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverValidationResult.self,
        from: data
    )

    #expect(result.status == "passed")
    #expect(result.requireProofValidation == true)
    #expect(result.proofValidation?.status == "validated")
    #expect(result.proofValidation?.proofArtifact.path == proofPath)
    #expect(result.proofValidation?.standardOutputArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID)
    #expect(result.proofValidation?.standardErrorArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStderrArtifactID)
    #expect(result.proofValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID)
    #expect(result.proofValidation != nil)
    #expect(result.proofValidation?.diagnostics.contains { $0.severity == "error" } == false)

    let persistedValidation = try await store.readJSON(
        XcircuiteSymbolicPlannerProofValidation.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/proof-validation.json"
    )
    #expect(persistedValidation.status == "validated")
    #expect(persistedValidation.standardOutputArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID)

    let manifest = (try await store.loadRunLedger(runID: "run-pddl")).runManifest
    let artifactIDs = Set(manifest.artifacts.map(\.artifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStderrArtifactID))
}

@Test func validateSymbolicPlannerSolverFailsWhenProofCheckerRejectsArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-proof-validation-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(
        root: root,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let solverURL = root.appending(path: "proof-rejected-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try await store.writeWorkspaceText(
        "proof-bad\n",
        to: proofPath
    )
    let checkerURL = root.appending(path: "rejecting-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "proof-ok", success: false)

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-proof-rejected-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireProofValidation: true,
            proofPath: proofPath,
            proofCheckerExecutablePath: checkerURL.path(percentEncoded: false)
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.proofValidation?.status == "failed")
    #expect(result.proofValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID)
    #expect(result.diagnostics.contains {
        $0.code == "proof-validation-proof-checker-non-zero-exit"
    })
    #expect(result.proofValidation != nil)
    #expect(result.proofValidation?.diagnostics.contains {
        $0.code == "proof-checker-non-zero-exit"
    } == true)
}

@Test func validateSymbolicPlannerSolverFailsWhenSolverCostClaimDoesNotMatchEvaluatedCost() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-cost-policy-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(root: root, runID: "run-pddl", workspaceStore: store, artifactStore: artifactStore)
    _ = try await exportSymbolicPlannerProblem(root: root, workspaceStore: store, artifactStore: artifactStore)
    let solverURL = root.appending(path: "expensive-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 4 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-expensive-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            maximumSolverCost: 1
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.solverMetadata?.optimalityStatus == "optimal")
    #expect(result.solverMetadata?.planCost == 4)
    #expect(result.planCostEvaluation?.evaluatedCost == 1)
    #expect(result.diagnostics.contains { $0.code == "solver-cost-claim-mismatch" })
    #expect(!result.diagnostics.contains { $0.code == "solver-cost-exceeds-bound" })
    #expect(result.solverMetadata?.planCost == 4)
    #expect(result.planCostEvaluation?.evaluatedCost == 1)
}

@Test func validateSymbolicPlannerSolverFailsWhenEvaluatedCostExceedsBound() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-evaluated-cost-policy-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(root: root, runID: "run-pddl", workspaceStore: store, artifactStore: artifactStore)
    _ = try await exportSymbolicPlannerProblem(root: root, workspaceStore: store, artifactStore: artifactStore)
    let solverURL = root.appending(path: "two-step-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\n1.000: (a-fix-m1-width) [1.000]\\nplan length: 2\\ncost = 2 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-two-step-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            maximumSolverCost: 1
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.solverMetadata?.optimalityStatus == "optimal")
    #expect(result.solverMetadata?.planCost == 2)
    #expect(result.planCostEvaluation?.planLength == 2)
    #expect(result.planCostEvaluation?.evaluatedCost == 2)
    #expect(result.diagnostics.contains { $0.code == "solver-cost-exceeds-bound" })
    #expect(result.planCostEvaluation?.evaluatedCost == 2)
}

@Test func validateSymbolicPlannerSolverFailsWhenReplayPreconditionsAreUnsatisfied() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-replay-policy-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        includeViolationAtom: false,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    _ = try await exportSymbolicPlannerProblem(root: root, workspaceStore: store, artifactStore: artifactStore)
    let solverURL = root.appending(path: "invalid-replay-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 1 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-invalid-replay-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            maximumSolverCost: 1
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.planReplayValidation?.status == "failed")
    #expect(result.planReplayValidation?.steps.first?.missingPreconditionAtoms == ["drc-width-violation"])
    #expect(result.planReplayValidation?.missingGoalAtoms == ["drc-width-fixed"])
    #expect(result.diagnostics.contains { $0.code == "plan-replay-preconditions-unsatisfied" })
    #expect(result.diagnostics.contains { $0.code == "plan-replay-goals-unsatisfied" })
    #expect(result.planReplayValidation?.diagnostics.filter { $0.severity == "error" }.count == 2)
    #expect(result.planReplayValidation?.steps.reduce(0) {
        $0 + $1.missingPreconditionAtoms.count
    } == 1)
    #expect(result.planReplayValidation?.missingGoalAtoms.count == 1)
    #expect(result.planReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
}

@Test func validateSymbolicPlannerSolverFailsWhenOptimalityIsRequiredButMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-optimality-policy-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(root: root, runID: "run-pddl", workspaceStore: store, artifactStore: artifactStore)
    _ = try await exportSymbolicPlannerProblem(root: root, workspaceStore: store, artifactStore: artifactStore)
    let solverURL = root.appending(path: "satisficing-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Satisficing solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 1 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-satisficing-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            maximumSolverCost: 1
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.solverMetadata?.optimalityStatus == "satisficing")
    #expect(result.diagnostics.contains { $0.code == "optimality-not-validated" })
    #expect(result.solverMetadata?.optimalityStatus != "optimal")
}

@Test func validateSymbolicPlannerSolverFailsWhenExpectedActionIsMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-validation-fail")
    defer { removeTemporaryRoot(root) }
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(root: root, runID: "run-pddl", workspaceStore: store, artifactStore: artifactStore)
    _ = try await exportSymbolicPlannerProblem(root: root, workspaceStore: store, artifactStore: artifactStore)
    let solverURL = root.appending(path: "wrong-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let result = try await XcircuiteSymbolicPlannerSolverValidator(
        workspaceStore: store,
        artifactStore: artifactStore
    ).validate(
        request: XcircuiteSymbolicPlannerSolverValidationRequest(
            runID: "run-pddl",
            toolID: "mock-failing-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-lvs-mismatch"]
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.observedActionIDs == ["fix-m1-width"])
    #expect(result.goalCoverageStatus == "covered")
    #expect(result.diagnostics.contains { $0.code == "expected-actions-missing" })
    #expect(result.validationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverValidationArtifactID)
}

@Test func promoteSymbolicPlannerSolverFamilyRejectsMismatchedComparisonID() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-mismatched-comparison")
    defer { removeTemporaryRoot(root) }
    let fixture = try await preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "actual-comparison"
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter(
            workspaceStore: fixture.workspaceStore,
            artifactStore: fixture.artifactStore
        ).promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: "run-pddl",
                comparisonID: "expected-comparison",
                comparisonArtifactID: fixture.comparisonArtifact.artifactID,
                verifyPromotedPlan: false
            ),
            projectRoot: root
        )
        Issue.record("Expected solverFamilyComparisonIDMismatch.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .solverFamilyComparisonIDMismatch(
            expected: "expected-comparison",
            actual: "actual-comparison"
        ))
    }
}

@Test func promoteSymbolicPlannerSolverFamilyRejectsAmbiguousCanonicalManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-duplicate-comparison")
    defer { removeTemporaryRoot(root) }
    let fixture = try await preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "duplicate-comparison"
    )
    let ledgerURL = root.appending(path: ".xcircuite/runs/run-pddl/ledger.json")
    try XcircuiteRunLedgerTamper.append([fixture.comparisonArtifact], to: ledgerURL)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter(
            workspaceStore: fixture.workspaceStore,
            artifactStore: fixture.artifactStore
        ).promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: "run-pddl",
                comparisonID: "duplicate-comparison",
                verifyPromotedPlan: false
            ),
            projectRoot: root
        )
        Issue.record("Expected an invalid run ledger error.")
    } catch let error as FlowRunLedgerPersistenceError {
        guard case .storageFailed(let reason) = error else {
            Issue.record("Expected storageFailed, got \(error).")
            return
        }
        #expect(reason.contains("must be unique"))
    }
}

@Test func compareSymbolicPlannerSolverFamilyRejectsAmbiguousCanonicalManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-duplicate-validation")
    defer { removeTemporaryRoot(root) }
    let fixture = try await preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "duplicate-validation"
    )
    let ledgerURL = root.appending(path: ".xcircuite/runs/run-pddl/ledger.json")
    try XcircuiteRunLedgerTamper.append([fixture.validationArtifact], to: ledgerURL)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilySelector(
            workspaceStore: fixture.workspaceStore,
            artifactStore: fixture.artifactStore
        ).compare(
            request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest(
                runID: "run-pddl",
                comparisonID: "duplicate-validation-comparison",
                validationArtifactIDs: [fixture.validationArtifact.artifactID]
            ),
            projectRoot: root
        )
        Issue.record("Expected an invalid run ledger error.")
    } catch let error as FlowRunLedgerPersistenceError {
        guard case .storageFailed(let reason) = error else {
            Issue.record("Expected storageFailed, got \(error).")
            return
        }
        #expect(reason.contains("must be unique"))
    }
}

@Test func promoteSymbolicPlannerSolverFamilyRejectsTamperedValidationArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-tampered-validation")
    defer { removeTemporaryRoot(root) }
    let fixture = try await preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "tampered-validation"
    )
    let tamperedValidationURL = root.appending(path: fixture.validationArtifact.path)
    try "tampered".write(to: tamperedValidationURL, atomically: true, encoding: .utf8)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter(
            workspaceStore: fixture.workspaceStore,
            artifactStore: fixture.artifactStore
        ).promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: "run-pddl",
                comparisonID: "tampered-validation",
                verifyPromotedPlan: false
            ),
            projectRoot: root
        )
        Issue.record("Expected artifactIntegrityFailed.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .artifactIntegrityFailed(let field, let artifactID, _, let status, _) = error else {
            Issue.record("Expected artifactIntegrityFailed, got \(error).")
            return
        }
        #expect(field == "validationArtifact")
        #expect(artifactID == fixture.validationArtifact.artifactID)
        #expect(status == .byteCountMismatch || status == .sha256Mismatch)
    }
}

private func preparePromotionFixture(
    root: URL,
    runID: String,
    comparisonID: String
) async throws -> PromotionFixture {
    let store = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: store)
    try await prepareRun(
        root: root,
        runID: runID,
        workspaceStore: store,
        artifactStore: artifactStore
    )
    let solverPlanPath = ".xcircuite/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)/fixture-solver-plan.txt"
    let solverPlanReference = try await store.persistArtifact(
        content: Data("0.000: (a-fix-m1-width) [1.000]\n".utf8),
        id: try ArtifactID(rawValue: "\(comparisonID)-fixture-solver-plan"),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: solverPlanPath),
            role: .output,
            kind: .other,
            format: .text
        ),
        runID: runID,
        mode: .replaceable
    )
    let candidatePlan = XcircuiteCandidatePlan(
        planID: "fixture-plan",
        problemID: "\(runID)-problem",
        runID: runID,
        strategy: "symbolic-planner-solver",
        executionReadiness: "ready",
        sourceProblemRef: XcircuitePlanningReference(
            refID: "planning-problem",
            kind: "planning-problem",
            artifactID: XcircuitePlanningArtifactStore.problemArtifactID
        ),
        steps: [
            XcircuiteCandidatePlanStep(
                stepID: "step-1",
                order: 1,
                actionID: "fix-m1-width",
                domainID: "drc-signoff",
                operationID: "adjust-device-width",
                maturity: "implemented",
                readiness: "ready",
                sourceObjectiveIDs: ["objective-1"],
                requiredInputRefs: ["layout-drc-input"],
                missingInputRefs: [],
                verificationGates: ["native-drc"],
                reason: "Fixture repair plan.",
                parameterHints: [:],
                blockers: []
            ),
        ],
        verificationGates: [],
        constraints: [],
        unresolvedObjectives: [],
        blockers: []
    )
    let importResult = XcircuiteSymbolicPlannerPlanImportResult(
        status: "imported",
        runID: runID,
        problemID: "\(runID)-problem",
        planID: "fixture-plan",
        importedActionCount: 1,
        solverPlanArtifact: solverPlanReference,
        pddlExportArtifact: solverPlanReference,
        candidatePlanArtifact: solverPlanReference,
        candidatePlan: candidatePlan,
        diagnostics: []
    )
    let solverResult = XcircuiteSymbolicPlannerSolverResult(
        status: "solved",
        runID: runID,
        exitCode: 0,
        didTimeout: false,
        didCancel: false,
        domainArtifact: solverPlanReference,
        problemArtifact: solverPlanReference,
        pddlExportArtifact: solverPlanReference,
        runArtifact: solverPlanReference,
        standardOutputArtifact: solverPlanReference,
        standardErrorArtifact: solverPlanReference,
        solverPlanArtifact: solverPlanReference,
        importResult: importResult,
        diagnostics: []
    )
    let validation = XcircuiteSymbolicPlannerSolverValidationResult(
        status: "passed",
        runID: runID,
        toolID: "fixture-symbolic-planner",
        policyID: "fixture-policy",
        expectedActionIDs: ["fix-m1-width"],
        observedActionIDs: ["fix-m1-width"],
        requireGoalCoverage: true,
        goalCoverageStatus: "covered",
        missingGoalAtoms: [],
        solverResult: solverResult,
        planVerificationArtifact: nil,
        diagnostics: []
    )
    let validationArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyValidation(
        validation,
        runID: runID,
        comparisonID: comparisonID,
        candidateID: "candidate-a",
        projectRoot: root
    )
    let candidate = XcircuiteSymbolicPlannerSolverFamilyCandidateResult(
        candidateIndex: 0,
        status: "passed",
        selected: true,
        selectionScore: 100,
        scoreComponents: [],
        toolID: "fixture-symbolic-planner",
        validationStatus: "passed",
        solverRunStatus: "solved",
        expectedActionIDs: ["fix-m1-width"],
        observedActionIDs: ["fix-m1-width"],
        missingExpectedActionIDs: [],
        goalCoverageStatus: "covered",
        missingGoalAtoms: [],
        planReplayStatus: nil,
        proofValidationStatus: nil,
        optimalityStatus: nil,
        evaluatedCost: 1,
        maximumSolverCost: nil,
        solverPlanLength: 1,
        solverExitCode: 0,
        didTimeout: false,
        didCancel: false,
        validationArtifact: validationArtifact,
        planVerificationArtifact: nil,
        diagnostics: []
    )
    let comparison = XcircuiteSymbolicPlannerSolverFamilyComparison(
        status: "selected-passing",
        runID: runID,
        comparisonID: comparisonID,
        selectionPolicy: "validated-first",
        requestedValidationArtifactIDs: [validationArtifact.artifactID],
        requestedValidationPaths: [],
        selectedCandidateIndex: 0,
        selectedToolID: "fixture-symbolic-planner",
        selectedValidationArtifact: validationArtifact,
        candidateCount: 1,
        passedCandidateCount: 1,
        failedCandidateCount: 0,
        candidates: [candidate]
    )
    let comparisonArtifact = try await artifactStore.persistSymbolicPlannerSolverFamilyComparison(
        comparison,
        runID: runID,
        projectRoot: root
    )
    return PromotionFixture(
        comparisonArtifact: comparisonArtifact,
        validationArtifact: validationArtifact,
        workspaceStore: store,
        artifactStore: artifactStore
    )
}

private struct PromotionFixture {
    let comparisonArtifact: ArtifactReference
    let validationArtifact: ArtifactReference
    let workspaceStore: XcircuiteWorkspaceStore
    let artifactStore: XcircuitePlanningArtifactStore
}

private func writeJSONFile<Value: Encodable>(_ value: Value, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(value).write(to: url, options: [.atomic])
}

private func exportSymbolicPlannerProblem(
    root: URL,
    workspaceStore: XcircuiteWorkspaceStore,
    artifactStore: XcircuitePlanningArtifactStore
) async throws -> XcircuiteSymbolicPlannerPDDLExportResult {
    return try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
}

}
