import Foundation

public struct XcircuitePlanRiskReview: Codable, Sendable, Hashable {
    public var riskID: String
    public var category: String
    public var severity: String
    public var scope: String
    public var status: String
    public var description: String
    public var affectedObjectiveIDs: [String]
    public var affectedActionIDs: [String]
    public var affectedStepIDs: [String]
    public var requiredApprovals: [String]
    public var approvalReviews: [XcircuitePlanApprovalReview]
    public var mitigationActions: [String]

    public init(
        riskID: String,
        category: String,
        severity: String,
        scope: String,
        status: String,
        description: String,
        affectedObjectiveIDs: [String] = [],
        affectedActionIDs: [String] = [],
        affectedStepIDs: [String] = [],
        requiredApprovals: [String] = [],
        approvalReviews: [XcircuitePlanApprovalReview] = [],
        mitigationActions: [String] = []
    ) {
        self.riskID = riskID
        self.category = category
        self.severity = severity
        self.scope = scope
        self.status = status
        self.description = description
        self.affectedObjectiveIDs = affectedObjectiveIDs
        self.affectedActionIDs = affectedActionIDs
        self.affectedStepIDs = affectedStepIDs
        self.requiredApprovals = requiredApprovals
        self.approvalReviews = approvalReviews
        self.mitigationActions = mitigationActions
    }

    private enum CodingKeys: String, CodingKey {
        case riskID
        case category
        case severity
        case scope
        case status
        case description
        case affectedObjectiveIDs
        case affectedActionIDs
        case affectedStepIDs
        case requiredApprovals
        case approvalReviews
        case mitigationActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        riskID = try container.decode(String.self, forKey: .riskID)
        category = try container.decode(String.self, forKey: .category)
        severity = try container.decode(String.self, forKey: .severity)
        scope = try container.decode(String.self, forKey: .scope)
        status = try container.decode(String.self, forKey: .status)
        description = try container.decode(String.self, forKey: .description)
        affectedObjectiveIDs = try container.decodeIfPresent([String].self, forKey: .affectedObjectiveIDs) ?? []
        affectedActionIDs = try container.decodeIfPresent([String].self, forKey: .affectedActionIDs) ?? []
        affectedStepIDs = try container.decodeIfPresent([String].self, forKey: .affectedStepIDs) ?? []
        requiredApprovals = try container.decodeIfPresent([String].self, forKey: .requiredApprovals) ?? []
        approvalReviews = try container.decodeIfPresent(
            [XcircuitePlanApprovalReview].self,
            forKey: .approvalReviews
        ) ?? []
        mitigationActions = try container.decodeIfPresent([String].self, forKey: .mitigationActions) ?? []
    }
}
