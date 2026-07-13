import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteSymbolicPlannerSolverFamilyPromotion: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var status: String
    public var runID: String
    public var comparisonID: String
    public var selectedCandidateIndex: Int
    public var selectedToolID: String
    public var sourceComparisonArtifact: XcircuiteFileReference?
    public var sourceQualificationArtifact: ArtifactReference?
    public var promotedCandidatePlanArtifact: XcircuiteFileReference
    public var promotedSolverPlanArtifact: XcircuiteFileReference?
    public var promotedPlanReplayValidationArtifact: XcircuiteFileReference?
    public var promotedPlanVerificationArtifact: XcircuiteFileReference?
    public var verificationStatus: String?
    public var verificationAccepted: Bool?
    public var diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic]

    public init(
        schemaVersion: Int = 1,
        status: String,
        runID: String,
        comparisonID: String,
        selectedCandidateIndex: Int,
        selectedToolID: String,
        sourceComparisonArtifact: XcircuiteFileReference?,
        sourceQualificationArtifact: ArtifactReference?,
        promotedCandidatePlanArtifact: XcircuiteFileReference,
        promotedSolverPlanArtifact: XcircuiteFileReference?,
        promotedPlanReplayValidationArtifact: XcircuiteFileReference?,
        promotedPlanVerificationArtifact: XcircuiteFileReference?,
        verificationStatus: String?,
        verificationAccepted: Bool?,
        diagnostics: [XcircuiteSymbolicPlannerSolverDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.runID = runID
        self.comparisonID = comparisonID
        self.selectedCandidateIndex = selectedCandidateIndex
        self.selectedToolID = selectedToolID
        self.sourceComparisonArtifact = sourceComparisonArtifact
        self.sourceQualificationArtifact = sourceQualificationArtifact
        self.promotedCandidatePlanArtifact = promotedCandidatePlanArtifact
        self.promotedSolverPlanArtifact = promotedSolverPlanArtifact
        self.promotedPlanReplayValidationArtifact = promotedPlanReplayValidationArtifact
        self.promotedPlanVerificationArtifact = promotedPlanVerificationArtifact
        self.verificationStatus = verificationStatus
        self.verificationAccepted = verificationAccepted
        self.diagnostics = diagnostics
    }
}
