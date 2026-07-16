import Foundation

public struct XcircuiteSignoffRepairFormulationResult: Codable, Sendable, Hashable {
    public struct SourceReport: Codable, Sendable, Hashable {
        public var sourceKind: String
        public var path: String
        public var backendID: String
        public var topCell: String
        public var status: String
        public var activeDiagnosticCount: Int
        public var hintCount: Int
        public var unsupportedDiagnosticCount: Int
        public var artifactID: String?
        public var sha256: String?
        public var byteCount: Int64?
        public var integrityStatus: String?

        public init(
            sourceKind: String,
            path: String,
            backendID: String,
            topCell: String,
            status: String,
            activeDiagnosticCount: Int,
            hintCount: Int,
            unsupportedDiagnosticCount: Int,
            artifactID: String? = nil,
            sha256: String? = nil,
            byteCount: Int64? = nil,
            integrityStatus: String? = nil
        ) {
            self.sourceKind = sourceKind
            self.path = path
            self.backendID = backendID
            self.topCell = topCell
            self.status = status
            self.activeDiagnosticCount = activeDiagnosticCount
            self.hintCount = hintCount
            self.unsupportedDiagnosticCount = unsupportedDiagnosticCount
            self.artifactID = artifactID
            self.sha256 = sha256
            self.byteCount = byteCount
            self.integrityStatus = integrityStatus
        }
    }

    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var formulationID: String
    public var problemID: String
    public var sourceReports: [SourceReport]
    public var compilation: XcircuiteRepairPlanFormulationCompilationResult

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        formulationID: String,
        problemID: String,
        sourceReports: [SourceReport],
        compilation: XcircuiteRepairPlanFormulationCompilationResult
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.formulationID = formulationID
        self.problemID = problemID
        self.sourceReports = sourceReports
        self.compilation = compilation
    }
}
