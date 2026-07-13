import Foundation
import DesignFlowKernel

public struct XcircuitePlanningObjective: Codable, Sendable, Hashable {
    public var objectiveID: String
    public var kind: String
    public var domain: String
    public var priority: String
    public var sourceRefIDs: [String]
    public var target: String
    public var currentValue: XcircuiteJSONValue?
    public var requiredValue: XcircuiteJSONValue?
    public var unit: String?
    public var description: String
    public var evidence: [String: XcircuiteJSONValue]
    public var suggestedActions: [String]

    public init(
        objectiveID: String,
        kind: String,
        domain: String,
        priority: String,
        sourceRefIDs: [String],
        target: String,
        currentValue: XcircuiteJSONValue? = nil,
        requiredValue: XcircuiteJSONValue? = nil,
        unit: String? = nil,
        description: String,
        evidence: [String: XcircuiteJSONValue] = [:],
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
