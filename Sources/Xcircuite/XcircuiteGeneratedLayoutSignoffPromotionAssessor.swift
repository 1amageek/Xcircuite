import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutSignoffPromotionAssessor: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let hasher: XcircuiteHasher
    private let identifierValidator: XcircuiteIdentifierValidator

    public init(
        workspaceStore: XcircuiteWorkspaceStore = XcircuiteWorkspaceStore(),
        hasher: XcircuiteHasher = XcircuiteHasher(),
        identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator()
    ) {
        self.workspaceStore = workspaceStore
        self.hasher = hasher
        self.identifierValidator = identifierValidator
    }

    public func assess(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL? = nil
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        try validate(
            request: request,
            qualification: qualification,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        let normalizedRequest = normalize(request)
        let retainedArtifact = try retainedSignoffReportURL.map(artifactReference)
        let externalSummary = externalOracleSummary(
            request: normalizedRequest,
            retainedSignoffReport: retainedSignoffReport
        )
        let generatedOracleReady = generatedLayoutOracleReady(qualification)
        let blockers = makeBlockers(
            request: normalizedRequest,
            qualification: qualification,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL,
            externalSummary: externalSummary,
            generatedOracleReady: generatedOracleReady
        )
        let status = assessmentStatus(
            qualification: qualification,
            generatedOracleReady: generatedOracleReady,
            externalOracleInfrastructureReady: externalSummary.ready,
            blockers: blockers
        )
        return makeAssessment(
            request: normalizedRequest,
            qualification: qualification,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportArtifact: retainedArtifact,
            externalSummary: externalSummary,
            generatedOracleReady: generatedOracleReady,
            blockers: blockers,
            status: status,
            assessmentArtifact: nil
        )
    }

    public func assessAndPersist(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?,
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        let assessmentWithoutSelfRef = try assess(
            request: request,
            qualification: qualification,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        let suiteDirectory = try suiteDirectoryURL(suiteID: qualification.suiteID, projectRoot: projectRoot)
        try workspaceStore.ensureDirectory(at: suiteDirectory)
        let assessmentPath = suiteProjectRelativePath(
            suiteID: qualification.suiteID,
            fileName: "promotion-assessment.json"
        )
        let assessmentURL = try workspaceStore.url(forProjectRelativePath: assessmentPath, inProjectAt: projectRoot)
        try workspaceStore.writeJSON(assessmentWithoutSelfRef, to: assessmentURL, forProjectAt: projectRoot)
        let assessmentArtifact = try workspaceStore.fileReference(
            forProjectRelativePath: assessmentPath,
            artifactID: "generated-layout-signoff-promotion-assessment",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try workspaceStore.upsertFileReference(assessmentArtifact, forProjectAt: projectRoot)

        var assessment = assessmentWithoutSelfRef
        assessment.assessmentArtifact = assessmentArtifact
        return assessment
    }

    private func validate(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?
    ) throws {
        guard request.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.unsupportedRequestSchemaVersion(
                request.schemaVersion
            )
        }
        guard qualification.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.unsupportedQualificationSchemaVersion(
                qualification.schemaVersion
            )
        }
        if let retainedSignoffReport {
            guard retainedSignoffReport.schemaVersion == 1 else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .unsupportedRetainedSignoffReportSchemaVersion(retainedSignoffReport.schemaVersion)
            }
            guard retainedSignoffReport.kind == "retained-signoff-report" else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.invalidRetainedSignoffReportKind(
                    retainedSignoffReport.kind
                )
            }
        }
        if retainedSignoffReport == nil, retainedSignoffReportURL != nil {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.retainedSignoffReportArtifactWithoutReport
        }
        if request.requireRetainedExternalOracleSuite,
           retainedSignoffReport != nil,
           retainedSignoffReportURL == nil {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.retainedSignoffReportArtifactMissing
        }
        try identifierValidator.validate(request.promotionID, kind: .artifactID)
        try identifierValidator.validate(qualification.suiteID, kind: .artifactID)
        try validateRequiredExternalOracleDomains(request.requiredExternalOracleDomains)
    }

    private func validateRequiredExternalOracleDomains(
        _ domains: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) throws {
        guard !domains.isEmpty else {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.emptyRequiredExternalOracleDomains
        }
        var seen: Set<XcircuiteGeneratedLayoutSignoffStageFamily> = []
        for domain in domains {
            guard isSupportedExternalOracleDomain(domain) else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .unsupportedRequiredExternalOracleDomain(domain)
            }
            guard !seen.contains(domain) else {
                throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
                    .duplicateRequiredExternalOracleDomain(domain)
            }
            seen.insert(domain)
        }
    }

    private func isSupportedExternalOracleDomain(
        _ domain: XcircuiteGeneratedLayoutSignoffStageFamily
    ) -> Bool {
        switch domain {
        case .drc, .lvs, .pex:
            true
        case .layout, .simulation, .postLayout, .other:
            false
        }
    }

    private func makeAssessment(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportArtifact: XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactReference?,
        externalSummary: ExternalOracleSummary,
        generatedOracleReady: Bool,
        blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker],
        status: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Status,
        assessmentArtifact: XcircuiteFileReference?
    ) -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        XcircuiteGeneratedLayoutSignoffPromotionAssessment(
            promotionID: request.promotionID,
            suiteID: qualification.suiteID,
            status: status,
            summary: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Summary(
                qualificationStatus: qualification.status,
                generatedLayoutOracleReady: generatedOracleReady,
                externalOracleInfrastructureReady: externalSummary.ready,
                retainedSignoffReportStatus: retainedSignoffReport?.status,
                retainedSignoffSuiteID: retainedSignoffReport?.suiteID,
                requiredExternalOracleDomains: request.requiredExternalOracleDomains,
                observedExternalOracleDomains: externalSummary.observedDomains,
                missingExternalOracleDomains: externalSummary.missingDomains,
                externalOracleLaneCount: externalSummary.laneCount,
                passedExternalOracleLaneCount: externalSummary.passedLaneCount,
                blockedExternalOracleLaneCount: externalSummary.blockedLaneCount,
                failedExternalOracleLaneCount: externalSummary.failedLaneCount,
                generatedLayoutAcceptedOracleStatuses: qualification.summary.acceptedOracleReadinessStatuses,
                blockerCount: blockers.filter { $0.severity == .error }.count
            ),
            blockers: blockers,
            suggestedActions: suggestedActions(
                qualification: qualification,
                generatedOracleReady: generatedOracleReady,
                externalSummary: externalSummary
            ),
            qualificationArtifact: qualification.qualificationArtifact,
            retainedSignoffReportArtifact: retainedSignoffReportArtifact,
            assessmentArtifact: assessmentArtifact
        )
    }

    private func makeBlockers(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?,
        externalSummary: ExternalOracleSummary,
        generatedOracleReady: Bool
    ) -> [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker] {
        var blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker] = []
        if qualification.status != .qualified {
            blockers.append(
                blocker(
                    code: "generated-layout-corpus-not-qualified",
                    message: "Generated-layout signoff corpus qualification status is \(qualification.status.rawValue)."
                )
            )
            for failure in qualification.failures where failure.severity == .error {
                blockers.append(
                    blocker(
                        code: "generated-layout-corpus-\(failure.code)",
                        message: failure.message,
                        family: failure.family
                    )
                )
            }
        }
        if request.requireGeneratedLayoutOracleReady && !generatedOracleReady {
            blockers.append(
                blocker(
                    code: "generated-layout-oracle-readiness-not-ready",
                    message: "Generated-layout corpus accepted oracle statuses include non-ready values, so case-level external oracle evidence is still missing."
                )
            )
        }
        if request.requireRetainedExternalOracleSuite {
            guard let retainedSignoffReport else {
                blockers.append(
                    blocker(
                        code: "retained-signoff-report-missing",
                        message: "A retained signoff report is required to prove DRC/LVS/PEX external oracle infrastructure readiness."
                    )
                )
                return blockers.sorted(by: blockerSortOrder)
            }
            let retainedReportPath = retainedSignoffReportURL?.path(percentEncoded: false)
            if retainedSignoffReport.status != "passed" {
                blockers.append(
                    blocker(
                        code: "retained-signoff-report-not-passed",
                        message: "Retained signoff report status is \(retainedSignoffReport.status).",
                        evidencePath: retainedReportPath
                    )
                )
            }
            if retainedSignoffReport.summary.externalOracleQualificationStatus != "passed" {
                blockers.append(
                    blocker(
                        code: "retained-external-oracle-qualification-not-passed",
                        message: "Retained signoff report external oracle qualification is \(retainedSignoffReport.summary.externalOracleQualificationStatus ?? "missing").",
                        evidencePath: retainedReportPath
                    )
                )
            }
            for family in externalSummary.missingDomains {
                blockers.append(
                    blocker(
                        code: "retained-external-oracle-domain-missing",
                        message: "Retained signoff report does not include a passing external oracle lane for \(family.rawValue).",
                        family: family,
                        evidencePath: retainedReportPath
                    )
                )
            }
            for lane in externalSummary.nonPassingLanes {
                blockers.append(
                    blocker(
                        code: "retained-external-oracle-lane-not-ready",
                        message: "Retained external oracle lane \(lane.domain) has status \(lane.status).",
                        domain: lane.domain,
                        evidencePath: retainedReportPath
                    )
                )
            }
        }
        return blockers.sorted(by: blockerSortOrder)
    }

    private func externalOracleSummary(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?
    ) -> ExternalOracleSummary {
        guard let retainedSignoffReport else {
            return ExternalOracleSummary(
                ready: false,
                observedDomains: [],
                missingDomains: request.requiredExternalOracleDomains,
                laneCount: 0,
                passedLaneCount: 0,
                blockedLaneCount: 0,
                failedLaneCount: 0,
                nonPassingLanes: []
            )
        }
        let lanes = retainedSignoffReport.externalOracleResults
        let passingLanes = retainedSignoffReport.passingExternalOracleResults
        let observedDomains = sortedStageFamilies(
            passingLanes.compactMap { stageFamily(domain: $0.domain) }
        )
        let missingDomains = missingDomains(
            required: request.requiredExternalOracleDomains,
            observed: observedDomains
        )
        let blockedLaneCount = lanes.filter { $0.status == "blocked" }.count
        let failedLaneCount = lanes.filter { $0.status == "failed" || $0.qualified == false }.count
        let nonPassingLanes = lanes.filter { !$0.provesRetainedExternalOracleReadiness }
        let retainedSummaryReady = retainedSignoffReport.provesRetainedExternalOracleInfrastructureReadiness
        return ExternalOracleSummary(
            ready: retainedSummaryReady && missingDomains.isEmpty && nonPassingLanes.isEmpty,
            observedDomains: observedDomains,
            missingDomains: missingDomains,
            laneCount: lanes.count,
            passedLaneCount: passingLanes.count,
            blockedLaneCount: blockedLaneCount,
            failedLaneCount: failedLaneCount,
            nonPassingLanes: nonPassingLanes
        )
    }

    private func assessmentStatus(
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        generatedOracleReady: Bool,
        externalOracleInfrastructureReady: Bool,
        blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker]
    ) -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.Status {
        guard qualification.status == .qualified else {
            return .blocked
        }
        guard blockers.contains(where: { $0.severity == .error }) else {
            return .productionReady
        }
        if externalOracleInfrastructureReady && !generatedOracleReady {
            return .readyForExternalCaseExpansion
        }
        return .blocked
    }

    private func generatedLayoutOracleReady(
        _ qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult
    ) -> Bool {
        let statuses = Set(qualification.summary.acceptedOracleReadinessStatuses)
        return statuses == [.ready]
            && qualification.summary.acceptedOracleReadinessCaseCount == qualification.summary.caseCount
            && qualification.summary.readyOracleReadinessWithoutEvidenceCount == 0
            && qualification.summary.readyOracleEvidenceWithoutHashCount == 0
            && qualification.summary.readyOracleEvidenceWithoutByteCount == 0
            && qualification.summary.readyOracleEvidenceRefCount > 0
    }

    private func suggestedActions(
        qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult,
        generatedOracleReady: Bool,
        externalSummary: ExternalOracleSummary
    ) -> [XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction] {
        var actions: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction] = []
        if qualification.status != .qualified {
            actions.append(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction(
                    actionKind: "repair-generated-layout-corpus",
                    reason: "The generated-layout corpus qualification did not pass."
                )
            )
        }
        if !externalSummary.ready {
            actions.append(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction(
                    actionKind: "run-retained-signoff-qualification",
                    reason: "The retained signoff suite does not yet prove external oracle infrastructure readiness."
                )
            )
        }
        if externalSummary.ready && !generatedOracleReady {
            actions.append(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction(
                    actionKind: "run-generated-layout-external-oracle-cases",
                    reason: "External oracle infrastructure is ready, but generated-layout cases have not been promoted with ready oracle evidence."
                )
            )
        }
        for domain in externalSummary.missingDomains {
            actions.append(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction(
                    actionKind: "extend-retained-signoff-suite",
                    reason: "A retained external oracle lane is missing.",
                    targetDomain: domain
                )
            )
        }
        return actions
    }

    private func artifactReference(
        for url: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactReference {
        try XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactReference(
            path: url.path(percentEncoded: false),
            sha256: try hasher.sha256(fileAt: url),
            byteCount: try hasher.byteCount(fileAt: url)
        )
    }

    private func normalize(
        _ request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest
    ) -> XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest {
        var normalized = request
        normalized.requiredExternalOracleDomains = sortedStageFamilies(unique(request.requiredExternalOracleDomains))
        return normalized
    }

    private func missingDomains(
        required: [XcircuiteGeneratedLayoutSignoffStageFamily],
        observed: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        let observedSet = Set(observed)
        return sortedStageFamilies(unique(required).filter { !observedSet.contains($0) })
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
        try workspaceStore.url(
            forProjectRelativePath: "\(XcircuiteWorkspace.directoryName)/qualification/generated-layout-signoff/\(suiteID)",
            inProjectAt: projectRoot
        )
    }

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuiteWorkspace.directoryName)/qualification/generated-layout-signoff/\(suiteID)/\(fileName)"
    }

    private func blocker(
        code: String,
        message: String,
        family: XcircuiteGeneratedLayoutSignoffStageFamily? = nil,
        domain: String? = nil,
        evidencePath: String? = nil
    ) -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker {
        XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker(
            code: code,
            message: message,
            family: family,
            domain: domain,
            evidencePath: evidencePath
        )
    }

    private func blockerSortOrder(
        _ left: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker,
        _ right: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker
    ) -> Bool {
        if left.code != right.code {
            return left.code < right.code
        }
        if left.family != right.family {
            return (left.family?.rawValue ?? "") < (right.family?.rawValue ?? "")
        }
        return (left.domain ?? "") < (right.domain ?? "")
    }

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
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

    private struct ExternalOracleSummary: Sendable, Hashable {
        var ready: Bool
        var observedDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        var missingDomains: [XcircuiteGeneratedLayoutSignoffStageFamily]
        var laneCount: Int
        var passedLaneCount: Int
        var blockedLaneCount: Int
        var failedLaneCount: Int
        var nonPassingLanes: [XcircuiteRetainedSignoffReport.ExternalOracleResult]
    }
}
