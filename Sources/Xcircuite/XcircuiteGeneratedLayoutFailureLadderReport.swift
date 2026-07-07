import DesignFlowKernel
import Foundation
import XcircuitePackage

public struct XcircuiteGeneratedLayoutFailureLadderReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var ladderID: String
    public var runID: String
    public var runStatus: FlowRunStatus
    public var summary: Summary
    public var stageNodes: [StageNode]
    public var suggestedActions: [SuggestedAction]
    /// Manifest reference for the persisted report file. Persisted report JSON omits this self-reference to keep the file digest acyclic.
    public var reportArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        ladderID: String,
        runID: String,
        runStatus: FlowRunStatus,
        summary: Summary,
        stageNodes: [StageNode],
        suggestedActions: [SuggestedAction],
        reportArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.ladderID = ladderID
        self.runID = runID
        self.runStatus = runStatus
        self.summary = summary
        self.stageNodes = stageNodes
        self.suggestedActions = suggestedActions
        self.reportArtifact = reportArtifact
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var stageCount: Int
        public var failingStageCount: Int
        public var blockedStageCount: Int
        public var skippedStageCount: Int
        public var artifactIssueCount: Int
        public var diagnosticCount: Int
        public var firstFailingStageID: String?
        public var firstFailingGateID: String?
        public var firstFailingFamily: XcircuiteGeneratedLayoutSignoffStageFamily?
        public var affectedDownstreamStageIDs: [String]
        public var suggestedActionCount: Int
        public var reviewItemCount: Int
        public var approvalCount: Int

        public init(
            stageCount: Int,
            failingStageCount: Int,
            blockedStageCount: Int,
            skippedStageCount: Int,
            artifactIssueCount: Int,
            diagnosticCount: Int,
            firstFailingStageID: String?,
            firstFailingGateID: String?,
            firstFailingFamily: XcircuiteGeneratedLayoutSignoffStageFamily?,
            affectedDownstreamStageIDs: [String],
            suggestedActionCount: Int,
            reviewItemCount: Int,
            approvalCount: Int
        ) {
            self.stageCount = stageCount
            self.failingStageCount = failingStageCount
            self.blockedStageCount = blockedStageCount
            self.skippedStageCount = skippedStageCount
            self.artifactIssueCount = artifactIssueCount
            self.diagnosticCount = diagnosticCount
            self.firstFailingStageID = firstFailingStageID
            self.firstFailingGateID = firstFailingGateID
            self.firstFailingFamily = firstFailingFamily
            self.affectedDownstreamStageIDs = affectedDownstreamStageIDs
            self.suggestedActionCount = suggestedActionCount
            self.reviewItemCount = reviewItemCount
            self.approvalCount = approvalCount
        }
    }

    public struct StageNode: Codable, Sendable, Hashable {
        public var stageID: String
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily
        public var order: Int
        public var status: FlowStageStatus
        public var isFirstFailure: Bool
        public var isAffectedDownstream: Bool
        public var gates: [GateNode]
        public var artifactRefs: [ArtifactReference]
        public var artifactIssues: [ArtifactIssue]
        public var diagnostics: [Diagnostic]
        public var attempts: [Attempt]

        public init(
            stageID: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily,
            order: Int,
            status: FlowStageStatus,
            isFirstFailure: Bool,
            isAffectedDownstream: Bool,
            gates: [GateNode],
            artifactRefs: [ArtifactReference],
            artifactIssues: [ArtifactIssue],
            diagnostics: [Diagnostic],
            attempts: [Attempt]
        ) {
            self.stageID = stageID
            self.family = family
            self.order = order
            self.status = status
            self.isFirstFailure = isFirstFailure
            self.isAffectedDownstream = isAffectedDownstream
            self.gates = gates
            self.artifactRefs = artifactRefs
            self.artifactIssues = artifactIssues
            self.diagnostics = diagnostics
            self.attempts = attempts
        }
    }

    public struct GateNode: Codable, Sendable, Hashable {
        public var gateID: String
        public var status: FlowGateStatus
        public var diagnostics: [Diagnostic]

        public init(gateID: String, status: FlowGateStatus, diagnostics: [Diagnostic]) {
            self.gateID = gateID
            self.status = status
            self.diagnostics = diagnostics
        }
    }

    public struct ArtifactReference: Codable, Sendable, Hashable {
        public var role: String
        public var artifactID: String?
        public var stageID: String?
        public var path: String
        public var kind: String
        public var format: String
        /// Digest copied from the review bundle artifact reference; integrityStatus carries the currentness verdict.
        public var sha256: String?
        public var byteCount: Int64?
        public var integrityStatus: String?
        public var integrityMessage: String?

        public init(
            role: String,
            artifactID: String?,
            stageID: String?,
            path: String,
            kind: String,
            format: String,
            sha256: String?,
            byteCount: Int64?,
            integrityStatus: String?,
            integrityMessage: String?
        ) {
            self.role = role
            self.artifactID = artifactID
            self.stageID = stageID
            self.path = path
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
            self.integrityStatus = integrityStatus
            self.integrityMessage = integrityMessage
        }
    }

    public struct ArtifactIssue: Codable, Sendable, Hashable {
        public var artifactID: String?
        public var path: String
        public var status: String
        public var message: String

        public init(artifactID: String?, path: String, status: String, message: String) {
            self.artifactID = artifactID
            self.path = path
            self.status = status
            self.message = message
        }
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public var severity: FlowDiagnosticSeverity
        public var code: String
        public var message: String

        public init(severity: FlowDiagnosticSeverity, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public struct Attempt: Codable, Sendable, Hashable {
        public var attemptIndex: Int
        public var maxAttempts: Int
        public var status: FlowStageStatus
        public var diagnosticCodes: [String]
        public var shouldRetry: Bool
        public var retryReason: FlowStageRetryDecisionReason
        public var matchedDiagnosticCodes: [String]

        public init(
            attemptIndex: Int,
            maxAttempts: Int,
            status: FlowStageStatus,
            diagnosticCodes: [String],
            shouldRetry: Bool,
            retryReason: FlowStageRetryDecisionReason,
            matchedDiagnosticCodes: [String]
        ) {
            self.attemptIndex = attemptIndex
            self.maxAttempts = maxAttempts
            self.status = status
            self.diagnosticCodes = diagnosticCodes
            self.shouldRetry = shouldRetry
            self.retryReason = retryReason
            self.matchedDiagnosticCodes = matchedDiagnosticCodes
        }
    }

    public struct SuggestedAction: Codable, Sendable, Hashable {
        public var actionID: String
        public var stageID: String
        public var family: XcircuiteGeneratedLayoutSignoffStageFamily
        public var priority: Int
        public var actionKind: String
        public var rationale: String
        public var evidenceArtifactIDs: [String]
        public var diagnosticCodes: [String]

        public init(
            actionID: String,
            stageID: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily,
            priority: Int,
            actionKind: String,
            rationale: String,
            evidenceArtifactIDs: [String],
            diagnosticCodes: [String]
        ) {
            self.actionID = actionID
            self.stageID = stageID
            self.family = family
            self.priority = priority
            self.actionKind = actionKind
            self.rationale = rationale
            self.evidenceArtifactIDs = evidenceArtifactIDs
            self.diagnosticCodes = diagnosticCodes
        }
    }
}
