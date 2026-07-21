import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

extension XcircuiteWorkspaceStore: FlowRunInfrastructure, FlowRunLedgerPersisting, FlowRunReviewLedgerLoading, FlowRunActionArtifactPersisting, FlowRunApprovalArtifactPersisting, ToolQualificationArtifactReading {
    public func verifyArtifact(
        _ reference: ArtifactReference
    ) async -> ArtifactIntegrity {
        LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
    }

    public func verifiedData(for reference: ArtifactReference) async throws -> Data {
        try ensureWorkspace()
        return try await loadArtifactContent(for: reference)
    }

    public func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        try await loadAttestedRunLedger(runID: runID)
    }

    public func loadRunLedgerForReview(runID: String) async throws -> FlowRunLedger {
        try loadRunLedgerMetadata(runID: runID)
    }

    /// Loads a run ledger and verifies every retained artifact against its
    /// recorded digest and byte count.
    ///
    /// Routine lifecycle updates use `loadRunLedger(runID:)` so an unrelated
    /// replaceable artifact cannot make metadata I/O observe a half-completed
    /// replacement. Resume, release, and explicit audit paths call this method
    /// when whole-run attestation is required.
    public func loadAttestedRunLedger(runID: String) async throws -> FlowRunLedger {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        do {
            guard fileManager.fileExists(atPath: workspaceRoot.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let lockURL = workspaceRoot.appending(path: ".workspace.lock")
            return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
                try transactionCoordinator.recoverPendingTransactions()
                let ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: readWorkspaceContent(
                        relativePath: ledgerRelativePath(for: runID)
                    )
                )
                guard ledger.runID == runID else {
                    throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                        requested: runID,
                        stored: ledger.runID
                    )
                }
                try validateLedgerProjection(ledger, requestedRunID: runID)
                try verifyRetainedArtifacts(in: ledger)
                try verifyDecisionProjections(for: ledger)
                return ledger
            }
        } catch let error as FlowRunLedgerPersistenceError {
            throw error
        } catch XcircuiteWorkspaceStoreError.missingArtifact {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        } catch XcircuiteWorkspaceStoreError.artifactIntegrityFailed(let path, let issues) {
            throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                path: path,
                reason: issues.map { $0.code.rawValue }.joined(separator: ",")
            )
        } catch {
            throw FlowRunLedgerPersistenceError.storageFailed(error.localizedDescription)
        }
    }

    /// Loads run manifest metadata without attesting every retained artifact.
    ///
    /// Consumers must verify each artifact reference before reading its content.
    /// Use `loadAttestedRunLedger(runID:)` when full retained-artifact attestation is
    /// required, such as resume, approval, and release authorization.
    public func loadRunManifest(runID: String) throws -> FlowRunManifest {
        try loadRunLedgerMetadata(runID: runID).runManifest
    }

    /// Loads approval metadata without attesting unrelated retained artifacts.
    /// Approval consumers must verify any evidence references they use.
    public func loadRunApprovals(runID: String) throws -> [FlowApprovalRecord] {
        try loadRunLedgerMetadata(runID: runID).approvals
    }

    private func loadRunLedgerMetadata(runID: String) throws -> FlowRunLedger {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        do {
            guard fileManager.fileExists(atPath: workspaceRoot.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let lockURL = workspaceRoot.appending(path: ".workspace.lock")
            return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
                try transactionCoordinator.recoverPendingTransactions()
                let ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: readWorkspaceContent(relativePath: ledgerRelativePath(for: runID))
                )
                guard ledger.runID == runID else {
                    throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                        requested: runID,
                        stored: ledger.runID
                    )
                }
                try validateLedgerProjection(ledger, requestedRunID: runID)
                return ledger
            }
        } catch let error as FlowRunLedgerPersistenceError {
            throw error
        } catch XcircuiteWorkspaceStoreError.missingArtifact {
            throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
        } catch {
            throw FlowRunLedgerPersistenceError.storageFailed(error.localizedDescription)
        }
    }

    private func validateLedgerProjection(
        _ ledger: FlowRunLedger,
        requestedRunID: String
    ) throws {
        guard ledger.runID == requestedRunID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: requestedRunID,
                stored: ledger.runID
            )
        }
        guard ledger.runManifest.runID == ledger.runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: ledger.runID,
                stored: ledger.runManifest.runID
            )
        }
        let ledgerArtifacts = Set(ledger.artifacts)
        let embeddedManifestArtifacts = Set(ledger.runManifest.artifacts)
        guard ledgerArtifacts == embeddedManifestArtifacts else {
            throw FlowRunLedgerPersistenceError.decodingFailed(
                "Run ledger and embedded manifest contain different artifact sets for \(requestedRunID)."
            )
        }
        let manifestPath = runManifestRelativePath(for: requestedRunID)
        let manifestURL = try workspaceURL(relativePath: manifestPath)
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw FlowRunLedgerPersistenceError.decodingFailed(
                "Canonical run manifest is missing for \(requestedRunID)."
            )
        }
        let manifest: FlowRunManifest
        do {
            manifest = try JSONDecoder().decode(
                FlowRunManifest.self,
                from: Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            )
        } catch let error as FlowRunLedgerPersistenceError {
            throw error
        } catch {
            throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
        }
        guard manifest == ledger.runManifest else {
            throw FlowRunLedgerPersistenceError.decodingFailed(
                "Canonical and embedded run manifests differ for \(requestedRunID)."
            )
        }
        if ledger.runManifest.status.isTerminal {
            guard let evidence = ledger.evidence,
                  Set(evidence.artifacts) == ledgerArtifacts,
                  evidence.artifacts.count == ledger.artifacts.count else {
                throw FlowRunLedgerPersistenceError.invalidTerminalProjection(
                    runID: requestedRunID,
                    issue: .unexpectedDecisionProjectionMutation
                )
            }
        }
    }

    private func verifyRetainedArtifacts(in ledger: FlowRunLedger) throws {
        let references = Set(
            ledger.artifacts + ledger.actions.flatMap(\.outputs)
        )
        for reference in references {
            let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
            guard integrity.isVerified else {
                throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                    path: reference.path,
                    reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                )
            }
        }
    }

    public func createRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        try await persistRunLedger(ledger, requireNew: true)
    }

    @discardableResult
    public func saveRunLedger(_ ledger: FlowRunLedger) async throws -> FlowRunLedger {
        try await persistRunLedger(ledger, requireNew: false)
    }

    private func persistRunLedger(
        _ ledger: FlowRunLedger,
        requireNew: Bool
    ) async throws -> FlowRunLedger {
        guard ledger.runManifest.runID == ledger.runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: ledger.runID,
                stored: ledger.runManifest.runID
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let path = ledgerRelativePath(for: ledger.runID)
        try createWorkspace()
        try ensureWorkspaceDirectory(at: ".xcircuite/runs/\(ledger.runID)")
        let ledgerURL = try workspaceURL(relativePath: path)
        return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: workspaceRoot.appending(path: ".workspace.lock")) {
            try transactionCoordinator.recoverPendingTransactions()
            let currentData = fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false))
                ? try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
                : nil
            let current: FlowRunLedger?
            if let currentData {
                do {
                    current = try JSONDecoder().decode(FlowRunLedger.self, from: currentData)
                    if let current {
                        try validateLedgerProjection(current, requestedRunID: ledger.runID)
                    }
                } catch {
                    if let error = error as? FlowRunLedgerPersistenceError {
                        throw error
                    }
                    throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
                }
            } else {
                current = nil
            }
            if requireNew, current != nil {
                throw FlowRunLedgerPersistenceError.runAlreadyExists(runID: ledger.runID)
            }
            if let current, current != ledger {
                let expectedRevision = current.runManifest.revision + 1
                guard ledger.runManifest.revision == expectedRevision else {
                    throw FlowRunLedgerPersistenceError.concurrentUpdate(
                        runID: ledger.runID,
                        expectedRevision: expectedRevision,
                        actualRevision: ledger.runManifest.revision
                    )
                }
            } else if current == nil, ledger.runManifest.revision != 0 {
                throw FlowRunLedgerPersistenceError.concurrentUpdate(
                    runID: ledger.runID,
                    expectedRevision: 0,
                    actualRevision: ledger.runManifest.revision
                )
            }
            if let current {
                try validateRetainedArtifactLineage(
                    current: current,
                    proposed: ledger
                )
            }

            var storedLedger = ledger
            let projections = try prepareDecisionProjections(
                for: storedLedger,
                encoder: encoder
            )
            storedLedger.artifacts.sort(by: artifactReferenceOrder)
            if let evidence = storedLedger.evidence {
                guard Set(evidence.artifacts) == Set(storedLedger.artifacts),
                      evidence.artifacts.count == storedLedger.artifacts.count else {
                    throw FlowRunLedgerPersistenceError.invalidEvidenceProjection(
                        runID: storedLedger.runID,
                        issue: .evidenceArtifactInventoryMismatch
                    )
                }
                let provenance = evidence.provenance
                let sortedInputs = provenance.inputs.sorted(by: artifactReferenceOrder)
                let sortedSupportingTools = provenance.supportingTools.sorted {
                    ($0.kind.rawValue, $0.identifier, $0.version, $0.build ?? "")
                        < ($1.kind.rawValue, $1.identifier, $1.version, $1.build ?? "")
                }
                let normalizedProvenance = try ExecutionProvenance(
                    producer: provenance.producer,
                    supportingTools: sortedSupportingTools,
                    inputs: sortedInputs,
                    invocation: provenance.invocation,
                    environment: provenance.environment,
                    configurationDigest: provenance.configurationDigest,
                    designRevision: provenance.designRevision,
                    randomSeed: provenance.randomSeed,
                    startedAt: provenance.startedAt,
                    completedAt: provenance.completedAt
                )
                storedLedger.evidence = EvidenceManifest(
                    schemaVersion: evidence.schemaVersion,
                    provenance: normalizedProvenance,
                    artifacts: storedLedger.artifacts
                )
            } else if storedLedger.runManifest.status.isTerminal {
                throw FlowRunLedgerPersistenceError.invalidTerminalProjection(
                    runID: storedLedger.runID,
                    issue: .evidenceArtifactInventoryMismatch
                )
            }
            storedLedger.runManifest = try FlowRunManifest(
                runID: storedLedger.runManifest.runID,
                status: storedLedger.runManifest.status,
                revision: storedLedger.runManifest.revision,
                actor: storedLedger.runManifest.actor,
                intent: storedLedger.runManifest.intent,
                parentRunID: storedLedger.runManifest.parentRunID,
                createdAt: storedLedger.runManifest.createdAt,
                updatedAt: storedLedger.runManifest.updatedAt,
                startedAt: storedLedger.runManifest.startedAt,
                finishedAt: storedLedger.runManifest.finishedAt,
                artifacts: storedLedger.artifacts
            )

            let actionIDs = storedLedger.actions.map(\.actionID)
            var seenActionIDs: Set<String> = []
            if let duplicate = actionIDs.first(where: {
                !seenActionIDs.insert($0).inserted
            }) {
                throw FlowRunLedgerPersistenceError.duplicateActionID(
                    runID: storedLedger.runID,
                    actionID: duplicate
                )
            }
            let retainedReferences = Set(
                storedLedger.artifacts + storedLedger.actions.flatMap(\.outputs)
            )
            if let unretained = storedLedger.actions
                .flatMap({ $0.inputs })
                .first(where: { !retainedReferences.contains($0) }) {
                throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                    runID: storedLedger.runID,
                    path: unretained.path
                )
            }
            try verifyRetainedArtifacts(in: storedLedger)

            let currentArtifacts = Set(current?.artifacts ?? [])
            let referencesToVerify = storedLedger.artifacts.filter { reference in
                return storedLedger.runManifest.status.isTerminal
                    || !currentArtifacts.contains(reference)
            }
            for reference in referencesToVerify {
                let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
                guard integrity.isVerified else {
                    throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                        path: reference.path,
                        reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                    )
                }
            }
            let projectManifestOperation = try projectManifestOperation(
                registering: storedLedger.runID,
                encoder: encoder
            )
            let storedLedgerData = try encoder.encode(storedLedger)
            let persistedLedger = try JSONDecoder().decode(
                FlowRunLedger.self,
                from: storedLedgerData
            )
            let operations = projections.map(\.operation) + [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: runManifestRelativePath(for: storedLedger.runID),
                    content: try encoder.encode(storedLedger.runManifest)
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: path,
                    content: storedLedgerData
                ),
                projectManifestOperation,
            ]
            try transactionCoordinator.commit(operations, fault: transactionFault)
            return persistedLedger
        }
    }

    func appendRunActionAtomically(_ action: FlowRunActionRecord) throws -> FlowRunLedger {
        let runID = action.runID
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        if let stageID = action.stageID {
            try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        }
        try ensureWorkspace()
        let path = ledgerRelativePath(for: runID)
        let ledgerURL = try workspaceURL(relativePath: path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        return try XcircuiteWorkspaceFileLock.withExclusiveLock(
            at: workspaceRoot.appending(path: ".workspace.lock")
        ) {
            try transactionCoordinator.recoverPendingTransactions()
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let data = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
            var ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(FlowRunLedger.self, from: data)
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            try verifyRetainedArtifacts(in: ledger)
            try verifyDecisionProjections(for: ledger)
            let reduced = try FlowRunActionReducer().appending(action, to: ledger)
            if reduced == ledger {
                return ledger
            }
            ledger = reduced
            let previousManifest = ledger.runManifest
            ledger.runManifest = try FlowRunManifest(
                runID: previousManifest.runID,
                status: previousManifest.status,
                revision: previousManifest.revision + 1,
                actor: previousManifest.actor,
                intent: previousManifest.intent,
                parentRunID: previousManifest.parentRunID,
                createdAt: previousManifest.createdAt,
                updatedAt: max(Date(), previousManifest.updatedAt),
                startedAt: previousManifest.startedAt,
                finishedAt: previousManifest.finishedAt,
                artifacts: previousManifest.artifacts
            )

            let projections = try prepareDecisionProjections(for: ledger, encoder: encoder)
            let projectManifestOperation = try projectManifestOperation(
                registering: runID,
                encoder: encoder
            )
            let ledgerData = try encoder.encode(ledger)
            let operations = projections.map(\.operation) + [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: runManifestRelativePath(for: runID),
                    content: try encoder.encode(ledger.runManifest)
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: path,
                    content: ledgerData
                ),
                projectManifestOperation,
            ]
            try transactionCoordinator.commit(operations, fault: transactionFault)
            return try JSONDecoder().decode(FlowRunLedger.self, from: ledgerData)
        }
    }

    /// Atomically replaces a mutable project artifact and appends the action
    /// that audits that exact change. Recovery always completes both writes,
    /// so the design source and run ledger cannot diverge after interruption.
    public func appendRunAction(
        _ action: FlowRunActionRecord,
        replacingProjectArtifactAt projectRelativePath: String,
        expectedContent: Data,
        replacementContent: Data
    ) async throws -> FlowRunLedger {
        let runID = action.runID
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        if let stageID = action.stageID {
            try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        }
        try XcircuiteWorkspaceLayout.validateProjectRelativePath(projectRelativePath)
        guard projectRelativePath.hasPrefix(".xcircuite/") == false else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(projectRelativePath)
        }
        let targetLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: projectRelativePath),
            role: .input,
            kind: .other,
            format: .unknown
        )
        let targetURL = try rawProjectArtifactURL(for: targetLocator)
        try ensureWorkspace()
        let ledgerPath = ledgerRelativePath(for: runID)
        let ledgerURL = try workspaceURL(relativePath: ledgerPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        return try XcircuiteWorkspaceFileLock.withExclusiveLock(
            at: workspaceRoot.appending(path: ".workspace.lock")
        ) {
            try transactionCoordinator.recoverPendingTransactions()
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            guard fileManager.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
                throw XcircuiteWorkspaceStoreError.missingArtifact(projectRelativePath)
            }
            let currentContent = try Data(contentsOf: targetURL, options: [.mappedIfSafe])
            let ledgerData = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
            var ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(FlowRunLedger.self, from: ledgerData)
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            try verifyRetainedArtifacts(in: ledger)
            try verifyDecisionProjections(for: ledger)

            if let existing = ledger.actions.first(where: { $0.actionID == action.actionID }) {
                guard existing == action, currentContent == replacementContent else {
                    throw FlowRunLedgerPersistenceError.duplicateActionID(
                        runID: runID,
                        actionID: action.actionID
                    )
                }
                return ledger
            }
            guard currentContent == expectedContent else {
                throw XcircuiteWorkspaceStoreError.projectArtifactChanged(projectRelativePath)
            }
            ledger = try FlowRunActionReducer().appending(action, to: ledger)
            let previousManifest = ledger.runManifest
            ledger.runManifest = try FlowRunManifest(
                runID: previousManifest.runID,
                status: previousManifest.status,
                revision: previousManifest.revision + 1,
                actor: previousManifest.actor,
                intent: previousManifest.intent,
                parentRunID: previousManifest.parentRunID,
                createdAt: previousManifest.createdAt,
                updatedAt: max(Date(), previousManifest.updatedAt),
                startedAt: previousManifest.startedAt,
                finishedAt: previousManifest.finishedAt,
                artifacts: previousManifest.artifacts
            )

            let projections = try prepareDecisionProjections(for: ledger, encoder: encoder)
            let projectManifestOperation = try projectManifestOperation(
                registering: runID,
                encoder: encoder
            )
            let updatedLedgerData = try encoder.encode(ledger)
            let operations = projections.map(\.operation) + [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: projectRelativePath,
                    content: replacementContent
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: runManifestRelativePath(for: runID),
                    content: try encoder.encode(ledger.runManifest)
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: ledgerPath,
                    content: updatedLedgerData
                ),
                projectManifestOperation,
            ]
            try transactionCoordinator.commit(operations, fault: transactionFault)
            return try JSONDecoder().decode(FlowRunLedger.self, from: updatedLedgerData)
        }
    }

    public func appendActionArtifact(
        content: Data,
        reference: ArtifactReference,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        try appendActionOwnedArtifact(
            content: content,
            reference: reference,
            approval: nil,
            action: action
        )
    }

    public func appendApprovalArtifact(
        content: Data,
        reference: ArtifactReference,
        approval: FlowApprovalRecord,
        action: FlowRunActionRecord
    ) async throws -> FlowRunLedger {
        try appendActionOwnedArtifact(
            content: content,
            reference: reference,
            approval: approval,
            action: action
        )
    }

    private func appendActionOwnedArtifact(
        content: Data,
        reference: ArtifactReference,
        approval: FlowApprovalRecord?,
        action: FlowRunActionRecord
    ) throws -> FlowRunLedger {
        let runID = action.runID
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        if let stageID = action.stageID {
            try FlowIdentifierValidator().validate(stageID, kind: .stageID)
        }
        guard approval?.runID == nil || approval?.runID == runID else {
            throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                requested: runID,
                stored: approval?.runID ?? ""
            )
        }
        let persistedLocator = try projectRelativeLocator(from: reference.locator)
        let path = try projectRelativePath(for: persistedLocator)
        let prefix = ".xcircuite/runs/\(runID)/"
        guard path.hasPrefix(prefix),
              persistedLocator.role == .output else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: path
            )
        }
        let relativePath = String(path.dropFirst(prefix.count))
        let isActionOwnedPath = relativePath.hasPrefix("approvals/")
            || relativePath.hasPrefix("review/")
            || relativePath.hasPrefix("actions/")
            || relativePath.hasPrefix("release/")
            || relativePath.hasPrefix("qualification/")
            || relativePath.hasPrefix("loop/")
            || relativePath.hasPrefix("reports/")
        guard isActionOwnedPath else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: path
            )
        }
        let expectedReference = ArtifactReference(
            id: reference.id,
            locator: persistedLocator,
            digest: try SHA256ContentDigester().digest(data: content, using: .sha256),
            byteCount: UInt64(content.count),
            producer: reference.producer
        )
        guard expectedReference == reference,
              action.outputs.contains(reference) else {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: path
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let approval {
            let canonicalApprovalPath = ".xcircuite/runs/\(runID)/approvals/\(approval.stageID).json"
            let canonicalApprovalContent = try encoder.encode(approval)
            let reviewedEvidence = Set([
                approval.evidence.plan,
                approval.evidence.stageResult,
            ])
            guard action.stageID == approval.stageID,
                  path == canonicalApprovalPath,
                  reference.id.rawValue == "approval-\(approval.stageID)",
                  persistedLocator.kind == .report,
                  persistedLocator.format == .json,
                  reviewedEvidence.isSubset(of: Set(action.inputs)),
                  content == canonicalApprovalContent else {
                throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                    runID: runID,
                    path: path
                )
            }
        } else if relativePath.hasPrefix("approvals/") {
            throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                runID: runID,
                path: path
            )
        }

        try ensureWorkspace()
        let ledgerPath = ledgerRelativePath(for: runID)
        let ledgerURL = try workspaceURL(relativePath: ledgerPath)
        let destination = try rawProjectArtifactURL(for: persistedLocator)
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")
        return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            try transactionCoordinator.recoverPendingTransactions()
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            var ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
                )
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            try verifyRetainedArtifacts(in: ledger)
            try verifyDecisionProjections(for: ledger)

            if let existingAction = ledger.actions.first(where: { $0.actionID == action.actionID }) {
                let approvalMatches = approval.map { ledger.approvals.contains($0) } ?? true
                guard existingAction == action,
                      approvalMatches,
                      fileManager.fileExists(atPath: destination.path(percentEncoded: false)),
                      try Data(contentsOf: destination, options: [.mappedIfSafe]) == content else {
                    throw FlowRunLedgerPersistenceError.duplicateActionID(
                        runID: runID,
                        actionID: action.actionID
                    )
                }
                return ledger
            }
            if let approval,
               ledger.approvals.contains(where: { $0.stageID == approval.stageID }) {
                throw FlowRunLedgerPersistenceError.duplicateApprovalID(
                    runID: runID,
                    approvalID: approval.stageID
                )
            }
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard existing == content else {
                    throw XcircuiteWorkspaceStoreError.immutableArtifactConflict(path)
                }
            }
            let knownArtifacts = Set(
                ledger.artifacts + ledger.actions.flatMap { $0.outputs }
            )
            guard action.inputs.allSatisfy(knownArtifacts.contains),
                  action.outputs.allSatisfy({ $0 == reference || knownArtifacts.contains($0) }) else {
                throw FlowRunLedgerPersistenceError.actionArtifactBindingMismatch(
                    runID: runID,
                    path: path
                )
            }

            ledger.actions.append(action)
            if let selection = try FlowRunSuggestedActionSelection(record: action) {
                ledger.suggestedActionSelections.append(selection)
            }
            if let approval {
                ledger.approvals.append(approval)
            }
            let currentManifest = ledger.runManifest
            ledger.runManifest = try FlowRunManifest(
                runID: currentManifest.runID,
                status: currentManifest.status,
                revision: currentManifest.revision + 1,
                actor: currentManifest.actor,
                intent: currentManifest.intent,
                parentRunID: currentManifest.parentRunID,
                createdAt: currentManifest.createdAt,
                updatedAt: max(Date(), currentManifest.updatedAt),
                startedAt: currentManifest.startedAt,
                finishedAt: currentManifest.finishedAt,
                artifacts: currentManifest.artifacts
            )
            guard Set(ledger.artifacts) == Set(ledger.runManifest.artifacts) else {
                throw FlowRunLedgerPersistenceError.decodingFailed(
                    "Run ledger and updated manifest contain different artifact sets for \(runID)."
                )
            }
            if ledger.runManifest.status.isTerminal {
                guard let evidence = ledger.evidence,
                      Set(evidence.artifacts) == Set(ledger.artifacts),
                      evidence.artifacts.count == ledger.artifacts.count else {
                    throw FlowRunLedgerPersistenceError.invalidTerminalProjection(
                        runID: runID,
                        issue: .unexpectedDecisionProjectionMutation
                    )
                }
            }

            let projections = try prepareDecisionProjections(for: ledger, encoder: encoder)
            let projectionOperations = projections
                .map(\.operation)
                .filter { $0.projectRelativePath != path }
            let ledgerData = try encoder.encode(ledger)
            let operations = [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: path,
                    content: content
                ),
            ] + projectionOperations + [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: runManifestRelativePath(for: runID),
                    content: try encoder.encode(ledger.runManifest)
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: ledgerPath,
                    content: ledgerData
                ),
                try projectManifestOperation(registering: runID, encoder: encoder),
            ]
            try transactionCoordinator.commit(operations, fault: transactionFault)
            return try JSONDecoder().decode(FlowRunLedger.self, from: ledgerData)
        }
    }

    /// Makes every persisted run discoverable from the canonical project
    /// manifest. The update shares the ledger writer lock so concurrent stores
    /// cannot lose run registrations while appending independent runs.
    private func projectManifestOperation(
        registering runID: String,
        encoder: JSONEncoder
    ) throws -> XcircuiteWorkspaceTransaction.Operation {
        let projectManifestURL = XcircuiteWorkspaceLayout(projectRoot: projectRoot).manifestURL
        let data = try Data(contentsOf: projectManifestURL, options: [.mappedIfSafe])
        var projectManifest: XcircuiteProjectManifest
        do {
            projectManifest = try JSONDecoder().decode(XcircuiteProjectManifest.self, from: data)
        } catch {
            throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
        }

        let reference = FlowRunReference(
            runID: runID,
            manifestPath: XcircuiteProjectManifest.runManifestPath(for: runID)
        )
        projectManifest.runs.removeAll { $0.runID == runID }
        projectManifest.runs.append(reference)
        projectManifest.runs.sort { $0.runID < $1.runID }
        try projectManifest.validate()
        return XcircuiteWorkspaceTransaction.Operation(
            projectRelativePath: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)",
            content: try encoder.encode(projectManifest)
        )
    }

    private func prepareDecisionProjections(
        for ledger: FlowRunLedger,
        encoder: JSONEncoder
    ) throws -> [(reference: ArtifactReference, operation: XcircuiteWorkspaceTransaction.Operation)] {
        var projections: [(reference: ArtifactReference, operation: XcircuiteWorkspaceTransaction.Operation)] = []
        for approval in ledger.approvals {
            try FlowIdentifierValidator().validate(approval.stageID, kind: .stageID)
            let data = try encoder.encode(approval)
            let path = ".xcircuite/runs/\(ledger.runID)/approvals/\(approval.stageID).json"
            projections.append(try prepareLedgerProjection(
                data,
                id: "approval-\(approval.stageID)",
                path: path,
                format: .json
            ))
        }
        if !ledger.actions.isEmpty {
            var data = Data()
            for action in ledger.actions {
                data.append(try encoder.encode(action))
                data.append(0x0A)
            }
            projections.append(try prepareLedgerProjection(
                data,
                id: "action-ledger",
                path: ".xcircuite/runs/\(ledger.runID)/actions.jsonl",
                format: .text
            ))
        }
        return projections
    }

    private func verifyDecisionProjections(for ledger: FlowRunLedger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let projections = try prepareDecisionProjections(for: ledger, encoder: encoder)
        for projection in projections {
            let path = projection.operation.projectRelativePath
            let url = try rawProjectArtifactURL(for: projection.reference.locator)
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                    path: path,
                    reason: "missing"
                )
            }
            let actual = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard actual == projection.operation.content else {
                throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                    path: path,
                    reason: "decision-projection-mismatch"
                )
            }
        }
    }

    private func artifactReferenceOrder(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path < rhs.path
        }
        if lhs.locator.role.rawValue != rhs.locator.role.rawValue {
            return lhs.locator.role.rawValue < rhs.locator.role.rawValue
        }
        if lhs.locator.kind.rawValue != rhs.locator.kind.rawValue {
            return lhs.locator.kind.rawValue < rhs.locator.kind.rawValue
        }
        if lhs.locator.format.rawValue != rhs.locator.format.rawValue {
            return lhs.locator.format.rawValue < rhs.locator.format.rawValue
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private func prepareLedgerProjection(
        _ data: Data,
        id: String,
        path: String,
        format: ArtifactFormat
    ) throws -> (reference: ArtifactReference, operation: XcircuiteWorkspaceTransaction.Operation) {
        let locator = try locator(
            path: path,
            role: .output,
            kind: .report,
            format: format
        )
        _ = try rawProjectArtifactURL(for: locator)
        let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
        let reference = ArtifactReference(
            id: try ArtifactID(rawValue: id),
            locator: locator,
            digest: digest,
            byteCount: UInt64(data.count)
        )
        return (
            reference,
            XcircuiteWorkspaceTransaction.Operation(
                projectRelativePath: path,
                content: data
            )
        )
    }

    public func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        try persistRunArtifact(
            content: content,
            id: id,
            locator: locator,
            runID: runID,
            producer: nil,
            mode: mode,
            permitsRunControlPath: false
        ) { _ in }
    }

    public func persistArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        producer: ProducerIdentity,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        try persistRunArtifact(
            content: content,
            id: id,
            locator: locator,
            runID: runID,
            producer: producer,
            mode: mode,
            permitsRunControlPath: false
        ) { _ in }
    }

    public func persistRunControlArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode
    ) async throws -> ArtifactReference {
        try persistRunArtifact(
            content: content,
            id: id,
            locator: locator,
            runID: runID,
            producer: nil,
            mode: mode,
            permitsRunControlPath: true
        ) { _ in }
    }

    func persistRunArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        producer: ProducerIdentity?,
        mode: FlowArtifactPersistenceMode,
        permitsRunControlPath: Bool,
        updatingLedger updateLedger: (inout FlowRunLedger) throws -> Void
    ) throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let persistedLocator = try projectRelativeLocator(from: locator)
        let projectRelativePath = try projectRelativePath(for: persistedLocator)
        try validateRunArtifactPath(
            projectRelativePath,
            runID: runID,
            permitsRunControlPath: permitsRunControlPath
        )
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: digest,
            byteCount: UInt64(content.count),
            producer: producer
        )
        try persistRunArtifactTransaction(
            content: content,
            reference: reference,
            runID: runID,
            projectRelativePath: projectRelativePath,
            mode: mode,
            updatingLedger: updateLedger
        )
        return reference
    }

    public func loadArtifactContent(
        for reference: ArtifactReference
    ) async throws -> Data {
        guard reference.locator.location.storage == .workspaceRelative else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(
                reference.locator.location.value
            )
        }
        let path = reference.locator.location.value
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")
        do {
            return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
                let source = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
                let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                var issues: [ArtifactIntegrityIssue] = []
                let actualByteCount = UInt64(data.count)
                if actualByteCount != reference.byteCount {
                    issues.append(.byteCountMismatch(
                        expected: reference.byteCount,
                        actual: actualByteCount
                    ))
                }
                let actualDigest = try SHA256ContentDigester().digest(
                    data: data,
                    using: reference.digest.algorithm
                )
                if actualDigest != reference.digest {
                    issues.append(.digestMismatch(
                        expected: reference.digest,
                        actual: actualDigest
                    ))
                }
                guard issues.isEmpty else {
                    throw XcircuiteWorkspaceStoreError.artifactIntegrityFailed(
                        path: path,
                        issues: issues
                    )
                }
                return data
            }
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.readFailed(error.localizedDescription)
        }
    }

    public func loadArtifactContent(
        at locator: ArtifactLocator
    ) async throws -> Data? {
        let persistedLocator = try projectRelativeLocator(from: locator)
        let path = persistedLocator.location.value
        let source = try projectArtifactURL(for: persistedLocator)
        do {
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
                return nil
            }
            return try Data(contentsOf: source, options: [.mappedIfSafe])
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch CocoaError.fileNoSuchFile {
            return nil
        } catch {
            throw XcircuiteWorkspaceStoreError.readFailed("\(path): \(error.localizedDescription)")
        }
    }

    public func artifactExists(
        at locator: ArtifactLocator
    ) async throws -> Bool {
        let source = try projectArtifactURL(for: projectRelativeLocator(from: locator))
        return fileManager.fileExists(atPath: source.path(percentEncoded: false))
    }

    /// Loads a standard project artifact without remapping it into `.xcircuite`.
    public func loadProjectArtifactContent(at locator: ArtifactLocator) throws -> Data? {
        let source = try rawProjectArtifactURL(for: locator)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            return nil
        }
        do {
            return try Data(contentsOf: source, options: [.mappedIfSafe])
        } catch {
            throw XcircuiteWorkspaceStoreError.readFailed(error.localizedDescription)
        }
    }

    /// Checks a standard project artifact without remapping it into `.xcircuite`.
    public func projectArtifactExists(at locator: ArtifactLocator) throws -> Bool {
        let source = try rawProjectArtifactURL(for: locator)
        return fileManager.fileExists(atPath: source.path(percentEncoded: false))
    }

    public func prepareRun(
        runID: String,
        requireNew: Bool
    ) async throws {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        try createWorkspace()
        let url = try workspaceURL(relativePath: ".xcircuite/runs/\(runID)")
        if requireNew, fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            throw FlowExecutionError.duplicateRunID(runID)
        }
        try ensureWorkspaceDirectory(at: ".xcircuite/runs/\(runID)")
    }

    public func runWorkspaceURL(runID: String) async throws -> URL {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        return try workspaceURL(relativePath: ".xcircuite/runs/\(runID)")
    }

    public func loadApproval(
        runID: String,
        stageID: String
    ) async throws -> FlowApprovalRecord? {
        try loadRunApprovals(runID: runID).last { $0.stageID == stageID }
    }

    public func loadCancellationRequest(
        runID: String
    ) async throws -> FlowRunCancellationRequest? {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let path = ".xcircuite/runs/\(runID)/cancellation.json"
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")
        return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            try transactionCoordinator.recoverPendingTransactions()
            let ledgerURL = try workspaceURL(relativePath: ledgerRelativePath(for: runID))
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
                )
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            guard let reference = ledger.artifacts.first(where: {
                $0.locator.location.value == path
            }) else {
                guard ledger.cancellationRequest == nil else {
                    throw FlowRunLedgerPersistenceError.decodingFailed(
                        "Cancellation request exists without a retained projection for \(runID)."
                    )
                }
                return nil
            }
            let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
            guard integrity.isVerified else {
                throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                    path: path,
                    reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                )
            }
            let request: FlowRunCancellationRequest
            do {
                request = try JSONDecoder().decode(
                    FlowRunCancellationRequest.self,
                    from: readWorkspaceContent(relativePath: path)
                )
            } catch {
                throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
            }
            guard request.runID == runID else {
                throw XcircuiteWorkspaceStoreError.decodeFailed(
                    "Cancellation request run ID does not match \(runID)."
                )
            }
            guard ledger.cancellationRequest == request else {
                throw FlowRunLedgerPersistenceError.decodingFailed(
                    "Cancellation projection and run ledger differ for \(runID)."
                )
            }
            return request
        }
    }

    public func appendProgressEvent(
        runID: String,
        kind: FlowRunProgressEventKind,
        stageID: String?,
        stageStatus: FlowStageStatus?,
        runStatus: FlowRunStatus?,
        message: String,
        createdAt: Date
    ) async throws -> FlowRunProgressEvent {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let path = ".xcircuite/runs/\(runID)/progress.jsonl"
        try createWorkspace()
        let ledgerPath = ledgerRelativePath(for: runID)
        let ledgerURL = try workspaceURL(relativePath: ledgerPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")
        return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            try transactionCoordinator.recoverPendingTransactions()
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            var ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
                )
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            if let retainedProgress = ledger.artifacts.first(where: {
                $0.locator.location.value == path
            }) {
                let integrity = LocalArtifactVerifier().verify(
                    retainedProgress,
                    relativeTo: projectRoot
                )
                guard integrity.isVerified else {
                    throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                        path: path,
                        reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                    )
                }
            }
            let sequence = (ledger.progressEvents.map(\.sequence).max() ?? 0) + 1
            let event = FlowRunProgressEvent(
                runID: runID,
                sequence: sequence,
                kind: kind,
                stageID: stageID,
                stageStatus: stageStatus,
                runStatus: runStatus,
                message: message,
                createdAt: createdAt
            )
            var updated: Data
            do {
                updated = try readWorkspaceContent(relativePath: path)
            } catch XcircuiteWorkspaceStoreError.missingArtifact {
                updated = Data()
            }
            let persistedEvents = try updated.split(separator: 0x0A).map {
                try JSONDecoder().decode(FlowRunProgressEvent.self, from: Data($0))
            }
            guard persistedEvents == ledger.progressEvents else {
                throw FlowRunLedgerPersistenceError.decodingFailed(
                    "Progress projection and run ledger differ for \(runID)."
                )
            }
            updated.append(try encoder.encode(event))
            updated.append(0x0A)
            let persistedLocator = try locator(
                path: path,
                role: .output,
                kind: .report,
                format: .text
            )
            let digest = try SHA256ContentDigester().digest(data: updated, using: .sha256)
            let reference = ArtifactReference(
                id: try ArtifactID(rawValue: "run-progress"),
                locator: persistedLocator,
                digest: digest,
                byteCount: UInt64(updated.count)
            )
            ledger.artifacts.removeAll {
                $0.locator == reference.locator
            }
            ledger.artifacts.append(reference)
            ledger.artifacts.sort(by: artifactReferenceOrder)
            ledger.progressEvents.append(event)
            ledger.progressEvents.sort { $0.sequence < $1.sequence }
            let currentManifest = ledger.runManifest
            ledger.runManifest = try FlowRunManifest(
                runID: currentManifest.runID,
                status: currentManifest.status,
                revision: currentManifest.revision + 1,
                actor: currentManifest.actor,
                intent: currentManifest.intent,
                parentRunID: currentManifest.parentRunID,
                createdAt: currentManifest.createdAt,
                updatedAt: max(Date(), currentManifest.updatedAt),
                startedAt: currentManifest.startedAt,
                finishedAt: currentManifest.finishedAt,
                artifacts: ledger.artifacts
            )
            try transactionCoordinator.commit(
                [
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: path,
                        content: updated
                    ),
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: runManifestRelativePath(for: runID),
                        content: try encoder.encode(ledger.runManifest)
                    ),
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: ledgerPath,
                        content: try encoder.encode(ledger)
                    ),
                ],
                fault: transactionFault
            )
            return event
        }
    }

    public func loadProgressEvents(
        runID: String
    ) async throws -> [FlowRunProgressEvent] {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let path = ".xcircuite/runs/\(runID)/progress.jsonl"
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")
        return try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            try transactionCoordinator.recoverPendingTransactions()
            let ledgerURL = try workspaceURL(relativePath: ledgerRelativePath(for: runID))
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(
                    FlowRunLedger.self,
                    from: Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
                )
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            guard let reference = ledger.artifacts.first(where: {
                $0.locator.location.value == path
            }) else {
                guard ledger.progressEvents.isEmpty else {
                    throw FlowRunLedgerPersistenceError.decodingFailed(
                        "Progress events exist without a retained projection for \(runID)."
                    )
                }
                return []
            }
            let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
            guard integrity.isVerified else {
                throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                    path: path,
                    reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                )
            }
            let content = try readWorkspaceContent(relativePath: path)
            let events = try content.split(separator: 0x0A).map {
                try JSONDecoder().decode(FlowRunProgressEvent.self, from: Data($0))
            }
            guard events == ledger.progressEvents else {
                throw FlowRunLedgerPersistenceError.decodingFailed(
                    "Progress projection and run ledger differ for \(runID)."
                )
            }
            return events
        }
    }

    public func persistCancellationRequest(
        _ request: FlowRunCancellationRequest,
    ) async throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(request.runID, kind: .runID)
        guard !request.requestedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteWorkspaceStoreError.invalidCancellationRequest(
                "requestedBy must not be empty."
            )
        }
        guard !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteWorkspaceStoreError.invalidCancellationRequest(
                "reason must not be empty."
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try persistRunArtifact(
            content: encoder.encode(request),
            id: ArtifactID(rawValue: "run-cancellation-request"),
            locator: try locator(
                path: ".xcircuite/runs/\(request.runID)/cancellation.json",
                role: .output,
                kind: .report,
                format: .json
            ),
            runID: request.runID,
            producer: nil,
            mode: .replaceable,
            permitsRunControlPath: true
        ) { ledger in
            ledger.cancellationRequest = request
        }
    }

    public func runControlArtifacts(
        runID: String,
    ) async throws -> [ArtifactReference] {
        do {
            let ledger = try await loadRunLedger(runID: runID)
            let paths = Set([
                ".xcircuite/runs/\(runID)/progress.jsonl",
                ".xcircuite/runs/\(runID)/cancellation.json",
            ])
            return ledger.artifacts.filter { paths.contains($0.locator.location.value) }
        } catch FlowRunLedgerPersistenceError.resumeTargetNotFound {
            return []
        }
    }

    public func loadArtifactEnvelopeRecords(
        runID: String,
    ) async throws -> [FlowArtifactEnvelopeRecord] {
        let ledger = try await loadRunLedger(runID: runID)
        var records: [FlowArtifactEnvelopeRecord] = []
        for reference in ledger.artifacts where reference.locator.location.value.contains("/evidence/") {
            let content = try await loadArtifactContent(for: reference)
            let envelope = try JSONDecoder().decode(FlowArtifactEnvelope.self, from: content)
            records.append(
                FlowArtifactEnvelopeRecord(
                    envelope: envelope,
                    persistedAt: ledger.runManifest.updatedAt
                )
            )
        }
        return records
    }

    public func persistCrossArtifactEvaluation(
        _ evaluation: FlowCrossArtifactEvaluation
    ) async throws -> ArtifactReference {
        try await RunActionArtifactStore(
            store: self,
            actionKind: "review.persist-cross-artifact-evaluation"
        ).persistCrossArtifactEvaluation(evaluation)
    }

    public func persistLoopIterationSummaries(
        _ iterations: [FlowLoopIterationSummary],
        runID: String
    ) async throws -> ArtifactReference {
        try await RunActionArtifactStore(
            store: self,
            actionKind: "review.persist-loop-iterations"
        ).persistLoopIterationSummaries(iterations, runID: runID)
    }

    public func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot
    ) async throws -> ArtifactReference {
        try await RunActionArtifactStore(
            store: self,
            actionKind: "review.persist-loop-snapshot"
        ).persistAgentLoopSnapshot(snapshot)
    }

    public func persistProjectArtifact(
        content: Data,
        id: ArtifactID,
        locator: ArtifactLocator,
        producer: ProducerIdentity? = nil,
        mode: FlowArtifactPersistenceMode = .replaceable
    ) async throws -> ArtifactReference {
        guard locator.location.storage == .workspaceRelative else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(locator.location.value)
        }
        let persistedLocator = locator
        let relativePath = try projectRelativePath(for: persistedLocator)
        try createWorkspace()
        let destination = try rawProjectArtifactURL(for: persistedLocator)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try rawProjectArtifactURL(for: persistedLocator)
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: digest,
            byteCount: UInt64(content.count),
            producer: producer
        )
        try XcircuiteWorkspaceFileLock.withExclusiveLock(
            at: workspaceRoot.appending(path: ".workspace.lock")
        ) {
            try transactionCoordinator.recoverPendingTransactions()
            let destinationExists = fileManager.fileExists(
                atPath: destination.path(percentEncoded: false)
            )
            switch mode {
            case .createOnly where destinationExists:
                throw XcircuiteWorkspaceStoreError.artifactAlreadyExists(relativePath)
            case .immutable where destinationExists:
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard existing == content else {
                    throw XcircuiteWorkspaceStoreError.immutableArtifactConflict(relativePath)
                }
            case .appendOnly where destinationExists:
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard content.starts(with: existing) else {
                    throw XcircuiteWorkspaceStoreError.appendOnlyArtifactConflict(relativePath)
                }
            case .createOnly, .immutable, .replaceable, .appendOnly:
                break
            }
            var manifest = try loadProjectManifestUnlocked()
            manifest.files.removeAll {
                $0.locator == reference.locator
            }
            manifest.files.append(reference)
            manifest.files.sort(by: artifactReferenceOrder)
            try manifest.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try transactionCoordinator.commit(
                [
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: relativePath,
                        content: content
                    ),
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: ".xcircuite/\(XcircuiteWorkspaceLayout.manifestFileName)",
                        content: try encoder.encode(manifest)
                    ),
                ],
                fault: transactionFault
            )
        }
        return reference
    }

    private func locator(
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactLocator {
        ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: role,
            kind: kind,
            format: format
        )
    }

    private func ledgerRelativePath(for runID: String) -> String {
        ".xcircuite/runs/\(runID)/ledger.json"
    }

    private func runManifestRelativePath(for runID: String) -> String {
        ".xcircuite/runs/\(runID)/manifest.json"
    }

    private func projectRelativePath(for locator: ArtifactLocator) throws -> String {
        guard locator.location.storage == .workspaceRelative else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(locator.location.value)
        }
        let path = locator.location.value
        try XcircuiteWorkspaceLayout.validateProjectRelativePath(path)
        _ = try rawProjectArtifactURL(for: locator)
        return path
    }

    private func projectArtifactURL(for locator: ArtifactLocator) throws -> URL {
        let projectRelativeLocator = try projectRelativeLocator(from: locator)
        return try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .url(forProjectRelativePath: projectRelativeLocator.location.value)
    }

    private func rawProjectArtifactURL(for locator: ArtifactLocator) throws -> URL {
        guard locator.location.storage == .workspaceRelative else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(locator.location.value)
        }
        let destination = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .url(forProjectRelativePath: locator.location.value)
        guard pathBoundary.contains(destination, projectRoot: projectRoot) else {
            throw XcircuiteWorkspaceStoreError.unsafeProjectPath(locator.location.value)
        }
        return destination
    }

    private func persistRunArtifactTransaction(
        content: Data,
        reference: ArtifactReference,
        runID: String,
        projectRelativePath: String,
        mode: FlowArtifactPersistenceMode,
        updatingLedger updateLedger: (inout FlowRunLedger) throws -> Void
    ) throws {
        try ensureWorkspace()
        let destination = try rawProjectArtifactURL(for: reference.locator)
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let ledgerPath = ledgerRelativePath(for: runID)
        let ledgerURL = try workspaceURL(relativePath: ledgerPath)
        let lockURL = workspaceRoot.appending(path: ".workspace.lock")

        try XcircuiteWorkspaceFileLock.withExclusiveLock(at: lockURL) {
            try transactionCoordinator.recoverPendingTransactions()
            guard fileManager.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
                throw FlowRunLedgerPersistenceError.resumeTargetNotFound(runID: runID)
            }
            let ledgerData = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
            var ledger: FlowRunLedger
            do {
                ledger = try JSONDecoder().decode(FlowRunLedger.self, from: ledgerData)
            } catch {
                throw FlowRunLedgerPersistenceError.decodingFailed(error.localizedDescription)
            }
            guard ledger.runID == runID else {
                throw FlowRunLedgerPersistenceError.runIdentifierMismatch(
                    requested: runID,
                    stored: ledger.runID
                )
            }
            try validateLedgerProjection(ledger, requestedRunID: runID)
            let destinationExists = fileManager.fileExists(
                atPath: destination.path(percentEncoded: false)
            )
            if ledger.runManifest.status.isTerminal, destinationExists {
                if mode == .immutable {
                    let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                    if existing == content {
                        guard ledger.artifacts.contains(reference) else {
                            throw FlowRunLedgerPersistenceError.artifactReferenceMutation(
                                runID: runID,
                                path: projectRelativePath
                            )
                        }
                        return
                    }
                }
                if mode != .appendOnly {
                    throw XcircuiteWorkspaceStoreError.terminalRunArtifactMutation(
                        runID: runID,
                        path: projectRelativePath
                    )
                }
            }
            switch mode {
            case .createOnly where destinationExists:
                throw XcircuiteWorkspaceStoreError.artifactAlreadyExists(projectRelativePath)
            case .immutable where destinationExists:
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard existing == content else {
                    throw XcircuiteWorkspaceStoreError.immutableArtifactConflict(projectRelativePath)
                }
            case .appendOnly where destinationExists:
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard content.starts(with: existing) else {
                    throw XcircuiteWorkspaceStoreError.appendOnlyArtifactConflict(projectRelativePath)
                }
            case .createOnly, .immutable, .replaceable, .appendOnly:
                break
            }

            ledger.artifacts.removeAll {
                $0.locator == reference.locator
            }
            ledger.artifacts.append(reference)
            ledger.artifacts.sort(by: artifactReferenceOrder)
            try updateLedger(&ledger)
            if ledger.runManifest.status.isTerminal, let evidence = ledger.evidence {
                ledger.evidence = EvidenceManifest(
                    provenance: evidence.provenance,
                    artifacts: ledger.artifacts
                )
            }
            let currentManifest = ledger.runManifest
            ledger.runManifest = try FlowRunManifest(
                runID: currentManifest.runID,
                status: currentManifest.status,
                revision: currentManifest.revision + 1,
                actor: currentManifest.actor,
                intent: currentManifest.intent,
                parentRunID: currentManifest.parentRunID,
                createdAt: currentManifest.createdAt,
                updatedAt: max(Date(), currentManifest.updatedAt),
                startedAt: currentManifest.startedAt,
                finishedAt: currentManifest.finishedAt,
                artifacts: ledger.artifacts
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try transactionCoordinator.commit(
                [
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: projectRelativePath,
                        content: content
                    ),
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: runManifestRelativePath(for: runID),
                        content: try encoder.encode(ledger.runManifest)
                    ),
                    XcircuiteWorkspaceTransaction.Operation(
                        projectRelativePath: ledgerPath,
                        content: try encoder.encode(ledger)
                    ),
                ],
                fault: transactionFault
            )
        }
    }

    private func validateRetainedArtifactLineage(
        current: FlowRunLedger,
        proposed: FlowRunLedger
    ) throws {
        let appendOnlyProjections: [(String, Bool)] = [
            ("actions", proposed.actions.starts(with: current.actions)),
            (
                "suggestedActionSelections",
                proposed.suggestedActionSelections.starts(with: current.suggestedActionSelections)
            ),
            ("approvals", proposed.approvals.starts(with: current.approvals)),
        ]
        if let changed = appendOnlyProjections.first(where: { !$0.1 }) {
            throw FlowRunLedgerPersistenceError.protectedProjectionMutation(
                runID: current.runID,
                field: changed.0
            )
        }

        for retained in current.artifacts {
            guard proposed.artifacts.contains(retained) else {
                throw FlowRunLedgerPersistenceError.artifactReferenceMutation(
                    runID: current.runID,
                    path: retained.path
                )
            }
        }

        for proposedReference in proposed.artifacts {
            if let retained = current.artifacts.first(where: {
                $0.locator == proposedReference.locator
            }), retained != proposedReference {
                throw FlowRunLedgerPersistenceError.artifactReferenceMutation(
                    runID: current.runID,
                    path: proposedReference.path
                )
            }
        }
    }

    private func loadProjectManifestUnlocked() throws -> XcircuiteProjectManifest {
        let manifestURL = XcircuiteWorkspaceLayout(projectRoot: projectRoot).manifestURL
        do {
            return try JSONDecoder().decode(
                XcircuiteProjectManifest.self,
                from: Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            )
        } catch let error as XcircuiteWorkspaceStoreError {
            throw error
        } catch {
            throw XcircuiteWorkspaceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func projectRelativeLocator(from locator: ArtifactLocator) throws -> ArtifactLocator {
        guard locator.location.storage == .workspaceRelative else {
            throw XcircuiteWorkspaceStoreError.invalidArtifactLocation(locator.location.value)
        }
        let workspacePrefix = "\(XcircuiteWorkspaceLayout.directoryName)/"
        let path: String
        if locator.location.value.hasPrefix(workspacePrefix) {
            path = locator.location.value
        } else if locator.location.value.hasPrefix("runs/") {
            path = "\(workspacePrefix)\(locator.location.value)"
        } else {
            path = locator.location.value
        }
        let persistedLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: locator.role,
            kind: locator.kind,
            format: locator.format
        )
        _ = try rawProjectArtifactURL(for: persistedLocator)
        return persistedLocator
    }

    private func validateRunArtifactPath(
        _ path: String,
        runID: String,
        permitsRunControlPath: Bool
    ) throws {
        let runPrefix = ".xcircuite/runs/\(runID)/"
        guard path.hasPrefix(runPrefix) else { return }
        guard !permitsRunControlPath else {
            return
        }
        let relativePath = String(path.dropFirst(runPrefix.count))
        let rootControlPaths: Set<String> = [
            "actions.jsonl",
            "cancellation.json",
            "ledger.json",
            "manifest.json",
            "plan.json",
            "progress.jsonl",
            "toolchain.json",
        ]
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let isStageControlPath = components.count == 3
            && components[0] == "stages"
            && (components[2] == "result.json" || components[2] == "attempts.json")
        guard !rootControlPaths.contains(relativePath),
              !relativePath.hasPrefix("approvals/"),
              !isStageControlPath else {
            throw XcircuiteWorkspaceStoreError.reservedRunControlPath(path)
        }
    }

    private func workspaceURL(relativePath: String) throws -> URL {
        let workspaceRelativePath = try workspaceRelativePath(fromProjectRelativePath: relativePath)
        let destination = workspaceRoot.appending(path: workspaceRelativePath).standardizedFileURL
        guard pathBoundary.contains(destination, projectRoot: workspaceRoot) else {
            throw XcircuiteWorkspaceStoreError.pathOutsideWorkspace(relativePath)
        }
        return destination
    }

    private func readWorkspaceContent(relativePath: String) throws -> Data {
        let source = try workspaceURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw XcircuiteWorkspaceStoreError.missingArtifact(relativePath)
        }
        return try Data(contentsOf: source, options: [.mappedIfSafe])
    }
}
