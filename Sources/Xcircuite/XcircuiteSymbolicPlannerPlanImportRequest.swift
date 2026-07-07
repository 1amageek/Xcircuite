public struct XcircuiteSymbolicPlannerPlanImportRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var pddlExportArtifactID: String?
    public var pddlExportPath: String?
    public var solverPlanArtifactID: String?
    public var solverPlanPath: String?
    public var solverPlanText: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        pddlExportArtifactID: String? = nil,
        pddlExportPath: String? = nil,
        solverPlanArtifactID: String? = nil,
        solverPlanPath: String? = nil,
        solverPlanText: String? = nil
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.pddlExportArtifactID = pddlExportArtifactID
        self.pddlExportPath = pddlExportPath
        self.solverPlanArtifactID = solverPlanArtifactID
        self.solverPlanPath = solverPlanPath
        self.solverPlanText = solverPlanText
    }
}
