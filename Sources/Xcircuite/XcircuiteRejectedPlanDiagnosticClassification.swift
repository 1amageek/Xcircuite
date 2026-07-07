import Foundation

public enum XcircuiteRejectedPlanDiagnosticClass: String, Codable, Sendable, Hashable {
    case unsupportedOperation = "unsupported_operation"
    case missingInput = "missing_input"
    case failedVerificationGate = "failed_verification_gate"
    case externalToolBlocker = "external_tool_blocker"
    case staleArtifact = "stale_artifact"
    case objectiveRegression = "objective_regression"
    case calibrationUncertainty = "calibration_uncertainty"
}

public struct XcircuiteRejectedPlanDiagnosticClassification: Codable, Sendable, Hashable {
    public var classificationID: String
    public var diagnosticClass: XcircuiteRejectedPlanDiagnosticClass
    public var severity: String
    public var reasonCodes: [String]
    public var status: String
    public var planID: String
    public var failedStepIDs: [String]
    public var failedGateIDs: [String]
    public var diagnosticCodes: [String]
    public var artifactIDs: [String]
    public var nextActions: [String]

    public init(
        classificationID: String,
        diagnosticClass: XcircuiteRejectedPlanDiagnosticClass,
        severity: String,
        reasonCodes: [String] = [],
        status: String,
        planID: String,
        failedStepIDs: [String] = [],
        failedGateIDs: [String] = [],
        diagnosticCodes: [String] = [],
        artifactIDs: [String] = [],
        nextActions: [String] = []
    ) {
        self.classificationID = classificationID
        self.diagnosticClass = diagnosticClass
        self.severity = severity
        self.reasonCodes = Self.unique(reasonCodes)
        self.status = status
        self.planID = planID
        self.failedStepIDs = Self.unique(failedStepIDs)
        self.failedGateIDs = Self.unique(failedGateIDs)
        self.diagnosticCodes = Self.unique(diagnosticCodes)
        self.artifactIDs = Self.unique(artifactIDs)
        self.nextActions = Self.unique(nextActions)
    }

    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            guard !value.isEmpty, !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }
}
