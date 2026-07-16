public struct XcircuiteSymbolicPlannerSolverFamilyBatchCandidateRequest: Codable, Sendable, Hashable {
    public var candidateID: String?
    public var toolID: String
    public var executablePath: String
    public var arguments: [String]
    public var timeoutSeconds: Double
    public var expectedActionIDs: [String]
    public var requireGoalCoverage: Bool
    public var requireOptimality: Bool
    public var maximumSolverCost: Double?
    public var requireNativeCertificate: Bool
    public var requireProofValidation: Bool
    public var policyID: String
    public var domainArtifactID: String?
    public var domainPath: String?
    public var problemArtifactID: String?
    public var problemPath: String?
    public var pddlExportArtifactID: String?
    public var pddlExportPath: String?
    public var workingDirectoryPath: String?
    public var solverPlanOutputPath: String?
    public var certificateArtifactID: String?
    public var certificatePath: String?
    public var certificateFormat: String
    public var proofArtifactID: String?
    public var proofPath: String?
    public var proofCheckerExecutablePath: String?
    public var proofCheckerArguments: [String]
    public var proofCheckerTimeoutSeconds: Double
    public var proofCheckerWorkingDirectoryPath: String?

    private enum CodingKeys: String, CodingKey {
        case candidateID
        case toolID
        case executablePath
        case arguments
        case timeoutSeconds
        case expectedActionIDs
        case requireGoalCoverage
        case requireOptimality
        case maximumSolverCost
        case requireNativeCertificate
        case requireProofValidation
        case policyID
        case domainArtifactID
        case domainPath
        case problemArtifactID
        case problemPath
        case pddlExportArtifactID
        case pddlExportPath
        case workingDirectoryPath
        case solverPlanOutputPath
        case certificateArtifactID
        case certificatePath
        case certificateFormat
        case proofArtifactID
        case proofPath
        case proofCheckerExecutablePath
        case proofCheckerArguments
        case proofCheckerTimeoutSeconds
        case proofCheckerWorkingDirectoryPath
    }

    public init(
        candidateID: String? = nil,
        toolID: String,
        executablePath: String,
        arguments: [String] = [],
        timeoutSeconds: Double = 300,
        expectedActionIDs: [String] = [],
        requireGoalCoverage: Bool = true,
        requireOptimality: Bool = false,
        maximumSolverCost: Double? = nil,
        requireNativeCertificate: Bool = false,
        requireProofValidation: Bool = false,
        policyID: String = "symbolic-planner-solver-qualification-v1",
        domainArtifactID: String? = nil,
        domainPath: String? = nil,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        pddlExportArtifactID: String? = nil,
        pddlExportPath: String? = nil,
        workingDirectoryPath: String? = nil,
        solverPlanOutputPath: String? = nil,
        certificateArtifactID: String? = nil,
        certificatePath: String? = nil,
        certificateFormat: String = "auto",
        proofArtifactID: String? = nil,
        proofPath: String? = nil,
        proofCheckerExecutablePath: String? = nil,
        proofCheckerArguments: [String] = [],
        proofCheckerTimeoutSeconds: Double = 30,
        proofCheckerWorkingDirectoryPath: String? = nil
    ) {
        self.candidateID = candidateID
        self.toolID = toolID
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.expectedActionIDs = expectedActionIDs
        self.requireGoalCoverage = requireGoalCoverage
        self.requireOptimality = requireOptimality
        self.maximumSolverCost = maximumSolverCost
        self.requireNativeCertificate = requireNativeCertificate
        self.requireProofValidation = requireProofValidation
        self.policyID = policyID
        self.domainArtifactID = domainArtifactID
        self.domainPath = domainPath
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.pddlExportArtifactID = pddlExportArtifactID
        self.pddlExportPath = pddlExportPath
        self.workingDirectoryPath = workingDirectoryPath
        self.solverPlanOutputPath = solverPlanOutputPath
        self.certificateArtifactID = certificateArtifactID
        self.certificatePath = certificatePath
        self.certificateFormat = certificateFormat
        self.proofArtifactID = proofArtifactID
        self.proofPath = proofPath
        self.proofCheckerExecutablePath = proofCheckerExecutablePath
        self.proofCheckerArguments = proofCheckerArguments
        self.proofCheckerTimeoutSeconds = proofCheckerTimeoutSeconds
        self.proofCheckerWorkingDirectoryPath = proofCheckerWorkingDirectoryPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            candidateID: try container.decodeIfPresent(String.self, forKey: .candidateID),
            toolID: try container.decode(String.self, forKey: .toolID),
            executablePath: try container.decode(String.self, forKey: .executablePath),
            arguments: try container.decode([String].self, forKey: .arguments),
            timeoutSeconds: try container.decode(Double.self, forKey: .timeoutSeconds),
            expectedActionIDs: try container.decode([String].self, forKey: .expectedActionIDs),
            requireGoalCoverage: try container.decode(Bool.self, forKey: .requireGoalCoverage),
            requireOptimality: try container.decode(Bool.self, forKey: .requireOptimality),
            maximumSolverCost: try container.decodeIfPresent(Double.self, forKey: .maximumSolverCost),
            requireNativeCertificate: try container.decode(Bool.self, forKey: .requireNativeCertificate),
            requireProofValidation: try container.decode(Bool.self, forKey: .requireProofValidation),
            policyID: try container.decode(String.self, forKey: .policyID),
            domainArtifactID: try container.decodeIfPresent(String.self, forKey: .domainArtifactID),
            domainPath: try container.decodeIfPresent(String.self, forKey: .domainPath),
            problemArtifactID: try container.decodeIfPresent(String.self, forKey: .problemArtifactID),
            problemPath: try container.decodeIfPresent(String.self, forKey: .problemPath),
            pddlExportArtifactID: try container.decodeIfPresent(String.self, forKey: .pddlExportArtifactID),
            pddlExportPath: try container.decodeIfPresent(String.self, forKey: .pddlExportPath),
            workingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .workingDirectoryPath),
            solverPlanOutputPath: try container.decodeIfPresent(String.self, forKey: .solverPlanOutputPath),
            certificateArtifactID: try container.decodeIfPresent(String.self, forKey: .certificateArtifactID),
            certificatePath: try container.decodeIfPresent(String.self, forKey: .certificatePath),
            certificateFormat: try container.decode(String.self, forKey: .certificateFormat),
            proofArtifactID: try container.decodeIfPresent(String.self, forKey: .proofArtifactID),
            proofPath: try container.decodeIfPresent(String.self, forKey: .proofPath),
            proofCheckerExecutablePath: try container.decodeIfPresent(String.self, forKey: .proofCheckerExecutablePath),
            proofCheckerArguments: try container.decode([String].self, forKey: .proofCheckerArguments),
            proofCheckerTimeoutSeconds: try container.decode(Double.self, forKey: .proofCheckerTimeoutSeconds),
            proofCheckerWorkingDirectoryPath: try container.decodeIfPresent(String.self, forKey: .proofCheckerWorkingDirectoryPath)
        )
    }

    public func qualificationRequest(runID: String) -> XcircuiteSymbolicPlannerSolverQualificationRequest {
        XcircuiteSymbolicPlannerSolverQualificationRequest(
            runID: runID,
            toolID: toolID,
            executablePath: executablePath,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds,
            expectedActionIDs: expectedActionIDs,
            requireGoalCoverage: requireGoalCoverage,
            requireOptimality: requireOptimality,
            maximumSolverCost: maximumSolverCost,
            requireNativeCertificate: requireNativeCertificate,
            requireProofValidation: requireProofValidation,
            policyID: policyID,
            domainArtifactID: domainArtifactID,
            domainPath: domainPath,
            problemArtifactID: problemArtifactID,
            problemPath: problemPath,
            pddlExportArtifactID: pddlExportArtifactID,
            pddlExportPath: pddlExportPath,
            workingDirectoryPath: workingDirectoryPath,
            solverPlanOutputPath: solverPlanOutputPath,
            certificateArtifactID: certificateArtifactID,
            certificatePath: certificatePath,
            certificateFormat: certificateFormat,
            proofArtifactID: proofArtifactID,
            proofPath: proofPath,
            proofCheckerExecutablePath: proofCheckerExecutablePath,
            proofCheckerArguments: proofCheckerArguments,
            proofCheckerTimeoutSeconds: proofCheckerTimeoutSeconds,
            proofCheckerWorkingDirectoryPath: proofCheckerWorkingDirectoryPath
        )
    }
}
