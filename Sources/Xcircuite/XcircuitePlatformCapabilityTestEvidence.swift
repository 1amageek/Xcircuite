import CircuiteFoundation

public struct XcircuitePlatformCapabilityTestEvidence: Codable, Sendable, Hashable {
    public var evidenceID: String
    public var packagePath: String
    public var invocation: XcircuiteXcodebuildTestInvocation
    public var testFilter: String
    public var coveredMilestoneIDs: [String]
    public var coveredRequirementKinds: [String]
    public var coveredArtifactKinds: [String]
    public var resultArtifact: ArtifactReference?
    public var retainedArtifacts: [ArtifactReference]
    public var provenance: ExecutionProvenance?
    public var exitStatus: Int32?

    public init(
        evidenceID: String,
        packagePath: String,
        invocation: XcircuiteXcodebuildTestInvocation,
        testFilter: String,
        coveredMilestoneIDs: [String],
        coveredRequirementKinds: [String],
        coveredArtifactKinds: [String],
        resultArtifact: ArtifactReference? = nil,
        retainedArtifacts: [ArtifactReference] = [],
        provenance: ExecutionProvenance? = nil,
        exitStatus: Int32? = nil
    ) {
        self.evidenceID = evidenceID
        self.packagePath = packagePath
        self.invocation = invocation
        self.testFilter = testFilter
        self.coveredMilestoneIDs = coveredMilestoneIDs
        self.coveredRequirementKinds = coveredRequirementKinds
        self.coveredArtifactKinds = coveredArtifactKinds
        self.resultArtifact = resultArtifact
        self.retainedArtifacts = retainedArtifacts
        self.provenance = provenance
        self.exitStatus = exitStatus
    }

    public var executionStatus: XcircuitePlatformCapabilityTestEvidenceExecutionStatus {
        guard let exitStatus else { return .unverified }
        return exitStatus == 0 ? .passed : .failed
    }

    public var command: [String] {
        invocation.command
    }

}
