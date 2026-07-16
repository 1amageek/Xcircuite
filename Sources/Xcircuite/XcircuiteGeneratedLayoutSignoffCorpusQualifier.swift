import Foundation
import DesignFlowKernel

public struct XcircuiteGeneratedLayoutSignoffCorpusQualifier: Sendable {
    private let workspaceStore: XcircuiteWorkspaceStore
    private let identifierValidator: FlowIdentifierValidator

    public init(
        workspaceStore: XcircuiteWorkspaceStore,
        identifierValidator: FlowIdentifierValidator = FlowIdentifierValidator()
    ) {
        self.workspaceStore = workspaceStore
        self.identifierValidator = identifierValidator
    }

    public func qualify(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) async throws -> XcircuiteGeneratedLayoutSignoffCorpusQualificationResult {
        try validate(report: report, policy: policy)

        let normalizedPolicy = normalize(policy)
        let projectRoot = workspaceStore.projectRoot
        let failures = collectFailures(
            report: report,
            policy: normalizedPolicy,
            projectRoot: projectRoot
        )
        let status: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Status = failures
            .contains { $0.severity == .error } ? .failed : .qualified
        return makeResult(
            report: report,
            policy: normalizedPolicy,
            status: status,
            failures: failures,
            projectRoot: projectRoot,
            policyArtifact: nil,
            qualificationArtifact: nil
        )
    }

    public func qualifyAndPersist(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy,
        projectRoot: URL
    ) async throws -> XcircuiteGeneratedLayoutSignoffCorpusQualificationResult {
        try validate(report: report, policy: policy)
        let normalizedPolicy = normalize(policy)
        let policyPath = suiteProjectRelativePath(
            suiteID: report.suiteID,
            fileName: "corpus-qualification-policy.json"
        )
        let policyArtifact = try await workspaceStore.persistProjectJSON(
            normalizedPolicy,
            id: "generated-layout-signoff-corpus-qualification-policy",
            path: policyPath
        )

        let failures = collectFailures(
            report: report,
            policy: normalizedPolicy,
            projectRoot: projectRoot
        )
        let status: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Status = failures
            .contains { $0.severity == .error } ? .failed : .qualified
        let resultWithoutSelfRef = makeResult(
            report: report,
            policy: normalizedPolicy,
            status: status,
            failures: failures,
            projectRoot: projectRoot,
            policyArtifact: policyArtifact,
            qualificationArtifact: nil
        )

        let qualificationPath = suiteProjectRelativePath(
            suiteID: report.suiteID,
            fileName: "corpus-qualification.json"
        )
        let qualificationArtifact = try await workspaceStore.persistProjectJSON(
            resultWithoutSelfRef,
            id: "generated-layout-signoff-corpus-qualification",
            path: qualificationPath
        )

        var result = resultWithoutSelfRef
        result.qualificationArtifact = qualificationArtifact
        return result
    }

    private func validate(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) throws {
        guard report.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusQualificationError.unsupportedReportSchemaVersion(
                report.schemaVersion
            )
        }
        guard policy.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusQualificationError.unsupportedPolicySchemaVersion(
                policy.schemaVersion
            )
        }
        guard policy.minimumCaseCount >= 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusQualificationError.invalidMinimumCaseCount(
                policy.minimumCaseCount
            )
        }
        guard policy.minimumSourceArtifactCount >= 0 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusQualificationError.invalidMinimumSourceArtifactCount(
                policy.minimumSourceArtifactCount
            )
        }
        guard policy.minimumSignoffArtifactCount >= 0 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusQualificationError.invalidMinimumSignoffArtifactCount(
                policy.minimumSignoffArtifactCount
            )
        }
        try identifierValidator.validate(report.suiteID, kind: .artifactID)
        try identifierValidator.validate(policy.policyID, kind: .artifactID)
        for coverageTag in policy.requiredCoverageTags {
            try identifierValidator.validate(coverageTag, kind: .artifactID)
        }
        for caseResult in report.caseResults {
            try identifierValidator.validate(caseResult.caseID, kind: .artifactID)
            try identifierValidator.validate(caseResult.runID, kind: .runID)
            for coverageTag in caseResult.coverageTags {
                try identifierValidator.validate(coverageTag, kind: .artifactID)
            }
            for stageResult in caseResult.stageResults {
                try identifierValidator.validate(stageResult.stageID, kind: .stageID)
            }
        }
    }

    private func collectFailures(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy,
        projectRoot: URL
    ) -> [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] {
        var failures: [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] = []
        if policy.requireReportPassed && report.status != .passed {
            failures.append(
                failure(
                    code: "corpus-report-failed",
                    message: "Corpus report status is \(report.status.rawValue), but the policy requires a passed report."
                )
            )
        }
        let caseIDs = report.caseResults.map(\.caseID)
        let uniqueCaseCount = unique(caseIDs).count
        if uniqueCaseCount < policy.minimumCaseCount {
            failures.append(
                failure(
                    code: "minimum-case-count-not-met",
                    message: "Corpus contains \(uniqueCaseCount) unique cases, below policy minimum \(policy.minimumCaseCount)."
                )
            )
        }
        if report.summary.caseCount != report.caseResults.count {
            failures.append(
                failure(
                    code: "case-count-mismatch",
                    message: "Corpus summary reports \(report.summary.caseCount) cases, but caseResults contains \(report.caseResults.count)."
                )
            )
        }
        for duplicateCaseID in duplicateValues(caseIDs).sorted() {
            failures.append(
                failure(
                    code: "duplicate-case",
                    message: "Generated-layout corpus case \(duplicateCaseID) appears more than once and cannot increase qualification coverage breadth.",
                    caseID: duplicateCaseID
                )
            )
        }
        for coverageTag in missingCoverageTags(report: report, policy: policy) {
            failures.append(
                failure(
                    code: "missing-coverage-tag",
                    message: "Required generated-layout signoff coverage tag \(coverageTag) is not covered.",
                    coverageTag: coverageTag
                )
            )
        }
        for family in missingStageFamilies(report: report, policy: policy) {
            failures.append(
                failure(
                    code: "missing-stage-family",
                    message: "Required generated-layout signoff stage family \(family.rawValue) was not observed.",
                    family: family
                )
            )
        }
        if !policy.allowExpectedVerdictMismatches && report.summary.expectedVerdictMismatchCount > 0 {
            failures.append(
                failure(
                    code: "expected-verdict-mismatch",
                    message: "Corpus report has \(report.summary.expectedVerdictMismatchCount) run or stage verdict mismatches."
                )
            )
        }
        let sourceArtifactCount = sourceArtifactRefCount(report)
        if sourceArtifactCount < policy.minimumSourceArtifactCount {
            failures.append(
                failure(
                    code: "minimum-source-artifact-count-not-met",
                    message: "Corpus contains \(sourceArtifactCount) source artifacts, below policy minimum \(policy.minimumSourceArtifactCount)."
                )
            )
        }
        if report.summary.standardLayoutArtifactCount != sourceArtifactCount {
            failures.append(
                failure(
                    code: "source-artifact-count-mismatch",
                    message: "Corpus summary reports \(report.summary.standardLayoutArtifactCount) source artifacts, but retained source artifact refs contain \(sourceArtifactCount)."
                )
            )
        }
        let signoffArtifactCount = signoffArtifactRefCount(report)
        if signoffArtifactCount < policy.minimumSignoffArtifactCount {
            failures.append(
                failure(
                    code: "minimum-signoff-artifact-count-not-met",
                    message: "Corpus contains \(signoffArtifactCount) signoff artifacts, below policy minimum \(policy.minimumSignoffArtifactCount)."
                )
            )
        }
        if report.summary.signoffArtifactCount != signoffArtifactCount {
            failures.append(
                failure(
                    code: "signoff-artifact-count-mismatch",
                    message: "Corpus summary reports \(report.summary.signoffArtifactCount) signoff artifacts, but retained signoff artifact refs contain \(signoffArtifactCount)."
                )
            )
        }
        failures.append(contentsOf: oracleReadinessFailures(report: report, policy: policy))
        failures.append(
            contentsOf: artifactFailures(
                report: report,
                policy: policy,
                projectRoot: projectRoot
            )
        )
        return failures.sorted(by: failureSortOrder)
    }

    private func oracleReadinessFailures(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] {
        var failures: [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] = []
        let acceptedStatuses = Set(policy.acceptedOracleReadinessStatuses)
        for caseResult in report.caseResults {
            let readinessByFamily = Dictionary(
                caseResult.oracleReadiness.map { ($0.domain, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for family in policy.requiredOracleReadinessFamilies {
                guard let readiness = readinessByFamily[family] else {
                    failures.append(
                        failure(
                            code: "missing-oracle-readiness",
                            message: "Case \(caseResult.caseID) does not declare oracle readiness for \(family.rawValue).",
                            caseID: caseResult.caseID,
                            family: family
                        )
                    )
                    continue
                }
                if !acceptedStatuses.contains(readiness.status) {
                    failures.append(
                        failure(
                            code: "oracle-readiness-not-accepted",
                            message: "Case \(caseResult.caseID) declares \(family.rawValue) oracle \(readiness.backendID) as \(readiness.status.rawValue), outside policy accepted statuses.",
                            caseID: caseResult.caseID,
                            family: family
                        )
                    )
                }
                if readiness.status == .ready {
                    failures.append(
                        contentsOf: readyOracleEvidenceFailures(
                            readiness,
                            caseResult: caseResult,
                            policy: policy
                        )
                    )
                }
            }
        }
        return failures
    }

    private func readyOracleEvidenceFailures(
        _ readiness: XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness,
        caseResult: XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] {
        var failures: [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] = []
        if policy.requireReadyOracleEvidenceRefs && readiness.evidenceRefs.isEmpty {
            failures.append(
                failure(
                    code: "ready-oracle-evidence-missing",
                    message: "Case \(caseResult.caseID) declares \(readiness.domain.rawValue) oracle \(readiness.backendID) as ready without evidence refs.",
                    caseID: caseResult.caseID,
                    family: readiness.domain
                )
            )
        }
        for evidenceRef in readiness.evidenceRefs {
            if policy.requireReadyOracleEvidenceHashes && (evidenceRef.sha256 ?? "").isEmpty {
                failures.append(
                    failure(
                        code: "ready-oracle-evidence-missing-sha256",
                        message: "Case \(caseResult.caseID) ready oracle evidence \(evidenceRef.path) does not include a SHA-256 digest.",
                        caseID: caseResult.caseID,
                        path: evidenceRef.path,
                        family: readiness.domain
                    )
                )
            }
            if policy.requireReadyOracleEvidenceByteCounts && (evidenceRef.byteCount ?? 0) <= 0 {
                failures.append(
                    failure(
                        code: "ready-oracle-evidence-missing-byte-count",
                        message: "Case \(caseResult.caseID) ready oracle evidence \(evidenceRef.path) does not include a positive byte count.",
                        caseID: caseResult.caseID,
                        path: evidenceRef.path,
                        family: readiness.domain
                    )
                )
            }
        }
        return failures
    }

    private func artifactFailures(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy,
        projectRoot: URL
    ) -> [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] {
        var failures: [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure] = []
        for artifact in uniqueArtifacts(report) {
            if policy.requireArtifactHashes && artifact.digest.hexadecimalValue.isEmpty {
                failures.append(
                    failure(
                        code: "artifact-missing-sha256",
                        message: "Artifact \(artifact.path) does not include a SHA-256 digest.",
                        stageID: nil,
                        artifactID: artifact.artifactID,
                        path: artifact.path
                    )
                )
            }
            if policy.requireArtifactByteCounts && artifact.byteCount == 0 {
                failures.append(
                    failure(
                        code: "artifact-missing-byte-count",
                        message: "Artifact \(artifact.path) does not include a positive byte count.",
                        stageID: nil,
                        artifactID: artifact.artifactID,
                        path: artifact.path
                    )
                )
            }
            let integrity = LocalArtifactVerifier().verify(artifact, relativeTo: projectRoot)
            if policy.requireArtifactIntegrityPassed, !integrity.isVerified {
                failures.append(
                    failure(
                        code: "artifact-integrity-failed",
                        message: integrity.issues.map(\.code.rawValue).joined(separator: ","),
                        stageID: nil,
                        artifactID: artifact.artifactID,
                        path: artifact.path
                    )
                )
            }
        }
        return failures
    }

    private func makeResult(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy,
        status: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Status,
        failures: [XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure],
        projectRoot: URL,
        policyArtifact: ArtifactReference?,
        qualificationArtifact: ArtifactReference?
    ) -> XcircuiteGeneratedLayoutSignoffCorpusQualificationResult {
        let artifacts = uniqueArtifacts(report)
        let sourceArtifactCount = sourceArtifactRefCount(report)
        let signoffArtifactCount = signoffArtifactRefCount(report)
        let missingHashCount = artifacts.filter { $0.digest.hexadecimalValue.isEmpty }.count
        let missingByteCount = artifacts.filter { $0.byteCount == 0 }.count
        let integrityFailureCount = artifacts.filter {
            !LocalArtifactVerifier().verify($0, relativeTo: projectRoot).isVerified
        }.count
        let observedStageFamilies = observedStageFamilies(report)
        let readyOracleEvidenceStats = readyOracleEvidenceStats(report: report, policy: policy)
        let acceptedReadinessCaseCount = report.caseResults.filter { caseResult in
            oracleReadinessAccepted(caseResult: caseResult, policy: policy)
        }.count
        let caseIDs = report.caseResults.map(\.caseID)
        let uniqueCaseCount = unique(caseIDs).count

        return XcircuiteGeneratedLayoutSignoffCorpusQualificationResult(
            suiteID: report.suiteID,
            policyID: policy.policyID,
            status: status,
            summary: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Summary(
                reportStatus: report.status,
                caseCount: report.caseResults.count,
                reportedCaseCount: report.summary.caseCount,
                uniqueCaseCount: uniqueCaseCount,
                duplicateCaseCount: report.caseResults.count - uniqueCaseCount,
                minimumCaseCount: policy.minimumCaseCount,
                passedCaseCount: report.caseResults.filter { $0.status == .passed }.count,
                failedCaseCount: report.caseResults.filter { $0.status == .failed }.count,
                requiredCoverageTags: policy.requiredCoverageTags,
                coveredCoverageTags: coveredCoverageTags(report),
                missingCoverageTags: missingCoverageTags(report: report, policy: policy),
                requiredStageFamilies: policy.requiredStageFamilies,
                observedStageFamilies: observedStageFamilies,
                missingStageFamilies: missingStageFamilies(
                    observedStageFamilies: observedStageFamilies,
                    policy: policy
                ),
                requiredOracleReadinessFamilies: policy.requiredOracleReadinessFamilies,
                acceptedOracleReadinessStatuses: policy.acceptedOracleReadinessStatuses,
                acceptedOracleReadinessCaseCount: acceptedReadinessCaseCount,
                readyOracleEvidenceRefCount: readyOracleEvidenceStats.refCount,
                readyOracleReadinessWithoutEvidenceCount: readyOracleEvidenceStats.readinessWithoutEvidenceCount,
                readyOracleEvidenceWithoutHashCount: readyOracleEvidenceStats.refWithoutHashCount,
                readyOracleEvidenceWithoutByteCount: readyOracleEvidenceStats.refWithoutByteCount,
                expectedVerdictMismatchCount: report.summary.expectedVerdictMismatchCount,
                sourceArtifactCount: sourceArtifactCount,
                reportedSourceArtifactCount: report.summary.standardLayoutArtifactCount,
                minimumSourceArtifactCount: policy.minimumSourceArtifactCount,
                signoffArtifactCount: signoffArtifactCount,
                reportedSignoffArtifactCount: report.summary.signoffArtifactCount,
                minimumSignoffArtifactCount: policy.minimumSignoffArtifactCount,
                artifactWithoutHashCount: missingHashCount,
                artifactWithoutByteCount: missingByteCount,
                artifactIntegrityFailureCount: integrityFailureCount,
                failureCount: failures.count
            ),
            failures: failures,
            policyArtifact: policyArtifact,
            qualificationArtifact: qualificationArtifact
        )
    }

    private func normalize(
        _ policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy {
        var normalized = policy
        normalized.requiredCoverageTags = unique(policy.requiredCoverageTags)
        normalized.requiredStageFamilies = sortedStageFamilies(unique(policy.requiredStageFamilies))
        normalized.requiredOracleReadinessFamilies = sortedStageFamilies(
            unique(policy.requiredOracleReadinessFamilies)
        )
        normalized.acceptedOracleReadinessStatuses = unique(policy.acceptedOracleReadinessStatuses)
        return normalized
    }

    private func missingCoverageTags(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> [String] {
        let covered = Set(coveredCoverageTags(report))
        return unique(policy.requiredCoverageTags).filter { !covered.contains($0) }
    }

    private func coveredCoverageTags(
        _ report: XcircuiteGeneratedLayoutSignoffCorpusReport
    ) -> [String] {
        unique(report.caseResults.flatMap(\.coverageTags)).sorted()
    }

    private func missingStageFamilies(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        missingStageFamilies(observedStageFamilies: observedStageFamilies(report), policy: policy)
    }

    private func missingStageFamilies(
        observedStageFamilies: [XcircuiteGeneratedLayoutSignoffStageFamily],
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        let observed = Set(observedStageFamilies)
        return sortedStageFamilies(unique(policy.requiredStageFamilies).filter { !observed.contains($0) })
    }

    private func observedStageFamilies(
        _ report: XcircuiteGeneratedLayoutSignoffCorpusReport
    ) -> [XcircuiteGeneratedLayoutSignoffStageFamily] {
        sortedStageFamilies(unique(report.caseResults.flatMap(\.stageResults).map(\.family)))
    }

    private func oracleReadinessAccepted(
        caseResult: XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> Bool {
        let acceptedStatuses = Set(policy.acceptedOracleReadinessStatuses)
        let readinessByFamily = Dictionary(
            caseResult.oracleReadiness.map { ($0.domain, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for family in policy.requiredOracleReadinessFamilies {
            guard let readiness = readinessByFamily[family],
                  acceptedStatuses.contains(readiness.status) else {
                return false
            }
        }
        return true
    }

    private func readyOracleEvidenceStats(
        report: XcircuiteGeneratedLayoutSignoffCorpusReport,
        policy: XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy
    ) -> ReadyOracleEvidenceStats {
        let requiredFamilies = Set(policy.requiredOracleReadinessFamilies)
        var refCount = 0
        var readinessWithoutEvidenceCount = 0
        var refWithoutHashCount = 0
        var refWithoutByteCount = 0
        for readiness in report.caseResults.flatMap(\.oracleReadiness)
            where readiness.status == .ready && requiredFamilies.contains(readiness.domain) {
            if readiness.evidenceRefs.isEmpty {
                readinessWithoutEvidenceCount += 1
            }
            refCount += readiness.evidenceRefs.count
            refWithoutHashCount += readiness.evidenceRefs.filter { ($0.sha256 ?? "").isEmpty }.count
            refWithoutByteCount += readiness.evidenceRefs.filter { ($0.byteCount ?? 0) <= 0 }.count
        }
        return ReadyOracleEvidenceStats(
            refCount: refCount,
            readinessWithoutEvidenceCount: readinessWithoutEvidenceCount,
            refWithoutHashCount: refWithoutHashCount,
            refWithoutByteCount: refWithoutByteCount
        )
    }

    private func uniqueArtifacts(
        _ report: XcircuiteGeneratedLayoutSignoffCorpusReport
    ) -> [ArtifactReference] {
        uniqueArtifactRefs(report.caseResults.flatMap { caseResult in
            caseResult.sourceArtifactRefs + caseResult.signoffArtifactRefs
        })
    }

    private func sourceArtifactRefCount(
        _ report: XcircuiteGeneratedLayoutSignoffCorpusReport
    ) -> Int {
        report.caseResults.flatMap(\.sourceArtifactRefs).count
    }

    private func signoffArtifactRefCount(
        _ report: XcircuiteGeneratedLayoutSignoffCorpusReport
    ) -> Int {
        report.caseResults.flatMap(\.signoffArtifactRefs).count
    }

    private func uniqueArtifactRefs(
        _ artifactRefs: [ArtifactReference]
    ) -> [ArtifactReference] {
        var seen: Set<String> = []
        var artifacts: [ArtifactReference] = []
        for artifact in artifactRefs {
            guard isRetainedSignoffArtifact(artifact) else {
                continue
            }
            let key = [
                artifact.locator.role.rawValue,
                artifact.artifactID,
                artifact.path,
            ].joined(separator: "|")
            if !seen.contains(key) {
                seen.insert(key)
                artifacts.append(artifact)
            }
        }
        return artifacts.sorted(by: artifactSortOrder)
    }

    private func isRetainedSignoffArtifact(
        _ artifact: ArtifactReference
    ) -> Bool {
        let artifactID = artifact.artifactID
        return [
            "drc-layout",
            "layout-gds",
            "layout-oasis",
            "drc-summary",
            "lvs-summary",
            "pex-summary",
            "post-layout-comparison",
            "simulation-summary",
        ].contains(artifactID)
    }

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuiteWorkspaceLayout.directoryName)/qualification/generated-layout-signoff/\(suiteID)/\(fileName)"
    }

    private func failure(
        code: String,
        message: String,
        caseID: String? = nil,
        stageID: String? = nil,
        artifactID: String? = nil,
        path: String? = nil,
        coverageTag: String? = nil,
        family: XcircuiteGeneratedLayoutSignoffStageFamily? = nil
    ) -> XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure {
        XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure(
            code: code,
            message: message,
            caseID: caseID,
            stageID: stageID,
            artifactID: artifactID,
            path: path,
            coverageTag: coverageTag,
            family: family
        )
    }

    private func artifactSortOrder(
        _ left: ArtifactReference,
        _ right: ArtifactReference
    ) -> Bool {
        if left.artifactID != right.artifactID {
            return left.artifactID < right.artifactID
        }
        if left.locator.role != right.locator.role {
            return left.locator.role.rawValue < right.locator.role.rawValue
        }
        return left.path < right.path
    }

    private func failureSortOrder(
        _ left: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure,
        _ right: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Failure
    ) -> Bool {
        if left.code != right.code {
            return left.code < right.code
        }
        if left.caseID != right.caseID {
            return (left.caseID ?? "") < (right.caseID ?? "")
        }
        if left.stageID != right.stageID {
            return (left.stageID ?? "") < (right.stageID ?? "")
        }
        if left.artifactID != right.artifactID {
            return (left.artifactID ?? "") < (right.artifactID ?? "")
        }
        return (left.path ?? "") < (right.path ?? "")
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

    private struct ReadyOracleEvidenceStats: Sendable, Hashable {
        var refCount: Int
        var readinessWithoutEvidenceCount: Int
        var refWithoutHashCount: Int
        var refWithoutByteCount: Int
    }
}
