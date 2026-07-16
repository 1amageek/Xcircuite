public struct XcircuiteSymbolicPlannerSolverCorpusSuiteSpec: Codable, Sendable, Hashable {
    public var schemaVersion: Int
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
        case schemaVersion
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
        schemaVersion: Int = 1,
        suiteID: String,
        toolID: String = "external-symbolic-planner",
        executablePath: String,
        arguments: [String] = [],
        timeoutSeconds: Double = 300,
        policyID: String = "symbolic-planner-solver-corpus-assessment-v1",
        requiredCoverageTags: [String] = [],
        requireProofValidation: Bool = false,
        proofCheckerExecutablePath: String? = nil,
        proofCheckerArguments: [String] = [],
        proofCheckerTimeoutSeconds: Double = 30,
        proofCheckerWorkingDirectoryPath: String? = nil,
        cases: [XcircuiteSymbolicPlannerSolverCorpusCaseRequest]
    ) {
        self.schemaVersion = schemaVersion
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

    public init(request: XcircuiteSymbolicPlannerSolverCorpusAssessmentRequest) {
        self.init(
            suiteID: request.suiteID,
            toolID: request.toolID,
            executablePath: request.executablePath,
            arguments: request.arguments,
            timeoutSeconds: request.timeoutSeconds,
            policyID: request.policyID,
            requiredCoverageTags: request.requiredCoverageTags,
            requireProofValidation: request.requireProofValidation,
            proofCheckerExecutablePath: request.proofCheckerExecutablePath,
            proofCheckerArguments: request.proofCheckerArguments,
            proofCheckerTimeoutSeconds: request.proofCheckerTimeoutSeconds,
            proofCheckerWorkingDirectoryPath: request.proofCheckerWorkingDirectoryPath,
            cases: request.cases
        )
    }

    public var assessmentRequest: XcircuiteSymbolicPlannerSolverCorpusAssessmentRequest {
        XcircuiteSymbolicPlannerSolverCorpusAssessmentRequest(
            suiteID: suiteID,
            toolID: toolID,
            executablePath: executablePath,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds,
            policyID: policyID,
            requiredCoverageTags: requiredCoverageTags,
            requireProofValidation: requireProofValidation,
            proofCheckerExecutablePath: proofCheckerExecutablePath,
            proofCheckerArguments: proofCheckerArguments,
            proofCheckerTimeoutSeconds: proofCheckerTimeoutSeconds,
            proofCheckerWorkingDirectoryPath: proofCheckerWorkingDirectoryPath,
            cases: cases
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            suiteID: try container.decode(String.self, forKey: .suiteID),
            toolID: try container.decode(String.self, forKey: .toolID),
            executablePath: try container.decode(String.self, forKey: .executablePath),
            arguments: try container.decode([String].self, forKey: .arguments),
            timeoutSeconds: try container.decode(Double.self, forKey: .timeoutSeconds),
            policyID: try container.decode(String.self, forKey: .policyID),
            requiredCoverageTags: try container.decode([String].self, forKey: .requiredCoverageTags),
            requireProofValidation: try container.decode(Bool.self, forKey: .requireProofValidation),
            proofCheckerExecutablePath: try container.decodeIfPresent(String.self, forKey: .proofCheckerExecutablePath),
            proofCheckerArguments: try container.decode([String].self, forKey: .proofCheckerArguments),
            proofCheckerTimeoutSeconds: try container.decode(Double.self, forKey: .proofCheckerTimeoutSeconds),
            proofCheckerWorkingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .proofCheckerWorkingDirectoryPath),
            cases: try container.decode([XcircuiteSymbolicPlannerSolverCorpusCaseRequest].self, forKey: .cases)
        )
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported symbolic planner solver corpus suite schema version: \(schemaVersion)."
            )
        }
    }
}
