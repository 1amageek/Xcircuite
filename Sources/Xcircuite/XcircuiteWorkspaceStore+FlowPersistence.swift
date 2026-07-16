import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ToolQualification

extension XcircuiteWorkspaceStore: FlowRunInfrastructure, FlowRunLedgerPersisting, ToolQualificationArtifactReading {
    public func verifyArtifact(
        _ reference: ArtifactReference
    ) async -> ArtifactIntegrity {
        LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
    }

    public func verifiedData(for reference: ArtifactReference) async throws -> Data {
        return try await loadArtifactContent(for: reference)
    }

    public func loadRunLedger(runID: String) async throws -> FlowRunLedger {
        try await loadAttestedRunLedger(runID: runID)
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
                for reference in ledger.artifacts {
                    let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
                    guard integrity.isVerified else {
                        throw FlowRunLedgerPersistenceError.artifactIntegrityFailure(
                            path: reference.path,
                            reason: integrity.issues.map { $0.code.rawValue }.joined(separator: ",")
                        )
                    }
                }
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
    /// required, such as resume and human review.
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
    }

    public func saveRunLedger(_ ledger: FlowRunLedger) async throws {
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
        try XcircuiteWorkspaceFileLock.withExclusiveLock(at: workspaceRoot.appending(path: ".workspace.lock")) {
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

            var storedLedger = ledger
            let projections = try prepareDecisionProjections(
                for: storedLedger,
                encoder: encoder
            )
            for projection in projections {
                let reference = projection.reference
                storedLedger.artifacts.removeAll {
                    $0.id == reference.id || $0.locator.location == reference.locator.location
                }
                storedLedger.artifacts.append(reference)
            }
            storedLedger.artifacts.sort { $0.path < $1.path }
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

            let currentArtifacts = Set(current?.artifacts ?? [])
            let projectionReferences = Set(projections.map(\.reference))
            for reference in storedLedger.artifacts where
                !currentArtifacts.contains(reference) && !projectionReferences.contains(reference) {
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
            let operations = projections.map(\.operation) + [
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: runManifestRelativePath(for: storedLedger.runID),
                    content: try encoder.encode(storedLedger.runManifest)
                ),
                XcircuiteWorkspaceTransaction.Operation(
                    projectRelativePath: path,
                    content: try encoder.encode(storedLedger)
                ),
                projectManifestOperation,
            ]
            try transactionCoordinator.commit(operations, fault: transactionFault)
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
            mode: mode
        ) { _ in }
    }

    func persistRunArtifact(
        content: Data,
        id: ArtifactID?,
        locator: ArtifactLocator,
        runID: String,
        mode: FlowArtifactPersistenceMode,
        updatingLedger updateLedger: (inout FlowRunLedger) throws -> Void
    ) throws -> ArtifactReference {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let persistedLocator = try projectRelativeLocator(from: locator)
        let projectRelativePath = try projectRelativePath(for: persistedLocator)
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: digest,
            byteCount: UInt64(content.count)
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
        let integrity = LocalArtifactVerifier().verify(reference, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw XcircuiteWorkspaceStoreError.artifactIntegrityFailed(
                path: path,
                issues: integrity.issues
            )
        }
        let source = try reference.locator.location.resolvedFileURL(relativeTo: projectRoot)
        do {
            return try Data(contentsOf: source, options: [.mappedIfSafe])
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
                $0.id == reference.id || $0.locator.location == reference.locator.location
            }
            ledger.artifacts.append(reference)
            ledger.artifacts.sort { $0.path < $1.path }
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
            mode: .replaceable
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
        _ evaluation: FlowCrossArtifactEvaluation,
    ) async throws -> ArtifactReference {
        try await persistJSON(
            evaluation,
            id: "cross-artifact-evaluation",
            path: ".xcircuite/runs/\(evaluation.runID)/reports/cross-artifact-evaluation.json",
            runID: evaluation.runID,
        )
    }

    public func persistLoopIterationSummaries(
        _ iterations: [FlowLoopIterationSummary],
        runID: String,
    ) async throws -> ArtifactReference {
        try await persistJSON(
            iterations,
            id: "agent-loop-iterations",
            path: ".xcircuite/runs/\(runID)/loop/iterations.json",
            runID: runID,
        )
    }

    public func persistAgentLoopSnapshot(
        _ snapshot: FlowAgentLoopSnapshot,
    ) async throws -> ArtifactReference {
        try await persistJSON(
            snapshot,
            id: "agent-loop-snapshot",
            path: ".xcircuite/runs/\(snapshot.runID)/loop/snapshot.json",
            runID: snapshot.runID,
        )
    }

    public func persistProjectArtifact(
        content: Data,
        id: ArtifactID,
        locator: ArtifactLocator,
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
        let digest = try SHA256ContentDigester().digest(data: content, using: .sha256)
        let reference = ArtifactReference(
            id: id,
            locator: persistedLocator,
            digest: digest,
            byteCount: UInt64(content.count)
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
            case .createOnly, .immutable, .replaceable:
                break
            }
            var manifest = try loadProjectManifestUnlocked()
            manifest.files.removeAll {
                $0.id == reference.id || $0.locator.location == reference.locator.location
            }
            manifest.files.append(reference)
            manifest.files.sort { $0.path < $1.path }
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

    private func persistJSON<Value: Encodable & Sendable>(
        _ value: Value,
        id: String,
        path: String,
        runID: String,
    ) async throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await persistArtifact(
            content: encoder.encode(value),
            id: ArtifactID(rawValue: id),
            locator: try locator(path: path, role: .output, kind: .report, format: .json),
            runID: runID,
            mode: .replaceable
        )
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
        return try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .url(forProjectRelativePath: locator.location.value)
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
            switch mode {
            case .createOnly where destinationExists:
                throw XcircuiteWorkspaceStoreError.artifactAlreadyExists(projectRelativePath)
            case .immutable where destinationExists:
                let existing = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard existing == content else {
                    throw XcircuiteWorkspaceStoreError.immutableArtifactConflict(projectRelativePath)
                }
            case .createOnly, .immutable, .replaceable:
                break
            }

            ledger.artifacts.removeAll {
                $0.locator.location == reference.locator.location || $0.id == reference.id
            }
            ledger.artifacts.append(reference)
            ledger.artifacts.sort { $0.locator.location.value < $1.locator.location.value }
            try updateLedger(&ledger)
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
