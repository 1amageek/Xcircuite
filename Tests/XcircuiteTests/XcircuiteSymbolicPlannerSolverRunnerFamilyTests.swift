import Foundation
import DesignFlowKernel
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

extension XcircuiteSymbolicPlannerSolverRunnerTests {
@Test func runSymbolicPlannerSolverFamilyBatchPersistsPlannerFamilyCertificateFixtures() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-certificate-fixtures")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let store = XcircuitePackageStore()
    let fastDownwardSolverURL = root.appending(path: "fast-downward-family-symbolic-planner.sh")
    try writeMockPlanner(to: fastDownwardSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")
    let metricFFSolverURL = root.appending(path: "metric-ff-family-symbolic-planner.sh")
    try writeMockPlanner(to: metricFFSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")

    let certificateDirectory = root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates")
    try FileManager.default.createDirectory(at: certificateDirectory, withIntermediateDirectories: true)
    let fastDownwardCertificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates/fast-downward.txt"
    try store.writeText(
        """
        Fast Downward 24.06
        Solution found.
        Search status: solved optimally
        Plan length: 1 step(s).
        Plan cost: 1
        Best solution cost so far: 1
        Actual search time: 0.01s
        """,
        to: root.appending(path: fastDownwardCertificatePath)
    )
    let metricFFCertificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/certificates/metric-ff.txt"
    try store.writeText(
        """
        Metric-FF v2.1
        ff: found legal plan as follows
        step    0: A-FIX-M1-WIDTH
        plan length: 1
        plan cost: 1
        """,
        to: root.appending(path: metricFFCertificatePath)
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
    try store.writeJSON(spec, to: specURL, forProjectAt: root)

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

    #expect(result.batchRun.status == "completed-with-qualified-selection")
    #expect(result.batchRun.qualifiedCandidateCount == 2)
    #expect(result.comparisonResult.comparison.selectedToolID == "fast-downward-fixture-planner")
    #expect(result.comparisonResult.comparison.candidates[0].nativeCertificateArtifact?.path.contains("/candidates/candidate-0-fast-downward/solver-certificate.json") == true)
    #expect(result.comparisonResult.comparison.candidates[1].nativeCertificateArtifact?.path.contains("/candidates/candidate-1-metric-ff/solver-certificate.json") == true)
    #expect(result.comparisonResult.comparison.candidates[0].scoreComponents.contains {
        $0.termID == "optimality" && $0.contribution > 0
    })
    #expect(result.comparisonResult.comparison.candidates[0].selectionScore > result.comparisonResult.comparison.candidates[1].selectionScore)

    let fastDownwardSnapshot = try store.readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-certificate-fixtures/candidates/candidate-0-fast-downward/solver-certificate.json")
    )
    #expect(fastDownwardSnapshot.certificate?.solverFamily == "fast-downward")
    #expect(fastDownwardSnapshot.certificate?.optimalityStatus == "optimal")
    #expect(fastDownwardSnapshot.certificate?.lowerBound == 1)
    #expect(fastDownwardSnapshot.certificate?.upperBound == 1)

    let metricFFSnapshot = try store.readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-certificate-fixtures/candidates/candidate-1-metric-ff/solver-certificate.json")
    )
    #expect(metricFFSnapshot.certificate?.solverFamily == "metric-ff")
    #expect(metricFFSnapshot.certificate?.optimalityStatus == nil)
    #expect(metricFFSnapshot.certificate?.goalCoverageStatus == "covered")
}

@Test func discoverInstalledSymbolicPlannerSolversCLIWritesLaneArtifactAndBatchSpec() async throws {
    let root = try makeTemporaryRoot("installed-symbolic-planner-lane")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
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

    let persistedLane = try XcircuitePackageStore().readJSON(
        XcircuiteSymbolicPlannerInstalledSolverLane.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/installed-solver-lane.json")
    )
    #expect(persistedLane.batchRequest?.candidates.count == 1)

    let writtenBatchSpec = try XcircuitePackageStore().readJSON(
        XcircuiteSymbolicPlannerSolverFamilyBatchRequest.self,
        from: batchSpecURL
    )
    #expect(writtenBatchSpec.comparisonID == "installed-fixture-lane")
    #expect(writtenBatchSpec.candidates.map(\.toolID) == ["fast-downward"])
}

@Test func discoverInstalledSymbolicPlannerSolversPrefersLaterExecutableOverEarlierNonExecutableFile() async throws {
    let root = try makeTemporaryRoot("installed-symbolic-planner-lane-path-priority")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
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

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner().run(
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

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner().run(
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

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyBatchRunner().run(
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

@Test func compareAndPromoteSymbolicPlannerSolverFamilyCLISelectsQualifiedCertificate() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-comparison")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let store = XcircuitePackageStore()
    let solverURL = root.appending(path: "family-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let failedSolverURL = root.appending(path: "failed-family-symbolic-planner.sh")
    try writeMockPlanner(to: failedSolverURL, planText: "0.000: (a-unmapped-action) [1.000]\\n")

    let qualifiedJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-qualified-family-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
        ]
    )
    let qualifiedData = try #require(qualifiedJSON.data(using: .utf8))
    var qualified = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: qualifiedData
    )
    qualified.qualificationArtifact = nil
    let qualifiedSolverPlanPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/qualified-solver-plan.txt"
    try FileManager.default.createDirectory(
        at: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs"),
        withIntermediateDirectories: true
    )
    try store.writeText("0.000: (a-fix-m1-width) [1.000]\n", to: root.appending(path: qualifiedSolverPlanPath))
    let qualifiedSolverPlanRef = try store.fileReference(
        forProjectRelativePath: qualifiedSolverPlanPath,
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-pddl"
    )
    qualified.solverResult.solverPlanArtifact = qualifiedSolverPlanRef
    if var importResult = qualified.solverResult.importResult {
        importResult.solverPlanArtifact = qualifiedSolverPlanRef
        qualified.solverResult.importResult = importResult
    }

    let failedJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
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
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: failedData
    )
    failed.qualificationArtifact = nil

    let inputDirectory = root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs")
    try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    let qualifiedPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/qualified.json"
    let failedPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family-inputs/failed.json"
    try store.writeJSON(qualified, to: root.appending(path: qualifiedPath), forProjectAt: root)
    try store.writeJSON(failed, to: root.appending(path: failedPath), forProjectAt: root)

    let comparisonJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "compare-symbolic-planner-solver-family",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--comparison-id",
            "solver-family-regression",
            "--qualification-path",
            qualifiedPath,
            "--qualification-path",
            failedPath,
            "--pretty",
        ]
    )
    let comparisonData = try #require(comparisonJSON.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyComparisonResult.self,
        from: comparisonData
    )

    #expect(result.comparison.status == "selected-qualified")
    #expect(result.comparison.selectedCandidateIndex == 0)
    #expect(result.comparison.selectedToolID == "mock-qualified-family-planner")
    #expect(result.comparison.candidateCount == 2)
    #expect(result.comparison.qualifiedCandidateCount == 1)
    #expect(result.comparison.failedCandidateCount == 1)
    #expect(result.comparison.candidates[0].selected == true)
    #expect(result.comparison.candidates[1].selected == false)
    #expect(result.comparison.candidates[0].toolHealthStatus == ToolHealthStatus.passed.rawValue)
    #expect(result.comparison.candidates[1].toolHealthStatus == ToolHealthStatus.failed.rawValue)
    #expect(result.comparison.candidates[1].missingExpectedActionIDs == ["missing-action"])
    #expect(result.comparison.candidates[0].selectionScore > result.comparison.candidates[1].selectionScore)
    #expect(result.comparisonArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyComparisonArtifactID)-solver-family-regression")

    let persisted = try store.readJSON(
        XcircuiteSymbolicPlannerSolverFamilyComparison.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-regression/solver-family-comparison.json")
    )
    #expect(persisted.selectedToolID == "mock-qualified-family-planner")
    let manifest = try store.readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
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
    #expect(promotionResult.promotion.selectedToolID == "mock-qualified-family-planner")
    #expect(promotionResult.promotion.promotedCandidatePlanArtifact.artifactID == XcircuitePlanningArtifactStore.candidatePlanArtifactID)
    #expect(promotionResult.promotion.promotedSolverPlanArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID)
    #expect(promotionResult.promotion.promotedPlanReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
    #expect(promotionResult.promotion.promotedPlanVerificationArtifact?.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID)
    #expect(promotionResult.promotion.verificationAccepted == false)
    #expect(promotionResult.promotion.diagnostics.map(\.code) == ["promoted-plan-verification-not-accepted"])
    #expect(promotionResult.promotionArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyPromotionArtifactID)-solver-family-regression")

    let promotedPlan = try store.readJSON(
        XcircuiteCandidatePlan.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/candidate-plan.json")
    )
    #expect(promotedPlan.steps.map(\.actionID) == ["fix-m1-width"])
    let promotedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(promotedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")
    let promotedManifest = try store.readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    #expect(promotedManifest.artifacts.contains {
        $0.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyPromotionArtifactID)-solver-family-regression"
    })
}

@Test func runSymbolicPlannerSolverFamilyBatchCLIQualifiesComparesAndPromotes() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-batch")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let store = XcircuitePackageStore()
    let qualifiedSolverURL = root.appending(path: "batch-qualified-symbolic-planner.sh")
    try writeMockPlanner(to: qualifiedSolverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")
    let failedSolverURL = root.appending(path: "batch-failed-symbolic-planner.sh")
    try writeMockPlanner(to: failedSolverURL, planText: "0.000: (a-unmapped-action) [1.000]\n")
    let spec = XcircuiteSymbolicPlannerSolverFamilyBatchRequest(
        runID: "run-pddl",
        comparisonID: "solver-family-batch-regression",
        candidates: [
            XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest(
                candidateID: "qualified",
                toolID: "mock-qualified-batch-planner",
                executablePath: qualifiedSolverURL.path(percentEncoded: false),
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
    try store.writeJSON(spec, to: specURL, forProjectAt: root)

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
    #expect(result.batchRun.qualifiedCandidateCount == 1)
    #expect(result.batchRun.failedCandidateCount == 1)
    #expect(result.comparisonResult.comparison.status == "selected-qualified")
    #expect(result.comparisonResult.comparison.selectedToolID == "mock-qualified-batch-planner")
    #expect(result.promotionResult?.promotion.selectedToolID == "mock-qualified-batch-planner")
    #expect(result.batchArtifact.artifactID == "\(XcircuitePlanningArtifactStore.symbolicPlannerSolverFamilyBatchArtifactID)-solver-family-batch-regression")

    let qualifiedCandidate = result.batchRun.candidates[0]
    #expect(qualifiedCandidate.candidateID == "candidate-0-qualified")
    #expect(qualifiedCandidate.qualificationStatus == "qualified")
    #expect(qualifiedCandidate.qualificationArtifact.path.contains("/candidates/candidate-0-qualified/solver-qualification.json"))
    #expect(qualifiedCandidate.solverPlanArtifact?.path.contains("/candidates/candidate-0-qualified/solver-plan.txt") == true)
    let failedCandidate = result.batchRun.candidates[1]
    #expect(failedCandidate.candidateID == "candidate-1-failed")
    #expect(failedCandidate.qualificationStatus == "failed")

    let selectedQualification = result.comparisonResult.comparison.selectedQualificationArtifact
    #expect(selectedQualification?.path.contains("/candidates/candidate-0-qualified/solver-qualification.json") == true)
    let qualifiedSnapshot = try store.readJSON(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-batch-regression/candidates/candidate-0-qualified/solver-qualification.json")
    )
    #expect(qualifiedSnapshot.qualificationArtifact == nil)
    #expect(qualifiedSnapshot.toolHealth.evidence.first?.artifact == nil)
    #expect(qualifiedSnapshot.solverResult.solverPlanArtifact?.artifactID == qualifiedCandidate.solverPlanArtifact?.artifactID)
    let qualifiedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-family/solver-family-batch-regression/candidates/candidate-0-qualified/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(qualifiedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")

    let promotedPlan = try store.readJSON(
        XcircuiteCandidatePlan.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/candidate-plan.json")
    )
    #expect(promotedPlan.steps.map(\.actionID) == ["fix-m1-width"])
    let promotedSolverPlanText = try String(
        contentsOf: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-plan.txt"),
        encoding: .utf8
    )
    #expect(promotedSolverPlanText == "0.000: (a-fix-m1-width) [1.000]\n")

    let manifest = try store.readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let promotionArtifactID = try #require(result.promotionResult?.promotionArtifact.artifactID)
    let qualifiedSolverPlanArtifactID = try #require(qualifiedCandidate.solverPlanArtifact?.artifactID)
    #expect(manifest.artifacts.contains { $0.artifactID == result.batchArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == result.comparisonResult.comparisonArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == promotionArtifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == qualifiedCandidate.qualificationArtifact.artifactID })
    #expect(manifest.artifacts.contains { $0.artifactID == qualifiedSolverPlanArtifactID })
}

@Test func qualifySymbolicPlannerSolverValidatesProofArtifactWithExternalChecker() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-proof-validation")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "proof-qualified-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\n")
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try XcircuitePackageStore().writeText(
        "proof-ok\n",
        to: root.appending(path: proofPath)
    )
    let checkerURL = root.appending(path: "proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "proof-ok", success: true)

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-proof-qualified-planner",
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
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.requireProofValidation == true)
    #expect(result.proofValidation?.status == "validated")
    #expect(result.proofValidation?.proofArtifact.path == proofPath)
    #expect(result.proofValidation?.standardOutputArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID)
    #expect(result.proofValidation?.standardErrorArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStderrArtifactID)
    #expect(result.proofValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID)
    #expect(result.toolHealth.status == .passed)
    let evidence = try #require(result.toolHealth.evidence.first?.qualification)
    #expect(evidence.observedCounts["proofValidationAttemptCount"] == 1)
    #expect(evidence.observedCounts["proofValidationValidatedCount"] == 1)
    #expect(evidence.observedCounts["proofValidationErrorCount"] == 0)
    #expect(evidence.failureCodes == [])

    let persistedValidation = try XcircuitePackageStore().readJSON(
        XcircuiteSymbolicPlannerProofValidation.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/proof-validation.json")
    )
    #expect(persistedValidation.status == "validated")
    #expect(persistedValidation.standardOutputArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID)

    let manifest = try XcircuitePackageStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let artifactIDs = Set(manifest.artifacts.map(\.artifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStdoutArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerProofValidationStderrArtifactID))
}

@Test func qualifySymbolicPlannerSolverFailsWhenProofCheckerRejectsArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-proof-validation-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "proof-rejected-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try XcircuitePackageStore().writeText(
        "proof-bad\n",
        to: root.appending(path: proofPath)
    )
    let checkerURL = root.appending(path: "rejecting-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "proof-ok", success: false)

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
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
    #expect(result.toolHealth.status == .failed)
    #expect(result.proofValidation?.status == "failed")
    #expect(result.proofValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerProofValidationArtifactID)
    #expect(result.diagnostics.contains {
        $0.code == "proof-validation-proof-checker-non-zero-exit"
    })
    let evidence = try #require(result.toolHealth.evidence.first?.qualification)
    #expect(evidence.qualified == false)
    #expect(evidence.observedCounts["proofValidationAttemptCount"] == 1)
    #expect(evidence.observedCounts["proofValidationValidatedCount"] == 0)
    #expect(evidence.observedCounts["proofValidationErrorCount"] == 1)
    #expect(evidence.failureCodes.contains("proof-validation-proof-checker-non-zero-exit"))
}

@Test func qualifySymbolicPlannerSolverFailsWhenSolverCostClaimDoesNotMatchEvaluatedCost() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-cost-policy-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "expensive-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 4 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
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
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("solver-cost-claim-mismatch") == true)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["solverClaimPlanCost"] == 4)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["evaluatedPlanCost"] == 1)
}

@Test func qualifySymbolicPlannerSolverFailsWhenEvaluatedCostExceedsBound() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-evaluated-cost-policy-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "two-step-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\n1.000: (a-fix-m1-width) [1.000]\\nplan length: 2\\ncost = 2 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
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
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("solver-cost-exceeds-bound") == true)
    #expect(result.toolHealth.evidence.first?.qualification?.observedMetrics["evaluatedPlanCost"] == 2)
}

@Test func qualifySymbolicPlannerSolverFailsWhenReplayPreconditionsAreUnsatisfied() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-replay-policy-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl", includeViolationAtom: false)
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "invalid-replay-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 1 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
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
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("plan-replay-preconditions-unsatisfied") == true)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["planReplayErrorCount"] == 2)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["planReplayMissingPreconditionAtomCount"] == 1)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["planReplayMissingGoalAtomCount"] == 1)
    #expect(result.planReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
}

@Test func qualifySymbolicPlannerSolverFailsWhenOptimalityIsRequiredButMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-optimality-policy-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "satisficing-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Satisficing solution found\\n0.000: (a-fix-m1-width) [1.000]\\ncost = 1 (unit cost)\\n"
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
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
    #expect(result.diagnostics.contains { $0.code == "optimality-not-qualified" })
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("optimality-not-qualified") == true)
    #expect(result.toolHealth.evidence.first?.qualification?.observedCounts["solverOptimalityClaimCount"] == 0)
}

@Test func qualifySymbolicPlannerSolverFailsWhenExpectedActionIsMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-qualification-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "wrong-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
            runID: "run-pddl",
            toolID: "mock-failing-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-lvs-mismatch"]
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.toolHealth.status == .failed)
    #expect(result.observedActionIDs == ["fix-m1-width"])
    #expect(result.goalCoverageStatus == "covered")
    #expect(result.diagnostics.contains { $0.code == "expected-actions-missing" })
    #expect(result.toolHealth.evidence.first?.qualification?.qualified == false)
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("expected-actions-missing") == true)
    #expect(result.qualificationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID)
}

@Test func promoteSymbolicPlannerSolverFamilyRejectsMismatchedComparisonID() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-mismatched-comparison")
    defer { removeTemporaryRoot(root) }
    let fixture = try preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "actual-comparison"
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter().promote(
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

@Test func promoteSymbolicPlannerSolverFamilyRejectsDuplicateComparisonArtifactID() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-duplicate-comparison")
    defer { removeTemporaryRoot(root) }
    let fixture = try preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "duplicate-comparison"
    )
    let store = XcircuitePackageStore()
    let manifestURL = root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    var manifest = try store.readJSON(XcircuiteRunManifest.self, from: manifestURL)
    manifest.artifacts.append(fixture.comparisonArtifact)
    try store.writeJSON(manifest, to: manifestURL, forProjectAt: root)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter().promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: "run-pddl",
                comparisonID: "duplicate-comparison",
                verifyPromotedPlan: false
            ),
            projectRoot: root
        )
        Issue.record("Expected duplicateArtifactReference.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        let artifactID = try #require(fixture.comparisonArtifact.artifactID)
        #expect(error == .duplicateArtifactReference(
            runID: "run-pddl",
            artifactID: artifactID,
            count: 2
        ))
    }
}

@Test func compareSymbolicPlannerSolverFamilyRejectsDuplicateQualificationArtifactID() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-duplicate-qualification")
    defer { removeTemporaryRoot(root) }
    let fixture = try preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "duplicate-qualification"
    )
    let store = XcircuitePackageStore()
    let manifestURL = root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    var manifest = try store.readJSON(XcircuiteRunManifest.self, from: manifestURL)
    manifest.artifacts.append(fixture.qualificationArtifact)
    try store.writeJSON(manifest, to: manifestURL, forProjectAt: root)

    do {
        _ = try XcircuiteSymbolicPlannerSolverFamilyComparator().compare(
            request: XcircuiteSymbolicPlannerSolverFamilyComparisonRequest(
                runID: "run-pddl",
                comparisonID: "duplicate-qualification-comparison",
                qualificationArtifactIDs: [fixture.qualificationArtifact.artifactID].compactMap { $0 }
            ),
            projectRoot: root
        )
        Issue.record("Expected duplicateArtifactReference.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        let artifactID = try #require(fixture.qualificationArtifact.artifactID)
        #expect(error == .duplicateArtifactReference(
            runID: "run-pddl",
            artifactID: artifactID,
            count: 2
        ))
    }
}

@Test func promoteSymbolicPlannerSolverFamilyRejectsTamperedQualificationArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-family-promotion-tampered-qualification")
    defer { removeTemporaryRoot(root) }
    let fixture = try preparePromotionFixture(
        root: root,
        runID: "run-pddl",
        comparisonID: "tampered-qualification"
    )
    let tamperedQualificationURL = root.appending(path: fixture.qualificationArtifact.path)
    try "tampered".write(to: tamperedQualificationURL, atomically: true, encoding: .utf8)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverFamilyPromoter().promote(
            request: XcircuiteSymbolicPlannerSolverFamilyPromotionRequest(
                runID: "run-pddl",
                comparisonID: "tampered-qualification",
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
        #expect(field == "qualificationArtifact")
        #expect(artifactID == fixture.qualificationArtifact.artifactID)
        #expect(status == .byteCountMismatch || status == .sha256Mismatch)
    }
}

private func preparePromotionFixture(
    root: URL,
    runID: String,
    comparisonID: String
) throws -> PromotionFixture {
    try prepareRun(root: root, runID: runID)
    let store = XcircuitePackageStore()
    let artifactStore = XcircuitePlanningArtifactStore()
    let solverPlanPath = ".xcircuite/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)/fixture-solver-plan.txt"
    try FileManager.default.createDirectory(
        at: root.appending(path: ".xcircuite/runs/\(runID)/planning/symbolic-planner/solver-family/\(comparisonID)"),
        withIntermediateDirectories: true
    )
    try store.writeText("0.000: (a-fix-m1-width) [1.000]\n", to: root.appending(path: solverPlanPath))
    let solverPlanReference = try store.fileReference(
        forProjectRelativePath: solverPlanPath,
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: runID
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
    let qualification = XcircuiteSymbolicPlannerSolverQualificationResult(
        status: "qualified",
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
        toolHealth: ToolHealthCheckResult(toolID: "fixture-symbolic-planner", status: .passed),
        diagnostics: []
    )
    let qualificationArtifact = try artifactStore.persistSymbolicPlannerSolverFamilyQualification(
        qualification,
        runID: runID,
        comparisonID: comparisonID,
        candidateID: "candidate-a",
        projectRoot: root
    )
    let candidate = XcircuiteSymbolicPlannerSolverFamilyCandidateResult(
        candidateIndex: 0,
        status: "qualified",
        selected: true,
        selectionScore: 100,
        scoreComponents: [],
        toolID: "fixture-symbolic-planner",
        qualificationStatus: "qualified",
        toolHealthStatus: ToolHealthStatus.passed.rawValue,
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
        qualificationArtifact: qualificationArtifact,
        planVerificationArtifact: nil,
        diagnostics: []
    )
    let comparison = XcircuiteSymbolicPlannerSolverFamilyComparison(
        status: "selected-qualified",
        runID: runID,
        comparisonID: comparisonID,
        selectionPolicy: "qualified-first",
        requestedQualificationArtifactIDs: [qualificationArtifact.artifactID].compactMap { $0 },
        requestedQualificationPaths: [],
        selectedCandidateIndex: 0,
        selectedToolID: "fixture-symbolic-planner",
        selectedQualificationArtifact: qualificationArtifact,
        candidateCount: 1,
        qualifiedCandidateCount: 1,
        failedCandidateCount: 0,
        candidates: [candidate]
    )
    let comparisonArtifact = try artifactStore.persistSymbolicPlannerSolverFamilyComparison(
        comparison,
        runID: runID,
        projectRoot: root
    )
    return PromotionFixture(
        comparisonArtifact: comparisonArtifact,
        qualificationArtifact: qualificationArtifact
    )
}

private struct PromotionFixture {
    var comparisonArtifact: XcircuiteFileReference
    var qualificationArtifact: XcircuiteFileReference
}

}
