import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutFailureLadderCoverageAuditor: Sendable {
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
        reports: [XcircuiteGeneratedLayoutFailureLadderReport],
        policy: XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy
    ) throws -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit {
        try validate(reports: reports, policy: policy)
        let normalizedPolicy = normalize(policy)
        return makeAudit(
            reports: reports,
            policy: normalizedPolicy,
            policyArtifact: nil,
            auditArtifact: nil
        )
    }

    public func auditAndPersist(
        reports: [XcircuiteGeneratedLayoutFailureLadderReport],
        policy: XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit {
        try validate(reports: reports, policy: policy)
        let normalizedPolicy = normalize(policy)
        let policyPath = auditProjectRelativePath(
            auditID: normalizedPolicy.auditID,
            fileName: "failure-ladder-coverage-audit-policy.json"
        )
        let policyArtifact = try await workspaceStore.persistProjectJSON(
            normalizedPolicy,
            id: "generated-layout-failure-ladder-coverage-audit-policy",
            path: policyPath
        )

        let auditWithoutSelfRef = makeAudit(
            reports: reports,
            policy: normalizedPolicy,
            policyArtifact: policyArtifact,
            auditArtifact: nil
        )
        let auditPath = auditProjectRelativePath(
            auditID: normalizedPolicy.auditID,
            fileName: "failure-ladder-coverage-audit.json"
        )
        let auditArtifact = try await workspaceStore.persistProjectJSON(
            auditWithoutSelfRef,
            id: "generated-layout-failure-ladder-coverage-audit",
            path: auditPath
        )

        var audit = auditWithoutSelfRef
        audit.auditArtifact = auditArtifact
        return audit
    }

    private func validate(
        reports: [XcircuiteGeneratedLayoutFailureLadderReport],
        policy: XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy
    ) throws {
        guard policy.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutFailureLadderCoverageAuditError
                .unsupportedPolicySchemaVersion(policy.schemaVersion)
        }
        guard !reports.isEmpty else {
            throw XcircuiteGeneratedLayoutFailureLadderCoverageAuditError.emptyReportSet
        }
        guard policy.minimumReportCount >= 1 else {
            throw XcircuiteGeneratedLayoutFailureLadderCoverageAuditError
                .invalidMinimumReportCount(policy.minimumReportCount)
        }
        try identifierValidator.validate(policy.auditID, kind: .artifactID)
        for actionKind in policy.requiredSuggestedActionKinds {
            try identifierValidator.validate(actionKind, kind: .artifactID)
        }
        for artifactID in policy.requiredEvidenceArtifactIDs {
            try identifierValidator.validate(artifactID, kind: .artifactID)
        }
        for report in reports {
            guard report.schemaVersion == 1 else {
                throw XcircuiteGeneratedLayoutFailureLadderCoverageAuditError
                    .unsupportedReportSchemaVersion(report.schemaVersion)
            }
            try identifierValidator.validate(report.ladderID, kind: .artifactID)
            try identifierValidator.validate(report.runID, kind: .runID)
        }
    }

    private func makeAudit(
        reports: [XcircuiteGeneratedLayoutFailureLadderReport],
        policy: XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy,
        policyArtifact: ArtifactReference?,
        auditArtifact: ArtifactReference?
    ) -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit {
        let reportCases = reports.map(reportCase).sorted { left, right in
            if left.firstFailingFamily?.rawValue != right.firstFailingFamily?.rawValue {
                return (left.firstFailingFamily?.rawValue ?? "") < (right.firstFailingFamily?.rawValue ?? "")
            }
            return left.runID < right.runID
        }
        let observedFamilies = sortedStageFamilies(unique(reportCases.compactMap(\.firstFailingFamily)))
        let observedActionKinds = unique(reportCases.flatMap(\.suggestedActionKinds)).sorted()
        let observedEvidenceArtifactIDs = unique(reportCases.flatMap(\.evidenceArtifactIDs)).sorted()
        let diagnosticCodeCount = unique(reportCases.flatMap(\.diagnosticCodes)).count
        let reportIdentities = reportCases.map(reportIdentity)
        let uniqueReportCount = unique(reportIdentities).count
        let duplicateReportIdentities = duplicateValues(reportIdentities).sorted()
        let duplicateReportCount = reports.count - uniqueReportCount
        let missingFamilies = missingStageFamilies(
            observed: observedFamilies,
            required: policy.requiredFirstFailingFamilies
        )
        let missingActionKinds = policy.requiredSuggestedActionKinds.filter {
            !observedActionKinds.contains($0)
        }
        let missingEvidenceArtifactIDs = policy.requiredEvidenceArtifactIDs.filter {
            !observedEvidenceArtifactIDs.contains($0)
        }

        var missingRequirements: [XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement] = []
        if uniqueReportCount < policy.minimumReportCount {
            missingRequirements.append(missingRequirement(
                kind: "report-count",
                identifier: "minimum-report-count",
                message: "Failure ladder coverage contains \(uniqueReportCount) unique reports, below policy minimum \(policy.minimumReportCount)."
            ))
        }
        missingRequirements.append(contentsOf: duplicateReportIdentities.map {
            missingRequirement(
                kind: "duplicate-report",
                identifier: $0,
                message: "Failure ladder report \($0) appears more than once and cannot increase coverage breadth."
            )
        })
        missingRequirements.append(contentsOf: missingFamilies.map {
            missingRequirement(
                kind: "first-failing-family",
                identifier: $0.rawValue,
                message: "Required first failing family \($0.rawValue) is not covered."
            )
        })
        missingRequirements.append(contentsOf: missingActionKinds.map {
            missingRequirement(
                kind: "suggested-action-kind",
                identifier: $0,
                message: "Required suggested action \($0) is not covered."
            )
        })
        missingRequirements.append(contentsOf: missingEvidenceArtifactIDs.map {
            missingRequirement(
                kind: "evidence-artifact-id",
                identifier: $0,
                message: "Required evidence artifact \($0) is not observed."
            )
        })
        if policy.requireDiagnosticCodes && diagnosticCodeCount == 0 {
            missingRequirements.append(missingRequirement(
                kind: "diagnostic-code",
                identifier: "diagnostic-codes",
                message: "Policy requires diagnostic codes, but no failure ladder diagnostics were retained."
            ))
        }

        let sortedMissingRequirements = missingRequirements.sorted(by: missingRequirementSortOrder)
        return XcircuiteGeneratedLayoutFailureLadderCoverageAudit(
            auditID: policy.auditID,
            status: sortedMissingRequirements.isEmpty ? .satisfied : .incomplete,
            summary: XcircuiteGeneratedLayoutFailureLadderCoverageAudit.Summary(
                reportCount: reports.count,
                uniqueReportCount: uniqueReportCount,
                duplicateReportCount: duplicateReportCount,
                minimumReportCount: policy.minimumReportCount,
                observedFirstFailingFamilies: observedFamilies,
                missingFirstFailingFamilies: missingFamilies,
                observedSuggestedActionKinds: observedActionKinds,
                missingSuggestedActionKinds: missingActionKinds,
                observedEvidenceArtifactIDs: observedEvidenceArtifactIDs,
                missingEvidenceArtifactIDs: missingEvidenceArtifactIDs,
                reportArtifactRefCount: reports.filter { $0.reportArtifact != nil }.count,
                diagnosticCodeCount: diagnosticCodeCount,
                missingRequirementCount: sortedMissingRequirements.count
            ),
            reportCases: reportCases,
            missingRequirements: sortedMissingRequirements,
            suggestedActions: suggestedActions(missingRequirements: sortedMissingRequirements),
            policyArtifact: policyArtifact,
            auditArtifact: auditArtifact
        )
    }

    private func reportCase(
        _ report: XcircuiteGeneratedLayoutFailureLadderReport
    ) -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit.ReportCase {
        XcircuiteGeneratedLayoutFailureLadderCoverageAudit.ReportCase(
            ladderID: report.ladderID,
            runID: report.runID,
            firstFailingStageID: report.summary.firstFailingStageID,
            firstFailingGateID: report.summary.firstFailingGateID,
            firstFailingFamily: report.summary.firstFailingFamily,
            suggestedActionKinds: unique(report.suggestedActions.map(\.actionKind)).sorted(),
            evidenceArtifactIDs: unique(report.suggestedActions.flatMap(\.evidenceArtifactIDs)).sorted(),
            diagnosticCodes: unique(report.suggestedActions.flatMap(\.diagnosticCodes)).sorted(),
            reportArtifactPath: report.reportArtifact?.path
        )
    }

    private func suggestedActions(
        missingRequirements: [XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement]
    ) -> [XcircuiteGeneratedLayoutFailureLadderCoverageAudit.SuggestedAction] {
        missingRequirements.map { requirement in
            switch requirement.kind {
            case "first-failing-family":
                return suggestedAction(
                    actionKind: "add-generated-layout-failure-case",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "suggested-action-kind":
                return suggestedAction(
                    actionKind: "extend-failure-ladder-action-classification",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "evidence-artifact-id":
                return suggestedAction(
                    actionKind: "retain-failure-evidence-artifact",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "diagnostic-code":
                return suggestedAction(
                    actionKind: "retain-failure-diagnostic-codes",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            case "duplicate-report":
                return suggestedAction(
                    actionKind: "remove-duplicate-failure-ladder-report",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            default:
                return suggestedAction(
                    actionKind: "expand-generated-layout-failure-ladder-coverage",
                    reason: requirement.message,
                    targetIdentifier: requirement.identifier
                )
            }
        }
    }

    private func normalize(
        _ policy: XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy
    ) -> XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy {
        var normalized = policy
        normalized.requiredFirstFailingFamilies = sortedStageFamilies(unique(policy.requiredFirstFailingFamilies))
        normalized.requiredSuggestedActionKinds = unique(policy.requiredSuggestedActionKinds).sorted()
        normalized.requiredEvidenceArtifactIDs = unique(policy.requiredEvidenceArtifactIDs).sorted()
        return normalized
    }

    private func missingStageFamilies(
        observed: [XcircuiteGeneratedLayoutSignoffStageFamily],
        required: [XcircuiteGeneratedLayoutSignoffStageFamily]
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        let observedSet = Set(observed)
        return sortedStageFamilies(required.filter { !observedSet.contains($0) })
    }

    private func auditProjectRelativePath(auditID: String, fileName: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/qualification/generated-layout-failure-ladder/\(auditID)/\(fileName)"
    }

    private func missingRequirement(
        kind: String,
        identifier: String,
        message: String
    ) -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement {
        XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement(
            kind: kind,
            identifier: identifier,
            message: message
        )
    }

    private func suggestedAction(
        actionKind: String,
        reason: String,
        targetIdentifier: String?
    ) -> XcircuiteGeneratedLayoutFailureLadderCoverageAudit.SuggestedAction {
        XcircuiteGeneratedLayoutFailureLadderCoverageAudit.SuggestedAction(
            actionKind: actionKind,
            reason: reason,
            targetIdentifier: targetIdentifier
        )
    }

    private func missingRequirementSortOrder(
        _ left: XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement,
        _ right: XcircuiteGeneratedLayoutFailureLadderCoverageAudit.MissingRequirement
    ) -> Bool {
        if left.kind != right.kind {
            return left.kind < right.kind
        }
        return left.identifier < right.identifier
    }

    private func reportIdentity(
        _ reportCase: XcircuiteGeneratedLayoutFailureLadderCoverageAudit.ReportCase
    ) -> String {
        "\(reportCase.runID):\(reportCase.ladderID)"
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
