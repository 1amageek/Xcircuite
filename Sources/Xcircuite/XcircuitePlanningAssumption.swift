import Foundation
import DesignFlowKernel

public struct XcircuitePlanningAssumption: Codable, Sendable, Hashable {
    public var assumptionID: String
    public var source: String
    public var statement: String
    public var status: String
    public var confidence: Double?
    public var sourceRefIDs: [String]
    public var requiredBeforeExecution: Bool
    public var evidence: [String: XcircuiteJSONValue]

    public init(
        assumptionID: String,
        source: String,
        statement: String,
        status: String,
        confidence: Double? = nil,
        sourceRefIDs: [String] = [],
        requiredBeforeExecution: Bool = false,
        evidence: [String: XcircuiteJSONValue] = [:]
    ) {
        self.assumptionID = assumptionID
        self.source = source
        self.statement = statement
        self.status = status
        self.confidence = confidence
        self.sourceRefIDs = sourceRefIDs
        self.requiredBeforeExecution = requiredBeforeExecution
        self.evidence = evidence
    }
}
