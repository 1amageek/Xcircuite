import DesignFlowKernel

public struct XcircuiteSymbolicPlannerPDDLArtifactSet: Codable, Sendable, Hashable {
    public var domainArtifact: XcircuiteFileReference
    public var problemArtifact: XcircuiteFileReference
    public var exportArtifact: XcircuiteFileReference

    public init(
        domainArtifact: XcircuiteFileReference,
        problemArtifact: XcircuiteFileReference,
        exportArtifact: XcircuiteFileReference
    ) {
        self.domainArtifact = domainArtifact
        self.problemArtifact = problemArtifact
        self.exportArtifact = exportArtifact
    }
}
