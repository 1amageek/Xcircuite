import Foundation
import DFTCore
import CircuiteFoundation
import DesignFlowKernel

public struct DFTReleaseArtifactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var createdAt: Date
    public var eligibility: ArtifactReference
    public var request: ArtifactReference
    public var result: ArtifactReference
    public var qualificationProvenance: ArtifactReference?
    public var processQualificationEvidence: ArtifactReference
    public var processQualificationSupportArtifacts: [ArtifactReference]
    public var downstreamEvidenceBundle: ArtifactReference
    public var downstreamEvidence: [DFTReleaseDownstreamEvidence]
    public var candidateArtifacts: [ArtifactReference]
    public var approval: DFTReleaseReviewApproval

    public init(
        runID: String,
        createdAt: Date = Date(),
        eligibility: ArtifactReference,
        request: ArtifactReference,
        result: ArtifactReference,
        qualificationProvenance: ArtifactReference?,
        processQualificationEvidence: ArtifactReference,
        processQualificationSupportArtifacts: [ArtifactReference],
        downstreamEvidenceBundle: ArtifactReference,
        downstreamEvidence: [DFTReleaseDownstreamEvidence],
        candidateArtifacts: [ArtifactReference],
        approval: DFTReleaseReviewApproval,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.createdAt = createdAt
        self.eligibility = eligibility
        self.request = request
        self.result = result
        self.qualificationProvenance = qualificationProvenance
        self.processQualificationEvidence = processQualificationEvidence
        self.processQualificationSupportArtifacts = processQualificationSupportArtifacts
        self.downstreamEvidenceBundle = downstreamEvidenceBundle
        self.downstreamEvidence = downstreamEvidence
        self.candidateArtifacts = candidateArtifacts
        self.approval = approval
    }
}
