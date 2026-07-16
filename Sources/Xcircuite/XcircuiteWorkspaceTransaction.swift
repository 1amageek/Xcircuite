import Foundation

struct XcircuiteWorkspaceTransaction: Sendable, Codable, Hashable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let transactionID: UUID
    let operations: [Operation]

    init(
        transactionID: UUID = UUID(),
        operations: [Operation]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.transactionID = transactionID
        self.operations = operations
    }

    struct Operation: Sendable, Codable, Hashable {
        let projectRelativePath: String
        let content: Data
    }
}
