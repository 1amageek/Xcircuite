public struct XcircuiteProblemTranslationAuditIssue: Codable, Sendable, Hashable {
    public var id: String
    public var kind: String
    public var sourceRefID: String?
    public var intentClauseID: String?
    public var reason: String

    public init(
        id: String,
        kind: String,
        sourceRefID: String? = nil,
        intentClauseID: String? = nil,
        reason: String
    ) {
        self.id = id
        self.kind = kind
        self.sourceRefID = sourceRefID
        self.intentClauseID = intentClauseID
        self.reason = reason
    }
}
