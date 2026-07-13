import Foundation
import DesignFlowKernel

public struct XcircuiteVerifiedImprovementCorpusReport: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var suiteID: String
    public var status: Status
    public var summary: Summary
    public var caseResults: [CaseResult]
    public var suiteSpecArtifact: XcircuiteFileReference?
    public var reportArtifact: XcircuiteFileReference?

    public init(
        schemaVersion: Int = 1,
        suiteID: String,
        status: Status,
        summary: Summary,
        caseResults: [CaseResult],
        suiteSpecArtifact: XcircuiteFileReference? = nil,
        reportArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.status = status
        self.summary = summary
        self.caseResults = caseResults
        self.suiteSpecArtifact = suiteSpecArtifact
        self.reportArtifact = reportArtifact
    }

    public enum Status: String, Codable, Sendable, Hashable {
        case passed
        case failed
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var caseCount: Int
        public var passedCaseCount: Int
        public var failedCaseCount: Int
        public var acceptedCaseCount: Int
        public var rejectedCaseCount: Int
        public var familyCounts: [String: Int]
        public var requiredFamilies: [XcircuiteVerifiedImprovementCorpusFamily]
        public var coveredFamilies: [XcircuiteVerifiedImprovementCorpusFamily]
        public var missingFamilies: [XcircuiteVerifiedImprovementCorpusFamily]
        public var sourceDiagnosticCoverageCount: Int
        public var designDiffArtifactCount: Int
        public var verificationArtifactCount: Int
        public var improvementArtifactCount: Int

        public init(
            caseCount: Int,
            passedCaseCount: Int,
            failedCaseCount: Int,
            acceptedCaseCount: Int,
            rejectedCaseCount: Int,
            familyCounts: [String: Int],
            requiredFamilies: [XcircuiteVerifiedImprovementCorpusFamily],
            coveredFamilies: [XcircuiteVerifiedImprovementCorpusFamily],
            missingFamilies: [XcircuiteVerifiedImprovementCorpusFamily],
            sourceDiagnosticCoverageCount: Int,
            designDiffArtifactCount: Int,
            verificationArtifactCount: Int,
            improvementArtifactCount: Int
        ) {
            self.caseCount = caseCount
            self.passedCaseCount = passedCaseCount
            self.failedCaseCount = failedCaseCount
            self.acceptedCaseCount = acceptedCaseCount
            self.rejectedCaseCount = rejectedCaseCount
            self.familyCounts = familyCounts
            self.requiredFamilies = requiredFamilies
            self.coveredFamilies = coveredFamilies
            self.missingFamilies = missingFamilies
            self.sourceDiagnosticCoverageCount = sourceDiagnosticCoverageCount
            self.designDiffArtifactCount = designDiffArtifactCount
            self.verificationArtifactCount = verificationArtifactCount
            self.improvementArtifactCount = improvementArtifactCount
        }
    }

    public struct CaseResult: Codable, Sendable, Hashable {
        public var caseID: String
        public var runID: String
        public var family: XcircuiteVerifiedImprovementCorpusFamily
        public var status: Status
        public var observedStatus: String
        public var expectedStatus: String
        public var statusMatches: Bool
        public var accepted: Bool?
        public var expectedAccepted: Bool?
        public var acceptedMatches: Bool
        public var diagnosticCodes: [String]
        public var requiredDiagnosticCodes: [String]
        public var missingDiagnosticCodes: [String]
        public var failedGateIDs: [String]
        public var requiredFailedGateIDs: [String]
        public var missingFailedGateIDs: [String]
        public var artifactRefs: [XcircuiteFileReference]
        public var missingArtifactIDs: [String]
        public var diagnostics: [Diagnostic]

        public init(
            caseID: String,
            runID: String,
            family: XcircuiteVerifiedImprovementCorpusFamily,
            status: Status,
            observedStatus: String,
            expectedStatus: String,
            statusMatches: Bool,
            accepted: Bool?,
            expectedAccepted: Bool?,
            acceptedMatches: Bool,
            diagnosticCodes: [String],
            requiredDiagnosticCodes: [String],
            missingDiagnosticCodes: [String],
            failedGateIDs: [String],
            requiredFailedGateIDs: [String],
            missingFailedGateIDs: [String],
            artifactRefs: [XcircuiteFileReference],
            missingArtifactIDs: [String],
            diagnostics: [Diagnostic]
        ) {
            self.caseID = caseID
            self.runID = runID
            self.family = family
            self.status = status
            self.observedStatus = observedStatus
            self.expectedStatus = expectedStatus
            self.statusMatches = statusMatches
            self.accepted = accepted
            self.expectedAccepted = expectedAccepted
            self.acceptedMatches = acceptedMatches
            self.diagnosticCodes = diagnosticCodes
            self.requiredDiagnosticCodes = requiredDiagnosticCodes
            self.missingDiagnosticCodes = missingDiagnosticCodes
            self.failedGateIDs = failedGateIDs
            self.requiredFailedGateIDs = requiredFailedGateIDs
            self.missingFailedGateIDs = missingFailedGateIDs
            self.artifactRefs = artifactRefs
            self.missingArtifactIDs = missingArtifactIDs
            self.diagnostics = diagnostics
        }
    }

    public struct Diagnostic: Codable, Sendable, Hashable {
        public var severity: String
        public var code: String
        public var message: String

        public init(severity: String, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }
}
