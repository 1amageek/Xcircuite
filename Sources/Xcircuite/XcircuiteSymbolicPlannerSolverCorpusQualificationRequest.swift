public struct XcircuiteSymbolicPlannerSolverCorpusQualificationRequest: Codable, Sendable, Hashable {
    public var suiteID: String
    public var toolID: String
    public var executablePath: String
    public var arguments: [String]
    public var timeoutSeconds: Double
    public var policyID: String
    public var requiredCoverageTags: [String]
    public var requireProofValidation: Bool
    public var proofCheckerExecutablePath: String?
    public var proofCheckerArguments: [String]
    public var proofCheckerTimeoutSeconds: Double
    public var proofCheckerWorkingDirectoryPath: String?
    public var cases: [XcircuiteSymbolicPlannerSolverCorpusCaseRequest]

    private enum CodingKeys: String, CodingKey {
        case suiteID
        case toolID
        case executablePath
        case arguments
        case timeoutSeconds
        case policyID
        case requiredCoverageTags
        case requireProofValidation
        case proofCheckerExecutablePath
        case proofCheckerArguments
        case proofCheckerTimeoutSeconds
        case proofCheckerWorkingDirectoryPath
        case cases
    }

    public init(
        suiteID: String,
        toolID: String = "external-symbolic-planner",
        executablePath: String,
        arguments: [String] = [],
        timeoutSeconds: Double = 300,
        policyID: String = "symbolic-planner-solver-corpus-qualification-v1",
        requiredCoverageTags: [String] = [],
        requireProofValidation: Bool = false,
        proofCheckerExecutablePath: String? = nil,
        proofCheckerArguments: [String] = [],
        proofCheckerTimeoutSeconds: Double = 30,
        proofCheckerWorkingDirectoryPath: String? = nil,
        cases: [XcircuiteSymbolicPlannerSolverCorpusCaseRequest]
    ) {
        self.suiteID = suiteID
        self.toolID = toolID
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.policyID = policyID
        self.requiredCoverageTags = requiredCoverageTags
        self.requireProofValidation = requireProofValidation
        self.proofCheckerExecutablePath = proofCheckerExecutablePath
        self.proofCheckerArguments = proofCheckerArguments
        self.proofCheckerTimeoutSeconds = proofCheckerTimeoutSeconds
        self.proofCheckerWorkingDirectoryPath = proofCheckerWorkingDirectoryPath
        self.cases = cases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            suiteID: try container.decode(String.self, forKey: .suiteID),
            toolID: try container.decodeIfPresent(String.self, forKey: .toolID) ?? "external-symbolic-planner",
            executablePath: try container.decode(String.self, forKey: .executablePath),
            arguments: try container.decodeIfPresent([String].self, forKey: .arguments) ?? [],
            timeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 300,
            policyID: try container.decodeIfPresent(String.self, forKey: .policyID) ?? "symbolic-planner-solver-corpus-qualification-v1",
            requiredCoverageTags: try container.decodeIfPresent([String].self, forKey: .requiredCoverageTags) ?? [],
            requireProofValidation: try container.decodeIfPresent(Bool.self, forKey: .requireProofValidation) ?? false,
            proofCheckerExecutablePath: try container.decodeIfPresent(String.self, forKey: .proofCheckerExecutablePath),
            proofCheckerArguments: try container.decodeIfPresent([String].self, forKey: .proofCheckerArguments) ?? [],
            proofCheckerTimeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .proofCheckerTimeoutSeconds) ?? 30,
            proofCheckerWorkingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .proofCheckerWorkingDirectoryPath),
            cases: try container.decode([XcircuiteSymbolicPlannerSolverCorpusCaseRequest].self, forKey: .cases)
        )
    }
}
