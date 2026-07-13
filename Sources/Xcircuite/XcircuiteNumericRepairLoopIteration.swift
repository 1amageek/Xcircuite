import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteNumericRepairLoopIteration: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var iterationIndex: Int
    public var status: String
    public var candidateGenerationStrategy: String
    public var synthesisStrategy: String
    public var verificationMode: String
    public var candidateGenerationStatus: String
    public var selectedCandidateID: String?
    public var selectedCandidateRank: Int?
    public var skippedRejectedCandidateIDs: [String]
    public var planID: String?
    public var executionStatus: String?
    public var verificationStatus: String?
    public var accepted: Bool
    public var policyTrace: XcircuiteNumericRepairLoopPolicyTrace?
    public var parameterCandidatesArtifact: ArtifactReference?
    public var searchTraceArtifact: ArtifactReference?
    public var selectionTraceArtifact: ArtifactReference?
    public var candidatePlanArtifact: ArtifactReference?
    public var planExecutionArtifact: ArtifactReference?
    public var designDiffArtifact: ArtifactReference?
    public var producedArtifacts: [ArtifactReference]
    public var planVerificationArtifact: ArtifactReference?
    public var rejectedPlansArtifact: ArtifactReference?
    public var archivedArtifactRefs: [ArtifactReference]
    public var diagnostics: [XcircuiteNumericRepairLoopDiagnostic]
    public var nextActions: [String]

    public init(
        schemaVersion: Int = 1,
        iterationIndex: Int,
        status: String,
        candidateGenerationStrategy: String,
        synthesisStrategy: String,
        verificationMode: String,
        candidateGenerationStatus: String,
        selectedCandidateID: String? = nil,
        selectedCandidateRank: Int? = nil,
        skippedRejectedCandidateIDs: [String] = [],
        planID: String? = nil,
        executionStatus: String? = nil,
        verificationStatus: String? = nil,
        accepted: Bool = false,
        policyTrace: XcircuiteNumericRepairLoopPolicyTrace? = nil,
        parameterCandidatesArtifact: ArtifactReference? = nil,
        searchTraceArtifact: ArtifactReference? = nil,
        selectionTraceArtifact: ArtifactReference? = nil,
        candidatePlanArtifact: ArtifactReference? = nil,
        planExecutionArtifact: ArtifactReference? = nil,
        designDiffArtifact: ArtifactReference? = nil,
        producedArtifacts: [ArtifactReference] = [],
        planVerificationArtifact: ArtifactReference? = nil,
        rejectedPlansArtifact: ArtifactReference? = nil,
        archivedArtifactRefs: [ArtifactReference] = [],
        diagnostics: [XcircuiteNumericRepairLoopDiagnostic] = [],
        nextActions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.iterationIndex = iterationIndex
        self.status = status
        self.candidateGenerationStrategy = candidateGenerationStrategy
        self.synthesisStrategy = synthesisStrategy
        self.verificationMode = verificationMode
        self.candidateGenerationStatus = candidateGenerationStatus
        self.selectedCandidateID = selectedCandidateID
        self.selectedCandidateRank = selectedCandidateRank
        self.skippedRejectedCandidateIDs = skippedRejectedCandidateIDs
        self.planID = planID
        self.executionStatus = executionStatus
        self.verificationStatus = verificationStatus
        self.accepted = accepted
        self.policyTrace = policyTrace
        self.parameterCandidatesArtifact = parameterCandidatesArtifact
        self.searchTraceArtifact = searchTraceArtifact
        self.selectionTraceArtifact = selectionTraceArtifact
        self.candidatePlanArtifact = candidatePlanArtifact
        self.planExecutionArtifact = planExecutionArtifact
        self.designDiffArtifact = designDiffArtifact
        self.producedArtifacts = producedArtifacts
        self.planVerificationArtifact = planVerificationArtifact
        self.rejectedPlansArtifact = rejectedPlansArtifact
        self.archivedArtifactRefs = archivedArtifactRefs
        self.diagnostics = diagnostics
        self.nextActions = nextActions
    }
}
