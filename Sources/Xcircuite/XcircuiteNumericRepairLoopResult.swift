import Foundation

public struct XcircuiteNumericRepairLoopResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var problemID: String?
    public var loopArtifactPath: String
    public var maxIterations: Int
    public var iterationCount: Int
    public var accepted: Bool
    public var acceptedIterationIndex: Int?
    public var selectedCandidateID: String?
    public var finalPlanID: String?
    public var calibrationPolicy: String?
    public var policyTraces: [XcircuiteNumericRepairLoopPolicyTrace]?
    public var iterations: [XcircuiteNumericRepairLoopIteration]
    public var diagnostics: [XcircuiteNumericRepairLoopDiagnostic]
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        problemID: String?,
        loopArtifactPath: String,
        maxIterations: Int,
        iterationCount: Int,
        accepted: Bool,
        acceptedIterationIndex: Int? = nil,
        selectedCandidateID: String? = nil,
        finalPlanID: String? = nil,
        calibrationPolicy: String? = nil,
        policyTraces: [XcircuiteNumericRepairLoopPolicyTrace]? = nil,
        iterations: [XcircuiteNumericRepairLoopIteration],
        diagnostics: [XcircuiteNumericRepairLoopDiagnostic] = [],
        nextActions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.problemID = problemID
        self.loopArtifactPath = loopArtifactPath
        self.maxIterations = maxIterations
        self.iterationCount = iterationCount
        self.accepted = accepted
        self.acceptedIterationIndex = acceptedIterationIndex
        self.selectedCandidateID = selectedCandidateID
        self.finalPlanID = finalPlanID
        self.calibrationPolicy = calibrationPolicy
        self.policyTraces = policyTraces
        self.iterations = iterations
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
