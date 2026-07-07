import Foundation

public struct XcircuiteLVSPolicyRepairReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var planID: String
    public var stepID: String
    public var operationID: String
    public var policyKind: String
    public var sourceRepairHintID: String?
    public var sourceDiagnosticIndex: Int?
    public var ruleID: String?
    public var category: String?
    public var layoutModel: String?
    public var schematicModel: String?
    public var terminalKind: String?
    public var terminalModel: String?
    public var terminalPinCount: Int?
    public var equivalentPinGroups: [[Int]]
    public var producedPolicyArtifactID: String
    public var producedPolicyPath: String
    public var rationale: String

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        planID: String,
        stepID: String,
        operationID: String,
        policyKind: String,
        sourceRepairHintID: String? = nil,
        sourceDiagnosticIndex: Int? = nil,
        ruleID: String? = nil,
        category: String? = nil,
        layoutModel: String? = nil,
        schematicModel: String? = nil,
        terminalKind: String? = nil,
        terminalModel: String? = nil,
        terminalPinCount: Int? = nil,
        equivalentPinGroups: [[Int]] = [],
        producedPolicyArtifactID: String,
        producedPolicyPath: String,
        rationale: String
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.planID = planID
        self.stepID = stepID
        self.operationID = operationID
        self.policyKind = policyKind
        self.sourceRepairHintID = sourceRepairHintID
        self.sourceDiagnosticIndex = sourceDiagnosticIndex
        self.ruleID = ruleID
        self.category = category
        self.layoutModel = layoutModel
        self.schematicModel = schematicModel
        self.terminalKind = terminalKind
        self.terminalModel = terminalModel
        self.terminalPinCount = terminalPinCount
        self.equivalentPinGroups = equivalentPinGroups
        self.producedPolicyArtifactID = producedPolicyArtifactID
        self.producedPolicyPath = producedPolicyPath
        self.rationale = rationale
    }
}
