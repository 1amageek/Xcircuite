public struct XcircuiteSymbolicPlannerSolverCertificate: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var certificateID: String?
    public var solverName: String?
    public var solverFamily: String?
    public var certificateFormat: String
    public var status: String
    public var optimalityStatus: String?
    public var proofStatus: String?
    public var planCost: Double?
    public var planCostUnit: String?
    public var planLength: Int?
    public var makespan: Double?
    public var lowerBound: Double?
    public var upperBound: Double?
    public var goalCoverageStatus: String?
    public var expectedActionIDs: [String]
    public var observedActionIDs: [String]
    public var claims: [XcircuiteSymbolicPlannerSolverCertificateClaim]
    public var evidenceLines: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case certificateID
        case solverName
        case solverFamily
        case certificateFormat
        case status
        case optimalityStatus
        case proofStatus
        case planCost
        case planCostUnit
        case planLength
        case makespan
        case lowerBound
        case upperBound
        case goalCoverageStatus
        case expectedActionIDs
        case observedActionIDs
        case claims
        case evidenceLines
    }

    public init(
        schemaVersion: Int = 1,
        certificateID: String? = nil,
        solverName: String? = nil,
        solverFamily: String? = nil,
        certificateFormat: String,
        status: String = "parsed",
        optimalityStatus: String? = nil,
        proofStatus: String? = nil,
        planCost: Double? = nil,
        planCostUnit: String? = nil,
        planLength: Int? = nil,
        makespan: Double? = nil,
        lowerBound: Double? = nil,
        upperBound: Double? = nil,
        goalCoverageStatus: String? = nil,
        expectedActionIDs: [String] = [],
        observedActionIDs: [String] = [],
        claims: [XcircuiteSymbolicPlannerSolverCertificateClaim] = [],
        evidenceLines: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.certificateID = certificateID
        self.solverName = solverName
        self.solverFamily = solverFamily
        self.certificateFormat = certificateFormat
        self.status = status
        self.optimalityStatus = optimalityStatus
        self.proofStatus = proofStatus
        self.planCost = planCost
        self.planCostUnit = planCostUnit
        self.planLength = planLength
        self.makespan = makespan
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.goalCoverageStatus = goalCoverageStatus
        self.expectedActionIDs = expectedActionIDs
        self.observedActionIDs = observedActionIDs
        self.claims = claims
        self.evidenceLines = evidenceLines
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            certificateID: try container.decodeIfPresent(String.self, forKey: .certificateID),
            solverName: try container.decodeIfPresent(String.self, forKey: .solverName),
            solverFamily: try container.decodeIfPresent(String.self, forKey: .solverFamily),
            certificateFormat: try container.decode(String.self, forKey: .certificateFormat),
            status: try container.decode(String.self, forKey: .status),
            optimalityStatus: try container.decodeIfPresent(String.self, forKey: .optimalityStatus),
            proofStatus: try container.decodeIfPresent(String.self, forKey: .proofStatus),
            planCost: try container.decodeIfPresent(Double.self, forKey: .planCost),
            planCostUnit: try container.decodeIfPresent(String.self, forKey: .planCostUnit),
            planLength: try container.decodeIfPresent(Int.self, forKey: .planLength),
            makespan: try container.decodeIfPresent(Double.self, forKey: .makespan),
            lowerBound: try container.decodeIfPresent(Double.self, forKey: .lowerBound),
            upperBound: try container.decodeIfPresent(Double.self, forKey: .upperBound),
            goalCoverageStatus: try container.decodeIfPresent(String.self, forKey: .goalCoverageStatus),
            expectedActionIDs: try container.decode([String].self, forKey: .expectedActionIDs),
            observedActionIDs: try container.decode([String].self, forKey: .observedActionIDs),
            claims: try container.decode([XcircuiteSymbolicPlannerSolverCertificateClaim].self, forKey: .claims),
            evidenceLines: try container.decode([String].self, forKey: .evidenceLines)
        )
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported symbolic planner solver certificate schema version: \(schemaVersion)."
            )
        }
    }
}
