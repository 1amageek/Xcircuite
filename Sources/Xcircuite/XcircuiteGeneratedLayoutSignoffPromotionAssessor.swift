import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutSignoffPromotionAssessor: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let fileFingerprinter: any FileFingerprinting
    private let identifierValidator: FlowIdentifierValidator

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        fileFingerprinter: any FileFingerprinting = LocalFileFingerprinter(),
        identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator()
    ) {
        self.workspaceStore = workspaceStore
        self.fileFingerprinter = fileFingerprinter
        self.identifierValidator = identifierValidator
    }

    public func assess(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL? = nil
    ) async throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        try validate(
            request: request,
            validation: validation,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        let normalizedRequest = normalize(request)
        let retainedArtifact = try retainedSignoffReportURL.map(artifactReference)
        let externalSummary = externalOracleSummary(
            request: normalizedRequest,
            retainedSignoffReport: retainedSignoffReport
        )
        let generatedOracleReady = generatedLayoutOracleReady(validation)
        let blockers = makeBlockers(
            request: normalizedRequest,
            validation: validation,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL,
            externalSummary: externalSummary,
            generatedOracleReady: generatedOracleReady
        )
        let status = assessmentStatus(
            validation: validation,
            generatedOracleReady: generatedOracleReady,
            externalOracleInfrastructureReady: externalSummary.ready,
            blockers: blockers
        )
        return try makeAssessment(
            request: normalizedRequest,
            validation: validation,
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
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        let assessmentWithoutSelfRef = try await assess(
            request: request,
            validation: validation,
            retainedSignoffReport: retainedSignoffReport,
            retainedSignoffReportURL: retainedSignoffReportURL
        )
        let assessmentPath = suiteProjectRelativePath(
            suiteID: validation.suiteID,
            fileName: "promotion-assessment.json"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let assessmentReference = try await workspaceStore.persistProjectArtifact(
            content: encoder.encode(assessmentWithoutSelfRef),
            id: ArtifactID(rawValue: "generated-layout-signoff-promotion-assessment"),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: assessmentPath),
                role: .output,
                kind: .report,
                format: .json
            )
        )
        let assessmentArtifact = try artifactFingerprint(assessmentReference)

        var assessment = assessmentWithoutSelfRef
        assessment.assessmentArtifact = assessmentArtifact
        return assessment
    }

    private func validate(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?
    ) throws {
        guard request.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.unsupportedRequestSchemaVersion(
                request.schemaVersion
            )
        }
        guard validation.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffPromotionAssessmentError.unsupportedValidationSchemaVersion(
                validation.schemaVersion
            )
        }
        if let retainedSignoffReport {
            guard retainedSignoffReport.schemaVersion == 4 else {
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
        try identifierValidator.validate(validation.suiteID, kind: .artifactID)
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
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportArtifact: XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint?,
        externalSummary: ExternalOracleSummary,
        generatedOracleReady: Bool,
        blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker],
        status: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Status,
        assessmentArtifact: ArtifactReference?
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment {
        XcircuiteGeneratedLayoutSignoffPromotionAssessment(
            promotionID: request.promotionID,
            suiteID: validation.suiteID,
            status: status,
            summary: XcircuiteGeneratedLayoutSignoffPromotionAssessment.Summary(
                validationStatus: validation.status,
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
                generatedLayoutAcceptedOracleStatuses: validation.summary.acceptedOracleReadinessStatuses,
                blockerCount: blockers.filter { $0.severity == .error }.count
            ),
            blockers: blockers,
            suggestedActions: suggestedActions(
                validation: validation,
                generatedOracleReady: generatedOracleReady,
                externalSummary: externalSummary
            ),
            validationArtifact: try validation.validationArtifact.map(artifactFingerprint),
            retainedSignoffReportArtifact: retainedSignoffReportArtifact,
            assessmentArtifact: try assessmentArtifact.map(artifactFingerprint)
        )
    }

    private func makeBlockers(
        request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        retainedSignoffReport: XcircuiteRetainedSignoffReport?,
        retainedSignoffReportURL: URL?,
        externalSummary: ExternalOracleSummary,
        generatedOracleReady: Bool
    ) -> [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker] {
        var blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker] = []
        if validation.status != .passed {
            blockers.append(
                blocker(
                    code: "generated-layout-corpus-validation-failed",
                    message: "Generated-layout signoff corpus validation status is \(validation.status.rawValue)."
                )
            )
            for failure in validation.failures where failure.severity == .error {
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
            if retainedSignoffReport.summary.externalOracleAssessmentStatus != "passed" {
                blockers.append(
                    blocker(
                        code: "retained-external-oracle-assessment-not-passed",
                        message: "Retained signoff report external oracle assessment is \(retainedSignoffReport.summary.externalOracleAssessmentStatus ?? "missing").",
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
        let failedLaneCount = lanes.filter { $0.status == "failed" || $0.assessmentPassed == false }.count
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
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        generatedOracleReady: Bool,
        externalOracleInfrastructureReady: Bool,
        blockers: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.Blocker]
    ) -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.Status {
        guard validation.status == .passed else {
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
        _ validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult
    ) -> Bool {
        let statuses = Set(validation.summary.acceptedOracleReadinessStatuses)
        return statuses == [.ready]
            && validation.summary.acceptedOracleReadinessCaseCount == validation.summary.caseCount
            && validation.summary.readyOracleReadinessWithoutEvidenceCount == 0
            && validation.summary.readyOracleEvidenceWithoutHashCount == 0
            && validation.summary.readyOracleEvidenceWithoutByteCount == 0
            && validation.summary.readyOracleEvidenceRefCount > 0
    }

    private func suggestedActions(
        validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult,
        generatedOracleReady: Bool,
        externalSummary: ExternalOracleSummary
    ) -> [XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction] {
        var actions: [XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction] = []
        if validation.status != .passed {
            actions.append(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.SuggestedAction(
                    actionKind: "repair-generated-layout-corpus",
                    reason: "The generated-layout corpus validation did not pass."
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
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint {
        let fingerprint = try fileFingerprinter.fingerprint(fileAt: url)
        return try XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint(
            path: url.path(percentEncoded: false),
            sha256: fingerprint.digest.hexadecimalValue,
            byteCount: Int64(fingerprint.byteCount)
        )
    }

    private func artifactFingerprint(
        _ reference: ArtifactReference
    ) throws -> XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint {
        try XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint(
            path: reference.locator.location.value,
            sha256: reference.digest.hexadecimalValue,
            byteCount: Int64(reference.byteCount)
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

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/validation/generated-layout-signoff/\(suiteID)/\(fileName)"
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
