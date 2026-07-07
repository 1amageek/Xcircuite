public struct XcircuiteSymbolicPlannerSolverRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var executablePath: String
    public var arguments: [String]
    public var timeoutSeconds: Double
    public var domainArtifactID: String?
    public var domainPath: String?
    public var problemArtifactID: String?
    public var problemPath: String?
    public var pddlExportArtifactID: String?
    public var pddlExportPath: String?
    public var workingDirectoryPath: String?
    public var solverPlanOutputPath: String?
    public var importCandidatePlan: Bool

    public init(
        runID: String,
        executablePath: String,
        arguments: [String] = [],
        timeoutSeconds: Double = 300,
        domainArtifactID: String? = nil,
        domainPath: String? = nil,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        pddlExportArtifactID: String? = nil,
        pddlExportPath: String? = nil,
        workingDirectoryPath: String? = nil,
        solverPlanOutputPath: String? = nil,
        importCandidatePlan: Bool = true
    ) {
        self.runID = runID
        self.executablePath = executablePath
        self.arguments = arguments.isEmpty ? ["{domain}", "{problem}"] : arguments
        self.timeoutSeconds = timeoutSeconds
        self.domainArtifactID = domainArtifactID
        self.domainPath = domainPath
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.pddlExportArtifactID = pddlExportArtifactID
        self.pddlExportPath = pddlExportPath
        self.workingDirectoryPath = workingDirectoryPath
        self.solverPlanOutputPath = solverPlanOutputPath
        self.importCandidatePlan = importCandidatePlan
    }
}
