import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

extension XcircuiteSymbolicPlannerSolverRunnerTests {
@Test func qualifySymbolicPlannerSolverRejectsInvalidStandaloneArtifactIDReference() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-invalid-artifact-id")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    let solverURL = root.appending(path: "invalid-artifact-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\n")

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).qualify(
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
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
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
    #expect(evidence.hasVerifiableArtifactBinding)
    #expect(evidence.artifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID)

    let manifest = try await workspaceStore.loadRunLedger(runID: "run-pddl").runManifest
    let manifestQualificationArtifact = try #require(manifest.artifacts.first {
        $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverQualificationArtifactID
    })
    #expect(manifestQualificationArtifact.sha256.utf8.count == 64)
    #expect(manifestQualificationArtifact.byteCount > 0)

    let persisted = try await workspaceStore.readJSON(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-qualification.json"
    )
    #expect(persisted.qualificationArtifact == nil)
    #expect(persisted.toolHealth.evidence.first?.artifact == nil)
}

@Test func qualifySymbolicPlannerSolverEnforcesOptimalityAndCostPolicy() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-optimality-policy")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
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
    let evidence = try #require(result.toolHealth.evidence.first)
    #expect(evidence.hasVerifiableArtifactBinding)
    #expect(result.planReplayValidation?.steps.count == 1)
    #expect(result.planReplayValidation?.diagnostics.isEmpty == true)
    #expect(result.diagnostics.isEmpty)

    let persisted = try await workspaceStore.readJSON(
        XcircuiteSymbolicPlannerSolverQualificationResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-qualification.json"
    )
    #expect(persisted.solverMetadata?.optimalityStatus == "optimal")
    #expect(persisted.solverMetadata?.planCost == 1)
    #expect(persisted.planCostEvaluation?.evaluatedCost == 1)
    #expect(persisted.planReplayValidation?.status == "validated")

    let persistedReplay = try await workspaceStore.readJSON(
        XcircuiteSymbolicPlannerPlanReplayValidation.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/plan-replay-validation.json"
    )
    #expect(persistedReplay.status == "validated")
    #expect(persistedReplay.steps.map(\.actionID) == ["fix-m1-width"])
}

@Test func qualifySymbolicPlannerSolverParsesNativeCertificateClaims() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-native-certificate")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "native-certificate-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "0.000: (a-fix-m1-width) [1.000]\\n"
    )
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    try await workspaceStore.writeJSON(
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
        to: certificatePath
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
    let evidence = try #require(result.toolHealth.evidence.first)
    #expect(evidence.hasVerifiableArtifactBinding)
    #expect(result.nativeCertificate?.certificate?.claims.count == 7)
    #expect(result.diagnostics.isEmpty)

    let persistedCertificate = try await workspaceStore.readJSON(
        XcircuiteSymbolicPlannerSolverCertificateParseResult.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-certificate.json"
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
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "native-certificate-cost-fail-symbolic-planner.sh")
    try writeMockPlanner(
        to: solverURL,
        planText: "0.000: (a-fix-m1-width) [1.000]\\n"
    )
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    try await workspaceStore.writeJSON(
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
        to: certificatePath
    )

    let result = try await XcircuiteSymbolicPlannerSolverQualifier(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).qualify(
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
    #expect(result.toolHealth.status == .failed)
}

@Test func qualifySymbolicPlannerSolverUsesStdoutAsNativeCertificateWhenPathIsMissing() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-stdout-certificate")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
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

    let result = try await XcircuiteSymbolicPlannerSolverQualifier(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).qualify(
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
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "duplicate-certificate-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let certificatePath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/native-certificate.json"
    let certificate = XcircuiteSymbolicPlannerSolverCertificate(
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
    )
    let certificateData = try JSONEncoder().encode(certificate)
    try await workspaceStore.writeJSON(certificate, to: certificatePath)
    let certificateReference = ArtifactReference(
        id: try ArtifactID(rawValue: "custom-native-certificate"),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: certificatePath),
            role: .input,
            kind: .other,
            format: .json
        ),
        digest: try SHA256ContentDigester().digest(data: certificateData),
        byteCount: UInt64(certificateData.count)
    )
    let ledgerURL = root.appending(path: ".xcircuite/runs/run-pddl/ledger.json")
    try XcircuiteRunLedgerTamper.append(
        [certificateReference, certificateReference],
        to: ledgerURL
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).qualify(
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
        Issue.record("Expected an invalid run ledger error.")
    } catch let error as FlowRunLedgerPersistenceError {
        guard case .storageFailed(let reason) = error else {
            Issue.record("Expected storageFailed, got \(error).")
            return
        }
        #expect(reason.contains("must be unique"))
    }
}

@Test func qualifySymbolicPlannerSolverRejectsTamperedPDDLExportArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-tampered-pddl-export")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
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
        _ = try await XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).qualify(
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
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "tampered-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    _ = try await workspaceStore.persistArtifact(
        content: Data("valid-proof\n".utf8),
        id: try ArtifactID(
            rawValue: XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID
        ),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: proofPath),
            role: .output,
            kind: .other,
            format: .text
        ),
        runID: "run-pddl",
        mode: .replaceable
    )
    try "tampered-proof\n".write(
        to: root.appending(path: proofPath),
        atomically: true,
        encoding: .utf8
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).qualify(
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
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "registered-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "registered-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let proofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    try await workspaceStore.writeWorkspaceText("valid-proof\n", to: proofPath)

    let result = try await XcircuiteSymbolicPlannerSolverQualifier(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).qualify(
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

    let manifest = try await workspaceStore.loadRunLedger(runID: "run-pddl").runManifest
    let proofArtifact = try #require(manifest.artifacts.first {
        $0.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID
    })
    #expect(proofArtifact.path == proofPath)
    #expect(result.proofValidation?.proofArtifact == proofArtifact)
    let persistedValidation = try await workspaceStore.readJSON(
        XcircuiteSymbolicPlannerProofValidation.self,
        from: ".xcircuite/runs/run-pddl/planning/symbolic-planner/proof-validation.json"
    )
    #expect(persistedValidation.proofArtifact == proofArtifact)
}

@Test func qualifySymbolicPlannerSolverRejectsExplicitProofPathThatConflictsWithRunManifest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-conflicting-proof-path")
    defer { removeTemporaryRoot(root) }
    let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
    let artifactStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
    try await prepareRun(
        root: root,
        runID: "run-pddl",
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    )
    _ = try await XcircuiteSymbolicPlannerPDDLExporter(
        workspaceStore: workspaceStore,
        artifactStore: artifactStore
    ).exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "conflicting-proof-symbolic-planner.sh")
    try writeMockPlanner(to: solverURL, planText: "0.000: (a-fix-m1-width) [1.000]\\n")
    let checkerURL = root.appending(path: "conflicting-proof-checker.sh")
    try writeMockProofChecker(to: checkerURL, expectedText: "valid-proof", success: true)
    let manifestProofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof.txt"
    let explicitProofPath = ".xcircuite/runs/run-pddl/planning/symbolic-planner/solver-proof-copy.txt"
    _ = try await workspaceStore.persistArtifact(
        content: Data("valid-proof\n".utf8),
        id: try ArtifactID(
            rawValue: XcircuitePlanningArtifactStore.symbolicPlannerSolverProofArtifactID
        ),
        locator: ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: manifestProofPath),
            role: .output,
            kind: .other,
            format: .text
        ),
        runID: "run-pddl",
        mode: .replaceable
    )
    try await workspaceStore.writeWorkspaceText("valid-proof\n", to: explicitProofPath)

    do {
        _ = try await XcircuiteSymbolicPlannerSolverQualifier(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).qualify(
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

@Test func solverCertificateParserRecognizesPlannerFamilyTextFixtures() async throws {
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
