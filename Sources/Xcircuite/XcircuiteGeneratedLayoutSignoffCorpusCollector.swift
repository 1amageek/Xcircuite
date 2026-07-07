import DesignFlowKernel
import Foundation
import XcircuitePackage

public struct XcircuiteGeneratedLayoutSignoffCorpusCollector: Sendable {
    private let ledgerLoader: any FlowRunLedgerLoading
    private let reviewBundler: any FlowRunReviewBundling
    private let packageStore: XcircuitePackageStore
    private let identifierValidator: XcircuiteIdentifierValidator

    public init(
        ledgerLoader: any FlowRunLedgerLoading = FlowRunLedgerLoader(),
        reviewBundler: any FlowRunReviewBundling = DefaultFlowRunReviewBundler(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore(),
        identifierValidator: XcircuiteIdentifierValidator = XcircuiteIdentifierValidator()
    ) {
        self.ledgerLoader = ledgerLoader
        self.reviewBundler = reviewBundler
        self.packageStore = packageStore
        self.identifierValidator = identifierValidator
    }

    public func collect(
        request: XcircuiteGeneratedLayoutSignoffCorpusRequest,
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusReport {
        try validate(request)
        let caseResults = try request.cases.map { corpusCase in
            try collectCase(corpusCase, projectRoot: projectRoot)
        }
        return makeReport(
            request: request,
            caseResults: caseResults,
            suiteSpecArtifact: nil,
            reportArtifact: nil
        )
    }

    public func collectAndPersist(
        request: XcircuiteGeneratedLayoutSignoffCorpusRequest,
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusReport {
        try validate(request)
        let suiteDirectory = try suiteDirectoryURL(suiteID: request.suiteID, projectRoot: projectRoot)
        try packageStore.ensureDirectory(at: suiteDirectory)

        let suiteSpecPath = suiteProjectRelativePath(suiteID: request.suiteID, fileName: "corpus-suite.json")
        let suiteSpecURL = try packageStore.url(forProjectRelativePath: suiteSpecPath, inProjectAt: projectRoot)
        try packageStore.writeJSON(request, to: suiteSpecURL, forProjectAt: projectRoot)
        let suiteSpecArtifact = try packageStore.fileReference(
            forProjectRelativePath: suiteSpecPath,
            artifactID: "generated-layout-signoff-corpus-suite",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(suiteSpecArtifact, forProjectAt: projectRoot)

        let caseResults = try request.cases.map { corpusCase in
            try collectCase(corpusCase, projectRoot: projectRoot)
        }
        let reportWithoutSelfRef = makeReport(
            request: request,
            caseResults: caseResults,
            suiteSpecArtifact: suiteSpecArtifact,
            reportArtifact: nil
        )
        let reportPath = suiteProjectRelativePath(suiteID: request.suiteID, fileName: "corpus-report.json")
        let reportURL = try packageStore.url(forProjectRelativePath: reportPath, inProjectAt: projectRoot)
        try packageStore.writeJSON(reportWithoutSelfRef, to: reportURL, forProjectAt: projectRoot)
        let reportArtifact = try packageStore.fileReference(
            forProjectRelativePath: reportPath,
            artifactID: "generated-layout-signoff-corpus-report",
            kind: .report,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(reportArtifact, forProjectAt: projectRoot)

        var report = reportWithoutSelfRef
        report.reportArtifact = reportArtifact
        return report
    }

    private func validate(_ request: XcircuiteGeneratedLayoutSignoffCorpusRequest) throws {
        guard request.schemaVersion == 1 else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.unsupportedSchemaVersion(request.schemaVersion)
        }
        try identifierValidator.validate(request.suiteID, kind: .artifactID)
        guard !request.cases.isEmpty else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.emptyCorpus
        }
        for coverageTag in request.requiredCoverageTags {
            try identifierValidator.validate(coverageTag, kind: .artifactID)
        }
        var caseIDs: Set<String> = []
        for corpusCase in request.cases {
            try identifierValidator.validate(corpusCase.caseID, kind: .artifactID)
            guard !caseIDs.contains(corpusCase.caseID) else {
                throw XcircuiteGeneratedLayoutSignoffCorpusError.duplicateCaseID(corpusCase.caseID)
            }
            caseIDs.insert(corpusCase.caseID)
            try identifierValidator.validate(corpusCase.runID, kind: .runID)
            guard !corpusCase.expectedStages.isEmpty else {
                throw XcircuiteGeneratedLayoutSignoffCorpusError.emptyExpectedStages(
                    caseID: corpusCase.caseID
                )
            }
            guard !corpusCase.coverageTags.isEmpty else {
                throw XcircuiteGeneratedLayoutSignoffCorpusError.emptyCoverageTags(
                    caseID: corpusCase.caseID
                )
            }
            for coverageTag in corpusCase.coverageTags {
                try identifierValidator.validate(coverageTag, kind: .artifactID)
            }
            var expectedStageIDs: Set<String> = []
            for expectedStage in corpusCase.expectedStages {
                try identifierValidator.validate(expectedStage.stageID, kind: .stageID)
                guard !expectedStageIDs.contains(expectedStage.stageID) else {
                    throw XcircuiteGeneratedLayoutSignoffCorpusError.duplicateExpectedStageID(
                        caseID: corpusCase.caseID,
                        stageID: expectedStage.stageID
                    )
                }
                expectedStageIDs.insert(expectedStage.stageID)
            }
            var oracleReadinessDomains: Set<XcircuiteGeneratedLayoutSignoffStageFamily> = []
            for readiness in corpusCase.oracleReadiness {
                guard !oracleReadinessDomains.contains(readiness.domain) else {
                    throw XcircuiteGeneratedLayoutSignoffCorpusError.duplicateOracleReadinessDomain(
                        caseID: corpusCase.caseID,
                        domain: readiness.domain
                    )
                }
                oracleReadinessDomains.insert(readiness.domain)
                try validateOracleReadiness(readiness, caseID: corpusCase.caseID)
            }
        }
    }

    private func validateOracleReadiness(
        _ readiness: XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness,
        caseID: String
    ) throws {
        do {
            try identifierValidator.validate(readiness.backendID, kind: .toolID)
        } catch {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleReadiness(
                caseID: caseID,
                domain: readiness.domain,
                field: "backendID",
                value: readiness.backendID,
                reason: error.localizedDescription
            )
        }
        let trimmedReason = readiness.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleReadiness(
                caseID: caseID,
                domain: readiness.domain,
                field: "reason",
                value: readiness.reason,
                reason: "reason must not be empty"
            )
        }

        var evidenceKeys: Set<String> = []
        for evidenceRef in readiness.evidenceRefs {
            try validateOracleEvidenceReference(
                evidenceRef,
                caseID: caseID,
                domain: readiness.domain
            )
            let evidenceKey = "\(evidenceRef.role)\n\(evidenceRef.path)"
            guard !evidenceKeys.contains(evidenceKey) else {
                throw XcircuiteGeneratedLayoutSignoffCorpusError.duplicateOracleEvidenceReference(
                    caseID: caseID,
                    domain: readiness.domain,
                    role: evidenceRef.role,
                    path: evidenceRef.path
                )
            }
            evidenceKeys.insert(evidenceKey)
        }
    }

    private func validateOracleEvidenceReference(
        _ evidenceRef: XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference,
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily
    ) throws {
        try validateOracleEvidenceIdentifier(
            evidenceRef.role,
            field: "role",
            path: evidenceRef.path,
            caseID: caseID,
            domain: domain
        )
        try validateOracleEvidencePath(evidenceRef.path, caseID: caseID, domain: domain)
        try validateOracleEvidenceIdentifier(
            evidenceRef.kind,
            field: "kind",
            path: evidenceRef.path,
            caseID: caseID,
            domain: domain
        )
        try validateOracleEvidenceIdentifier(
            evidenceRef.format,
            field: "format",
            path: evidenceRef.path,
            caseID: caseID,
            domain: domain
        )
        if let sha256 = evidenceRef.sha256 {
            try validateOracleEvidenceSHA256(
                sha256,
                path: evidenceRef.path,
                caseID: caseID,
                domain: domain
            )
        }
        if let byteCount = evidenceRef.byteCount, byteCount <= 0 {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: evidenceRef.path,
                field: "byteCount",
                value: String(byteCount),
                reason: "byteCount must be positive when present"
            )
        }
    }

    private func validateOracleEvidenceIdentifier(
        _ value: String,
        field: String,
        path: String,
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily
    ) throws {
        do {
            try identifierValidator.validate(value, kind: .artifactID)
        } catch {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: path,
                field: field,
                value: value,
                reason: error.localizedDescription
            )
        }
    }

    private func validateOracleEvidencePath(
        _ path: String,
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily
    ) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, trimmedPath == path else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: path,
                field: "path",
                value: path,
                reason: "path must not be empty or padded with whitespace"
            )
        }
        guard !path.hasPrefix("~"),
              !path.contains("\0"),
              path.rangeOfCharacter(from: .newlines) == nil else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: path,
                field: "path",
                value: path,
                reason: "path must not contain home-directory expansion, null bytes, or newlines"
            )
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("."), !components.contains("..") else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: path,
                field: "path",
                value: path,
                reason: "path must not contain '.' or '..' components"
            )
        }
    }

    private func validateOracleEvidenceSHA256(
        _ sha256: String,
        path: String,
        caseID: String,
        domain: XcircuiteGeneratedLayoutSignoffStageFamily
    ) throws {
        let trimmedSHA256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSHA256 == sha256,
              sha256.count == 64,
              sha256.allSatisfy({ character in
                  character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
              }) else {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.invalidOracleEvidenceReference(
                caseID: caseID,
                domain: domain,
                path: path,
                field: "sha256",
                value: sha256,
                reason: "sha256 must be a 64-character hex digest when present"
            )
        }
    }

    private func collectCase(
        _ corpusCase: XcircuiteGeneratedLayoutSignoffCorpusRequest.CaseRequest,
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult {
        let ledger = try ledgerLoader.loadRunLedger(runID: corpusCase.runID, projectRoot: projectRoot)
        let bundle = try reviewBundler.makeReviewBundle(runID: corpusCase.runID, projectRoot: projectRoot)
        let expectedStagesByID = Dictionary(
            corpusCase.expectedStages.map { ($0.stageID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for expectedStage in corpusCase.expectedStages where !ledger.stages.contains(where: { $0.stageID == expectedStage.stageID }) {
            throw XcircuiteGeneratedLayoutSignoffCorpusError.missingExpectedStage(
                caseID: corpusCase.caseID,
                stageID: expectedStage.stageID
            )
        }

        let stageResults = try ledger.stages.map { stage in
            try makeStageResult(
                stage,
                expectedStage: expectedStagesByID[stage.stageID],
                bundle: bundle
            )
        }
        let runStatusMatches = ledger.runManifest.status.flowStatus == corpusCase.expectedRunStatus
        let stageStatusMatches = stageResults.allSatisfy(\.statusMatches)
        let diagnostics = stageResults.flatMap(\.diagnostics)
        let sourceArtifacts = try generatedLayoutSourceArtifacts(from: bundle)
        let signoffArtifacts = try generatedLayoutSignoffArtifacts(from: bundle)
        let status: XcircuiteGeneratedLayoutSignoffCorpusReport.Status =
            runStatusMatches && stageStatusMatches ? .passed : .failed

        return XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult(
            caseID: corpusCase.caseID,
            runID: corpusCase.runID,
            status: status,
            runStatus: ledger.runManifest.status.flowStatus,
            expectedRunStatus: corpusCase.expectedRunStatus,
            runStatusMatches: runStatusMatches,
            coverageTags: corpusCase.coverageTags.sorted(),
            oracleReadiness: corpusCase.oracleReadiness,
            stageResults: stageResults,
            sourceArtifactRefs: sourceArtifacts,
            signoffArtifactRefs: signoffArtifacts,
            diagnostics: diagnostics
        )
    }

    private func makeStageResult(
        _ stage: FlowStageResult,
        expectedStage: XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage?,
        bundle: FlowRunReviewBundle
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusReport.StageResult {
        let family = expectedStage?.family ?? inferredFamily(for: stage)
        let artifactRefs = try bundle.artifacts
            .filter { $0.stageID == stage.stageID }
            .map(artifactReference)
            .sorted(by: artifactReferenceSortOrder)
        let diagnostics = stage.diagnostics.map(reportDiagnostic)
        return XcircuiteGeneratedLayoutSignoffCorpusReport.StageResult(
            stageID: stage.stageID,
            family: family,
            status: stage.status,
            expectedStatus: expectedStage?.expectedStatus,
            statusMatches: expectedStage.map { $0.expectedStatus == stage.status } ?? true,
            gateResults: stage.gates.map { gate in
                XcircuiteGeneratedLayoutSignoffCorpusReport.GateResult(
                    gateID: gate.gateID,
                    status: gate.status,
                    diagnostics: gate.diagnostics.map(reportDiagnostic)
                )
            },
            artifactRefs: artifactRefs,
            diagnostics: diagnostics
        )
    }

    private func makeReport(
        request: XcircuiteGeneratedLayoutSignoffCorpusRequest,
        caseResults: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult],
        suiteSpecArtifact: XcircuiteFileReference?,
        reportArtifact: XcircuiteFileReference?
    ) -> XcircuiteGeneratedLayoutSignoffCorpusReport {
        let coveredTags = Array(Set(caseResults.flatMap(\.coverageTags))).sorted()
        let missingTags = request.requiredCoverageTags
            .filter { !coveredTags.contains($0) }
            .sorted()
        let passedCaseCount = caseResults.filter { $0.status == .passed }.count
        let stageFamilyCounts = makeStageFamilyCounts(caseResults)
        let expectedMismatchCount = caseResults.reduce(0) { partial, result in
            partial
                + (result.runStatusMatches ? 0 : 1)
                + result.stageResults.filter { !$0.statusMatches }.count
        }
        let oracleReadinessDeclaredCaseCount = caseResults.filter { !$0.oracleReadiness.isEmpty }.count
        let standardLayoutArtifactCount = caseResults.flatMap(\.sourceArtifactRefs).count
        let signoffArtifactCount = caseResults.flatMap(\.signoffArtifactRefs).count
        let status: XcircuiteGeneratedLayoutSignoffCorpusReport.Status =
            missingTags.isEmpty && expectedMismatchCount == 0 ? .passed : .failed

        return XcircuiteGeneratedLayoutSignoffCorpusReport(
            suiteID: request.suiteID,
            status: status,
            summary: XcircuiteGeneratedLayoutSignoffCorpusReport.Summary(
                caseCount: caseResults.count,
                passedCaseCount: passedCaseCount,
                failedCaseCount: caseResults.count - passedCaseCount,
                requiredCoverageTags: request.requiredCoverageTags.sorted(),
                coveredCoverageTags: coveredTags,
                missingCoverageTags: missingTags,
                stageFamilyCounts: stageFamilyCounts,
                expectedVerdictMismatchCount: expectedMismatchCount,
                oracleReadinessDeclaredCaseCount: oracleReadinessDeclaredCaseCount,
                standardLayoutArtifactCount: standardLayoutArtifactCount,
                signoffArtifactCount: signoffArtifactCount
            ),
            caseResults: caseResults,
            suiteSpecArtifact: suiteSpecArtifact,
            reportArtifact: reportArtifact
        )
    }

    private func generatedLayoutSourceArtifacts(
        from bundle: FlowRunReviewBundle
    ) throws -> [XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference] {
        try bundle.artifacts
            .filter { artifact in
                artifact.role == "stage-result"
                    || artifact.artifactID == "layout-command-result"
                    || artifact.artifactID == "layout-command-manifest"
                    || artifact.artifactID == "layout-command-effective-request"
                    || artifact.artifactID == "drc-layout"
                    || artifact.artifactID == "layout-gds"
                    || artifact.artifactID == "layout-oasis"
            }
            .map(artifactReference)
            .sorted(by: artifactReferenceSortOrder)
    }

    private func generatedLayoutSignoffArtifacts(
        from bundle: FlowRunReviewBundle
    ) throws -> [XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference] {
        try bundle.artifacts
            .filter { artifact in
                artifact.role == "stage-summary"
                    || artifact.artifactID == "drc-summary"
                    || artifact.artifactID == "lvs-summary"
                    || artifact.artifactID == "pex-summary"
                    || artifact.artifactID == "post-layout-comparison"
                    || artifact.artifactID == "simulation-summary"
            }
            .map(artifactReference)
            .sorted(by: artifactReferenceSortOrder)
    }

    private func inferredFamily(for stage: FlowStageResult) -> XcircuiteGeneratedLayoutSignoffStageFamily {
        let gateIDs = Set(stage.gates.map(\.gateID))
        if gateIDs.contains("layout-command") {
            return .layout
        }
        if gateIDs.contains("drc") {
            return .drc
        }
        if gateIDs.contains("lvs") {
            return .lvs
        }
        if gateIDs.contains("pex") {
            return .pex
        }
        if gateIDs.contains("simulation") {
            return .simulation
        }
        if gateIDs.contains("post-layout-comparison") || gateIDs.contains("comparison") {
            return .postLayout
        }
        return .other
    }

    private func makeStageFamilyCounts(
        _ caseResults: [XcircuiteGeneratedLayoutSignoffCorpusReport.CaseResult]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for family in caseResults.flatMap(\.stageResults).map(\.family) {
            counts[family.rawValue, default: 0] += 1
        }
        return counts
    }

    private func artifactReference(
        _ artifact: FlowRunReviewArtifact
    ) throws -> XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference {
        try XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference(
            role: artifact.role,
            artifactID: artifact.artifactID,
            stageID: artifact.stageID,
            path: artifact.path,
            kind: artifact.kind.rawValue,
            format: artifact.format.rawValue,
            sha256: artifact.sha256,
            byteCount: artifact.byteCount,
            integrityStatus: artifact.integrity?.status.rawValue,
            integrityMessage: artifact.integrity?.message
        )
    }

    private func reportDiagnostic(_ diagnostic: FlowDiagnostic) -> XcircuiteGeneratedLayoutSignoffCorpusReport.Diagnostic {
        XcircuiteGeneratedLayoutSignoffCorpusReport.Diagnostic(
            severity: diagnostic.severity,
            code: diagnostic.code,
            message: diagnostic.message
        )
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

    private func artifactReferenceSortOrder(
        _ left: XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference,
        _ right: XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference
    ) -> Bool {
        if left.stageID != right.stageID {
            return (left.stageID ?? "") < (right.stageID ?? "")
        }
        if left.role != right.role {
            return left.role < right.role
        }
        if left.artifactID != right.artifactID {
            return (left.artifactID ?? "") < (right.artifactID ?? "")
        }
        return left.path < right.path
    }
}

private extension XcircuiteRunStatus {
    var flowStatus: FlowRunStatus {
        switch self {
        case .created:
            .created
        case .running:
            .running
        case .succeeded:
            .succeeded
        case .failed:
            .failed
        case .blocked:
            .blocked
        case .cancelled:
            .cancelled
        case .partial:
            .partial
        }
    }
}
