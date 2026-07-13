import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPDDLArtifactSet: Codable, Sendable, Hashable {
    public var domainArtifact: ArtifactReference
    public var problemArtifact: ArtifactReference
    public var exportArtifact: ArtifactReference

    public init(
        domainArtifact: ArtifactReference,
        problemArtifact: ArtifactReference,
        exportArtifact: ArtifactReference
    ) {
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.exportArtifact = exportArtifact
    }
}
