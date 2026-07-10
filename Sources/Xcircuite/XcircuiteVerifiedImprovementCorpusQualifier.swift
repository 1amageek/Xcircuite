import Foundation
import XcircuitePackage

public struct XcircuiteVerifiedImprovementCorpusQualifier: Sendable {
    private let packageStore: XcircuitePackageStore
    private let identifierValidator: XcircuiteIdentifierValidator
    private let fileReferenceVerifier: XcircuiteFileReferenceVerifier

    public init(
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator(),
        fileReferenceVerifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()
    ) {
        self.packageStore = packageStore
        self.identifierValidator = identifierValidator
        self.fileReferenceVerifier = fileReferenceVerifier
    }

    public func qualify(
        suiteSpec: XcircuiteVerifiedImprovementCorpusSuiteSpec,
        projectRoot: URL
    ) throws -> XcircuiteVerifiedImprovementCorpusReport {
        try validate(suiteSpec)
        let caseResults = suiteSpec.cases.map { caseSpec in
            qualifyCase(caseSpec, projectRoot: projectRoot)
        }
        return makeReport(
            suiteSpec: suiteSpec,
            caseResults: caseResults,
            suiteSpecArtifact: nil,
            reportArtifact: nil
        )
    }

    public func qualifyAndPersist(
        suiteSpec: XcircuiteVerifiedImprovementCorpusSuiteSpec,
        projectRoot: URL
    ) throws -> XcircuiteVerifiedImprovementCorpusReport {
        try validate(suiteSpec)
        let suiteDirectory = try suiteDirectoryURL(suiteID: suiteSpec.suiteID, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: suiteDirectory)

        let suiteSpecPath = suiteProjectRelativePath(suiteID: suiteSpec.suiteID, fileName: "corpus-suite.json")
        let suiteSpecURL = try packageStore.url(forProjectRelativePath: suiteSpecPath, inProjectAt: projectRoot)
        try packageStore.writeJSON(suiteSpec, to: suiteSpecURL, forProjectAt: projectRoot)
        let suiteSpecArtifact = try packageStore.fileReference(
            forProjectRelativePath: suiteSpecPath,
            artifactID: "verified-improvement-corpus-suite",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(suiteSpecArtifact, forProjectAt: projectRoot)

        let caseResults = suiteSpec.cases.map { caseSpec in
            qualifyCase(caseSpec, projectRoot: projectRoot)
        }
        let reportWithoutSelfRef = makeReport(
            suiteSpec: suiteSpec,
            caseResults: caseResults,
            suiteSpecArtifact: suiteSpecArtifact,
            reportArtifact: nil
        )

        let reportPath = suiteProjectRelativePath(suiteID: suiteSpec.suiteID, fileName: "corpus-report.json")
        let reportURL = try packageStore.url(forProjectRelativePath: reportPath, inProjectAt: projectRoot)
        try packageStore.writeJSON(reportWithoutSelfRef, to: reportURL, forProjectAt: projectRoot)
        let reportArtifact = try packageStore.fileReference(
            forProjectRelativePath: reportPath,
            artifactID: "verified-improvement-corpus-report",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(reportArtifact, forProjectAt: projectRoot)

        var report = reportWithoutSelfRef
        report.reportArtifact = reportArtifact
        return report
    }

    private func validate(_ suiteSpec: XcircuiteVerifiedImprovementCorpusSuiteSpec) throws {
        guard suiteSpec.schemaVersion == 1 else {
            throw XcircuiteVerifiedImprovementCorpusError.unsupportedSchemaVersion(suiteSpec.schemaVersion)
        }
        try identifierValidator.validate(suiteSpec.suiteID, kind: .artifactID)
        guard !suiteSpec.cases.isEmpty else {
            throw XcircuiteVerifiedImprovementCorpusError.emptyCorpus
        }

        var seenCaseIDs: Set<String> = []
        for family in suiteSpec.requiredFamilies {
            try identifierValidator.validate(family.rawValue, kind: .artifactID)
        }
        for caseSpec in suiteSpec.cases {
            try identifierValidator.validate(caseSpec.caseID, kind: .artifactID)
            guard !seenCaseIDs.contains(caseSpec.caseID) else {
                throw XcircuiteVerifiedImprovementCorpusError.duplicateCaseID(caseSpec.caseID)
            }
            seenCaseIDs.insert(caseSpec.caseID)
            try identifierValidator.validate(caseSpec.runID, kind: .runID)
            try identifierValidator.validate(caseSpec.family.rawValue, kind: .artifactID)
            for diagnosticCode in caseSpec.requiredDiagnosticCodes {
                try identifierValidator.validate(diagnosticCode, kind: .artifactID)
            }
            for gateID in caseSpec.requiredFailedGateIDs {
                try identifierValidator.validate(gateID, kind: .stageID)
            }
            for artifactID in caseSpec.requiredArtifactIDs {
                try identifierValidator.validate(artifactID, kind: .artifactID)
            }
        }
    }

    private func qualifyCase(
        _ caseSpec: XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec,
        projectRoot: URL
    ) -> XcircuiteVerifiedImprovementCorpusReport.CaseResult {
        var diagnostics: [XcircuiteVerifiedImprovementCorpusReport.Diagnostic] = []
        var artifactRefs: [XcircuiteFileReference] = []
        var producedArtifactIDs: [String] = []
        var diagnosticCodes: [String] = []
        var failedGateIDs: [String] = []
        var numericLoop: XcircuiteNumericRepairLoopResult?
        var improvementLoop: XcircuiteImprovementLoopResult?

        let runManifest = loadRunManifest(runID: caseSpec.runID, projectRoot: projectRoot, diagnostics: &diagnostics)

        let numericLoopResolution = resolveLoopArtifact(
            explicitPath: caseSpec.numericRepairLoopPath,
            artifactID: XcircuitePlanningArtifactStore.numericRepairLoopArtifactID,
            field: "numericRepairLoopPath",
            runManifest: runManifest,
            runID: caseSpec.runID,
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        )
        if let numericLoopResolution {
            artifactRefs.append(numericLoopResolution.reference)
            numericLoop = readJSON(
                XcircuiteNumericRepairLoopResult.self,
                from: numericLoopResolution.url,
                description: "numeric repair loop",
                diagnostics: &diagnostics
            )
        }

        let improvementLoopResolution = resolveLoopArtifact(
            explicitPath: caseSpec.improvementLoopPath,
            artifactID: XcircuitePlanningArtifactStore.improvementLoopArtifactID,
            field: "improvementLoopPath",
            runManifest: runManifest,
            runID: caseSpec.runID,
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        )
        if let improvementLoopResolution {
            artifactRefs.append(improvementLoopResolution.reference)
            improvementLoop = readJSON(
                XcircuiteImprovementLoopResult.self,
                from: improvementLoopResolution.url,
                description: "improvement loop",
                diagnostics: &diagnostics
            )
        }

        if let numericLoop {
            let numericDiagnostics = collectNumericDiagnostics(numericLoop)
            diagnostics.append(contentsOf: numericDiagnostics.reportDiagnostics)
            diagnosticCodes.append(contentsOf: numericDiagnostics.codes)
            artifactRefs.append(contentsOf: collectNumericArtifactRefs(numericLoop))

            for planVerificationArtifact in collectPlanVerificationRefs(numericLoop) {
                let verification = readPlanVerification(
                    planVerificationArtifact,
                    runID: caseSpec.runID,
                    projectRoot: projectRoot,
                    diagnostics: &diagnostics
                )
                if let verification {
                    let verificationDiagnostics = collectVerificationDiagnostics(verification)
                    diagnostics.append(contentsOf: verificationDiagnostics.reportDiagnostics)
                    diagnosticCodes.append(contentsOf: verificationDiagnostics.codes)
                    failedGateIDs.append(contentsOf: collectFailedGateIDs(verification))
                    artifactRefs.append(contentsOf: verification.artifactRefs)
                    artifactRefs.append(verification.candidatePlanRef)
                }
            }
        }

        if let improvementLoop {
            producedArtifactIDs.append(contentsOf: improvementLoop.iterations.flatMap(\.producedArtifactIDs))
            failedGateIDs.append(contentsOf: improvementLoop.iterations.flatMap(\.failedGateIDs))
            diagnostics.append(contentsOf: improvementLoop.diagnostics.map { diagnostic in
                XcircuiteVerifiedImprovementCorpusReport.Diagnostic(
                    severity: "info",
                    code: diagnostic,
                    message: diagnostic
                )
            })
            diagnosticCodes.append(contentsOf: improvementLoop.diagnostics)
        }

        artifactRefs = stableUniqueArtifactRefs(artifactRefs)
        diagnosticCodes = stableUnique(diagnosticCodes).sorted()
        failedGateIDs = stableUnique(failedGateIDs).sorted()
        let observedStatus = improvementLoop?.status ?? numericLoop?.status ?? "missing"
        let accepted = acceptedValue(numericLoop: numericLoop, improvementLoop: improvementLoop)
        let statusMatches = observedStatus == caseSpec.expectedStatus
        let acceptedMatches = caseSpec.expectedAccepted.map { $0 == accepted } ?? true
        let observedArtifactIDs = stableUnique(
            artifactRefs.compactMap(\.artifactID) + producedArtifactIDs
        )
        let missingArtifactIDs = caseSpec.requiredArtifactIDs
            .filter { !observedArtifactIDs.contains($0) }
            .sorted()
        let missingDiagnosticCodes = caseSpec.requiredDiagnosticCodes
            .filter { !diagnosticCodes.contains($0) }
            .sorted()
        let missingFailedGateIDs = caseSpec.requiredFailedGateIDs
            .filter { !failedGateIDs.contains($0) }
            .sorted()
        let hasQualificationErrors = diagnostics.contains(where: isQualificationFailureDiagnostic)
        let casePassed = statusMatches
            && acceptedMatches
            && missingArtifactIDs.isEmpty
            && missingDiagnosticCodes.isEmpty
            && missingFailedGateIDs.isEmpty
            && !hasQualificationErrors

        return XcircuiteVerifiedImprovementCorpusReport.CaseResult(
            caseID: caseSpec.caseID,
            runID: caseSpec.runID,
            family: caseSpec.family,
            status: casePassed ? .passed : .failed,
            observedStatus: observedStatus,
            expectedStatus: caseSpec.expectedStatus,
            statusMatches: statusMatches,
            accepted: accepted,
            expectedAccepted: caseSpec.expectedAccepted,
            acceptedMatches: acceptedMatches,
            diagnosticCodes: diagnosticCodes,
            requiredDiagnosticCodes: caseSpec.requiredDiagnosticCodes.sorted(),
            missingDiagnosticCodes: missingDiagnosticCodes,
            failedGateIDs: failedGateIDs,
            requiredFailedGateIDs: caseSpec.requiredFailedGateIDs.sorted(),
            missingFailedGateIDs: missingFailedGateIDs,
            artifactRefs: artifactRefs.sorted(by: artifactRefSortOrder),
            missingArtifactIDs: missingArtifactIDs,
            diagnostics: diagnostics.sorted(by: diagnosticSortOrder)
        )
    }

    private func makeReport(
        suiteSpec: XcircuiteVerifiedImprovementCorpusSuiteSpec,
        caseResults: [XcircuiteVerifiedImprovementCorpusReport.CaseResult],
        suiteSpecArtifact: XcircuiteFileReference?,
        reportArtifact: XcircuiteFileReference?
    ) -> XcircuiteVerifiedImprovementCorpusReport {
        let coveredFamilies = Array(Set(caseResults.map(\.family))).sorted { $0.rawValue < $1.rawValue }
        let requiredFamilies = Array(Set(suiteSpec.requiredFamilies)).sorted { $0.rawValue < $1.rawValue }
        let missingFamilies = requiredFamilies
            .filter { !coveredFamilies.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        let passedCaseCount = caseResults.filter { $0.status == .passed }.count
        let acceptedCaseCount = caseResults.filter { $0.accepted == true }.count
        let rejectedCaseCount = caseResults.filter { $0.accepted == false }.count
        let allArtifactRefs = caseResults.flatMap(\.artifactRefs)
        let status: XcircuiteVerifiedImprovementCorpusReport.Status =
            missingFamilies.isEmpty && passedCaseCount == caseResults.count ? .passed : .failed

        return XcircuiteVerifiedImprovementCorpusReport(
            suiteID: suiteSpec.suiteID,
            status: status,
            summary: XcircuiteVerifiedImprovementCorpusReport.Summary(
                caseCount: caseResults.count,
                passedCaseCount: passedCaseCount,
                failedCaseCount: caseResults.count - passedCaseCount,
                acceptedCaseCount: acceptedCaseCount,
                rejectedCaseCount: rejectedCaseCount,
                familyCounts: familyCounts(caseResults),
                requiredFamilies: requiredFamilies,
                coveredFamilies: coveredFamilies,
                missingFamilies: missingFamilies,
                sourceDiagnosticCoverageCount: caseResults.filter { !$0.diagnosticCodes.isEmpty }.count,
                designDiffArtifactCount: allArtifactRefs.filter(isDesignDiffArtifact).count,
                verificationArtifactCount: allArtifactRefs.filter {
                    $0.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID
                }.count,
                improvementArtifactCount: allArtifactRefs.filter {
                    $0.artifactID == XcircuitePlanningArtifactStore.improvementLoopArtifactID
                }.count
            ),
            caseResults: caseResults.sorted { $0.caseID < $1.caseID },
            suiteSpecArtifact: suiteSpecArtifact,
            reportArtifact: reportArtifact
        )
    }

    private func loadRunManifest(
        runID: String,
        projectRoot: URL,
        diagnostics: inout [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]
    ) -> XcircuiteRunManifest? {
        do {
            return try packageStore.loadRunManifest(runID: runID, inProjectAt: projectRoot)
        } catch {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "run-manifest-unavailable",
                    message: "Run manifest for \(runID) could not be loaded: \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    private func resolveLoopArtifact(
        explicitPath: String?,
        artifactID: String,
        field: String,
        runManifest: XcircuiteRunManifest?,
        runID: String,
        projectRoot: URL,
        diagnostics: inout [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]
    ) -> (reference: XcircuiteFileReference, url: URL)? {
        let matches = runManifest?.artifacts.filter { $0.artifactID == artifactID } ?? []
        if let explicitPath {
            guard !matches.isEmpty else {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "artifact-missing",
                        message: "Run \(runID) does not contain required artifact \(artifactID) for \(field) at \(explicitPath)."
                    )
                )
                return nil
            }
            guard matches.count == 1 else {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "artifact-reference-duplicate",
                        message: "Run \(runID) contains \(matches.count) references for artifact \(artifactID); qualification requires one unambiguous artifact."
                    )
                )
                return nil
            }

            let reference = matches[0]
            guard reference.path == explicitPath else {
                diagnostics.append(
                    diagnostic(
                        severity: "error",
                        code: "artifact-reference-mismatch",
                        message: "\(field) for artifact \(artifactID) points to \(explicitPath), but run manifest records \(reference.path)."
                    )
                )
                return nil
            }
            guard let url = verifiedArtifactURL(
                reference,
                expectedArtifactID: artifactID,
                expectedFormat: .json,
                runID: runID,
                field: field,
                projectRoot: projectRoot,
                diagnostics: &diagnostics
            ) else {
                return nil
            }
            return (reference, url)
        }

        guard !matches.isEmpty else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-missing",
                    message: "Run \(runID) does not contain required artifact \(artifactID)."
                )
            )
            return nil
        }
        guard matches.count == 1 else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-reference-duplicate",
                    message: "Run \(runID) contains \(matches.count) references for artifact \(artifactID); qualification requires one unambiguous artifact."
                )
            )
            return nil
        }

        let reference = matches[0]
        guard let url = verifiedArtifactURL(
            reference,
            expectedArtifactID: artifactID,
            expectedFormat: .json,
            runID: runID,
            field: field,
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        ) else {
            return nil
        }
        return (reference, url)
    }

    private func readJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        description: String,
        diagnostics: inout [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]
    ) -> T? {
        do {
            return try packageStore.readJSON(type, from: url)
        } catch {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "\(description.replacingOccurrences(of: " ", with: "-"))-unavailable",
                    message: "\(description) could not be loaded from \(url.lastPathComponent): \(error.localizedDescription)"
                )
            )
            return nil
        }
    }

    private func readPlanVerification(
        _ reference: XcircuiteFileReference,
        runID: String,
        projectRoot: URL,
        diagnostics: inout [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]
    ) -> XcircuitePlanVerification? {
        guard let url = verifiedArtifactURL(
            reference,
            expectedArtifactID: XcircuitePlanningArtifactStore.planVerificationArtifactID,
            expectedFormat: .json,
            runID: runID,
            field: "planVerificationArtifact",
            projectRoot: projectRoot,
            diagnostics: &diagnostics
        ) else {
            return nil
        }
        return readJSON(
            XcircuitePlanVerification.self,
            from: url,
            description: "plan verification",
            diagnostics: &diagnostics
        )
    }

    private func verifiedArtifactURL(
        _ reference: XcircuiteFileReference,
        expectedArtifactID: String,
        expectedFormat: XcircuiteFileFormat,
        runID: String,
        field: String,
        projectRoot: URL,
        diagnostics: inout [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]
    ) -> URL? {
        guard reference.artifactID == expectedArtifactID else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-reference-invalid",
                    message: "\(field) expected artifact \(expectedArtifactID) but found \(reference.artifactID ?? "<missing>")."
                )
            )
            return nil
        }
        guard reference.format == expectedFormat else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-reference-invalid",
                    message: "\(field) for artifact \(expectedArtifactID) must be \(expectedFormat.rawValue), not \(reference.format.rawValue)."
                )
            )
            return nil
        }
        guard reference.producedByRunID == runID else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-reference-invalid",
                    message: "\(field) for artifact \(expectedArtifactID) must be produced by run \(runID), not \(reference.producedByRunID ?? "<missing>")."
                )
            )
            return nil
        }

        let integrity = fileReferenceVerifier.verify(reference, projectRoot: projectRoot)
        guard integrity.status == .verified else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-integrity-failed",
                    message: "\(field) for artifact \(expectedArtifactID) failed integrity verification with \(integrity.status.rawValue): \(integrity.message)"
                )
            )
            return nil
        }
        guard let url = fileReferenceVerifier.resolvedURL(for: reference, projectRoot: projectRoot) else {
            diagnostics.append(
                diagnostic(
                    severity: "error",
                    code: "artifact-path-unavailable",
                    message: "\(field) for artifact \(expectedArtifactID) path \(reference.path) could not be resolved inside the project root."
                )
            )
            return nil
        }
        return url
    }

    private func collectNumericArtifactRefs(
        _ loop: XcircuiteNumericRepairLoopResult
    ) -> [XcircuiteFileReference] {
        loop.iterations.flatMap { iteration in
            [
                iteration.parameterCandidatesArtifact,
                iteration.searchTraceArtifact,
                iteration.selectionTraceArtifact,
                iteration.candidatePlanArtifact,
                iteration.planExecutionArtifact,
                iteration.designDiffArtifact,
                iteration.planVerificationArtifact,
                iteration.rejectedPlansArtifact
            ].compactMap { $0 }
                + iteration.producedArtifacts
                + iteration.archivedArtifactRefs
        }
    }

    private func collectPlanVerificationRefs(
        _ loop: XcircuiteNumericRepairLoopResult
    ) -> [XcircuiteFileReference] {
        stableUniqueArtifactRefs(loop.iterations.compactMap(\.planVerificationArtifact))
    }

    private func collectNumericDiagnostics(
        _ loop: XcircuiteNumericRepairLoopResult
    ) -> (codes: [String], reportDiagnostics: [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]) {
        let diagnostics = loop.diagnostics + loop.iterations.flatMap(\.diagnostics)
        return (
            diagnostics.map(\.code),
            diagnostics.map { diagnostic in
                XcircuiteVerifiedImprovementCorpusReport.Diagnostic(
                    severity: diagnostic.severity,
                    code: diagnostic.code,
                    message: diagnostic.message
                )
            }
        )
    }

    private func collectVerificationDiagnostics(
        _ verification: XcircuitePlanVerification
    ) -> (codes: [String], reportDiagnostics: [XcircuiteVerifiedImprovementCorpusReport.Diagnostic]) {
        let diagnostics = verification.diagnostics
            + verification.gateResults.flatMap(\.diagnostics)
            + verification.correctnessGateResults.flatMap(\.diagnostics)
        return (
            diagnostics.map(\.code),
            diagnostics.map { diagnostic in
                XcircuiteVerifiedImprovementCorpusReport.Diagnostic(
                    severity: diagnostic.severity,
                    code: diagnostic.code,
                    message: diagnostic.message
                )
            }
        )
    }

    private func collectFailedGateIDs(_ verification: XcircuitePlanVerification) -> [String] {
        let gateIDs = verification.gateResults
            .filter { !isPassingStatus($0.status) }
            .map(\.gateID)
        let correctnessGateIDs = verification.correctnessGateResults
            .filter { !isPassingStatus($0.status) }
            .map(\.gateID)
        let diagnosticGateIDs = (
            verification.diagnostics
                + verification.gateResults.flatMap(\.diagnostics)
                + verification.correctnessGateResults.flatMap(\.diagnostics)
        )
        .compactMap(\.gateID)
        return stableUnique(gateIDs + correctnessGateIDs + diagnosticGateIDs)
    }

    private func acceptedValue(
        numericLoop: XcircuiteNumericRepairLoopResult?,
        improvementLoop: XcircuiteImprovementLoopResult?
    ) -> Bool? {
        if let improvementLoop {
            return improvementLoop.acceptedCandidateID != nil
                || improvementLoop.iterations.contains(where: \.accepted)
        }
        return numericLoop?.accepted
    }

    private func familyCounts(
        _ caseResults: [XcircuiteVerifiedImprovementCorpusReport.CaseResult]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for caseResult in caseResults {
            counts[caseResult.family.rawValue, default: 0] += 1
        }
        return counts
    }

    private func suiteDirectoryURL(suiteID: String, projectRoot: URL) throws -> URL {
        try packageStore.url(
            forProjectRelativePath: "\(XcircuitePackage.directoryName)/qualification/verified-improvement/\(suiteID)",
            inProjectAt: projectRoot
        )
    }

    private func suiteProjectRelativePath(suiteID: String, fileName: String) -> String {
        "\(XcircuitePackage.directoryName)/qualification/verified-improvement/\(suiteID)/\(fileName)"
    }

    private func isDesignDiffArtifact(_ reference: XcircuiteFileReference) -> Bool {
        reference.kind == .designDiff
            || reference.artifactID?.contains("design-diff") == true
            || reference.path.contains("design-diff")
    }

    private func isPassingStatus(_ status: String) -> Bool {
        let passingStatuses: Set<String> = [
            "accepted",
            "ok",
            "passed",
            "qualified",
            "success",
            "succeeded"
        ]
        return passingStatuses.contains(status.lowercased())
    }

    private func isQualificationFailureDiagnostic(
        _ diagnostic: XcircuiteVerifiedImprovementCorpusReport.Diagnostic
    ) -> Bool {
        guard diagnostic.severity.lowercased() == "error" else {
            return false
        }
        let failureCodes: Set<String> = [
            "artifact-integrity-failed",
            "artifact-missing",
            "artifact-path-unavailable",
            "artifact-reference-duplicate",
            "artifact-reference-invalid",
            "artifact-reference-mismatch",
            "artifact-reference-unavailable",
            "improvement-loop-unavailable",
            "numeric-repair-loop-unavailable",
            "plan-verification-unavailable",
            "run-manifest-unavailable",
        ]
        return failureCodes.contains(diagnostic.code)
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func stableUniqueArtifactRefs(_ refs: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        var seen: Set<String> = []
        var result: [XcircuiteFileReference] = []
        for ref in refs where !seen.contains(ref.path) {
            seen.insert(ref.path)
            result.append(ref)
        }
        return result
    }

    private func artifactRefSortOrder(_ lhs: XcircuiteFileReference, _ rhs: XcircuiteFileReference) -> Bool {
        let lhsID = lhs.artifactID ?? ""
        let rhsID = rhs.artifactID ?? ""
        if lhsID != rhsID {
            return lhsID < rhsID
        }
        return lhs.path < rhs.path
    }

    private func diagnosticSortOrder(
        _ lhs: XcircuiteVerifiedImprovementCorpusReport.Diagnostic,
        _ rhs: XcircuiteVerifiedImprovementCorpusReport.Diagnostic
    ) -> Bool {
        if lhs.severity != rhs.severity {
            return lhs.severity < rhs.severity
        }
        if lhs.code != rhs.code {
            return lhs.code < rhs.code
        }
        return lhs.message < rhs.message
    }

    private func diagnostic(
        severity: String,
        code: String,
        message: String
    ) -> XcircuiteVerifiedImprovementCorpusReport.Diagnostic {
        XcircuiteVerifiedImprovementCorpusReport.Diagnostic(
            severity: severity,
            code: code,
            message: message
        )
    }
}
