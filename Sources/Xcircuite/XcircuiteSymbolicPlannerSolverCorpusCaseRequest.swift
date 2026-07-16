public struct XcircuiteSymbolicPlannerSolverCorpusCaseRequest: Codable, Sendable, Hashable {
    public var caseID: String
    public var runID: String
    public var expectedActionIDs: [String]
    public var coverageTags: [String]
    public var requireGoalCoverage: Bool
    public var requireOptimality: Bool
    public var maximumSolverCost: Double?
    public var domainArtifactID: String?
    public var domainPath: String?
    public var problemArtifactID: String?
    public var problemPath: String?
    public var pddlExportArtifactID: String?
    public var pddlExportPath: String?
    public var workingDirectoryPath: String?
    public var solverPlanOutputPath: String?
    public var proofArtifactID: String?
    public var proofPath: String?
    public var proofCheckerWorkingDirectoryPath: String?

    private enum CodingKeys: String, CodingKey {
        case caseID
        case runID
        case expectedActionIDs
        case coverageTags
        case requireGoalCoverage
        case requireOptimality
        case maximumSolverCost
        case domainArtifactID
        case domainPath
        case problemArtifactID
        case problemPath
        case pddlExportArtifactID
        case pddlExportPath
        case workingDirectoryPath
        case solverPlanOutputPath
        case proofArtifactID
        case proofPath
        case proofCheckerWorkingDirectoryPath
    }

    public init(
        caseID: String,
        runID: String,
        expectedActionIDs: [String] = [],
        coverageTags: [String] = [],
        requireGoalCoverage: Bool = true,
        requireOptimality: Bool = false,
        maximumSolverCost: Double? = nil,
        domainArtifactID: String? = nil,
        domainPath: String? = nil,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        pddlExportArtifactID: String? = nil,
        pddlExportPath: String? = nil,
        workingDirectoryPath: String? = nil,
        solverPlanOutputPath: String? = nil,
        proofArtifactID: String? = nil,
        proofPath: String? = nil,
        proofCheckerWorkingDirectoryPath: String? = nil
    ) {
        self.caseID = caseID
        self.runID = runID
        self.expectedActionIDs = expectedActionIDs
        self.coverageTags = coverageTags
        self.requireGoalCoverage = requireGoalCoverage
        self.requireOptimality = requireOptimality
        self.maximumSolverCost = maximumSolverCost
        self.domainArtifactID = domainArtifactID
        self.domainPath = domainPath
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.pddlExportArtifactID = pddlExportArtifactID
        self.pddlExportPath = pddlExportPath
        self.workingDirectoryPath = workingDirectoryPath
        self.solverPlanOutputPath = solverPlanOutputPath
        self.proofArtifactID = proofArtifactID
        self.proofPath = proofPath
        self.proofCheckerWorkingDirectoryPath = proofCheckerWorkingDirectoryPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            caseID: try container.decode(String.self, forKey: .caseID),
            runID: try container.decode(String.self, forKey: .runID),
            expectedActionIDs: try container.decode([String].self, forKey: .expectedActionIDs),
            coverageTags: try container.decode([String].self, forKey: .coverageTags),
            requireGoalCoverage: try container.decode(Bool.self, forKey: .requireGoalCoverage),
            requireOptimality: try container.decode(Bool.self, forKey: .requireOptimality),
            maximumSolverCost: try container.decodeIfPresent(Double.self, forKey: .maximumSolverCost),
            domainArtifactID: try container.decodeIfPresent(String.self, forKey: .domainArtifactID),
            domainPath: try container.decodeIfPresent(String.self, forKey: .domainPath),
            problemArtifactID: try container.decodeIfPresent(String.self, forKey: .problemArtifactID),
            problemPath: try container.decodeIfPresent(String.self, forKey: .problemPath),
            pddlExportArtifactID: try container.decodeIfPresent(String.self, forKey: .pddlExportArtifactID),
            pddlExportPath: try container.decodeIfPresent(String.self, forKey: .pddlExportPath),
            workingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .workingDirectoryPath),
            solverPlanOutputPath: try container.decodeIfPresent(String.self, forKey: .solverPlanOutputPath),
            proofArtifactID: try container.decodeIfPresent(String.self, forKey: .proofArtifactID),
            proofPath: try container.decodeIfPresent(String.self, forKey: .proofPath),
            proofCheckerWorkingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .proofCheckerWorkingDirectoryPath)
        )
    }
}
