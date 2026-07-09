import Foundation

public struct OpAmpDesignDiagnostic: Sendable, Hashable, Codable {
    public enum Severity: String, Sendable, Hashable, Codable {
        case info
        case warning
        case error
    }

    public var severity: Severity
    public var code: String
    public var message: String
    public var relatedMetricIDs: [OpAmpMetricID]
    public var suggestedActions: [String]

    public init(
        severity: Severity,
        code: String,
        message: String,
        relatedMetricIDs: [OpAmpMetricID] = [],
        suggestedActions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.relatedMetricIDs = relatedMetricIDs
        self.suggestedActions = suggestedActions
    }
}
