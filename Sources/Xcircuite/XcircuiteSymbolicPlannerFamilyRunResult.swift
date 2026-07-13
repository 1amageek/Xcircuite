import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerFamilyRunResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var familyRun: XcircuiteSymbolicPlannerFamilyRun
    public var familyRunArtifact: ArtifactReference

    public init(
        schemaVersion: Int = 1,
        status: String,
        familyRun: XcircuiteSymbolicPlannerFamilyRun,
        familyRunArtifact: ArtifactReference
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.familyRun = familyRun
        self.familyRunArtifact = familyRunArtifact
    }
}
