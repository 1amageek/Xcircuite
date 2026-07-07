public struct XcircuiteSymbolicPlannerPDDLExport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var domainName: String
    public var problemName: String
    public var requirements: [String]
    public var domainPDDL: String
    public var problemPDDL: String
    public var atomMappings: [XcircuiteSymbolicPlannerPDDLAtomMapping]
    public var actionMappings: [XcircuiteSymbolicPlannerPDDLActionMapping]
    public var diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        domainName: String,
        problemName: String,
        requirements: [String] = [":strips"],
        domainPDDL: String,
        problemPDDL: String,
        atomMappings: [XcircuiteSymbolicPlannerPDDLAtomMapping],
        actionMappings: [XcircuiteSymbolicPlannerPDDLActionMapping],
        diagnostics: [XcircuiteSymbolicPlannerPDDLDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.domainName = domainName
        self.problemName = problemName
        self.requirements = requirements
        self.domainPDDL = domainPDDL
        self.problemPDDL = problemPDDL
        self.atomMappings = atomMappings
        self.actionMappings = actionMappings
        self.diagnostics = diagnostics
    }
}
