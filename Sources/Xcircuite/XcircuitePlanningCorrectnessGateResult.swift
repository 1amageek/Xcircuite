import Foundation

public struct XcircuitePlanningCorrectnessGateResult: Codable, Sendable, Hashable {
    public var gateID: String
    public var status: String
    public var summary: String
    public var evidenceArtifactIDs: [String]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]
    public var nextActions: [String]

    public init(
        gateID: String,
        status: String,
        summary: String,
        evidenceArtifactIDs: [String] = [],
        diagnostics: [XcircuitePlanVerificationDiagnostic] = [],
        nextActions: [String] = []
    ) {
        self.gateID = gateID
        self.status = status
        self.summary = summary
        self.evidenceArtifactIDs = evidenceArtifactIDs
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
