import Foundation
import CircuiteFoundation
import Testing
import Xcircuite

@Suite("Xcircuite retained signoff report")
struct XcircuiteRetainedSignoffReportTests {
    @Test func retainedExternalOracleReadinessRequiresExplicitQualificationAndArtifactEvidence() throws {
        let passingLane = try makeExternalOracleLane()
        #expect(passingLane.provesRetainedExternalOracleReadiness)

        var missingQualification = passingLane
        missingQualification.qualified = nil
        #expect(!missingQualification.provesRetainedExternalOracleReadiness)

        var missingReport = passingLane
        missingReport.report = nil
        #expect(!missingReport.provesRetainedExternalOracleReadiness)

        var failedCaseCount = passingLane
        failedCaseCount.failedCaseCount = 1
        #expect(!failedCaseCount.provesRetainedExternalOracleReadiness)

        var unknownDomain = passingLane
        unknownDomain.domain = "layout"
        #expect(!unknownDomain.provesRetainedExternalOracleReadiness)

        let report = makeRetainedReport(lanes: [passingLane])
        #expect(report.provesRetainedExternalOracleInfrastructureReadiness)
        #expect(report.passingExternalOracleResults == [passingLane])
    }

    @Test func promotionAssessmentBlocksRetainedExternalOracleLaneWithoutExplicitQualification() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let retainedReportURL = root.appending(path: "retained-signoff-report.json")
        try Data("{}".utf8).write(to: retainedReportURL, options: [.atomic])

        var unqualifiedLane = try makeExternalOracleLane()
        unqualifiedLane.qualified = nil
        let retainedReport = makeRetainedReport(lanes: [unqualifiedLane])
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let assessment = try await XcircuiteGeneratedLayoutSignoffPromotionAssessor(
            workspaceStore: workspaceStore
        ).assess(
            request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: [.drc],
                requireGeneratedLayoutOracleReady: false
            ),
            qualification: makeQualifiedGeneratedLayoutQualification(),
            retainedSignoffReport: retainedReport,
            retainedSignoffReportURL: retainedReportURL
        )

        #expect(assessment.status == .blocked)
        #expect(!assessment.summary.externalOracleInfrastructureReady)
        #expect(assessment.summary.missingExternalOracleDomains == [.drc])
        #expect(assessment.blockers.contains {
            $0.code == "retained-external-oracle-domain-missing" && $0.family == .drc
        })
        #expect(assessment.blockers.contains {
            $0.code == "retained-external-oracle-lane-not-ready" && $0.domain == "drc"
        })
    }

    private func makeRetainedReport(
        lanes: [XcircuiteRetainedSignoffReport.ExternalOracleResult]
    ) -> XcircuiteRetainedSignoffReport {
        XcircuiteRetainedSignoffReport(
            schemaVersion: 2,
            kind: "retained-signoff-report",
            suiteID: "retained-signoff-suite",
            status: "passed",
            summary: XcircuiteRetainedSignoffReport.Summary(
                dashboardStatus: "passed",
                externalOracleStatus: "passed",
                externalOracleQualificationStatus: "passed",
                externalOracleLaneCount: lanes.count,
                passedExternalOracleLaneCount: lanes.filter(\.provesRetainedExternalOracleReadiness).count,
                blockedExternalOracleLaneCount: lanes.filter { $0.status == "blocked" }.count,
                failedExternalOracleLaneCount: lanes.filter { !$0.provesRetainedExternalOracleReadiness }.count
            ),
            externalOracleResults: lanes,
            failures: []
        )
    }

    private func makeExternalOracleLane() throws -> XcircuiteRetainedSignoffReport.ExternalOracleResult {
        return XcircuiteRetainedSignoffReport.ExternalOracleResult(
            domain: "drc",
            status: "passed",
            oracleBackendID: "magic",
            qualified: true,
            caseCount: 1,
            passedCaseCount: 1,
            failedCaseCount: 0,
            passRate: 1,
            oracleAgreementRate: 1,
            readinessFailureCount: 0,
            requiredProbeIDs: ["magic-drc"],
            report: ArtifactReference(
                id: try ArtifactID(rawValue: "drc-external-oracle-report"),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath: "ci-artifacts/signoff/drc/drc-corpus-report.json"
                    ),
                    role: try ArtifactRole(validatingRawValue: "drc-external-oracle-report"),
                    kind: .report,
                    format: .json
                ),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "a", count: 64)
                ),
                byteCount: 128
            )
        )
    }

    private func makeQualifiedGeneratedLayoutQualification()
        -> XcircuiteGeneratedLayoutSignoffCorpusQualificationResult
    {
        XcircuiteGeneratedLayoutSignoffCorpusQualificationResult(
            suiteID: "generated-layout-signoff-suite",
            policyID: "test-policy",
            status: .qualified,
            summary: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.Summary(
                reportStatus: .passed,
                caseCount: 1,
                minimumCaseCount: 1,
                passedCaseCount: 1,
                failedCaseCount: 0,
                requiredCoverageTags: [],
                coveredCoverageTags: [],
                missingCoverageTags: [],
                requiredStageFamilies: [.drc],
                observedStageFamilies: [.drc],
                missingStageFamilies: [],
                requiredOracleReadinessFamilies: [.drc],
                acceptedOracleReadinessStatuses: [.ready],
                acceptedOracleReadinessCaseCount: 1,
                readyOracleEvidenceRefCount: 1,
                readyOracleReadinessWithoutEvidenceCount: 0,
                readyOracleEvidenceWithoutHashCount: 0,
                readyOracleEvidenceWithoutByteCount: 0,
                expectedVerdictMismatchCount: 0,
                sourceArtifactCount: 1,
                minimumSourceArtifactCount: 1,
                signoffArtifactCount: 1,
                minimumSignoffArtifactCount: 1,
                artifactWithoutHashCount: 0,
                artifactWithoutByteCount: 0,
                artifactIntegrityFailureCount: 0,
                failureCount: 0
            ),
            failures: []
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteRetainedSignoffReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }
}
