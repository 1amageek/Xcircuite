import Foundation

public struct XcircuiteSymbolicPlannerTrace: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var strategy: String
    public var problemPath: String
    public var actionDomainSnapshotPath: String?
    public var actionDomainSnapshotArtifactID: String?
    public var rejectedPlansPath: String?
    public var rejectedPlanFeedbackRecordCount: Int
    public var globalRejectedPlanFeedbackCount: Int
    public var policyTrace: XcircuiteSymbolicPlannerPolicyTrace?
    public var calibrationTrace: XcircuiteSymbolicPlannerCalibrationTrace?
    public var generatedPlanID: String
    public var selectedActionIDs: [String]
    public var unresolvedObjectiveIDs: [String]
    public var initialSymbolicState: [String]
    public var finalSymbolicState: [String]
    public var goalCoverageStatus: String
    public var goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage]
    public var missingGoalAtoms: [String]
    public var objectiveTraces: [XcircuiteSymbolicPlannerObjectiveTrace]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        strategy: String,
        problemPath: String,
        actionDomainSnapshotPath: String? = nil,
        actionDomainSnapshotArtifactID: String? = nil,
        rejectedPlansPath: String? = nil,
        rejectedPlanFeedbackRecordCount: Int = 0,
        globalRejectedPlanFeedbackCount: Int = 0,
        policyTrace: XcircuiteSymbolicPlannerPolicyTrace? = nil,
        calibrationTrace: XcircuiteSymbolicPlannerCalibrationTrace? = nil,
        generatedPlanID: String,
        selectedActionIDs: [String],
        unresolvedObjectiveIDs: [String],
        initialSymbolicState: [String] = [],
        finalSymbolicState: [String] = [],
        goalCoverageStatus: String = "not-evaluated",
        goalCoverage: [XcircuiteSymbolicPlannerGoalCoverage] = [],
        missingGoalAtoms: [String] = [],
        objectiveTraces: [XcircuiteSymbolicPlannerObjectiveTrace]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.strategy = strategy
        self.problemPath = problemPath
        self.actionDomainSnapshotPath = actionDomainSnapshotPath
        self.actionDomainSnapshotArtifactID = actionDomainSnapshotArtifactID
        self.rejectedPlansPath = rejectedPlansPath
        self.rejectedPlanFeedbackRecordCount = rejectedPlanFeedbackRecordCount
        self.globalRejectedPlanFeedbackCount = globalRejectedPlanFeedbackCount
        self.policyTrace = policyTrace
        self.calibrationTrace = calibrationTrace
        self.generatedPlanID = generatedPlanID
        self.selectedActionIDs = selectedActionIDs
        self.unresolvedObjectiveIDs = unresolvedObjectiveIDs
        self.initialSymbolicState = initialSymbolicState
        self.finalSymbolicState = finalSymbolicState
        self.goalCoverageStatus = goalCoverageStatus
        self.goalCoverage = goalCoverage
        self.missingGoalAtoms = missingGoalAtoms
        self.objectiveTraces = objectiveTraces
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case problemID
        case strategy
        case problemPath
        case actionDomainSnapshotPath
        case actionDomainSnapshotArtifactID
        case rejectedPlansPath
        case rejectedPlanFeedbackRecordCount
        case globalRejectedPlanFeedbackCount
        case policyTrace
        case calibrationTrace
        case generatedPlanID
        case selectedActionIDs
        case unresolvedObjectiveIDs
        case initialSymbolicState
        case finalSymbolicState
        case goalCoverageStatus
        case goalCoverage
        case missingGoalAtoms
        case objectiveTraces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.runID = try container.decode(String.self, forKey: .runID)
        self.problemID = try container.decode(String.self, forKey: .problemID)
        self.strategy = try container.decode(String.self, forKey: .strategy)
        self.problemPath = try container.decode(String.self, forKey: .problemPath)
        self.actionDomainSnapshotPath = try container.decodeIfPresent(String.self, forKey: .actionDomainSnapshotPath)
        self.actionDomainSnapshotArtifactID = try container.decodeIfPresent(String.self, forKey: .actionDomainSnapshotArtifactID)
        self.rejectedPlansPath = try container.decodeIfPresent(String.self, forKey: .rejectedPlansPath)
        self.rejectedPlanFeedbackRecordCount = try container.decodeIfPresent(
            Int.self,
            forKey: .rejectedPlanFeedbackRecordCount
        ) ?? 0
        self.globalRejectedPlanFeedbackCount = try container.decodeIfPresent(
            Int.self,
            forKey: .globalRejectedPlanFeedbackCount
        ) ?? 0
        self.policyTrace = try container.decodeIfPresent(
            XcircuiteSymbolicPlannerPolicyTrace.self,
            forKey: .policyTrace
        )
        self.calibrationTrace = try container.decodeIfPresent(
            XcircuiteSymbolicPlannerCalibrationTrace.self,
            forKey: .calibrationTrace
        )
        self.generatedPlanID = try container.decode(String.self, forKey: .generatedPlanID)
        self.selectedActionIDs = try container.decode([String].self, forKey: .selectedActionIDs)
        self.unresolvedObjectiveIDs = try container.decode([String].self, forKey: .unresolvedObjectiveIDs)
        self.initialSymbolicState = try container.decodeIfPresent([String].self, forKey: .initialSymbolicState) ?? []
        self.finalSymbolicState = try container.decodeIfPresent([String].self, forKey: .finalSymbolicState) ?? []
        self.goalCoverageStatus = try container.decodeIfPresent(String.self, forKey: .goalCoverageStatus) ?? "not-evaluated"
        self.goalCoverage = try container.decodeIfPresent(
            [XcircuiteSymbolicPlannerGoalCoverage].self,
            forKey: .goalCoverage
        ) ?? []
        self.missingGoalAtoms = try container.decodeIfPresent([String].self, forKey: .missingGoalAtoms) ?? []
        self.objectiveTraces = try container.decode([XcircuiteSymbolicPlannerObjectiveTrace].self, forKey: .objectiveTraces)
    }
}
