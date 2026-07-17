import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
@testable import Xcircuite

@Suite("Selected semantic flow action projection")
struct XcircuiteSelectedSuggestedActionResolverTests {
    @Test func projectsEverySemanticOperationAtTheProjectBoundary() async throws {
        let root = try makeTemporaryRoot("selected-semantic-action-projection")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-1", store: store)

        let cases: [(FlowRunSuggestedOperation, String)] = [
            (.summarizeRunLoop, "summarize-loop"),
            (.inspectRun, "inspect-run"),
            (.reviewRun, "review-run"),
            (.evaluateRunGuard, "evaluate-run-guard"),
            (.validatePlanningProblem, "validate-planning-problem"),
            (.auditProblemTranslation, "audit-problem-translation"),
            (.generateCandidatePlan(rejectedPlansArtifactID: nil), "generate-candidate-plan"),
            (.executeCandidatePlan, "execute-candidate-plan"),
            (.verifyCandidatePlan(scope: .preExecution), "verify-candidate-plan"),
            (.verifyCandidatePlan(scope: .postExecution), "verify-candidate-plan"),
            (.generateParameterCandidates, "generate-parameter-candidates"),
            (.synthesizeParameterCandidatePlan, "synthesize-parameter-candidate-plan"),
            (.runNumericRepairLoop, "run-numeric-repair-loop"),
            (.buildStageArtifactLadder, "build-stage-artifact-ladder"),
            (.validateDecisionPacket, "validate-decision-packet"),
            (.buildReleaseEnvelope, "build-release-envelope"),
        ]

        for (index, item) in cases.enumerated() {
            let actionID = "semantic-action-\(index)"
            try await store.appendRunAction(
                FlowRunActionRecord(
                    actionID: "selection-\(index)",
                    runID: "run-1",
                    actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                    actionKind: FlowRunSuggestedActionSelection.actionKind,
                    status: .succeeded,
                    context: FlowRunActionContext(
                        suggestedAction: .init(
                            nextActionID: actionID,
                            nextActionKind: "semanticFlowOperation",
                            action: FlowRunSuggestedAction(
                                id: actionID,
                                readiness: .ready,
                                operation: item.0,
                                runID: "run-1",
                                reason: "Project the selected semantic operation."
                            )
                        )
                    )
                )
            )

            let resolved = try await XcircuiteSelectedSuggestedActionResolver(
                workspaceStore: store
            ).resolve(
                request: XcircuiteSelectedSuggestedActionResolutionRequest(
                    runID: "run-1",
                    actionID: actionID
                )
            )

            #expect(resolved.command.rawValue == item.1)
            #expect(resolved.selection.action.operation == item.0)
            #expect(resolved.dispatchArguments.starts(with: [
                "--project-root", store.projectRoot.path(percentEncoded: false),
                "--run-id", "run-1",
            ]))
            #expect(!resolved.dispatchArguments.contains("xcircuite-flow"))
        }
    }

    @Test func projectsTypedAssociatedValuesWithoutAcceptingRawArguments() async throws {
        let root = try makeTemporaryRoot("selected-action-associated-values")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-1", store: store)
        let rejectedPlansArtifactID = try ArtifactID(rawValue: "planning-rejected-plans")
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-feedback",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(
                    suggestedAction: .init(
                        nextActionID: "generate-with-feedback",
                        nextActionKind: "semanticFlowOperation",
                        action: FlowRunSuggestedAction(
                            id: "generate-with-feedback",
                            readiness: .ready,
                            operation: .generateCandidatePlan(
                                rejectedPlansArtifactID: rejectedPlansArtifactID
                            ),
                            runID: "run-1",
                            reason: "Generate a candidate using retained rejection evidence."
                        )
                    )
                )
            )
        )

        let resolved = try await XcircuiteSelectedSuggestedActionResolver(
            workspaceStore: store
        ).resolve(
            request: XcircuiteSelectedSuggestedActionResolutionRequest(
                runID: "run-1",
                actionID: "generate-with-feedback"
            )
        )

        #expect(resolved.dispatchArguments.contains("--rejected-plans-artifact-id"))
        #expect(resolved.dispatchArguments.contains(rejectedPlansArtifactID.rawValue))
    }

    @Test func rejectsInconsistentSelectionIdentity() async throws {
        let root = try makeTemporaryRoot("inconsistent-selected-action")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-1", store: store)
        try await store.appendRunAction(
            FlowRunActionRecord(
                actionID: "selection-inconsistent",
                runID: "run-1",
                actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                actionKind: FlowRunSuggestedActionSelection.actionKind,
                status: .succeeded,
                context: FlowRunActionContext(
                    suggestedAction: .init(
                        nextActionID: "expected-action",
                        nextActionKind: "semanticFlowOperation",
                        action: FlowRunSuggestedAction(
                            id: "different-action",
                            readiness: .ready,
                            operation: .inspectRun,
                            runID: "run-1",
                            reason: "Inspect the selected run."
                        )
                    )
                )
            )
        )

        await #expect(
            throws: XcircuiteSelectedSuggestedActionResolutionError.self
        ) {
            _ = try await XcircuiteSelectedSuggestedActionResolver(
                workspaceStore: store
            ).resolve(
                request: XcircuiteSelectedSuggestedActionResolutionRequest(
                    runID: "run-1",
                    actionID: "different-action"
                )
            )
        }
    }

    @Test func latestFailedSelectionSupersedesAnEarlierSuccessfulSelection() async throws {
        let root = try makeTemporaryRoot("failed-selection-supersedes-success")
        defer { removeTemporaryRoot(root) }
        let store = try XcircuiteWorkspaceStore(projectRoot: root)
        try await prepareTestRun(runID: "run-1", store: store)

        for (index, status) in [FlowRunActionStatus.succeeded, .failed].enumerated() {
            try await store.appendRunAction(
                FlowRunActionRecord(
                    actionID: "selection-\(index)",
                    runID: "run-1",
                    actor: FlowRunActor(kind: .human, identifier: "reviewer-1"),
                    actionKind: FlowRunSuggestedActionSelection.actionKind,
                    status: status,
                    context: FlowRunActionContext(
                        suggestedAction: .init(
                            nextActionID: "inspect-run",
                            nextActionKind: "semanticFlowOperation",
                            action: FlowRunSuggestedAction(
                                id: "inspect-run",
                                readiness: .ready,
                                operation: .inspectRun,
                                runID: "run-1",
                                reason: "Inspect the selected run."
                            )
                        )
                    )
                )
            )
        }

        await #expect(
            throws: XcircuiteSelectedSuggestedActionResolutionError.selectionNotSucceeded(
                actionID: "inspect-run",
                status: .failed
            )
        ) {
            _ = try await XcircuiteSelectedSuggestedActionResolver(
                workspaceStore: store
            ).resolve(
                request: XcircuiteSelectedSuggestedActionResolutionRequest(runID: "run-1")
            )
        }
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
