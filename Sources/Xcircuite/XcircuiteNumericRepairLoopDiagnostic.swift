import Foundation

public struct XcircuiteNumericRepairLoopDiagnostic: Codable, Sendable, Hashable {
    public var severity: String
    public var code: String
    public var message: String
    public var iterationIndex: Int?

    public init(
        severity: String,
        code: String,
        message: String,
        iterationIndex: Int? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.iterationIndex = iterationIndex
    }
}
