import Foundation

public struct XcircuiteProblemTranslationAuditGate: Sendable {
    private let auditor: XcircuiteProblemTranslationAuditor

    public init(auditor: XcircuiteProblemTranslationAuditor = XcircuiteProblemTranslationAuditor()) {
        self.auditor = auditor
    }

    public func refreshAudit(
        runID: String,
        problemPath: String,
        projectRoot: URL
    ) throws -> XcircuiteProblemTranslationAuditResult {
        try auditor.auditProblemTranslation(
            request: XcircuiteProblemTranslationAuditRequest(
                runID: runID,
                problemPath: problemPath
            ),
            projectRoot: projectRoot
        )
    }

    public func requireFreshNonBlockingAudit(
        runID: String,
        problemPath: String,
        projectRoot: URL
    ) throws -> XcircuiteProblemTranslationAuditResult {
        let result = try refreshAudit(
            runID: runID,
            problemPath: problemPath,
            projectRoot: projectRoot
        )
        guard result.audit.blocking == false else {
            throw XcircuiteProblemTranslationAuditGateError.blocking(
                runID: runID,
                problemID: result.problemID,
                diagnosticCodes: result.audit.diagnostics.map(\.code)
            )
        }
        return result
    }

    public func validationDiagnostics(
        for audit: XcircuiteProblemTranslationAudit
    ) -> [XcircuitePlanningProblemValidationDiagnostic] {
        guard audit.blocking else {
            return []
        }
        let codes = audit.diagnostics.map(\.code).joined(separator: ",")
        return [
            XcircuitePlanningProblemValidationDiagnostic(
                severity: "error",
                code: "problem-translation-audit-blocking",
                message: "Problem translation audit blocks planner entry. Diagnostic codes: \(codes)."
            ),
        ]
    }
}
