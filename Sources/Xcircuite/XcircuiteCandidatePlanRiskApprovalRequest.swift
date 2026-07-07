import Foundation
import XcircuitePackage

public struct XcircuiteCandidatePlanRiskApprovalRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var approvalID: String
    public var verdict: XcircuiteApprovalRecord.Verdict
    public var reviewer: String
    public var reviewerKind: XcircuiteRunActionActor.Kind
    public var note: String
    public var decidedAt: Date

    public init(
        runID: String,
        approvalID: String,
        verdict: XcircuiteApprovalRecord.Verdict = .approved,
        reviewer: String,
        reviewerKind: XcircuiteRunActionActor.Kind = .human,
        note: String = "",
        decidedAt: Date = Date()
    ) {
        self.runID = runID
        self.approvalID = approvalID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey {
        case runID
        case approvalID
        case verdict
        case reviewer
        case reviewerKind
        case note
        case decidedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(String.self, forKey: .runID)
        approvalID = try container.decode(String.self, forKey: .approvalID)
        verdict = try container.decode(XcircuiteApprovalRecord.Verdict.self, forKey: .verdict)
        reviewer = try container.decode(String.self, forKey: .reviewer)
        reviewerKind = try container.decodeIfPresent(
            XcircuiteRunActionActor.Kind.self,
            forKey: .reviewerKind
        ) ?? .human
        note = try container.decode(String.self, forKey: .note)
        decidedAt = try container.decode(Date.self, forKey: .decidedAt)
    }
}
