import Foundation

enum XcircuiteWorkspaceTransactionError: Error, Sendable, Equatable {
    case injectedFailure(XcircuiteWorkspaceTransactionFault)
    case invalidJournalPath(String)
}
