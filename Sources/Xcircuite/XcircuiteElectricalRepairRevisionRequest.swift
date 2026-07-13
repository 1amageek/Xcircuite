import ElectricalSignoffEngine
import Foundation
import PhysicalDesignCore
import DesignFlowKernel

public struct XcircuiteElectricalRepairRevisionRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var repairPlanArtifact: XcircuiteFileReference
    public var selectedCandidateID: String
    public var physicalDesignRequest: PhysicalDesignRequest

    public init(
        runID: String,
        repairPlanArtifact: XcircuiteFileReference,
        selectedCandidateID: String,
        physicalDesignRequest: PhysicalDesignRequest,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.repairPlanArtifact = repairPlanArtifact
        self.selectedCandidateID = selectedCandidateID
        self.physicalDesignRequest = physicalDesignRequest
    }
}
