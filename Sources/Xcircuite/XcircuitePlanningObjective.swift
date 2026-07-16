import Foundation
import DesignFlowKernel

public struct XcircuitePlanningObjective: Codable, Sendable, Hashable {
    public var objectiveID: String
    public var kind: String
    public var domain: String
    public var priority: String
    public var sourceRefIDs: [String]
    public var target: String
    public var currentValue: PlanningParameterValue?
    public var requiredValue: PlanningParameterValue?
    public var unit: String?
    public var description: String
    public var evidence: [String: PlanningParameterValue]
    public var suggestedActions: [String]

    public init(
        objectiveID: String,
        kind: String,
        domain: String,
        priority: String,
        sourceRefIDs: [String],
        target: String,
        currentValue: PlanningParameterValue? = nil,
        requiredValue: PlanningParameterValue? = nil,
        unit: String? = nil,
        description: String,
        evidence: [String: PlanningParameterValue] = [:],
        suggestedActions: [String] = []
    ) {
        self.objectiveID = objectiveID
        self.kind = kind
        self.domain = domain
        self.priority = priority
        self.sourceRefIDs = sourceRefIDs
        self.target = target
        self.currentValue = currentValue
        self.requiredValue = requiredValue
        self.unit = unit
        self.description = description
        self.evidence = evidence
        self.suggestedActions = suggestedActions
    }
}
