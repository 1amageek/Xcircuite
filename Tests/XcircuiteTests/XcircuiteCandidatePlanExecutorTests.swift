import Foundation
import CircuiteFoundation
import LayoutCommands
import LayoutTech
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite candidate plan executor")
struct XcircuiteCandidatePlanExecutorTests {
    @Test func candidatePlanExecutionEncodesCanonicalArtifactReferencesAndReadsLegacyKey() throws {
        let legacyArtifact = XcircuiteFileReference(
            artifactID: "execution-report",
            path: ".xcircuite/runs/run-artifact/planning/report.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "a", count: 64),
            byteCount: 7,
            producedByRunID: "run-artifact"
        )
        let execution = try XcircuiteCandidatePlanExecution(
            runID: "run-artifact",
            problemID: "problem-artifact",
            planID: "plan-artifact",
            status: "executed",
            candidatePlanRef: XcircuiteFileReference(
                artifactID: "candidate-plan",
                path: ".xcircuite/runs/run-artifact/planning/candidate-plan.json",
                kind: .other,
                format: .json
            ),
            stepResults: [],
            artifactRefs: [legacyArtifact],
            diagnostics: [],
            nextActions: []
        )

        let encoded = try JSONEncoder().encode(execution)
        var encodedObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(encodedObject["schemaVersion"] as? Int == 2)
        #expect(encodedObject["artifactReferences"] != nil)
        #expect(encodedObject["artifactRefs"] == nil)

        let legacyArtifacts = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([legacyArtifact])
        )
        encodedObject.removeValue(forKey: "artifactReferences")
        encodedObject["schemaVersion"] = 1
        encodedObject["artifactRefs"] = legacyArtifacts
        let legacyData = try JSONSerialization.data(withJSONObject: encodedObject)
        let decoded = try JSONDecoder().decode(XcircuiteCandidatePlanExecution.self, from: legacyData)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedObject = try #require(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        #expect(reencodedObject["schemaVersion"] as? Int == 2)
        #expect(reencodedObject["artifactReferences"] != nil)
        #expect(reencodedObject["artifactRefs"] == nil)
        #expect(decoded.artifactReferences.count == 1)
        #expect(decoded.artifactReferences[0].id.rawValue == "execution-report")
        #expect(decoded.artifactReferences[0].digest.hexadecimalValue == String(repeating: "a", count: 64))
        #expect(decoded.artifactReferences[0].byteCount == 7)
    }

    @Test func executeCandidatePlanCLIRunsLayoutAddRectAndWritesArtifacts() async throws {
        let root = try makeTemporaryRoot("candidate-plan-execute-cli")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        _ = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuiteCandidatePlanExecutionResult.self, from: data)

        #expect(result.status == "executed")
        #expect(result.planExecutionArtifact.artifactID == XcircuitePlanningArtifactStore.planExecutionArtifactID)
        #expect(result.planExecutionArtifact.path == ".xcircuite/runs/run-1/planning/plan-execution.json")
        #expect(result.designDiffArtifact?.path == ".xcircuite/runs/run-1/design-diff.json")
        #expect(result.producedArtifacts.contains { $0.artifactID == "candidate-step-1-layout-document" })
        #expect(result.producedArtifacts.contains { $0.artifactID == "candidate-step-1-layout-result" })
        #expect(result.nextActions.contains("run-verification-gate:native-drc"))
        #expect(result.nextActions.contains("run-verification-gate:native-lvs"))

        let store = XcircuitePackageStore()
        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.status == "executed")
        #expect(execution.stepResults.map(\.status) == ["executed"])
        #expect(execution.designDiffRef?.artifactID == nil)
        let layoutDocument = try #require(execution.artifactRefs.first {
            $0.artifactID == "candidate-step-1-layout-document"
        })
        #expect(fileExists(layoutDocument.path, in: root))
        #expect(layoutDocument.sha256?.isEmpty == false)
        #expect((layoutDocument.byteCount ?? 0) > 0)

        let diff = try store.loadDesignDiff(runID: "run-1", inProjectAt: root)
        #expect(diff.title == "Candidate plan run-1-drc-repair-problem-candidate-plan-1 execution")
        #expect(diff.changes.count == 1)
        #expect(diff.changes.first?.domain == .layout)
        #expect(diff.changes.first?.operation == .add)
        #expect(diff.changes.first?.artifacts.contains { $0.artifactID == "candidate-step-1-layout-document" } == true)

        let actions = try store.loadRunActions(runID: "run-1", inProjectAt: root)
        let action = try #require(actions.last)
        #expect(action.actionKind == "planning.execute-candidate-plan")
        #expect(action.status == .succeeded)
        #expect(action.inputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.candidatePlanArtifactID))
        #expect(action.outputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.planExecutionArtifactID))
        #expect(action.outputs.map(\.artifactID).contains("candidate-step-1-layout-document"))

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.planExecutionArtifactID
        })
        #expect(manifest.artifacts.contains {
            $0.artifactID == "candidate-step-1-layout-document"
        })
    }

    @Test func executeCandidatePlanCLIRejectsTamperedCandidatePlanBeforeUse() async throws {
        let root = try makeTemporaryRoot("candidate-plan-execute-cli-tampered-plan")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-1", problem: makeDRCPlanningProblem())
        let generation = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-1"),
            projectRoot: root
        )
        try Data(#"{"tampered":true}"#.utf8).write(
            to: root.appending(path: generation.candidatePlanArtifact.path),
            options: [.atomic]
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "execute-candidate-plan",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
            ])
            Issue.record("Expected tampered candidate plan artifact to fail integrity verification.")
        } catch let error as XcircuiteCandidatePlanExecutionError {
            guard case .artifactIntegrityFailed(let path, let status, _) = error else {
                Issue.record("Unexpected candidate plan execution error: \(error)")
                return
            }
            #expect(path == generation.candidatePlanArtifact.path)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func lvsPolicyRepairExecutionIsBlockedWithoutApprovalAndDesignDiff() async throws {
        let root = try makeTemporaryRoot("candidate-plan-execute-blocked")
        defer { removeTemporaryRoot(root) }
        try prepareRun(root: root, runID: "run-2", problem: makeLVSPlanningProblem())
        _ = try XcircuiteCandidatePlanGenerator().generateCandidatePlan(
            request: XcircuiteCandidatePlanGenerationRequest(runID: "run-2"),
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-2"),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.designDiffArtifact == nil)
        #expect(result.nextActions.contains("request-human-approval:policy-repair-approval"))
        let execution = try XcircuitePackageStore().readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.first?.status == "blocked")
        #expect(execution.diagnostics.contains { $0.code == "risk-approval-required" })
    }

    @Test func executorBlocksApprovalRequiredRiskBeforeDesignMutation() async throws {
        let root = try makeTemporaryRoot("candidate-plan-execute-approval-risk")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-risk", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeApprovalRequiredLayoutPlan(),
            runID: "run-risk",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-risk"),
            projectRoot: root
        )

        #expect(result.status == "blocked")
        #expect(result.designDiffArtifact == nil)
        #expect(result.producedArtifacts.isEmpty)
        #expect(result.nextActions == ["request-human-approval:policy-repair-approval"])

        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.status == "blocked")
        #expect(execution.stepResults.map(\.status) == ["blocked"])
        #expect(execution.diagnostics.contains { $0.code == "risk-approval-required" })
        #expect(execution.stepResults.first?.diagnostics.contains {
            $0.code == "risk-approval-required" && $0.stepID == "step-1"
        } == true)

        let action = try #require(store.loadRunActions(runID: "run-risk", inProjectAt: root).last)
        #expect(action.status == .blocked)
        #expect(action.outputs.map(\.artifactID).contains(XcircuitePlanningArtifactStore.planExecutionArtifactID))
        #expect(action.outputs.contains { $0.artifactID == "candidate-step-1-layout-document" } == false)
    }

    @Test func approveCandidatePlanRiskCLIAllowsExecutionAfterReview() async throws {
        let root = try makeTemporaryRoot("candidate-plan-execute-approved-risk")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-risk", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeApprovalRequiredLayoutPlan(),
            runID: "run-risk",
            projectRoot: root
        )

        let approvalJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "approve-candidate-plan-risk",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            "run-risk",
            "--approval-id",
            "policy-repair-approval",
            "--reviewer",
            "reviewer-1",
            "--reviewer-kind",
            "agent",
            "--note",
            "Approved for execution regression.",
            "--pretty",
        ])
        let approvalResult = try JSONDecoder().decode(
            XcircuiteCandidatePlanRiskApprovalResult.self,
            from: try #require(approvalJSON.data(using: .utf8))
        )
        #expect(approvalResult.status == "approved")
        #expect(approvalResult.approvalPath == ".xcircuite/runs/run-risk/approvals/policy-repair-approval.json")
        #expect(approvalResult.approval.reviewerKind == .agent)

        let verification = XcircuiteCandidatePlanVerifier().makePlanVerification(
            plan: makeApprovalRequiredLayoutPlan(),
            candidatePlanRef: XcircuiteFileReference(
                artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                path: ".xcircuite/runs/run-risk/planning/candidate-plan.json",
                kind: .other,
                format: .json,
                sha256: "abc",
                byteCount: 12,
                producedByRunID: "run-risk"
            ),
            approvals: try store.loadApprovals(runID: "run-risk", inProjectAt: root)
        )
        #expect(verification.riskReviews.first?.status == "approved")
        #expect(verification.gateResults.contains { $0.gateID == "approval-gate" && $0.status == "passed" })

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-risk"),
            projectRoot: root
        )

        #expect(result.status == "executed")
        #expect(result.designDiffArtifact != nil)
        #expect(result.producedArtifacts.contains { $0.artifactID == "candidate-step-1-layout-document" })

        let actions = try store.loadRunActions(runID: "run-risk", inProjectAt: root)
        #expect(actions.contains { $0.actionKind == "planning.approve-candidate-plan-risk" })
        let approvalAction = try #require(actions.first { $0.actionKind == "planning.approve-candidate-plan-risk" })
        #expect(approvalAction.actor.kind == .agent)
        #expect(approvalAction.actor.identifier == "reviewer-1")
        #expect(actions.last?.actionKind == "planning.execute-candidate-plan")
        #expect(actions.last?.status == .succeeded)
    }

    @Test func executorChainsImplementedLayoutCommandsAcrossSteps() async throws {
        let root = try makeTemporaryRoot("candidate-plan-layout-chain")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-3", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeChainedLayoutPlan(),
            runID: "run-3",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-3"),
            projectRoot: root
        )

        #expect(result.status == "executed")
        #expect(result.producedArtifacts.contains { $0.artifactID == "candidate-step-10-layout-document" })

        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.map(\.operationID) == [
            "layout.create-cell",
            "layout.add-net",
            "layout.add-rect",
            "layout.translate-shape",
            "layout.resize-shape",
            "layout.split-shape",
            "layout.add-label",
            "layout.add-via",
            "layout.add-rect",
            "layout.delete-shape",
        ])
        #expect(execution.stepResults.allSatisfy { $0.status == "executed" })

        let stepDocuments = try execution.stepResults.map { result in
            try #require(result.artifactRefs.first { $0.artifactID == "candidate-step-\(result.order)-layout-document" })
        }
        let stepRequests = try execution.stepResults.map { result in
            let reference = try #require(result.artifactRefs.first {
                $0.artifactID == "candidate-step-\(result.order)-layout-request"
            })
            return try store.readJSON(
                DecodedLayoutCommandRequest.self,
                from: root.appending(path: reference.path)
            )
        }
        #expect(stepRequests[0].inputDocumentPath == nil)
        for index in 1..<stepRequests.count {
            #expect(stepRequests[index].inputDocumentPath == stepDocuments[index - 1].path)
        }

        let finalDocumentRef = try #require(stepDocuments.last)
        let finalDocument = try store.readJSON(
            DecodedLayoutDocument.self,
            from: root.appending(path: finalDocumentRef.path)
        )
        let cell = try #require(finalDocument.cells.first)
        #expect(cell.nets.map(\.name) == ["out"])
        #expect(cell.shapes.count == 2)
        #expect(cell.labels.count == 1)
        #expect(cell.vias.count == 1)

        let diff = try store.loadDesignDiff(runID: "run-3", inProjectAt: root)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-4" }?.operation == .move)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-5" }?.operation == .replace)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-6" }?.operation == .replace)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-10" }?.operation == .remove)
    }

    @Test func executorExportsStandardLayoutArtifactsFromLayoutStepHint() async throws {
        let root = try makeTemporaryRoot("candidate-plan-standard-layout-export")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-5", inProjectAt: root)
        try writeStandardLayoutTechnology(root: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeStandardLayoutExportPlan(),
            runID: "run-5",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-5"),
            projectRoot: root
        )

        #expect(result.status == "executed")
        let layoutGDS = try #require(result.producedArtifacts.first {
            $0.artifactID == "candidate-layout-gds"
        })
        #expect(layoutGDS.locator.kind == .layout)
        #expect(layoutGDS.locator.format == .gdsii)
        #expect(layoutGDS.locator.location.value.hasSuffix("candidate-layout-gds.gds"))
        #expect(!layoutGDS.digest.hexadecimalValue.isEmpty)
        #expect(layoutGDS.byteCount > 0)
        #expect(fileExists(layoutGDS.locator.location.value, in: root))

        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.locator.location.value)
        )
        #expect(execution.stepResults.first?.artifactRefs.contains {
            $0.artifactID == "candidate-layout-gds"
        } == true)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-5/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == "candidate-layout-gds" && $0.format == .gdsii
        })

        let diff = try store.loadDesignDiff(runID: "run-5", inProjectAt: root)
        #expect(diff.changes.first?.artifacts.contains {
            $0.artifactID == "candidate-layout-gds"
        } == true)
    }

    @Test func executorRecordsMultiFamilyCoverageAndNetlistArtifactHandoff() async throws {
        let root = try makeTemporaryRoot("candidate-plan-multi-family-coverage")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-coverage", inProjectAt: root)
        try writeSPICENetlist(root: root, path: "circuits/input.spice")
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeMultiFamilyCoveragePlan(),
            runID: "run-coverage",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-coverage"),
            projectRoot: root
        )

        #expect(result.status == "executed")
        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.map(\.status) == ["executed", "executed", "executed", "executed"])
        #expect(execution.executionCoverage.status == "covered")
        #expect(execution.executionCoverage.requiredFamilyIDs == ["layout", "netlist", "parameter", "policy"])
        #expect(execution.executionCoverage.coveredFamilyIDs == ["layout", "netlist", "parameter", "policy"])
        #expect(execution.executionCoverage.missingFamilyIDs.isEmpty)
        #expect(execution.executionCoverage.familyCoverage.contains {
            $0.familyID == "layout"
                && $0.stepIDs == ["step-1"]
                && $0.artifactIDs.contains("candidate-step-1-layout-document")
        })
        #expect(execution.executionCoverage.familyCoverage.contains {
            $0.familyID == "netlist"
                && $0.stepIDs == ["step-2", "step-3"]
                && $0.artifactIDs.contains("candidate-step-2-edited-netlist")
                && $0.artifactIDs.contains("candidate-step-3-edited-netlist")
        })
        #expect(execution.executionCoverage.familyCoverage.contains {
            $0.familyID == "parameter"
                && $0.stepIDs == ["step-2", "step-3"]
                && $0.operationIDs == ["simulation.set-netlist-parameters"]
        })
        #expect(execution.executionCoverage.familyCoverage.contains {
            $0.familyID == "policy"
                && $0.stepIDs == ["step-4"]
                && $0.artifactIDs.contains("candidate-step-4-model-equivalence-policy")
        })

        let firstEditReportRef = try #require(execution.stepResults[1].artifactRefs.first {
            $0.artifactID == "candidate-step-2-netlist-parameter-edit-report"
        })
        let firstEditReport = try store.readJSON(
            XcircuiteNetlistParameterEditReport.self,
            from: root.appending(path: firstEditReportRef.path)
        )
        let secondEditReportRef = try #require(execution.stepResults[2].artifactRefs.first {
            $0.artifactID == "candidate-step-3-netlist-parameter-edit-report"
        })
        let secondEditReport = try store.readJSON(
            XcircuiteNetlistParameterEditReport.self,
            from: root.appending(path: secondEditReportRef.path)
        )
        #expect(firstEditReport.outputNetlistPath == secondEditReport.sourceNetlistPath)

        let diff = try store.loadDesignDiff(runID: "run-coverage", inProjectAt: root)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-2" }?.domain == .netlist)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-3" }?.domain == .netlist)
        #expect(diff.changes.first { $0.path == "/planning/candidate-plan/steps/step-4" }?.domain == .verification)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-coverage/manifest.json")
        )
        for artifactID in execution.executionCoverage.producedArtifactIDs {
            #expect(manifest.artifacts.contains { $0.artifactID == artifactID })
        }
    }

    @Test func candidatePlanExecutionRejectsMissingExecutionCoverage() throws {
        let payload = Data("""
        {
          "schemaVersion": 1,
          "runID": "run-incomplete",
          "problemID": "problem-incomplete",
          "planID": "plan-incomplete",
          "status": "executed",
          "candidatePlanRef": {
            "artifactID": "planning-candidate-plan",
            "path": ".xcircuite/runs/run-incomplete/planning/candidate-plan.json",
            "kind": "other",
            "format": "JSON"
          },
          "stepResults": [],
          "artifactRefs": [],
          "diagnostics": [],
          "nextActions": []
        }
        """.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(XcircuiteCandidatePlanExecution.self, from: payload)
        }
    }

    @Test func executorPersistsLayoutCommandFailureAsPlanExecutionDiagnostic() async throws {
        let root = try makeTemporaryRoot("candidate-plan-layout-failure")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-4", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeFailingLayoutPlan(),
            runID: "run-4",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-4"),
            projectRoot: root
        )

        #expect(result.status == "failed")
        #expect(result.designDiffArtifact == nil)
        #expect(result.nextActions.contains("inspect-execution-diagnostic:step-1"))

        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.first?.status == "failed")
        #expect(execution.diagnostics.contains { $0.code == "execution-failed" })

        let action = try #require(store.loadRunActions(runID: "run-4", inProjectAt: root).last)
        #expect(action.status == .failed)
        #expect(action.diagnostics.contains { $0.code == "execution-failed" })
    }

    @Test func executorRejectsLayoutCommandOutputPathMismatchBeforeArtifactPromotion() async throws {
        let root = try makeTemporaryRoot("candidate-plan-layout-output-path-mismatch")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-layout-path-mismatch", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeSingleLayoutPlan(runID: "run-layout-path-mismatch"),
            runID: "run-layout-path-mismatch",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor(
            layoutRunner: TamperingLayoutCommandRunner(mode: .outputPathMismatch)
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-layout-path-mismatch"),
            projectRoot: root
        )

        #expect(result.status == "failed")
        #expect(result.producedArtifacts.isEmpty)
        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.first?.status == "failed")
        #expect(execution.diagnostics.contains { $0.code == "layout-command-result-path-mismatch" })
        #expect(execution.artifactRefs.isEmpty)
    }

    @Test func executorRejectsLayoutCommandDigestMismatchBeforeArtifactPromotion() async throws {
        let root = try makeTemporaryRoot("candidate-plan-layout-digest-mismatch")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-layout-digest-mismatch", inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeSingleLayoutPlan(runID: "run-layout-digest-mismatch"),
            runID: "run-layout-digest-mismatch",
            projectRoot: root
        )

        let result = try await XcircuiteCandidatePlanExecutor(
            layoutRunner: TamperingLayoutCommandRunner(mode: .digestMismatch)
        ).executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-layout-digest-mismatch"),
            projectRoot: root
        )

        #expect(result.status == "failed")
        #expect(result.producedArtifacts.isEmpty)
        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: root.appending(path: result.planExecutionArtifact.path)
        )
        #expect(execution.stepResults.first?.status == "failed")
        #expect(execution.diagnostics.contains { $0.code == "layout-command-output-digest-mismatch" })
        #expect(execution.artifactRefs.isEmpty)
    }


    private func prepareRun(
        root: URL,
        runID: String,
        problem: XcircuiteCircuitPlanningProblem
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: runID,
            projectRoot: root
        )
    }

    private func makeChainedLayoutPlan() -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "run-3-layout-chain-plan",
            problemID: "run-3-layout-chain-problem",
            runID: "run-3",
            strategy: "layout-command-chain",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-3/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.create-cell",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "cellName": .string("top"),
                        "makeTop": .bool(true),
                    ],
                    gates: ["artifact-integrity"]
                ),
                layoutPlanStep(
                    order: 2,
                    operationID: "layout.add-net",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "netID": .string("10000000-0000-0000-0000-000000000032"),
                        "netName": .string("out"),
                    ],
                    gates: ["artifact-integrity"]
                ),
                layoutPlanStep(
                    order: 3,
                    operationID: "layout.add-rect",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "netID": .string("10000000-0000-0000-0000-000000000032"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000033"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(2),
                        "height": .number(1),
                    ],
                    gates: ["artifact-integrity", "native-drc"]
                ),
                layoutPlanStep(
                    order: 4,
                    operationID: "layout.translate-shape",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000033"),
                        "deltaX": .number(1),
                        "deltaY": .number(0),
                    ],
                    gates: ["artifact-integrity", "native-drc"]
                ),
                layoutPlanStep(
                    order: 5,
                    operationID: "layout.resize-shape",
                    hints: [
                        "shapeID": .string("10000000-0000-0000-0000-000000000033"),
                        "deltaMinX": .number(0),
                        "deltaMinY": .number(0),
                        "deltaMaxX": .number(1),
                        "deltaMaxY": .number(1),
                    ],
                    gates: ["artifact-integrity", "native-drc", "native-lvs"]
                ),
                layoutPlanStep(
                    order: 6,
                    operationID: "layout.split-shape",
                    hints: [
                        "shapeID": .string("10000000-0000-0000-0000-000000000033"),
                        "firstShapeID": .string("10000000-0000-0000-0000-000000000037"),
                        "secondShapeID": .string("10000000-0000-0000-0000-000000000038"),
                        "axis": .string("vertical"),
                    ],
                    gates: ["artifact-integrity", "native-drc", "native-lvs"]
                ),
                layoutPlanStep(
                    order: 7,
                    operationID: "layout.add-label",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "netID": .string("10000000-0000-0000-0000-000000000032"),
                        "labelID": .string("10000000-0000-0000-0000-000000000034"),
                        "text": .string("out"),
                        "layer": .string("M1"),
                        "positionX": .number(1),
                        "positionY": .number(0),
                    ],
                    gates: ["artifact-integrity", "native-lvs"]
                ),
                layoutPlanStep(
                    order: 8,
                    operationID: "layout.add-via",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "netID": .string("10000000-0000-0000-0000-000000000032"),
                        "viaID": .string("10000000-0000-0000-0000-000000000035"),
                        "viaDefinitionID": .string("VIA1"),
                        "positionX": .number(1),
                        "positionY": .number(0),
                    ],
                    gates: ["artifact-integrity", "native-drc", "native-lvs"]
                ),
                layoutPlanStep(
                    order: 9,
                    operationID: "layout.add-rect",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000031"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000036"),
                        "layer": .string("M1"),
                        "originX": .number(20),
                        "originY": .number(20),
                        "width": .number(1),
                        "height": .number(1),
                        "role": .string("temporary-fill"),
                    ],
                    gates: ["artifact-integrity", "native-drc"]
                ),
                layoutPlanStep(
                    order: 10,
                    operationID: "layout.delete-shape",
                    hints: [
                        "shapeID": .string("10000000-0000-0000-0000-000000000036"),
                    ],
                    gates: ["artifact-integrity", "native-drc", "native-lvs"]
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate layout must pass DRC."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate layout must remain LVS-equivalent."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeSingleLayoutPlan(runID: String) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-layout-plan",
            problemID: "\(runID)-layout-problem",
            runID: runID,
            strategy: "single-layout-command-artifact-gate",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.create-cell",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000701"),
                        "cellName": .string("top"),
                        "makeTop": .bool(true),
                    ],
                    gates: ["artifact-integrity"]
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Candidate layout command result must match retained artifacts."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeApprovalRequiredLayoutPlan() -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "run-risk-approval-plan",
            problemID: "run-risk-approval-problem",
            runID: "run-risk",
            strategy: "approval-required-risk-gate",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-risk/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            assumptions: [],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "policy-mutation-risk",
                    category: "lvs-policy",
                    severity: "high",
                    scope: "candidate-plan",
                    description: "Policy mutation requires explicit review before execution.",
                    affectedObjectiveIDs: ["layout-chain-objective"],
                    affectedActionIDs: ["layout-action-1"],
                    requiredApprovals: ["policy-repair-approval"],
                    mitigationActions: ["approval-gate", "native-lvs"]
                ),
            ],
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.create-cell",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000091"),
                        "cellName": .string("top"),
                        "makeTop": .bool(true),
                    ],
                    gates: ["artifact-integrity"]
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Candidate plan artifact must remain inspectable."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeFailingLayoutPlan() -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "run-4-layout-failure-plan",
            problemID: "run-4-layout-failure-problem",
            runID: "run-4",
            strategy: "layout-command-failure-capture",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-4/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.translate-shape",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000041"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000043"),
                        "deltaX": .number(1),
                    ],
                    gates: ["artifact-integrity", "native-drc"]
                ),
            ],
            verificationGates: [],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeStandardLayoutExportPlan() -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "run-5-standard-layout-export-plan",
            problemID: "run-5-standard-layout-export-problem",
            runID: "run-5",
            strategy: "layout-edit-with-standard-export",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-5/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.add-rect",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000501"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000502"),
                        "cellName": .string("top"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(2),
                        "height": .number(1),
                        "standardLayoutExports": .array([
                            .object([
                                "artifactID": .string("candidate-layout-gds"),
                                "format": .string("gds"),
                                "technologyInput": .object([
                                    "kind": .string("path"),
                                    "value": .string("tech/layout-tech.json"),
                                ]),
                            ]),
                        ]),
                    ],
                    gates: ["artifact-integrity"]
                ),
            ],
            verificationGates: [],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func makeMultiFamilyCoveragePlan() -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "run-coverage-multi-family-plan",
            problemID: "run-coverage-multi-family-problem",
            runID: "run-coverage",
            strategy: "multi-family-candidate-execution-coverage",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-coverage/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                layoutPlanStep(
                    order: 1,
                    operationID: "layout.add-rect",
                    hints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000601"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000602"),
                        "cellName": .string("top"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(2),
                        "height": .number(1),
                    ],
                    gates: ["artifact-integrity", "native-drc"]
                ),
                executionPlanStep(
                    order: 2,
                    actionID: "parameter-action-2",
                    domainID: "simulation-and-pex-improvement",
                    operationID: "simulation.set-netlist-parameters",
                    hints: [
                        "netlistPath": .string("circuits/input.spice"),
                        "assignments": .array([
                            .object([
                                "name": .string("M1.w"),
                                "value": .number(2),
                                "unit": .string("u"),
                            ]),
                        ]),
                    ],
                    gates: ["artifact-integrity", "simulation-metric-gate"]
                ),
                executionPlanStep(
                    order: 3,
                    actionID: "parameter-action-3",
                    domainID: "simulation-and-pex-improvement",
                    operationID: "simulation.set-netlist-parameters",
                    hints: [
                        "assignments": .array([
                            .object([
                                "name": .string("M1.l"),
                                "value": .number(0.18),
                                "unit": .string("u"),
                            ]),
                        ]),
                    ],
                    gates: ["artifact-integrity", "simulation-metric-gate"]
                ),
                executionPlanStep(
                    order: 4,
                    actionID: "policy-action-4",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    hints: [
                        "policyKind": .string("model-equivalence"),
                        "schematicModel": .string("nfet"),
                        "layoutModel": .string("sky130_fd_pr__nfet_01v8"),
                        "canonicalModel": .string("nfet"),
                        "ruleID": .string("model-equivalence:nfet"),
                    ],
                    gates: ["artifact-integrity", "native-lvs"]
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate layout must pass DRC."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate policy must pass LVS."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Candidate parameters must satisfy simulation metrics."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func layoutPlanStep(
        order: Int,
        operationID: String,
        hints: [String: XcircuiteJSONValue],
        gates: [String]
    ) -> XcircuiteCandidatePlanStep {
        XcircuiteCandidatePlanStep(
            stepID: "step-\(order)",
            order: order,
            actionID: "layout-action-\(order)",
            domainID: "layout-edit",
            operationID: operationID,
            maturity: "implemented",
            readiness: "ready",
            sourceObjectiveIDs: ["layout-chain-objective"],
            requiredInputRefs: [],
            missingInputRefs: [],
            verificationGates: gates,
            reason: "Exercise LayoutCommands-backed candidate execution.",
            parameterHints: hints,
            blockers: []
        )
    }

    private func executionPlanStep(
        order: Int,
        actionID: String,
        domainID: String,
        operationID: String,
        hints: [String: XcircuiteJSONValue],
        gates: [String]
    ) -> XcircuiteCandidatePlanStep {
        XcircuiteCandidatePlanStep(
            stepID: "step-\(order)",
            order: order,
            actionID: actionID,
            domainID: domainID,
            operationID: operationID,
            maturity: "implemented",
            readiness: "ready",
            sourceObjectiveIDs: ["multi-family-objective"],
            requiredInputRefs: [],
            missingInputRefs: [],
            verificationGates: gates,
            reason: "Exercise multi-family candidate execution over shared artifacts.",
            parameterHints: hints,
            blockers: []
        )
    }

    private func makeDRCPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-1-drc-repair-problem",
            runID: "run-1",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "drc-summary",
                    kind: "drc-summary",
                    path: ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json",
                    artifactID: "drc-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: ".xcircuite/runs/run-1/stages/006-layout/raw/layout.gds"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-m1-width-1",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["drc-summary"],
                    target: "no-active-violations-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair M1 width violation."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The candidate must pass DRC.",
                    sourceRefIDs: ["drc-summary"]
                ),
            ],
            actionDomainRefs: ["drc-signoff", "layout-edit", "lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-add-rect-1",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Apply a concrete layout edit family.",
                    sourceObjectiveIDs: ["drc-m1-width-1"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-drc", "native-lvs"],
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000001"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000003"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(2),
                        "height": .number(1),
                        "ruleID": .string("M1.width"),
                    ]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
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

    private func makeLVSPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-2-lvs-repair-problem",
            runID: "run-2",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "lvs-summary",
                    kind: "lvs-summary",
                    path: ".xcircuite/runs/run-2/stages/008-lvs/raw/lvs-summary.json",
                    artifactID: "lvs-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/top.spice"
                ),
            ],
            riskClassifications: [
                XcircuitePlanningRiskClassification(
                    riskID: "lvs-policy-mutation-risk",
                    category: "policy-mutation",
                    severity: "high",
                    scope: "candidate-plan",
                    description: "Policy mutation changes LVS equivalence semantics.",
                    affectedActionIDs: ["lvs-policy-1"],
                    requiredApprovals: ["policy-repair-approval"],
                    mitigationActions: ["approval-gate", "native-lvs"]
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-model-policy-1",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: ["lvs-summary"],
                    target: "layout-and-schematic-equivalent-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair model policy mismatch."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "policy-repair-approval",
                    kind: "human-approval",
                    severity: "warning",
                    description: "Policy repair requires approval.",
                    sourceRefIDs: ["lvs-summary"]
                ),
            ],
            actionDomainRefs: ["lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "lvs-policy-1",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "implemented",
                    reason: "Resolve model equivalence through an auditable policy update.",
                    sourceObjectiveIDs: ["lvs-model-policy-1"],
                    requiredInputRefs: ["lvs-summary", "schematic-netlist-ref"],
                    verificationGates: ["approval-gate", "native-lvs"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Policy repair requires approval."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["approval-required"]
            )
        )
    }

    private struct DecodedLayoutCommandRequest: Decodable {
        var inputDocumentPath: String?
        var outputDocumentPath: String
    }

    private struct DecodedLayoutDocument: Decodable {
        var cells: [DecodedLayoutCell]
    }

    private struct DecodedLayoutCell: Decodable {
        var shapes: [DecodedLayoutEntity]
        var vias: [DecodedLayoutEntity]
        var labels: [DecodedLayoutEntity]
        var nets: [DecodedLayoutNet]
    }

    private struct DecodedLayoutEntity: Decodable {
        var id: UUID
    }

    private struct DecodedLayoutNet: Decodable {
        var id: UUID
        var name: String
    }

    private func fileExists(_ path: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
    }

    private func writeStandardLayoutTechnology(root: URL) throws {
        let url = root.appending(path: "tech/layout-tech.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(LayoutTechDatabase.standard())
        try data.write(to: url, options: [.atomic])
    }

    private func writeSPICENetlist(root: URL, path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let netlist = """
        * candidate execution coverage fixture
        M1 out in vss vss nfet w=1u l=0.15u
        .model nfet nmos
        .end
        """
        try netlist.write(to: url, atomically: true, encoding: .utf8)
    }

    private struct TamperingLayoutCommandRunner: LayoutCommandRunning {
        enum Mode: Sendable {
            case outputPathMismatch
            case digestMismatch
        }

        var mode: Mode
        private let runner = LayoutCommandRunner()

        func run(request: LayoutCommandRequest, baseURL: URL) throws -> LayoutCommandResult {
            let result = try runner.run(request: request, baseURL: baseURL)
            switch mode {
            case .outputPathMismatch:
                return LayoutCommandResult(
                    schemaVersion: result.schemaVersion,
                    status: result.status,
                    commandCount: result.commandCount,
                    appliedCommands: result.appliedCommands,
                    outputDocumentPath: baseURL
                        .deletingLastPathComponent()
                        .appending(path: "outside-layout.json")
                        .path(percentEncoded: false),
                    outputDocumentSHA256: result.outputDocumentSHA256,
                    outputDocumentByteCount: result.outputDocumentByteCount,
                    artifactManifestPath: result.artifactManifestPath,
                    cellCount: result.cellCount,
                    shapeCount: result.shapeCount,
                    viaCount: result.viaCount,
                    labelCount: result.labelCount,
                    netCount: result.netCount
                )
            case .digestMismatch:
                return LayoutCommandResult(
                    schemaVersion: result.schemaVersion,
                    status: result.status,
                    commandCount: result.commandCount,
                    appliedCommands: result.appliedCommands,
                    outputDocumentPath: result.outputDocumentPath,
                    outputDocumentSHA256: String(repeating: "0", count: 64),
                    outputDocumentByteCount: result.outputDocumentByteCount,
                    artifactManifestPath: result.artifactManifestPath,
                    cellCount: result.cellCount,
                    shapeCount: result.shapeCount,
                    viaCount: result.viaCount,
                    labelCount: result.labelCount,
                    netCount: result.netCount
                )
            }
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteCandidatePlanExecutorTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
