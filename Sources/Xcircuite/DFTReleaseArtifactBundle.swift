import Foundation
import DFTCore
import XcircuitePackage

public struct DFTReleaseArtifactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var createdAt: Date
    public var eligibility: XcircuiteFileReference
    public var request: XcircuiteFileReference
    public var result: XcircuiteFileReference
    public var qualificationProvenance: XcircuiteFileReference?
    public var processQualificationEvidence: XcircuiteFileReference
    public var downstreamEvidenceBundle: XcircuiteFileReference
    public var downstreamEvidence: [DFTReleaseDownstreamEvidence]
    public var candidateArtifacts: [XcircuiteFileReference]
    public var approval: DFTReleaseReviewApproval

    public init(
        runID: String,
        createdAt: Date = Date(),
        eligibility: XcircuiteFileReference,
        request: XcircuiteFileReference,
        result: XcircuiteFileReference,
        qualificationProvenance: XcircuiteFileReference?,
        processQualificationEvidence: XcircuiteFileReference,
        downstreamEvidenceBundle: XcircuiteFileReference,
        downstreamEvidence: [DFTReleaseDownstreamEvidence],
        candidateArtifacts: [XcircuiteFileReference],
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
        self.downstreamEvidenceBundle = downstreamEvidenceBundle
        self.downstreamEvidence = downstreamEvidence
        self.candidateArtifacts = candidateArtifacts
        self.approval = approval
    }
}
