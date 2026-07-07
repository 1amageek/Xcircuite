import Foundation
import XcircuitePackage

public struct XcircuiteRepairPlanFormulationCompilationResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var formulationID: String
    public var problemID: String
    public var formulationArtifact: XcircuiteFileReference
    public var problemArtifact: XcircuiteFileReference
    public var diagnosticCodes: [String]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        formulationID: String,
        problemID: String,
        formulationArtifact: XcircuiteFileReference,
        problemArtifact: XcircuiteFileReference,
        diagnosticCodes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.formulationID = formulationID
        self.problemID = problemID
        self.formulationArtifact = formulationArtifact
        self.problemArtifact = problemArtifact
        self.diagnosticCodes = diagnosticCodes
    }
}
