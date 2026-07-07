import Foundation

public struct XcircuiteParameterCandidateDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var actionID: String?

    public init(
        severity: String,
        code: String,
        message: String,
        actionID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.actionID = actionID
    }
}
