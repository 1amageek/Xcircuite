import Foundation

/// Commits related workspace files with a durable roll-forward journal.
///
/// Every target contains its complete post-transaction content in the journal.
/// Readers recover pending journals while holding the workspace writer lock, so
/// they never consume a partially applied ledger generation.
struct XcircuiteWorkspaceTransactionCoordinator {
    private static let transactionDirectory = ".xcircuite/transactions"

    let projectRoot: URL
    let workspaceRoot: URL
    let fileManager: FileManager

    func commit(
        _ operations: [XcircuiteWorkspaceTransaction.Operation],
        fault: XcircuiteWorkspaceTransactionFault?
    ) throws {
        guard !operations.isEmpty else {
            return
        }
        let transaction = XcircuiteWorkspaceTransaction(operations: operations)
        let journalURL = try journalURL(for: transaction.transactionID)
        try fileManager.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(transaction).write(to: journalURL, options: .atomic)
        if fault == .afterJournalWrite {
            throw XcircuiteWorkspaceTransactionError.injectedFailure(.afterJournalWrite)
        }

        for (index, operation) in operations.enumerated() {
            try apply(operation)
            if fault == .afterOperation(index) {
                throw XcircuiteWorkspaceTransactionError.injectedFailure(.afterOperation(index))
            }
        }
        try fileManager.removeItem(at: journalURL)
    }

    func recoverPendingTransactions() throws {
        let directory = projectRoot.appending(path: Self.transactionDirectory, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return
        }
        let journalURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for journalURL in journalURLs {
            let transaction = try JSONDecoder().decode(
                XcircuiteWorkspaceTransaction.self,
                from: Data(contentsOf: journalURL, options: [.mappedIfSafe])
            )
            guard transaction.schemaVersion == XcircuiteWorkspaceTransaction.currentSchemaVersion else {
                throw XcircuiteWorkspaceStoreError.decodeFailed(
                    "Unsupported workspace transaction schema version \(transaction.schemaVersion)."
                )
            }
            for operation in transaction.operations {
                try apply(operation)
            }
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func apply(_ operation: XcircuiteWorkspaceTransaction.Operation) throws {
        let destination = try destinationURL(for: operation.projectRelativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try operation.content.write(to: destination, options: .atomic)
    }

    private func destinationURL(for projectRelativePath: String) throws -> URL {
        try XcircuiteWorkspaceLayout.validateProjectRelativePath(projectRelativePath)
        let destination = try XcircuiteWorkspaceLayout(projectRoot: projectRoot)
            .url(forProjectRelativePath: projectRelativePath)
        guard ProjectPathBoundary().contains(destination, projectRoot: projectRoot) else {
            throw XcircuiteWorkspaceTransactionError.invalidJournalPath(projectRelativePath)
        }
        return destination
    }

    private func journalURL(for transactionID: UUID) throws -> URL {
        let relativePath = "\(Self.transactionDirectory)/\(transactionID.uuidString.lowercased()).json"
        return try destinationURL(for: relativePath)
    }
}
