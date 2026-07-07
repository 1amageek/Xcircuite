import Foundation

public struct XcircuitePlanVerificationGateResult: Codable, Sendable, Hashable {
    public var gateID: String
    public var required: Bool
    public var status: String
    public var sourceStepIDs: [String]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]

    public init(
        gateID: String,
        required: Bool,
        status: String,
        sourceStepIDs: [String] = [],
        diagnostics: [XcircuitePlanVerificationDiagnostic] = []
    ) {
        self.gateID = gateID
        self.required = required
        self.status = status
        self.sourceStepIDs = sourceStepIDs
        self.diagnostics = diagnostics
    }
}
