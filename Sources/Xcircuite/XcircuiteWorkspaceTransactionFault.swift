import Foundation

/// Test-only fault point used to prove recovery from an interrupted workspace transaction.
enum XcircuiteWorkspaceTransactionFault: Sendable, Equatable {
    case afterJournalWrite
    case afterOperation(Int)
}
