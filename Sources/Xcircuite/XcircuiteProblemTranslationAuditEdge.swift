public struct XcircuiteProblemTranslationAuditEdge: Codable, Sendable, Hashable {
    public var sourceRefID: String
    public var sourceKind: String
    public var intentClauseID: String?
    public var targetKind: String
    public var targetID: String
    public var relation: String

    public init(
        sourceRefID: String,
        sourceKind: String,
        intentClauseID: String? = nil,
        targetKind: String,
        targetID: String,
        relation: String
    ) {
        self.sourceRefID = sourceRefID
        self.sourceKind = sourceKind
        self.intentClauseID = intentClauseID
        self.targetKind = targetKind
        self.targetID = targetID
        self.relation = relation
    }
}
