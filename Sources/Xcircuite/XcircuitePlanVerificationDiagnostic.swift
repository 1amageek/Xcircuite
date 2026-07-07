import Foundation

public struct XcircuitePlanVerificationDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var stepID: String?
    public var gateID: String?

    public init(
        severity: String,
        code: String,
        message: String,
        stepID: String? = nil,
        gateID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.stepID = stepID
        self.gateID = gateID
    }
}
