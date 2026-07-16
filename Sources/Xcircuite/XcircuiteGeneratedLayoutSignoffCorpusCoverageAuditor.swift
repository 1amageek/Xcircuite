import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditor: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let identifierValidator: FlowIdentifierValidator

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator()
    ) {
        self.workspaceStore = workspaceStore
        self.identifierValidator = identifierValidator
    }

    public func audit(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy
    ) async throws -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit {
        try validate(report: report, policy: policy)
        let normalizedPolicy = normalize(policy)
        return makeAudit(
            report: report,
            policy: normalizedPolicy,
            policyArtifact: nil,
            auditArtifact: nil
        )
    }

    public func auditAndPersist(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit {
        try validate(report: report, policy: policy)
        let normalizedPolicy = normalize(policy)
        let policyPath = suiteProjectRelativePath(
            suiteID: report.suiteID,
            fileName: "corpus-coverage-audit-policy.json"
        )
        let policyArtifact = try await workspaceStore.persistProjectJSON(
            normalizedPolicy,
            id: "generated-layout-signoff-corpus-coverage-audit-policy",
            path: policyPath
        )

        let auditWithoutSelfRef = makeAudit(
            report: report,
            policy: normalizedPolicy,
            policyArtifact: policyArtifact,
            auditArtifact: nil
        )
        let auditPath = suiteProjectRelativePath(
            suiteID: report.suiteID,
            fileName: "corpus-coverage-audit.json"
        )
        let auditArtifact = try await workspaceStore.persistProjectJSON(
            auditWithoutSelfRef,
            id: "generated-layout-signoff-corpus-coverage-audit",
            path: auditPath
        )

        var audit = auditWithoutSelfRef
        audit.auditArtifact = auditArtifact
        return audit
    }

    private func validate(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy
    ) throws {
        guard report.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditError
                .unsupportedReportSchemaVersion(report.schemaVersion)
        }
        guard policy.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditError
                .unsupportedPolicySchemaVersion(policy.schemaVersion)
        }
        guard policy.minimumCaseCount >= 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditError
                .invalidMinimumCaseCount(policy.minimumCaseCount)
        }
        try identifierValidator.validate(report.suiteID, kind: .artifactID)
        try identifierValidator.validate(policy.policyID, kind: .artifactID)
        for coverageTag in policy.requiredCoverageTags {
            try identifierValidator.validate(coverageTag, kind: .artifactID)
        }
        for artifactID in policy.requiredSignoffArtifactIDs {
            try identifierValidator.validate(artifactID, kind: .artifactID)
        }
        for caseResult in report.caseResults {
            try identifierValidator.validate(caseResult.caseID, kind: .artifactID)
            try identifierValidator.validate(caseResult.runID, kind: .runID)
        }
    }

    private func makeAudit(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy,
        policyArtifact: ArtifactReference?,
        auditArtifact: ArtifactReference?
    ) -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit {
        let coveredTags = unique(report.caseResults.flatMap(\.coverageTags)).sorted()
        let sourceFormats = unique(
            report.caseResults.flatMap(\.sourceArtifactRefs).map { normalizeFormat($0.format.rawValue) }
        )
        let signoffArtifactIDs = unique(report.caseResults.flatMap(\.signoffArtifactRefs).map(\.artifactID)).sorted()
        let stageFamilies = sortedStageFamilies(unique(report.caseResults.flatMap(\.stageResults).map(\.family)))
        let readyOracleEvidenceRefCount = report.caseResults
            .flatMap(\.oracleReadiness)
            .filter { $0.status == .ready }
            .reduce(0) { $0 + $1.evidenceRefs.count }
        let caseIDs = report.caseResults.map(\.caseID)
        let uniqueCaseCount = unique(caseIDs).count
        let duplicateCaseIDs = duplicateValues(caseIDs).sorted()
        let duplicateCaseCount = report.caseResults.count - uniqueCaseCount

        let missingCoverageTags = policy.requiredCoverageTags.filter { !coveredTags.contains($0) }
        let missingSourceFormats = policy.requiredSourceArtifactFormats
            .map(normalizeFormat)
            .filter { !sourceFormats.contains($0) }
        let missingSignoffArtifactIDs = policy.requiredSignoffArtifactIDs
            .filter { !signoffArtifactIDs.contains($0) }
        let missingStageFamilies = missingStageFamilies(observed: stageFamilies, required: policy.requiredStageFamilies)

        var missingRequirements: [XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement] = []
        if uniqueCaseCount < policy.minimumCaseCount {
            missingRequirements.append(
                missingRequirement(
                    kind: "case-count",
                    identifier: "minimum-case-count",
                    message: "Corpus contains \(uniqueCaseCount) unique cases, below policy minimum \(policy.minimumCaseCount)."
                )
            )
        }
        if report.summary.caseCount != report.caseResults.count {
            missingRequirements.append(
                missingRequirement(
                    kind: "case-count-mismatch",
                    identifier: "summary-case-count",
                    message: "Corpus summary reports \(report.summary.caseCount) cases, but caseResults contains \(report.caseResults.count)."
                )
            )
        }
        missingRequirements.append(
            contentsOf: duplicateCaseIDs.map {
                missingRequirement(
                    kind: "duplicate-case",
                    identifier: $0,
                    message: "Generated-layout corpus case \($0) appears more than once and cannot increase coverage breadth."
                )
            }
        )
        missingRequirements.append(
            contentsOf: missingCoverageTags.map {
                missingRequirement(
                    kind: "coverage-tag",
                    identifier: $0,
                    message: "Required generated-layout coverage tag \($0) is not covered."
                )
            }
        )
        missingRequirements.append(
            contentsOf: missingSourceFormats.map {
                missingRequirement(
                    kind: "source-artifact-format",
                    identifier: $0,
                    message: "Required generated-layout source artifact format \($0) is not observed."
                )
            }
        )
        missingRequirements.append(
            contentsOf: missingSignoffArtifactIDs.map {
                missingRequirement(
                    kind: "signoff-artifact-id",
                    identifier: $0,
                    message: "Required generated-layout signoff artifact \($0) is not observed."
                )
            }
        )
        missingRequirements.append(
            contentsOf: missingStageFamilies.map {
                missingRequirement(
                    kind: "stage-family",
                    identifier: $0.rawValue,
                    message: "Required generated-layout stage family \($0.rawValue) is not observed."
                )
            }
        )
        if policy.requireReadyOracleEvidence && readyOracleEvidenceRefCount == 0 {
            missingRequirements.append(
                missingRequirement(
                    kind: "ready-oracle-evidence",
                    identifier: "ready-oracle-evidence-refs",
                    message: "Policy requires ready oracle evidence refs, but none are attached."
                )
            )
        }

        let sortedMissingRequirements = missingRequirements.sorted(by: missingRequirementSortOrder)
        return XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit(
            suiteID: report.suiteID,
            policyID: policy.policyID,
            status: sortedMissingRequirements.isEmpty ? .satisfied : .incomplete,
            summary: XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.Summary(
                caseCount: report.caseResults.count,
                reportedCaseCount: report.summary.caseCount,
                uniqueCaseCount: uniqueCaseCount,
                duplicateCaseCount: duplicateCaseCount,
                minimumCaseCount: policy.minimumCaseCount,
                coveredCoverageTags: coveredTags,
                missingCoverageTags: missingCoverageTags,
                observedSourceArtifactFormats: sourceFormats,
                missingSourceArtifactFormats: missingSourceFormats,
                observedSignoffArtifactIDs: signoffArtifactIDs,
                missingSignoffArtifactIDs: missingSignoffArtifactIDs,
                observedStageFamilies: stageFamilies,
                missingStageFamilies: missingStageFamilies,
                readyOracleEvidenceRefCount: readyOracleEvidenceRefCount,
                missingRequirementCount: sortedMissingRequirements.count
            ),
            missingRequirements: sortedMissingRequirements,
            suggestedActions: suggestedActions(missingRequirements: sortedMissingRequirements),
            policyArtifact: policyArtifact,
            auditArtifact: auditArtifact
        )
    }

    private func suggestedActions(
        missingRequirements: [XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement]
    ) -> [XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.SuggestedAction] {
        missingRequirements.map { requirement in
            switch requirement.kind {
            case "coverage-tag":
                return suggestedAction(
                    actionKind: "add-generated-layout-coverage-case",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "source-artifact-format":
                return suggestedAction(
                    actionKind: "add-standard-layout-export-case",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "signoff-artifact-id":
                return suggestedAction(
                    actionKind: "add-signoff-artifact-case",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "stage-family":
                return suggestedAction(
                    actionKind: "extend-signoff-stage-ladder",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "ready-oracle-evidence":
                return suggestedAction(
                    actionKind: "attach-generated-layout-ready-oracle-evidence",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "duplicate-case":
                return suggestedAction(
                    actionKind: "remove-duplicate-generated-layout-corpus-case",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "case-count-mismatch":
                return suggestedAction(
                    actionKind: "regenerate-generated-layout-signoff-corpus-report",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            default:
                return suggestedAction(
                    actionKind: "expand-generated-layout-corpus",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            }
        }
    }

    private func normalize(
        _ policy: XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy
    ) -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy {
        var normalized = policy
        normalized.requiredCoverageTags = unique(policy.requiredCoverageTags).sorted()
        normalized.requiredSourceArtifactFormats = unique(policy.requiredSourceArtifactFormats.map(normalizeFormat))
        normalized.requiredSignoffArtifactIDs = unique(policy.requiredSignoffArtifactIDs).sorted()
        normalized.requiredStageFamilies = sortedStageFamilies(unique(policy.requiredStageFamilies))
        return normalized
    }

    private func missingStageFamilies(
        observed: [XcircuiteGeneratedLayoutSignoffStageFamily],
        required: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        let observedSet = Set(observed)
        return sortedStageFamilies(required.filter { !observedSet.contains($0) })
    }

    private func normalizeFormat(_ format: String) -> String {
        format.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/validation/generated-layout-signoff/\(suiteID)/\(fileName)"
    }

    private func missingRequirement(
        kind: String,
        identifier: String,
        message: String
    ) -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement {
        XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement(
            kind: kind,
            identifier: identifier,
            message: message
        )
    }

    private func suggestedAction(
        actionKind: String,
        reason: String,
        targetIdentifier: String?
    ) -> XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.SuggestedAction {
        XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.SuggestedAction(
            actionKind: actionKind,
            reason: reason,
            targetIdentifier: targetIdentifier
        )
    }

    private func missingRequirementSortOrder(
        _ left: XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement,
        _ right: XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.MissingRequirement
    ) -> Bool {
        if left.kind != right.kind {
            return left.kind < right.kind
        }
        return left.identifier < right.identifier
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

    private func duplicateValues<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var duplicates: [T] = []
        for value in values {
            if seen.contains(value) {
                duplicates.append(value)
            } else {
                seen.insert(value)
            }
        }
        return unique(duplicates)
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
}
import CircuiteFoundation
