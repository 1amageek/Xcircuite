import Foundation
import DesignFlowKernel

public struct XcircuiteNetlistParameterEditReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var runID: String
    public var problemID: String
    public var planID: String
    public var stepID: String
    public var sourceParameterCandidateID: String?
    public var sourceNetlistPath: String
    public var outputNetlistPath: String
    public var outputNetlistArtifactID: String
    public var edits: [XcircuiteNetlistParameterEdit]
    public var diagnostics: [XcircuitePlanVerificationDiagnostic]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        problemID: String,
        planID: String,
        stepID: String,
        sourceParameterCandidateID: String?,
        sourceNetlistPath: String,
        outputNetlistPath: String,
        outputNetlistArtifactID: String,
        edits: [XcircuiteNetlistParameterEdit],
        diagnostics: [XcircuitePlanVerificationDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.problemID = problemID
        self.planID = planID
        self.stepID = stepID
        self.sourceParameterCandidateID = sourceParameterCandidateID
        self.sourceNetlistPath = sourceNetlistPath
        self.outputNetlistPath = outputNetlistPath
        self.outputNetlistArtifactID = outputNetlistArtifactID
        self.edits = edits
        self.diagnostics = diagnostics
    }
}
