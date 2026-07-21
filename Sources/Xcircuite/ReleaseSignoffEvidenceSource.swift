import CircuiteFoundation
import Foundation
import ReleaseCore

public struct ReleaseSignoffEvidenceSource: Sendable, Hashable, Codable {
    public var axis: ReleaseSignoffAxis
    public var producer: ReleaseSignoffEvidenceProducer
    public var requestArtifact: ArtifactReference
    public var resultArtifact: ArtifactReference
    public var executionInputs: [ArtifactReference]
    public var derivedInputs: [ArtifactReference]
    public var rawEvidence: [ArtifactReference]
    public var manifestArtifact: ArtifactReference?
    public var reportArtifact: ArtifactReference?
    public var qualificationEvidence: [ArtifactReference]
    public var qualificationArtifact: ArtifactReference

    public init(
        axis: ReleaseSignoffAxis,
        producer: ReleaseSignoffEvidenceProducer,
        requestArtifact: ArtifactReference,
        resultArtifact: ArtifactReference,
        executionInputs: [ArtifactReference] = [],
        derivedInputs: [ArtifactReference] = [],
        rawEvidence: [ArtifactReference] = [],
        manifestArtifact: ArtifactReference? = nil,
        reportArtifact: ArtifactReference? = nil,
        qualificationEvidence: [ArtifactReference] = [],
        qualificationArtifact: ArtifactReference
    ) {
        self.axis = axis
        self.producer = producer
        self.requestArtifact = requestArtifact
        self.resultArtifact = resultArtifact
        self.executionInputs = executionInputs
        self.derivedInputs = derivedInputs
        self.rawEvidence = rawEvidence
        self.manifestArtifact = manifestArtifact
        self.reportArtifact = reportArtifact
        self.qualificationEvidence = qualificationEvidence
        self.qualificationArtifact = qualificationArtifact
    }

    public var allArtifacts: [ArtifactReference] {
        [requestArtifact, resultArtifact, qualificationArtifact]
            + executionInputs
            + derivedInputs
            + rawEvidence
            + [manifestArtifact, reportArtifact].compactMap { $0 }
            + qualificationEvidence
    }
}
