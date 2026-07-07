import Foundation
import XcircuitePackage

public struct XcircuitePlanningRiskClassification: Codable, Sendable, Hashable {
    public var riskID: String
    public var category: String
    public var severity: String
    public var scope: String
    public var description: String
    public var affectedObjectiveIDs: [String]
    public var affectedActionIDs: [String]
    public var requiredApprovals: [String]
    public var mitigationActions: [String]
    public var evidence: [String: XcircuiteJSONValue]

    public init(
        riskID: String,
        category: String,
        severity: String,
        scope: String,
        description: String,
        affectedObjectiveIDs: [String] = [],
        affectedActionIDs: [String] = [],
        requiredApprovals: [String] = [],
        mitigationActions: [String] = [],
        evidence: [String: XcircuiteJSONValue] = [:]
    ) {
        self.riskID = riskID
        self.category = category
        self.severity = severity
        self.scope = scope
        self.description = description
        self.affectedObjectiveIDs = affectedObjectiveIDs
        self.affectedActionIDs = affectedActionIDs
        self.requiredApprovals = requiredApprovals
        self.mitigationActions = mitigationActions
        self.evidence = evidence
    }
}
