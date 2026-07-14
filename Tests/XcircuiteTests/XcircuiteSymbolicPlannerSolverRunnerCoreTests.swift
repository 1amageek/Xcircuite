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
@Test func planCostEvaluatorUsesWeightedPDDLActionCosts() throws {
    let candidatePlan = XcircuiteCandidatePlan(
        planID: "weighted-plan",
        problemID: "weighted-problem",
        runID: "weighted-run",
        strategy: "imported-symbolic-planner",
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
                actionID: "repair-with-approval",
                domainID: "drc-signoff",
                operationID: "drc.repair-width",
                maturity: "implemented",
                readiness: "ready",
                sourceObjectiveIDs: ["objective-1"],
                requiredInputRefs: ["layout-drc-input"],
                missingInputRefs: [],
                verificationGates: ["native-drc", "approval-gate"],
                reason: "Repair width after approval.",
                parameterHints: [:],
                blockers: []
            ),
            XcircuiteCandidatePlanStep(
                stepID: "step-2",
                order: 2,
                actionID: "repair-without-approval",
                domainID: "drc-signoff",
                operationID: "drc.repair-spacing",
                maturity: "implemented",
                readiness: "ready",
                sourceObjectiveIDs: ["objective-2"],
                requiredInputRefs: ["layout-drc-input"],
                missingInputRefs: [],
                verificationGates: ["native-drc"],
                reason: "Repair spacing directly.",
                parameterHints: [:],
                blockers: []
            ),
        ],
        verificationGates: [],
        constraints: [],
        unresolvedObjectives: [],
        blockers: []
    )
    let pddlExport = XcircuiteSymbolicPlannerPDDLExport(
        runID: "weighted-run",
        problemID: "weighted-problem",
        domainName: "domain-weighted-problem",
        problemName: "problem-weighted-problem",
        requirements: [":strips", ":action-costs"],
        domainPDDL: "",
        problemPDDL: "",
        atomMappings: [],
        actionMappings: [
            XcircuiteSymbolicPlannerPDDLActionMapping(
                actionID: "repair-with-approval",
                domainID: "drc-signoff",
                operationID: "drc.repair-width",
                pddlAction: "a-repair-with-approval",
                included: true,
                preconditionAtoms: [],
                effectAtoms: [],
                actionCost: 3,
                actionCostUnit: "planner action cost",
                actionCostSource: "planning-cost-model"
            ),
            XcircuiteSymbolicPlannerPDDLActionMapping(
                actionID: "repair-without-approval",
                domainID: "drc-signoff",
                operationID: "drc.repair-spacing",
                pddlAction: "a-repair-without-approval",
                included: true,
                preconditionAtoms: [],
                effectAtoms: [],
                actionCost: 1,
                actionCostUnit: "planner action cost",
                actionCostSource: "planning-cost-model"
            ),
        ]
    )

    let evaluation = XcircuiteSymbolicPlannerPlanCostEvaluator().evaluate(
        candidatePlan: candidatePlan,
        pddlExport: pddlExport
    )

    #expect(evaluation.strategy == "pddl-action-cost")
    #expect(evaluation.planLength == 2)
    #expect(evaluation.evaluatedCost == 4)
    #expect(evaluation.evaluatedCostUnit == "planner action cost")
    #expect(evaluation.stepCosts.map(\.cost) == [3.0, 1.0])
}

@Test func planReplayValidatorFailsWhenPreconditionsAndGoalsAreUnsatisfied() throws {
    let candidatePlan = XcircuiteCandidatePlan(
        planID: "invalid-replay-plan",
        problemID: "invalid-replay-problem",
        runID: "invalid-replay-run",
        strategy: "imported-symbolic-planner",
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
                actionID: "repair-missing-precondition",
                domainID: "drc-signoff",
                operationID: "drc.repair-width",
                maturity: "implemented",
                readiness: "ready",
                sourceObjectiveIDs: ["objective-1"],
                requiredInputRefs: ["layout-drc-input"],
                missingInputRefs: [],
                verificationGates: ["native-drc"],
                reason: "Imported invalid replay step.",
                parameterHints: [:],
                blockers: []
            ),
        ],
        verificationGates: [],
        constraints: [],
        unresolvedObjectives: [],
        blockers: []
    )
    let pddlExport = XcircuiteSymbolicPlannerPDDLExport(
        runID: "invalid-replay-run",
        problemID: "invalid-replay-problem",
        domainName: "domain-invalid-replay-problem",
        problemName: "problem-invalid-replay-problem",
        requirements: [":strips", ":action-costs"],
        domainPDDL: "",
        problemPDDL: "",
        atomMappings: [
            XcircuiteSymbolicPlannerPDDLAtomMapping(
                atom: "ready",
                predicate: "p-ready",
                roles: ["initial"]
            ),
            XcircuiteSymbolicPlannerPDDLAtomMapping(
                atom: "done",
                predicate: "p-done",
                roles: ["goal", "effect"]
            ),
            XcircuiteSymbolicPlannerPDDLAtomMapping(
                atom: "missing-precondition",
                predicate: "p-missing-precondition",
                roles: ["precondition"]
            ),
        ],
        actionMappings: [
            XcircuiteSymbolicPlannerPDDLActionMapping(
                actionID: "repair-missing-precondition",
                domainID: "drc-signoff",
                operationID: "drc.repair-width",
                pddlAction: "a-repair-missing-precondition",
                included: true,
                preconditionAtoms: ["missing-precondition"],
                effectAtoms: ["done"],
                actionCost: 5,
                actionCostUnit: "planner action cost",
                actionCostSource: "planning-cost-model"
            ),
        ]
    )

    let validation = XcircuiteSymbolicPlannerPlanReplayValidator().validate(
        candidatePlan: candidatePlan,
        pddlExport: pddlExport
    )

    #expect(validation.status == "failed")
    #expect(validation.validationStrategy == "pddl-additive-precondition-effect-replay")
    #expect(validation.initialAtoms == ["ready"])
    #expect(validation.missingGoalAtoms == ["done"])
    #expect(validation.evaluatedCost == 5)
    #expect(validation.steps.first?.status == "failed")
    #expect(validation.steps.first?.missingPreconditionAtoms == ["missing-precondition"])
    #expect(validation.diagnostics.contains { $0.code == "preconditions-unsatisfied" })
    #expect(validation.diagnostics.contains { $0.code == "goals-unsatisfied" })
}

@Test func runSymbolicPlannerSolverCLIWritesArtifactsAndImportsCandidatePlan() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-runner")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "mock-symbolic-planner.sh")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        printf 'Solution Found\\n'
        printf '0.000: (a-fix-m1-width) [1.000]\\n'
        printf 'cost = 1 (unit cost)\\n'
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    let json = try await XcircuiteFlowCLICommand.run(
        arguments: [
            "run-symbolic-planner-solver",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-pddl",
            "--executable-path",
            solverURL.path(percentEncoded: false),
            "--pretty",
        ]
    )
    let data = try #require(json.data(using: .utf8))
    let result = try JSONDecoder().decode(XcircuiteSymbolicPlannerSolverResult.self, from: data)

    #expect(result.status == "solved")
    #expect(result.exitCode == 0)
    #expect(result.didTimeout == false)
    #expect(result.runArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverRunArtifactID)
    #expect(result.standardOutputArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverStdoutArtifactID)
    #expect(result.standardErrorArtifact.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverStderrArtifactID)
    #expect(result.solverPlanArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID)
    #expect(result.planReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
    #expect(result.planReplayValidation?.status == "validated")
    #expect(result.planReplayValidation?.steps.map(\.actionID) == ["fix-m1-width"])
    let metadata = try #require(result.solverMetadata)
    #expect(metadata.planCost == 1)
    #expect(metadata.planCostUnit == "unit cost")
    #expect(metadata.evidenceLines.contains("cost = 1 (unit cost)"))
    let importResult = try #require(result.importResult)
    #expect(importResult.status == "imported")
    #expect(importResult.candidatePlan.steps.map(\.actionID) == ["fix-m1-width"])

    let solverRun = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverExecutionReport.self,
        from: root.appending(path: result.runArtifact.path)
    )
    #expect(solverRun.status == "solved")
    #expect(solverRun.solverPlanSource == "stdout")
    #expect(solverRun.solverMetadata?.planCost == 1)
    #expect(solverRun.solverMetadata?.planCostUnit == "unit cost")
    #expect(solverRun.planReplayValidationStatus == "validated")
    #expect(solverRun.planReplayValidationArtifact?.artifactID == XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID)
    #expect(solverRun.arguments.count == 2)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: result.standardOutputArtifact.path).path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: result.standardErrorArtifact.path).path(percentEncoded: false)))

    let replayValidation = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerPlanReplayValidation.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/planning/symbolic-planner/plan-replay-validation.json")
    )
    #expect(replayValidation.status == "validated")
    #expect(replayValidation.missingGoalAtoms == [])
    #expect(replayValidation.steps.first?.status == "applied")

    let verifierResult = try await XcircuiteCandidatePlanVerifier().verifyCandidatePlan(
        request: XcircuiteCandidatePlanVerificationRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let verification = try XcircuiteWorkspaceStore().readJSON(
        XcircuitePlanVerification.self,
        from: root.appending(path: verifierResult.planVerificationArtifact.path)
    )
    #expect(verification.goalCoverageStatus == "covered")
    #expect(verification.missingGoalAtoms == [])

    let manifest = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let artifactIDs = Set(manifest.artifacts.map(\.artifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverRunArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverStdoutArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverStderrArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.candidatePlanArtifactID))
}

@Test func runSymbolicPlannerSolverRecordsMissingPlanWithoutImportingCandidatePlan() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-empty-plan")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "empty-symbolic-planner.sh")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        exit 0
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    let result = try await XcircuiteSymbolicPlannerSolverRunner().solve(
        request: XcircuiteSymbolicPlannerSolverRequest(
            runID: "run-pddl",
            executablePath: solverURL.path(percentEncoded: false)
        ),
        projectRoot: root
    )

    #expect(result.status == "solver-plan-missing")
    #expect(result.exitCode == 0)
    #expect(result.solverPlanArtifact == nil)
    #expect(result.importResult == nil)
    #expect(result.planReplayValidationArtifact == nil)
    #expect(result.planReplayValidation == nil)
    #expect(result.diagnostics.contains { $0.code == "missing-solver-plan-output" })
    #expect(FileManager.default.fileExists(atPath: root.appending(path: result.runArtifact.path).path(percentEncoded: false)))

    let manifest = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteRunManifest.self,
        from: root.appending(path: ".xcircuite/runs/run-pddl/manifest.json")
    )
    let artifactIDs = Set(manifest.artifacts.map(\.artifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverRunArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverStdoutArtifactID))
    #expect(artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverStderrArtifactID))
    #expect(!artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerSolverPlanArtifactID))
    #expect(!artifactIDs.contains(XcircuitePlanningArtifactStore.symbolicPlannerPlanReplayValidationArtifactID))
    #expect(!artifactIDs.contains(XcircuitePlanningArtifactStore.candidatePlanArtifactID))
}

@Test func runSymbolicPlannerSolverReportsUnreadableCancellationRequest() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-unreadable-cancel")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let runDirectory = root
        .appending(path: XcircuiteWorkspace.directoryName)
        .appending(path: "runs")
        .appending(path: "run-pddl")
    try Data("{".utf8).write(
        to: runDirectory.appending(path: FlowRunProgressStore.cancellationRelativePath),
        options: [.atomic]
    )

    let markerURL = root.appending(path: "unreadable-cancel-planner-launched.txt")
    let solverURL = root.appending(path: "unreadable-cancel-symbolic-planner.sh")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        printf 'launched\\n' > '\(markerURL.path(percentEncoded: false))'
        printf 'Solution Found\\n'
        printf '0.000: (a-fix-m1-width) [1.000]\\n'
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    let result = try await XcircuiteSymbolicPlannerSolverRunner().solve(
        request: XcircuiteSymbolicPlannerSolverRequest(
            runID: "run-pddl",
            executablePath: solverURL.path(percentEncoded: false)
        ),
        projectRoot: root
    )

    #expect(result.status == "solver-failed")
    #expect(result.exitCode == nil)
    #expect(!result.didCancel)
    #expect(!result.didTimeout)
    #expect(result.diagnostics.contains { $0.code == "cancellation-check-failed" })
    #expect(!FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)))

    let solverRun = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverExecutionReport.self,
        from: root.appending(path: result.runArtifact.path)
    )
    #expect(solverRun.status == "solver-failed")
    #expect(solverRun.exitCode == nil)
    #expect(solverRun.diagnostics.contains { $0.code == "cancellation-check-failed" })
}

@Test func runSymbolicPlannerSolverRejectsSolverPlanOutputConflictingWithDomainArtifact() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-output-conflict")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    let pddlArtifacts = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let markerURL = root.appending(path: "conflicting-output-planner-launched.txt")
    let solverURL = root.appending(path: "conflicting-output-symbolic-planner.sh")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        printf 'launched\\n' > '\(markerURL.path(percentEncoded: false))'
        exit 0
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverRunner().solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: "run-pddl",
                executablePath: solverURL.path(percentEncoded: false),
                arguments: ["--plan-file", "{solverPlan}"],
                solverPlanOutputPath: pddlArtifacts.domainArtifact.path
            ),
            projectRoot: root
        )
        Issue.record("Expected conflicting solver plan output path validation to fail.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .conflictingSolverPlanOutputPath(
            let path,
            let conflictingArtifactID,
            let conflictingPath
        ) = error else {
            Issue.record("Expected conflictingSolverPlanOutputPath, got \(error).")
            return
        }
        #expect(path == pddlArtifacts.domainArtifact.path)
        #expect(conflictingArtifactID == XcircuitePlanningArtifactStore.symbolicPlannerPDDLDomainArtifactID)
        #expect(conflictingPath == pddlArtifacts.domainArtifact.path)
    }
    #expect(!FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)))
}

@Test func runSymbolicPlannerSolverRejectsSolverPlanOutputOutsideWorkingDirectory() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-output-outside-work")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let markerURL = root.appending(path: "outside-output-planner-launched.txt")
    let solverURL = root.appending(path: "outside-output-symbolic-planner.sh")
    let outputPath = "\(XcircuiteWorkspace.directoryName)/runs/run-pddl/planning/symbolic-planner/external-solver-plan.out"
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        printf 'launched\\n' > '\(markerURL.path(percentEncoded: false))'
        exit 0
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverRunner().solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: "run-pddl",
                executablePath: solverURL.path(percentEncoded: false),
                arguments: ["--plan-file", "{solverPlan}"],
                solverPlanOutputPath: outputPath
            ),
            projectRoot: root
        )
        Issue.record("Expected outside working directory solver plan output validation to fail.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .solverPlanOutputOutsideWorkingDirectory(let path, let workingDirectoryPath) = error else {
            Issue.record("Expected solverPlanOutputOutsideWorkingDirectory, got \(error).")
            return
        }
        #expect(path == outputPath)
        #expect(workingDirectoryPath == "\(XcircuiteWorkspace.directoryName)/runs/run-pddl/planning/symbolic-planner/solver-work")
    }
    #expect(!FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)))
}

@Test func runSymbolicPlannerSolverRejectsExistingSolverPlanOutputBeforeLaunch() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-stale-output")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let outputPath = "\(XcircuiteWorkspace.directoryName)/runs/run-pddl/planning/symbolic-planner/solver-work/solver-plan.out"
    let outputURL = root.appending(path: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try XcircuiteWorkspaceStore().writeText("0.000: (a-stale-action) [1.000]\n", to: outputURL)
    let markerURL = root.appending(path: "stale-output-planner-launched.txt")
    let solverURL = root.appending(path: "stale-output-symbolic-planner.sh")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        printf 'launched\\n' > '\(markerURL.path(percentEncoded: false))'
        exit 0
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    do {
        _ = try await XcircuiteSymbolicPlannerSolverRunner().solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: "run-pddl",
                executablePath: solverURL.path(percentEncoded: false),
                arguments: ["--plan-file", "{solverPlan}"]
            ),
            projectRoot: root
        )
        Issue.record("Expected existing solver plan output validation to fail.")
    } catch let error as XcircuiteSymbolicPlannerSolverError {
        guard case .existingSolverPlanOutput(let path) = error else {
            Issue.record("Expected existingSolverPlanOutput, got \(error).")
            return
        }
        #expect(path == outputPath)
    }
    #expect(!FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)))
}

@Test(.timeLimit(.minutes(1)))
func runSymbolicPlannerSolverCancelsExternalProcessWhenRunCancellationIsRecorded() async throws {
    let root = try makeTemporaryRoot("symbolic-planner-solver-cancelled")
    defer { removeTemporaryRoot(root) }
    try prepareRun(root: root, runID: "run-pddl")
    _ = try XcircuiteSymbolicPlannerPDDLExporter().exportSymbolicPlannerProblem(
        request: XcircuiteSymbolicPlannerPDDLExportRequest(runID: "run-pddl"),
        projectRoot: root
    )
    let solverURL = root.appending(path: "cancelled-symbolic-planner.sh")
    let childPIDURL = root.appending(path: "cancelled-symbolic-planner-child.pid")
    try XcircuiteWorkspaceStore().writeText(
        """
        #!/bin/sh
        trap '' TERM
        (trap '' TERM; while true; do sleep 1; done) &
        child=$!
        echo child=$child
        printf '%s\\n' "$child" > \(childPIDURL.path(percentEncoded: false))
        while true; do sleep 1; done
        """,
        to: solverURL
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: solverURL.path(percentEncoded: false)
    )

    let task = Task {
        try await XcircuiteSymbolicPlannerSolverRunner().solve(
            request: XcircuiteSymbolicPlannerSolverRequest(
                runID: "run-pddl",
                executablePath: solverURL.path(percentEncoded: false),
                timeoutSeconds: 30
            ),
            projectRoot: root
        )
    }

    let observedChildPID = try #require(try await waitForChildPID(at: childPIDURL))
    _ = try DefaultFlowRunCancellationRecorder().requestCancellation(
        projectRoot: root,
        runID: "run-pddl",
        requestedBy: "solver-cancellation-test",
        reason: "Stop external solver process."
    )

    let result = try await task.value

    #expect(result.status == "cancelled")
    #expect(result.didCancel)
    #expect(!result.didTimeout)
    #expect(result.diagnostics.contains { $0.code == "cancelled" })
    let standardOutput = try String(
        contentsOf: root.appending(path: result.standardOutputArtifact.path),
        encoding: .utf8
    )
    let childPID = try #require(parseChildPID(from: standardOutput))
    #expect(childPID == observedChildPID)
    #expect(await waitForProcessExit(childPID, timeoutSeconds: 2.0))

    let solverRun = try XcircuiteWorkspaceStore().readJSON(
        XcircuiteSymbolicPlannerSolverExecutionReport.self,
        from: root.appending(path: result.runArtifact.path)
    )
    #expect(solverRun.status == "cancelled")
    #expect(solverRun.didCancel)
    #expect(solverRun.didTimeout == false)
}

}
