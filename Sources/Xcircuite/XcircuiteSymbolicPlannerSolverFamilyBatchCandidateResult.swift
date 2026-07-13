import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyBatchCandidateResult: Codable, Sendable, Hashable {
    public var candidateIndex: Int
    public var candidateID: String
    public var toolID: String
    public var qualificationStatus: String
    public var qualificationArtifact: ArtifactReference
    public var solverPlanArtifact: ArtifactReference?
    public var nativeCertificateArtifact: ArtifactReference?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        candidateIndex: Int,
        candidateID: String,
        toolID: String,
        qualificationStatus: String,
        qualificationArtifact: ArtifactReference,
        solverPlanArtifact: ArtifactReference?,
        nativeCertificateArtifact: ArtifactReference? = nil,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.candidateIndex = candidateIndex
        self.candidateID = candidateID
        self.toolID = toolID
        self.qualificationStatus = qualificationStatus
        self.qualificationArtifact = qualificationArtifact
        self.solverPlanArtifact = solverPlanArtifact
        self.nativeCertificateArtifact = nativeCertificateArtifact
        self.diagnostics = diagnostics
    }
}
