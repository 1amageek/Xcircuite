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
@Test func qualifySymbolicPlannerSolverRejectsInvalidStandaloneArtifactIDReference() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-invalid-artifact-id")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    let solverURL = root.appending(path: "invalid-artifact-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: "run-pddl",
                toolID: "mock-invalid-artifact-id-planner",
                executablePath: solverURL.path(percentEncoded: false),
                domainArtifactID: "../domain"
            ),
            projectRoot: root
        )
        Issue.record("Expected invalid solver qualification reference.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .invalidSolverQualificationReference(
            field: "domainArtifactID",
            value: "../domain"
        ))
    }
}

@Test func qualifySymbolicPlannerSolverCLIProducesPassingToolHealth() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-qualification")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "qualified-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-qualified-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.toolHealth.status == .passed)
    #expect(result.observedActionIDs == ["fix-m1-width"])
    #expect(result.goalCoverageStatus == "covered")
    #expect(result.missingGoalAtoms == [])
    #expect(result.qualificationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID)
    let evidence = try #require(result.toolHealth.evidence.first)
    #expect(evidence.kind == .corpus)
    #expect(evidence.qualification?.qualified == true)
    #expect(evidence.artifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID)

    let manifest = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let manifestQualificationArtifact = try #require(manifest.artifacts.first {
        $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID
    })
    #expect(manifestQualificationArtifact.sha256 != nil)
    #expect(manifestQualificationArtifact.byteCount != nil)

    let persisted = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-qualification.json")
    )
    #expect(persisted.qualificationArtifact == nil)
    #expect(persisted.toolHealth.evidence.first?.artifact == nil)
}

@Test func qualifySymbolicPlannerSolverEnforcesOptimalityAndCostPolicy() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-optimality-policy")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "optimal-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "Optimal solution found\\n0.000: (a-fix-m1-width) [1.000]\\nplan length: 1\\ncost = 1 (unit cost)\\n"
    )

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-optimal-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
            "--require-optimality",
            "--max-solver-cost",
            "1",
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.requireOptimality == true)
    #expect(result.maximumSolverCost == 1)
    #expect(result.solverMetadata?.optimalityStatus == "optimal")
    #expect(result.solverMetadata?.planCost == 1)
    #expect(result.solverMetadata?.planCostUnit == "unit cost")
    #expect(result.solverMetadata?.planLength == 1)
    #expect(result.planCostEvaluation?.strategy == "pddl-action-cost")
    #expect(result.planCostEvaluation?.planLength == 1)
    #expect(result.planCostEvaluation?.evaluatedCost == 1)
    #expect(result.planReplayValidation?.status == "validated")
    #expect(result.planReplayValidation?.evaluatedCost == 1)
    #expect(result.planReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
    let evidence = try #require(result.toolHealth.evidence.first?.qualification)
    #expect(evidence.observedMetrics["solverClaimPlanCost"] == 1)
    #expect(evidence.observedMetrics["evaluatedPlanCost"] == 1)
    #expect(evidence.observedMetrics["replayEvaluatedPlanCost"] == 1)
    #expect(evidence.observedMetrics["maximumSolverCost"] == 1)
    #expect(evidence.observedCounts["solverPlanLength"] == 1)
    #expect(evidence.observedCounts["evaluatedPlanLength"] == 1)
    #expect(evidence.observedCounts["planReplayStepCount"] == 1)
    #expect(evidence.observedCounts["planReplayErrorCount"] == 0)
    #expect(evidence.observedCounts["planReplayMissingPreconditionAtomCount"] == 0)
    #expect(evidence.observedCounts["planReplayMissingGoalAtomCount"] == 0)
    #expect(evidence.observedCounts["solverOptimalityClaimCount"] == 1)
    #expect(evidence.observedCounts["solverCostClaimCount"] == 1)
    #expect(evidence.failureCodes == [])

    let persisted = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-qualification.json")
    )
    #expect(persisted.solverMetadata?.optimalityStatus == "optimal")
    #expect(persisted.solverMetadata?.planCost == 1)
    #expect(persisted.planCostEvaluation?.evaluatedCost == 1)
    #expect(persisted.planReplayValidation?.status == "validated")

    let persistedReplay = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerPlanReplayValidation.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/plan-replay-validation.json")
    )
    #expect(persistedReplay.status == "validated")
    #expect(persistedReplay.steps.map(\.actionID) == ["fix-m1-width"])
}

@Test func qualifySymbolicPlannerSolverParsesNativeCertificateClaims() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-native-certificate")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "native-certificate-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "0.000: (a-fix-m1-width) [1.000]\\n"
    )
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    try XcircuiteWorkspaceStore().writeJSON(
        XcircuiteSymbolicPlannerSolverCertificate(
            certificateID: "certificate-1",
            solverName: "mock-native-certificate-planner",
            certificateFormat: "generic-json",
            status: "parsed",
            optimalityStatus: "optimal",
            proofStatus: "validated",
            planCost: 1,
            planCostUnit: "unit cost",
            planLength: 1,
            lowerBound: 1,
            upperBound: 1,
            goalCoverageStatus: "covered",
            observedActionIDs: ["fix-m1-width"],
            evidenceLines: ["native certificate fixture"]
        ),
        to: root.appending(path: certificatePath),
        forProjectAt: root
    )

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "qualify-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--tool-id",
            "mock-native-certificate-planner",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--expected-action-id",
            "fix-m1-width",
            "--require-optimality",
            "--require-native-certificate",
            "--certificate-path",
            certificatePath,
            "--certificate-format",
            "generic-json",
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: data
    )

    #expect(result.status == "qualified")
    #expect(result.requireNativeCertificate == true)
    #expect(result.nativeCertificate?.status == "parsed")
    #expect(result.nativeCertificate?.detectedFormat == "generic-json")
    #expect(result.nativeCertificate?.certificate?.optimalityStatus == "optimal")
    #expect(result.nativeCertificate?.certificate?.proofStatus == "validated")
    #expect(result.nativeCertificate?.certificate?.planCost == 1)
    #expect(result.nativeCertificateArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverCertificateArtifactID)
    let evidence = try #require(result.toolHealth.evidence.first?.qualification)
    #expect(evidence.observedMetrics["nativeCertificatePlanCost"] == 1)
    #expect(evidence.observedMetrics["nativeCertificateLowerBound"] == 1)
    #expect(evidence.observedMetrics["nativeCertificateUpperBound"] == 1)
    #expect(evidence.observedCounts["nativeCertificateParseCount"] == 1)
    #expect(evidence.observedCounts["nativeCertificateClaimCount"] == 7)
    #expect(evidence.observedCounts["nativeCertificateOptimalityClaimCount"] == 1)
    #expect(evidence.observedCounts["nativeCertificateProofValidatedCount"] == 1)
    #expect(evidence.failureCodes == [])

    let persistedCertificate = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-certificate.json")
    )
    #expect(persistedCertificate.sourceArtifact.path == certificatePath)
    #expect(persistedCertificate.certificate?.claims.contains { $0.kind == "optimality" } == true)

    let comparisonJSON = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "compare-symbolic-planner-solver-family",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--comparison-id",
            "native-certificate-comparison",
            "--qualification-artifact-id",
            XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID,
            "--pretty",
        ]
    )
    let comparisonData = try #require(comparisonJSON.data(using: .utf8))
    let comparison = try JSONDecoder().decode(
        XcircuiteSymbolicPlannerSolverFamilyComparisonResult.self,
        from: comparisonData
    )
    let selected = try #require(comparison.comparison.candidates.first)
    #expect(selected.nativeCertificateArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverCertificateArtifactID)
    #expect(selected.optimalityStatus == "optimal")
    #expect(selected.scoreComponents.contains {
        $0.termID == "native-certificate" && $0.contribution > 0
    })
}

@Test func qualifySymbolicPlannerSolverFailsWhenNativeCertificateCostDiffers() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-native-certificate-cost-fail")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "native-certificate-cost-fail-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "0.000: (a-fix-m1-width) [1.000]\\n"
    )
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    try XcircuiteWorkspaceStore().writeJSON(
        XcircuiteSymbolicPlannerSolverCertificate(
            certificateID: "certificate-cost-fail",
            solverName: "mock-native-certificate-planner",
            certificateFormat: "generic-json",
            status: "parsed",
            optimalityStatus: "optimal",
            proofStatus: "validated",
            planCost: 2,
            planLength: 1,
            lowerBound: 2,
            upperBound: 2,
            goalCoverageStatus: "covered",
            observedActionIDs: ["fix-m1-width"]
        ),
        to: root.appending(path: certificatePath),
        forProjectAt: root
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
            runID: "run-pddl",
            toolID: "mock-native-certificate-cost-fail-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            requireNativeCertificate: true,
            certificatePath: certificatePath,
            certificateFormat: "generic-json"
        ),
        projectRoot: root
    )

    #expect(result.status == "failed")
    #expect(result.nativeCertificate?.status == "parsed")
    #expect(result.nativeCertificateArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverCertificateArtifactID)
    #expect(result.diagnostics.contains { $0.code == "native-certificate-cost-mismatch" })
    #expect(result.toolHealth.evidence.first?.qualification?.failureCodes.contains("native-certificate-cost-mismatch") == true)
}

@Test func qualifySymbolicPlannerSolverUsesStdoutAsNativeCertificateWhenPathIsMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-stdout-certificate")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "stdout-certificate-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: """
        Fast Downward 24.06
        Solution found.
        Search status: solved optimally
        Plan length: 1 step(s).
        Plan cost: 1
        Best solution cost so far: 1
        0.000: (a-fix-m1-width) [1.000]

        """
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
            runID: "run-pddl",
            toolID: "fast-downward-stdout-fixture",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireOptimality: true,
            requireNativeCertificate: true,
            certificateFormat: "fast-downward-text"
        ),
        projectRoot: root
    )

    #expect(result.status == "qualified")
    #expect(result.nativeCertificate?.sourceArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverStdoutArtifactID)
    #expect(result.nativeCertificate?.certificate?.solverFamily == "fast-downward")
    #expect(result.nativeCertificate?.certificate?.optimalityStatus == "optimal")
    #expect(result.nativeCertificate?.certificate?.planCost == 1)
    #expect(result.nativeCertificate?.certificate?.planLength == 1)
}

@Test func qualifySymbolicPlannerSolverRejectsAmbiguousCanonicalManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-duplicate-certificate-artifact")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "duplicate-certificate-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let store = XcircuiteWorkspaceStore()
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    try store.writeJSON(
        XcircuiteSymbolicPlannerSolverCertificate(
            certificateID: "duplicate-certificate",
            solverName: "mock-duplicate-certificate-planner",
            certificateFormat: "generic-json",
            status: "parsed",
            optimalityStatus: "optimal",
            proofStatus: "validated",
            planCost: 1,
            planLength: 1,
            lowerBound: 1,
            upperBound: 1,
            goalCoverageStatus: "covered",
            observedActionIDs: ["fix-m1-width"]
        ),
        to: root.appending(path: certificatePath),
        forProjectAt: root
    )
    let certificateReference = try store.fileReference(
        forProjectRelativePath: certificatePath,
        artifactID: "custom-native-certificate",
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-pddl"
    )
    let manifestURL = root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    try XcircuiteRunManifestTamper.append(
        [certificateReference, certificateReference],
        to: manifestURL
    )

    await #expect(throws: XcircuiteWorkspaceError.decodeFailed(
        "manifest.json: Invalid run manifest for run-pddl: artifact path '.xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json' must be unique."
    )) {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: "run-pddl",
                toolID: "mock-duplicate-certificate-planner",
                executablePath: solverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"],
                requireNativeCertificate: true,
                certificateArtifactID: "custom-native-certificate",
                certificateFormat: "generic-json"
            ),
            projectRoot: root
        )
    }
}

@Test func qualifySymbolicPlannerSolverRejectsTamperedPDDLExportArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-tampered-pddl-export")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    try "tampered".write(
        to: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/pddl-export.json"),
        atomically: true,
        encoding: .utf8
    )
    let solverURL = root.appending(path: "tampered-pddl-export-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: "run-pddl",
                toolID: "mock-tampered-pddl-export-planner",
                executablePath: solverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"]
            ),
            projectRoot: root
        )
        Issue.record("Expected artifactIntegrityFailed.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .artifactIntegrityFailed(let field, let artifactID, _, let status, _) = error else {
            Issue.record("Expected artifactIntegrityFailed, got \(error).")
            return
        }
        #expect(field == "solverInputArtifact")
        #expect(artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLExportArtifactID)
        #expect(status == .byteCountMismatch || status == .sha256Mismatch)
    }
}

@Test func qualifySymbolicPlannerSolverRejectsTamperedProofArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-tampered-proof")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "tampered-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let store = XcircuiteWorkspaceStore()
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try store.writeText("valid-proof\n", to: root.appending(path: proofPath))
    let proofReference = try store.fileReference(
        forProjectRelativePath: proofPath,
        artifactID: XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID,
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-pddl"
    )
    try store.upsertRunArtifact(proofReference, runID: "run-pddl", inProjectAt: root)
    try "tampered-proof\n".write(
        to: root.appending(path: proofPath),
        atomically: true,
        encoding: .utf8
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: "run-pddl",
                toolID: "mock-tampered-proof-planner",
                executablePath: solverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"],
                requireProofValidation: true,
                proofCheckerExecutablePath: checkerURL.path(percentEncoded: false)
            ),
            projectRoot: root
        )
        Issue.record("Expected artifactIntegrityFailed.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .artifactIntegrityFailed(let field, let artifactID, _, let status, _) = error else {
            Issue.record("Expected artifactIntegrityFailed, got \(error).")
            return
        }
        #expect(field == "proofArtifact")
        #expect(artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID)
        #expect(status == .byteCountMismatch || status == .sha256Mismatch)
    }
}

@Test func qualifySymbolicPlannerSolverRegistersExplicitProofPathInRunManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-proof-path-registration")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "registered-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "registered-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let store = XcircuiteWorkspaceStore()
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try store.writeText("valid-proof\n", to: root.appending(path: proofPath))

    let result = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
        request: XcircuiteSymbolicPlannerSolverQualificationRequest(
            runID: "run-pddl",
            toolID: "mock-registered-proof-planner",
            executablePath: solverURL.path(percentEncoded: false),
            expectedActionIDs: ["fix-m1-width"],
            requireProofValidation: true,
            proofPath: proofPath,
            proofCheckerExecutablePath: checkerURL.path(percentEncoded: false)
        ),
        projectRoot: root
    )

    let manifest = try store.readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let proofArtifact = try #require(manifest.artifacts.first {
        $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID
    })
    let foundationProofArtifact = try foundationReference(proofArtifact, role: .output)
    #expect(proofArtifact.path == proofPath)
    #expect(result.proofValidation?.proofArtifact == foundationProofArtifact)
    let persistedValidation = try store.readJSON(
        XcircuiteSymbolicPlannerProofValidation.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/proof-validation.json")
    )
    #expect(persistedValidation.proofArtifact == foundationProofArtifact)
}

@Test func qualifySymbolicPlannerSolverRejectsExplicitProofPathThatConflictsWithRunManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-conflicting-proof-path")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "conflicting-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "conflicting-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let store = XcircuiteWorkspaceStore()
    let manifestProofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    let explicitProofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof-copy.txt"
    try store.writeText("valid-proof\n", to: root.appending(path: manifestProofPath))
    try store.writeText("valid-proof\n", to: root.appending(path: explicitProofPath))
    let manifestProofReference = try store.fileReference(
        forProjectRelativePath: manifestProofPath,
        artifactID: XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID,
        kind: .other,
        format: .text,
        inProjectAt: root,
        producedByRunID: "run-pddl"
    )
    try store.upsertRunArtifact(manifestProofReference, runID: "run-pddl", inProjectAt: root)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier().qualify(
            request: XcircuiteSymbolicPlannerSolverQualificationRequest(
                runID: "run-pddl",
                toolID: "mock-conflicting-proof-planner",
                executablePath: solverURL.path(percentEncoded: false),
                expectedActionIDs: ["fix-m1-width"],
                requireProofValidation: true,
                proofPath: explicitProofPath,
                proofCheckerExecutablePath: checkerURL.path(percentEncoded: false)
            ),
            projectRoot: root
        )
        Issue.record("Expected artifactReferenceMismatch.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        #expect(error == .artifactReferenceMismatch(
            field: "proofArtifact",
            artifactID: XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID,
            path: explicitProofPath,
            manifestPath: manifestProofPath
        ))
    }
}

@Test func solverCertificateParserRecognizesPlannerFamilyTextFixtures() throws {
    let parser = XcircuiteSymbolicPlannerSolverCertificateParser()

    let fastDownward = parser.parse(
        text: """
        Fast Downward 24.06
        Solution found.
        Search status: solved optimally
        Plan length: 1 step(s).
        Plan cost: 1
        Best solution cost so far: 1
        Actual search time: 0.01s
        """,
        requestedFormat: "auto"
    )
    #expect(fastDownward.status == "parsed")
    #expect(fastDownward.detectedFormat == "fast-downward-text")
    #expect(fastDownward.certificate?.solverFamily == "fast-downward")
    #expect(fastDownward.certificate?.planCost == 1)
    #expect(fastDownward.certificate?.planLength == 1)
    #expect(fastDownward.certificate?.lowerBound == 1)
    #expect(fastDownward.certificate?.upperBound == 1)
    #expect(fastDownward.certificate?.optimalityStatus == "optimal")
    #expect(fastDownward.certificate?.goalCoverageStatus == "covered")
    #expect(fastDownward.certificate?.claims.contains { $0.kind == "solver-family" && $0.value == "fast-downward" } == true)

    let metricFF = parser.parse(
        text: """
        Metric-FF v2.1
        ff: found legal plan as follows
        step    0: A-FIX-M1-WIDTH
        plan length: 1
        plan cost: 1
        """,
        requestedFormat: "metric-ff-text"
    )
    #expect(metricFF.status == "parsed")
    #expect(metricFF.detectedFormat == "metric-ff-text")
    #expect(metricFF.certificate?.solverFamily == "metric-ff")
    #expect(metricFF.certificate?.planCost == 1)
    #expect(metricFF.certificate?.planLength == 1)
    #expect(metricFF.certificate?.optimalityStatus == nil)
    #expect(metricFF.certificate?.goalCoverageStatus == "covered")

    let optic = parser.parse(
        text: """
        OPTIC temporal planner
        ;;;; Solution Found
        ;;;; Cost: 1.000
        ;;;; Makespan: 1.000
        Plan valid
        """,
        requestedFormat: "optic-text"
    )
    #expect(optic.status == "parsed")
    #expect(optic.detectedFormat == "optic-text")
    #expect(optic.certificate?.solverFamily == "optic")
    #expect(optic.certificate?.planCost == 1)
    #expect(optic.certificate?.makespan == 1)
    #expect(optic.certificate?.proofStatus == "validated")

    let madagascar = parser.parse(
        text: """
        Madagascar planner
        PLAN FOUND
        optimal plan found
        plan length: 1
        plan cost: 1
        """,
        requestedFormat: "madagascar-text"
    )
    #expect(madagascar.status == "parsed")
    #expect(madagascar.detectedFormat == "madagascar-text")
    #expect(madagascar.certificate?.solverFamily == "madagascar")
    #expect(madagascar.certificate?.optimalityStatus == "optimal")
    #expect(madagascar.certificate?.lowerBound == 1)
    #expect(madagascar.certificate?.upperBound == 1)
}

}
