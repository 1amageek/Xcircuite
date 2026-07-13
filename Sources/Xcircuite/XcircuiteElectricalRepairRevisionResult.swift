import ElectricalSignoffEngine
import Foundation
import PhysicalDesignCore
import XcircuitePackage

public struct XcircuiteElectricalRepairRevisionResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct DigestLineage: Sendable, Hashable, Codable {
        public var parentLayoutDigest: String
        public var newLayoutDigest: String?
        public var designDigest: String
        public var pdkDigest: String

        public init(
            parentLayoutDigest: String,
            newLayoutDigest: String?,
            designDigest: String,
            pdkDigest: String
        ) {
            self.parentLayoutDigest = parentLayoutDigest
            self.newLayoutDigest = newLayoutDigest
            self.designDigest = designDigest
            self.pdkDigest = pdkDigest
        }
    }

    public var schemaVersion: Int
    public var runID: String
    public var selectedCandidateID: String
    public var repairPlanArtifact: XcircuiteFileReference
    public var physicalDesignResult: XcircuiteEngineResultEnvelope<PhysicalDesignPayload>
    public var digestLineage: DigestLineage
    public var rerunRequired: Bool

    public init(
        runID: String,
        selectedCandidateID: String,
        repairPlanArtifact: XcircuiteFileReference,
        physicalDesignResult: XcircuiteEngineResultEnvelope<PhysicalDesignPayload>,
        digestLineage: DigestLineage,
        rerunRequired: Bool = true,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.selectedCandidateID = selectedCandidateID
        self.repairPlanArtifact = repairPlanArtifact
        self.physicalDesignResult = physicalDesignResult
        self.digestLineage = digestLineage
        self.rerunRequired = rerunRequired
    }

    public var committedNewRevision: Bool {
        guard physicalDesignResult.status == .completed,
              let newDigest = digestLineage.newLayoutDigest else {
            return false
        }
        return !newDigest.isEmpty && newDigest != digestLineage.parentLayoutDigest
    }
}
