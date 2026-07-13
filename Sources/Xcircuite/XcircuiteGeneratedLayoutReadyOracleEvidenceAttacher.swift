import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutReadyOracleEvidenceAttacher: Sendable {
    private let packageStore: XcircuitePackageStore
    private let hasher: XcircuiteHasher
    private let identifierValidator: XcircuiteIdentifierValidator

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        hasher: XcircuiteHasher = XcircuiteHasher(),
        identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator()
    ) {
        self.packageStore = packageStore
        self.hasher = hasher
        self.identifierValidator = identifierValidator
    }

    public func attach(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        retainedSignoffReport: XcircuiteRetainedSignoffReport,
        retainedSignoffReportURL: URL
    ) throws -> XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult {
        try validate(report: report, retainedSignoffReport: retainedSignoffReport)
        let evidenceByDomain = try retainedEvidenceByDomain(
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        return makeResult(
            report: report,
            retainedSignoffReport: retainedSignoffReport,
            evidenceByDomain: evidenceByDomain,
            reportArtifact: nil
        )
    }

    public func attachAndPersist(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        retainedSignoffReport: XcircuiteRetainedSignoffReport,
        retainedSignoffReportURL: URL,
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult {
        let resultWithoutSelfRef = try attach(
            report: report,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        let suiteDirectory = try suiteDirectoryURL(suiteID: report.suiteID, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: suiteDirectory)

        let reportPath = suiteProjectRelativePath(
            suiteID: report.suiteID,
            fileName: "corpus-report-ready-oracle-evidence.json"
        )
        let reportURL = try packageStore.url(forProjectRelativePath: reportPath, inProjectAt: projectRoot)
        var reportWithoutSelfRef = resultWithoutSelfRef.updatedReport
        reportWithoutSelfRef.reportArtifact = nil
        try packageStore.writeJSON(reportWithoutSelfRef, to: reportURL, forProjectAt: projectRoot)
        let reportArtifact = try packageStore.fileReference(
            forProjectRelativePath: reportPath,
            artifactID: "generated-layout-signoff-ready-oracle-corpus-report",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(reportArtifact, forProjectAt: projectRoot)

        var updatedReport = resultWithoutSelfRef.updatedReport
        updatedReport.reportArtifact = reportArtifact
        return XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult(
            suiteID: resultWithoutSelfRef.suiteID,
            status: resultWithoutSelfRef.status,
            summary: resultWithoutSelfRef.summary,
            updatedReport: updatedReport,
            reportArtifact: try requireFoundationArtifactReference(
                reportArtifact,
                field: "generated-layout-signoff-ready-oracle-corpus-report"
            ),
            diagnostics: resultWithoutSelfRef.diagnostics
        )
    }

    private func validate(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        retainedSignoffReport: XcircuiteRetainedSignoffReport
    ) throws {
        guard report.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentError
                .unsupportedReportSchemaVersion(report.schemaVersion)
        }
        guard retainedSignoffReport.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentError
                .unsupportedRetainedSignoffReportSchemaVersion(retainedSignoffReport.schemaVersion)
        }
        guard retainedSignoffReport.kind == "retained-signoff-report" else {
            throw XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentError
                .invalidRetainedSignoffReportKind(retainedSignoffReport.kind)
        }
        guard !retainedSignoffReport.externalOracleResults.isEmpty else {
            throw XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentError.noRetainedExternalOracleLanes
        }
        try identifierValidator.validate(report.suiteID, kind: .artifactID)
        for caseResult in report.caseResults {
            try identifierValidator.validate(caseResult.caseID, kind: .artifactID)
            try identifierValidator.validate(caseResult.runID, kind: .runID)
        }
    }

    private func makeResult(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        retainedSignoffReport: XcircuiteRetainedSignoffReport,
        evidenceByDomain: [XcircuiteGeneratedLayoutSignoffStageFamily: DomainEvidence],
        reportArtifact: ArtifactReference?
    ) -> XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult {
        var updatedReadinessCount = 0
        var diagnostics: [XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Diagnostic] = []
        var updatedReport = report
        updatedReport.caseResults = report.caseResults.map { caseResult in
            var updatedCase = caseResult
            updatedCase.oracleReadiness = caseResult.oracleReadiness.map { readiness in
                guard let domainEvidence = evidenceByDomain[readiness.domain] else {
                    diagnostics.append(
                        diagnostic(
                            severity: "warning",
                            code: "ready-oracle-domain-evidence-missing",
                            message: "No retained passing external oracle lane is available for \(readiness.domain.rawValue).",
                            caseID: caseResult.caseID,
                            domain: readiness.domain
                        )
                    )
                    return readiness
                }
                var updatedReadiness = readiness
                updatedReadiness.status = .ready
                updatedReadiness.backendID = domainEvidence.backendID
                updatedReadiness.reason = domainEvidence.reason
                updatedReadiness.evidenceRefs = domainEvidence.evidenceRefs
                updatedReadinessCount += 1
                return updatedReadiness
            }
            return updatedCase
        }

        let readinessValues = updatedReport.caseResults.flatMap(\.oracleReadiness)
        let readyReadinessCount = readinessValues.filter { $0.status == .ready }.count
        let evidenceRefCount = readinessValues.reduce(0) { $0 + $1.evidenceRefs.count }
        let missingDomains = missingDomains(report: report, evidenceByDomain: evidenceByDomain)
        let status = attachmentStatus(
            updatedReadinessCount: updatedReadinessCount,
            missingDomains: missingDomains
        )
        return XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult(
            suiteID: report.suiteID,
            status: status,
            summary: XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Summary(
                caseCount: updatedReport.caseResults.count,
                readinessCount: readinessValues.count,
                updatedReadinessCount: updatedReadinessCount,
                readyReadinessCount: readyReadinessCount,
                evidenceRefCount: evidenceRefCount,
                retainedExternalLaneCount: retainedSignoffReport.externalOracleResults.count,
                readyRetainedExternalLaneCount: evidenceByDomain.count,
                missingDomainCount: missingDomains.count,
                missingDomains: missingDomains
            ),
            updatedReport: updatedReport,
            reportArtifact: reportArtifact,
            diagnostics: diagnostics.sorted(by: diagnosticSortOrder)
        )
    }

    private func retainedEvidenceByDomain(
        retainedSignoffReport: XcircuiteRetainedSignoffReport,
        retainedSignoffReportURL: URL
    ) throws -> [XcircuiteGeneratedLayoutSignoffStageFamily: DomainEvidence] {
        var evidenceByDomain: [XcircuiteGeneratedLayoutSignoffStageFamily: DomainEvidence] = [:]
        let retainedReportEvidence = try retainedReportEvidenceRef(retainedSignoffReportURL)
        for lane in retainedSignoffReport.passingExternalOracleResults {
            guard let domain = stageFamily(domain: lane.domain) else {
                continue
            }
            var evidenceRefs = [retainedReportEvidence]
            if let laneEvidence = laneReportEvidenceRef(lane) {
                evidenceRefs.append(laneEvidence)
            }
            evidenceByDomain[domain] = DomainEvidence(
                backendID: lane.oracleBackendID ?? lane.domain,
                reason: "Retained \(lane.domain) external oracle lane passed with case-level report evidence.",
                evidenceRefs: evidenceRefs
            )
        }
        return evidenceByDomain
    }

    private func retainedReportEvidenceRef(
        _ retainedSignoffReportURL: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference {
        XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
            role: "retained-signoff-report",
            path: retainedSignoffReportURL.path(percentEncoded: false),
            kind: "report",
            format: "JSON",
            sha256: try hasher.sha256(fileAt: retainedSignoffReportURL),
            byteCount: try hasher.byteCount(fileAt: retainedSignoffReportURL)
        )
    }

    private func laneReportEvidenceRef(
        _ lane: XcircuiteRetainedSignoffReport.ExternalOracleResult
    ) -> XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference? {
        guard let report = lane.report,
              report.provesRetainedExternalOracleReportEvidence,
              let path = report.path,
              let sha256 = report.sha256,
              let byteCount = report.byteCount else {
            return nil
        }
        return XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
            role: "\(lane.domain)-external-oracle-report",
            path: path,
            kind: "report",
            format: "JSON",
            sha256: sha256,
            byteCount: byteCount
        )
    }

    private func missingDomains(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        evidenceByDomain: [XcircuiteGeneratedLayoutSignoffStageFamily: DomainEvidence]
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        let requiredDomains = Set(report.caseResults.flatMap(\.oracleReadiness).map(\.domain))
        return sortedStageFamilies(requiredDomains.filter { evidenceByDomain[$0] == nil })
    }

    private func attachmentStatus(
        updatedReadinessCount: Int,
        missingDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) -> XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Status {
        guard updatedReadinessCount > 0 else {
            return .blocked
        }
        return missingDomains.isEmpty ? .attached : .partial
    }

    private func stageFamily(domain: String) -> XcircuiteGeneratedLayoutSignoffStageFamily? {
        switch domain {
        case "drc":
            return .drc
        case "lvs":
            return .lvs
        case "pex":
            return .pex
        default:
            return nil
        }
    }

    private func suiteDirectoryURL(suiteID: String, projectRoot: URL) throws -> URL {
        try packageStore.url(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/qualification/generated-layout-signoff/\(suiteID)",
            inProjectAt: projectRoot
        )
    }

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuitePackage.directoryName)/qualification/generated-layout-signoff/\(suiteID)/\(fileName)"
    }

    private func diagnostic(
        severity: String,
        code: String,
        message: String,
        caseID: String? = nil,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily? = nil
    ) -> XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Diagnostic {
        XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Diagnostic(
            severity: severity,
            code: code,
            message: message,
            caseID: caseID,
            domain: domain
        )
    }

    private func diagnosticSortOrder(
        _ left: XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Diagnostic,
        _ right: XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.Diagnostic
    ) -> Bool {
        if left.code != right.code {
            return left.code < right.code
        }
        if left.caseID != right.caseID {
            return (left.caseID ?? "") < (right.caseID ?? "")
        }
        return (left.domain?.rawValue ?? "") < (right.domain?.rawValue ?? "")
    }

    private func sortedStageFamilies(
        _ families: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        families.sorted { left, right in
            stageFamilyIndex(left) < stageFamilyIndex(right)
        }
    }

    private func stageFamilyIndex(_ family: XcircuiteGeneratedLayoutSignoffStageFamily) -> Int {
        XcircuiteGeneratedLayoutSignoffStageFamily.allCases.firstIndex(of: family) ?? Int.max
    }

    private struct DomainEvidence: Sendable, Hashable {
        var backendID: String
        var reason: String
        var evidenceRefs: [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference]
    }
}
