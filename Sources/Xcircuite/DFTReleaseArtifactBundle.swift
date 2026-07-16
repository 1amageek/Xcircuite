import CircuiteFoundation
import DesignFlowKernel
import DFTCore
import Foundation

public struct DFTReleaseArtifactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var createdAt: Date
    public var request: ArtifactReference
    public var result: ArtifactReference
    public var processQualificationEvidence: ArtifactReference
    public var downstreamEvidenceBundle: ArtifactReference
    public var downstreamEvidence: [DFTReleaseDownstreamEvidence]
    public var candidateArtifacts: [ArtifactReference]
    public var approval: FlowApprovalRecord

    public init(
        runID: String,
        createdAt: Date = Date(),
        request: ArtifactReference,
        result: ArtifactReference,
        processQualificationEvidence: ArtifactReference,
        downstreamEvidenceBundle: ArtifactReference,
        downstreamEvidence: [DFTReleaseDownstreamEvidence],
        candidateArtifacts: [ArtifactReference],
        approval: FlowApprovalRecord,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.createdAt = createdAt
        self.request = request
        self.result = result
        self.processQualificationEvidence = processQualificationEvidence
        self.downstreamEvidenceBundle = downstreamEvidenceBundle
        self.downstreamEvidence = downstreamEvidence
        self.candidateArtifacts = candidateArtifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.approval = approval
    }
}
