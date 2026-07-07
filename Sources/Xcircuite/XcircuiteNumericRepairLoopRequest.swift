import Foundation

public struct XcircuiteNumericRepairLoopRequest: Codable, Sendable, Hashable {
    public var runID: String
    public var problemArtifactID: String?
    public var problemPath: String?
    public var initialCandidateStrategy: String
    public var feedbackCandidateStrategy: String
    public var maxCandidates: Int
    public var maxIterations: Int
    public var synthesisStrategy: String
    public var verificationMode: String
    public var actor: String
    public var calibrationPolicy: String?

    public init(
        runID: String,
        problemArtifactID: String? = nil,
        problemPath: String? = nil,
        initialCandidateStrategy: String = "adaptive-bounded-refinement",
        feedbackCandidateStrategy: String = "feedback-aware-bounded-refinement",
        maxCandidates: Int = 9,
        maxIterations: Int = 5,
        synthesisStrategy: String = "parameter-candidate-to-netlist-edit",
        verificationMode: String = "post-execution",
        actor: String = "xcircuite-numeric-repair-loop",
        calibrationPolicy: String? = "disabled"
    ) {
        self.runID = runID
        self.problemArtifactID = problemArtifactID
        self.problemPath = problemPath
        self.initialCandidateStrategy = initialCandidateStrategy
        self.feedbackCandidateStrategy = feedbackCandidateStrategy
        self.maxCandidates = maxCandidates
        self.maxIterations = maxIterations
        self.synthesisStrategy = synthesisStrategy
        self.verificationMode = verificationMode
        self.actor = actor
        self.calibrationPolicy = calibrationPolicy
    }
}
