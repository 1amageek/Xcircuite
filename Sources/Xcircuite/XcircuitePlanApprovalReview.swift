import Foundation

public struct XcircuitePlanApprovalReview: Codable, Sendable, Hashable {
    public var approvalID: String
    public var status: String
    public var reviewer: String?
    public var note: String?
    public var decidedAt: Date?

    public init(
        approvalID: String,
        status: String,
        reviewer: String? = nil,
        note: String? = nil,
        decidedAt: Date? = nil
    ) {
        self.approvalID = approvalID
        self.status = status
        self.reviewer = reviewer
        self.note = note
        self.decidedAt = decidedAt
    }
}
