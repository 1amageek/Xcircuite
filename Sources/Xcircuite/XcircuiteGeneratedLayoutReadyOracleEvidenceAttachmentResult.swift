import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var status: Status
    public var summary: Summary
    public var updatedReport: XcircuiteGeneratedLayoutSignoffCorpusReport
    public var reportArtifact: ArtifactReference?
    public var diagnostics: [Diagnostic]

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        status: Status,
        summary: Summary,
        updatedReport: XcircuiteGeneratedLayoutSignoffCorpusReport,
        reportArtifact: ArtifactReference? = nil,
        diagnostics: [Diagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.updatedReport = updatedReport
        self.reportArtifact = reportArtifact
        self.diagnostics = diagnostics
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case attached
        case partial
        case blocked
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var caseCount: Int
        public var readinessCount: Int
        public var updatedReadinessCount: Int
        public var readyReadinessCount: Int
        public var evidenceRefCount: Int
        public var retainedExternalLaneCount: Int
        public var readyRetainedExternalLaneCount: Int
        public var missingDomainCount: Int
        public var missingDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]

        public init(
            caseCount: Int,
            readinessCount: Int,
            updatedReadinessCount: Int,
            readyReadinessCount: Int,
            evidenceRefCount: Int,
            retainedExternalLaneCount: Int,
            readyRetainedExternalLaneCount: Int,
            missingDomainCount: Int,
            missingDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        ) {
            self.caseCount = caseCount
            self.readinessCount = readinessCount
            self.updatedReadinessCount = updatedReadinessCount
            self.readyReadinessCount = readyReadinessCount
            self.evidenceRefCount = evidenceRefCount
            self.retainedExternalLaneCount = retainedExternalLaneCount
            self.readyRetainedExternalLaneCount = readyRetainedExternalLaneCount
            self.missingDomainCount = missingDomainCount
            self.missingDomains = missingDomains
        }
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public var severity: String
        public var code: String
        public var message: String
        public var caseID: String?
        public var domain: XcircuiteGeneratedLayoutSignoffStageFamily?

        public init(
            severity: String,
            code: String,
            message: String,
            caseID: String? = nil,
            domain: XcircuiteGeneratedLayoutSignoffStageFamily? = nil
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.caseID = caseID
            self.domain = domain
        }
    }
}
