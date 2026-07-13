import Foundation
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
    public var parameterCandidatesArtifact: XcircuiteFileReference?
    public var searchTraceArtifact: XcircuiteFileReference?
    public var selectionTraceArtifact: XcircuiteFileReference?
    public var candidatePlanArtifact: XcircuiteFileReference?
    public var planExecutionArtifact: XcircuiteFileReference?
    public var designDiffArtifact: XcircuiteFileReference?
    public var producedArtifacts: [XcircuiteFileReference]
    public var planVerificationArtifact: XcircuiteFileReference?
    public var rejectedPlansArtifact: XcircuiteFileReference?
    public var archivedArtifactRefs: [XcircuiteFileReference]
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
        parameterCandidatesArtifact: XcircuiteFileReference? = nil,
        searchTraceArtifact: XcircuiteFileReference? = nil,
        selectionTraceArtifact: XcircuiteFileReference? = nil,
        candidatePlanArtifact: XcircuiteFileReference? = nil,
        planExecutionArtifact: XcircuiteFileReference? = nil,
        designDiffArtifact: XcircuiteFileReference? = nil,
        producedArtifacts: [XcircuiteFileReference] = [],
        planVerificationArtifact: XcircuiteFileReference? = nil,
        rejectedPlansArtifact: XcircuiteFileReference? = nil,
        archivedArtifactRefs: [XcircuiteFileReference] = [],
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
