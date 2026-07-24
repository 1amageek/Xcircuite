import Foundation
import CircuiteFoundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func persistRejectedPlanIfNeeded(
        status: String,
        verification: XcircuitePlanVerification,
        candidatePlanRef: ArtifactReference,
        verificationRef: ArtifactReference,
        projectRoot: URL
    ) async throws -> ArtifactReference? {
        guard status == "rejected" || status == "blocked" else {
            return nil
        }
        let record = XcircuiteRejectedPlanRecord(
            rejectionID: rejectedPlanIdentifier(verification: verification, status: status),
            runID: verification.runID,
            problemID: verification.problemID,
            planID: verification.planID,
            verificationMode: verification.verificationMode,
            status: status,
            sourceParameterCandidateIDs: try await sourceParameterCandidateIDs(from: verification),
            failedStepIDs: verification.stepResults
                .filter { $0.status == "failed" || $0.status == "blocked" }
                .map(\.stepID),
            failedGateIDs: verification.gateResults
                .filter { $0.status == "failed" || $0.status == "blocked" }
                .map(\.gateID),
            candidatePlanRef: candidatePlanRef,
            planVerificationRef: verificationRef,
            artifactRefs: verification.artifactRefs,
            diagnostics: verification.diagnostics,
            diagnosticClassifications: XcircuiteRejectedPlanDiagnosticClassifier().classify(
                verification: verification,
                status: status
            ),
            nextActions: verification.nextActions
        )
        return try await artifactStore.appendRejectedPlan(
            record,
            runID: verification.runID,
            projectRoot: projectRoot
        )
    }

    func rejectedPlanIdentifier(
        verification: XcircuitePlanVerification,
        status: String
    ) -> String {
        "\(verification.runID)-\(verification.planID)-\(verification.verificationMode)-\(status)"
    }

    func sourceParameterCandidateIDs(
        from verification: XcircuitePlanVerification
    ) async throws -> [String] {
        let artifactReferences = verification.artifactRefs
        var ids: [String] = []
        for reference in artifactReferences {
            guard reference.id.rawValue.hasSuffix("-netlist-parameter-edit-report") else {
                continue
            }
            let report: XcircuiteNetlistParameterEditReport = try await decodeRetainedArtifact(
                reference,
                as: XcircuiteNetlistParameterEditReport.self
            )
            if let sourceParameterCandidateID = report.sourceParameterCandidateID {
                ids.append(sourceParameterCandidateID)
            }
        }
        return unique(ids.filter { !$0.isEmpty })
    }

    func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    func appendActionRecord(
        verification: XcircuitePlanVerification,
        candidatePlanRef: ArtifactReference,
        verificationRef: ArtifactReference
    ) async throws {
        let actionStatus: FlowRunActionStatus
        switch verificationStatus(for: verification) {
        case "accepted":
            actionStatus = .succeeded
        case "blocked":
            actionStatus = .blocked
        case "rejected":
            actionStatus = .failed
        default:
            actionStatus = .partial
        }
        let diagnostics = verification.diagnostics.map {
            FlowRunDiagnostic(
                severity: runActionSeverity($0.severity),
                code: $0.code,
                message: $0.message
            )
        }
        let actionID = "\(verification.planID)-\(candidatePlanRef.digest.hexadecimalValue)-"
            + "\(verificationRef.digest.hexadecimalValue)-verification"
        try await appendIdempotentVerificationAction(
            actionID: actionID,
            runID: verification.runID,
            status: actionStatus,
            inputs: [candidatePlanRef],
            outputs: [verificationRef],
            diagnostics: diagnostics
        )
    }

    private func appendIdempotentVerificationAction(
        actionID: String,
        runID: String,
        status: FlowRunActionStatus,
        inputs: [ArtifactReference],
        outputs: [ArtifactReference],
        diagnostics: [FlowRunDiagnostic]
    ) async throws {
        let existing = try await workspaceStore.loadRunActions(runID: runID).first {
            $0.actionID == actionID
        }
        let action = verificationAction(
            actionID: actionID,
            runID: runID,
            status: status,
            inputs: inputs,
            outputs: outputs,
            diagnostics: diagnostics,
            createdAt: existing?.createdAt ?? Date()
        )
        if let existing {
            guard existing == action else {
                throw FlowRunLedgerPersistenceError.duplicateActionID(
                    runID: runID,
                    actionID: actionID
                )
            }
            return
        }
        do {
            try await workspaceStore.appendRunAction(action)
        } catch let persistenceError as FlowRunLedgerPersistenceError {
            switch persistenceError {
            case .duplicateActionID, .concurrentUpdate:
                break
            default:
                throw persistenceError
            }
            let concurrentlyAppended = try await workspaceStore.loadRunActions(runID: runID).first {
                $0.actionID == actionID
            }
            guard let concurrentlyAppended,
                  concurrentlyAppended == verificationAction(
                    actionID: actionID,
                    runID: runID,
                    status: status,
                    inputs: inputs,
                    outputs: outputs,
                    diagnostics: diagnostics,
                    createdAt: concurrentlyAppended.createdAt
                  ) else {
                throw persistenceError
            }
        }
    }

    private func verificationAction(
        actionID: String,
        runID: String,
        status: FlowRunActionStatus,
        inputs: [ArtifactReference],
        outputs: [ArtifactReference],
        diagnostics: [FlowRunDiagnostic],
        createdAt: Date
    ) -> FlowRunActionRecord {
        FlowRunActionRecord(
            actionID: actionID,
            runID: runID,
            actor: FlowRunActor(kind: .cli, identifier: "xcircuite-flow"),
            actionKind: "planning.verify-candidate-plan",
            status: status,
            inputs: inputs,
            outputs: outputs,
            diagnostics: diagnostics,
            createdAt: createdAt
        )
    }

    func runActionSeverity(_ severity: String) -> FlowRunDiagnosticSeverity {
        switch severity {
        case "info":
            return .info
        case "warning":
            return .warning
        default:
            return .error
        }
    }

    func loadRunManifest(runID: String) async throws -> FlowRunManifest {
        try await workspaceStore.loadRunManifest(runID: runID)
    }

    func loadPlanningProblem(
        for plan: XcircuiteCandidatePlan,
        manifest: FlowRunManifest
    ) async throws -> XcircuiteCircuitPlanningProblem? {
        guard plan.sourceProblemRef.path != nil || plan.sourceProblemRef.artifactID != nil else {
            return nil
        }
        let reference = try await requiredSourceProblemReference(
            plan.sourceProblemRef,
            manifest: manifest,
            runID: plan.runID
        )
        let problem: XcircuiteCircuitPlanningProblem = try await decodeRetainedArtifact(
            reference,
            as: XcircuiteCircuitPlanningProblem.self
        )
        guard problem.runID == plan.runID else {
            throw XcircuiteCandidatePlanVerificationError.runMismatch(
                expected: plan.runID,
                actual: problem.runID
            )
        }
        return problem
    }

    func decodeRetainedArtifact<Value: Decodable>(
        _ reference: ArtifactReference,
        as type: Value.Type
    ) async throws -> Value {
        let content: Data
        do {
            content = try await workspaceStore.loadArtifactContent(for: reference)
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteCandidatePlanVerificationError.artifactIntegrityFailed(
                path: reference.path,
                status: .unreadableArtifact,
                message: error.localizedDescription
            )
        }
        do {
            return try JSONDecoder().decode(type, from: content)
        } catch {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactPayload(
                path: reference.path,
                reason: error.localizedDescription
            )
        }
    }

    func requiredSourceProblemReference(
        _ source: XcircuitePlanningReference,
        manifest: FlowRunManifest,
        runID: String
    ) async throws -> ArtifactReference {
        let ledger = try await workspaceStore.loadRunLedger(runID: runID)
        let retained = Set(manifest.artifacts + ledger.actions.flatMap(\.outputs))
        let matches = retained.filter { reference in
            let pathMatches = source.path.map { reference.path == $0 } ?? true
            let identifierMatches = source.artifactID.map { reference.artifactID == $0 } ?? true
            return pathMatches && identifierMatches
        }
        guard matches.count == 1, let reference = matches.first else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: source.path ?? source.artifactID ?? source.refID,
                reason: "source planning problem must resolve to exactly one retained artifact; found \(matches.count)."
            )
        }
        guard reference.locator.format == .json else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "source planning problem must be a retained JSON artifact."
            )
        }
        let runPrefix = ".xcircuite/runs/\(runID)/"
        guard reference.path.hasPrefix(runPrefix) else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "source planning problem is not scoped to run \(runID)."
            )
        }
        return reference
    }

    func validatedRiskApprovals(
        in ledger: FlowRunLedger,
        for plan: XcircuiteCandidatePlan,
        candidatePlanReference: ArtifactReference
    ) async throws -> [FlowApprovalRecord] {
        let requiredApprovalIDs = Set(
            plan.riskClassifications.flatMap(\.requiredApprovals)
        )
        guard !requiredApprovalIDs.isEmpty else {
            return []
        }
        var approvalsByID: [String: FlowApprovalRecord] = [:]
        for approval in ledger.approvals where requiredApprovalIDs.contains(approval.stageID) {
            guard approvalsByID.updateValue(approval, forKey: approval.stageID) == nil else {
                throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                    "Multiple approval records exist for \(approval.stageID)."
                )
            }
        }
        guard !approvalsByID.isEmpty else {
            return []
        }

        let currentVerificationReference = try await currentPlanVerificationReference(
            in: ledger,
            for: plan,
            candidatePlanReference: candidatePlanReference
        )
        var validated: [FlowApprovalRecord] = []
        for approvalID in requiredApprovalIDs.sorted() {
            guard let approval = approvalsByID[approvalID] else {
                continue
            }
            guard approval.runID == plan.runID,
                  approval.evidence.plan == candidatePlanReference,
                  approval.evidence.stageResult == currentVerificationReference else {
                throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                    "Approval \(approvalID) is not bound to the current candidate plan and its current verification."
                )
            }
            let expectedInputs = Set([
                approval.evidence.plan,
                approval.evidence.stageResult,
            ])
            let expectedActionStatus: FlowRunActionStatus = approval.verdict == .approved
                ? .succeeded
                : .failed
            let approvalActions = ledger.actions.filter { action in
                action.runID == plan.runID
                    && action.stageID == approvalID
                    && action.actionKind == "planning.approve-candidate-plan-risk"
                    && action.status == expectedActionStatus
                    && action.inputs.count == expectedInputs.count
                    && Set(action.inputs) == expectedInputs
                    && action.outputs.count == 1
                    && action.outputs.allSatisfy { output in
                        output.artifactID == "approval-\(approvalID)"
                            && output.locator.role == .output
                            && output.locator.kind == .report
                            && output.locator.format == .json
                            && output.path == ".xcircuite/runs/\(plan.runID)/approvals/\(approvalID).json"
                    }
            }
            guard approvalActions.count == 1 else {
                throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                    "Approval \(approvalID) must have exactly one attested action-artifact binding; found \(approvalActions.count)."
                )
            }
            let approvalArtifact = approvalActions[0].outputs[0]
            let retainedApproval: FlowApprovalRecord = try await decodeRetainedArtifact(
                approvalArtifact,
                as: FlowApprovalRecord.self
            )
            guard retainedApproval == approval else {
                throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
                    "Approval \(approvalID) projection does not match its retained approval artifact."
                )
            }
            validated.append(approval)
        }
        return validated
    }

    private func currentPlanVerificationReference(
        in ledger: FlowRunLedger,
        for plan: XcircuiteCandidatePlan,
        candidatePlanReference: ArtifactReference
    ) async throws -> ArtifactReference {
        let retained = Set(ledger.artifacts + ledger.actions.flatMap(\.outputs))
        var matchingReferences: Set<ArtifactReference> = []
        for reference in retained where
            reference.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID {
            let verification: XcircuitePlanVerification = try await decodeRetainedArtifact(
                reference,
                as: XcircuitePlanVerification.self
            )
            if verification.runID == plan.runID,
               verification.planID == plan.planID,
               verification.problemID == plan.problemID,
               verification.candidatePlanRef == candidatePlanReference,
               verification.artifactRefs.contains(candidatePlanReference) {
                matchingReferences.insert(reference)
            }
        }
        for action in ledger.actions.reversed() where
            action.actionKind == "planning.verify-candidate-plan" {
            if let reference = action.outputs.first(where: matchingReferences.contains) {
                return reference
            }
        }
        throw XcircuiteCandidatePlanVerificationError.stalePlanVerification(
            "No action-bound plan verification matches the current candidate plan."
        )
    }

    func loadOrPersistActionDomainSnapshot(
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) async throws -> ActionDomainSnapshotContext {
        let resolved = try await XcircuiteActionDomainSnapshotResolver(
            workspaceStore: workspaceStore,
            artifactStore: artifactStore
        ).loadDefaultOrPersist(
            manifest: manifest,
            runID: runID,
            projectRoot: projectRoot
        )
        return ActionDomainSnapshotContext(snapshot: resolved.snapshot, reference: resolved.reference)
    }

    func requiredCandidatePlanReference(
        explicitPath: String?,
        artifactID: String?,
        manifest: FlowRunManifest,
        runID: String,
        projectRoot: URL
    ) throws -> ArtifactReference {
        if let explicitPath {
            let matches = manifest.artifacts.filter { $0.path == explicitPath }
            guard matches.count <= 1 else {
                throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                    path: explicitPath,
                    reason: "multiple manifest artifacts reference the same explicit path."
                )
            }
            let reference = try matches.first ?? artifactBuilder.reference(
                for: projectURL(for: explicitPath, projectRoot: projectRoot),
                projectRoot: projectRoot,
                artifactID: artifactID ?? XcircuitePlanningArtifactStore.candidatePlanArtifactID,
                kind: .other,
                format: .json
            )
            try validateCandidatePlanReference(
                reference,
                expectedArtifactID: artifactID,
                runID: runID,
                projectRoot: projectRoot
            )
            return reference
        }
        guard let artifactID else {
            throw XcircuiteCandidatePlanVerificationError.missingCandidatePlanReference
        }
        let matches = manifest.artifacts.filter { $0.artifactID == artifactID }
        guard !matches.isEmpty else {
            throw XcircuiteCandidatePlanVerificationError.artifactNotFound(runID: runID, artifactID: artifactID)
        }
        guard matches.count == 1 else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: artifactID,
                reason: "run manifest contains \(matches.count) artifacts with the same artifact ID."
            )
        }
        let reference = matches[0]
        try validateCandidatePlanReference(
            reference,
            expectedArtifactID: artifactID,
            runID: runID,
            projectRoot: projectRoot
        )
        return reference
    }

    private func validateCandidatePlanReference(
        _ reference: ArtifactReference,
        expectedArtifactID: String?,
        runID: String,
        projectRoot: URL
    ) throws {
        if let expectedArtifactID, reference.artifactID != expectedArtifactID {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "artifactID does not match requested \(expectedArtifactID)."
            )
        }
        guard reference.kind == .other, reference.format == .json else {
            throw XcircuiteCandidatePlanVerificationError.invalidArtifactReference(
                path: reference.path,
                reason: "candidate plans must be JSON artifacts."
            )
        }
        let integrity = artifactVerifier.verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteCandidatePlanVerificationError.artifactIntegrityFailed(
                path: reference.path,
                status: integrity.flowVerificationStatus,
                message: integrity.diagnosticMessage
            )
        }
    }
}
