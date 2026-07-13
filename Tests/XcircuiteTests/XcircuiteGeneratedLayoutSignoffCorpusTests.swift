import DesignFlowKernel
import DRCEngine
import Foundation
import LayoutIO
import LayoutTech
import LVSEngine
import PEXEngine
import Testing
import ToolQualification
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

extension XcircuiteFlowRuntimeTests {
    @Test func generatedLayoutCLIRejectsMalformedJSONAsTypedReadError() async throws {
        let root = try makeTemporaryRoot("generated-layout-cli-malformed-json")
        defer { removeTemporaryRoot(root) }

        let malformedRequestURL = root.appending(path: "malformed-request.json")
        try "{".write(to: malformedRequestURL, atomically: true, encoding: .utf8)

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "collect-generated-layout-signoff-corpus",
                "--project-root",
                root.path(percentEncoded: false),
                "--request",
                malformedRequestURL.path(percentEncoded: false),
            ])
            Issue.record("Malformed generated-layout corpus JSON should fail before collection.")
        } catch let error as XcircuiteFlowCLIError {
            guard case .readFailed(let reason) = error else {
                Issue.record("Expected readFailed, got \(error).")
                return
            }
            #expect(reason.contains("--request"))
            #expect(reason.contains(malformedRequestURL.path(percentEncoded: false)))
            #expect(reason.contains("Invalid JSON"))
        }
    }

    @Test func generatedLayoutSignoffCorpusArtifactReferenceRejectsUnbackedVerifiedIntegrity() throws {
        let artifactPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
        #expect(
            throws: XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.missingVerifiedSHA256(
                path: artifactPath
            )
        ) {
            _ = try XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference(
                role: "stage-summary",
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: artifactPath,
                kind: XcircuiteFileKind.report.rawValue,
                format: XcircuiteFileFormat.json.rawValue,
                sha256: nil,
                byteCount: 128,
                integrityStatus: FlowRunReviewArtifactIntegrityStatus.verified.rawValue,
                integrityMessage: nil
            )
        }

        let payload = Data(
            """
            {
              "role": "stage-summary",
              "artifactID": "drc-summary",
              "stageID": "001-drc",
              "path": "\(artifactPath)",
              "kind": "report",
              "format": "json",
              "integrityStatus": "verified"
            }
            """.utf8
        )
        #expect(
            throws: XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.missingVerifiedSHA256(
                path: artifactPath
            )
        ) {
            _ = try JSONDecoder().decode(
                XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactReference.self,
                from: payload
            )
        }
    }

    @Test func generatedLayoutSignoffCorpusCollectsStandardArtifactRefs() async throws {
        let root = try makeTemporaryRoot("generated-layout-signoff-corpus")
        defer { removeTemporaryRoot(root) }
        let gdsRunID = "generated-layout-corpus-gds-run"
        let oasisRunID = "generated-layout-corpus-oasis-run"
        try writeLayoutCommandRequest(root: root)
        try writeStandardLayoutTechnology(root: root)
        _ = try writeNetlist(
            """
            .subckt top
            .ends top
            """,
            name: "circuits/top.spice",
            root: root
        )
        func runGeneratedLayoutSignoffCase(
            runID: String,
            exportedLayoutArtifactID: String,
            exportFormat: LayoutFileFormat,
            artifactFormat: XcircuiteFileFormat,
            lvsFormat: LVSLayoutFormat,
            pexFormat: LayoutFormat
        ) async throws {
            let canonicalArtifactFormat = try ArtifactFormat(
                rawValue: artifactFormat.rawValue.lowercased()
            )
            let spec = XcircuiteFlowRuntimeSpec(
                executors: [
                    .layoutCommand(
                        XcircuiteFlowStageExecutorSpec.LayoutCommand(
                            stageID: "006-layout",
                            requestPath: "layout-command-request.json",
                            drcExport: LayoutCommandDRCExportSpec(
                                technologyID: "flow-test",
                                topCell: "top",
                                rules: [
                                    NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 0.5),
                                ]
                            ),
                            standardLayoutExports: [
                                LayoutCommandStandardLayoutExportSpec(
                                    artifactID: exportedLayoutArtifactID,
                                    format: exportFormat,
                                    technologyInput: .path("tech/process.json")
                                ),
                            ],
                            tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                        )
                    ),
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutInput: .stageArtifact(
                                XcircuiteFlowInputReference.StageArtifact(
                                    stageID: "006-layout",
                                    artifactID: "drc-layout",
                                    kind: .layout,
                                    format: .json
                                )
                            ),
                            topCell: "top",
                            tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                        )
                    ),
                    .nativeLVS(
                        XcircuiteFlowStageExecutorSpec.NativeLVS(
                            stageID: "008-lvs",
                            layoutGDSInput: .stageArtifact(
                                XcircuiteFlowInputReference.StageArtifact(
                                    stageID: "006-layout",
                                    artifactID: exportedLayoutArtifactID,
                                    kind: .layout,
                                    format: canonicalArtifactFormat
                                )
                            ),
                            layoutFormat: lvsFormat,
                            schematicNetlistPath: "circuits/top.spice",
                            topCell: "top",
                            technologyPath: "tech/process.json",
                            tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                        )
                    ),
                    .mockPEX(
                        XcircuiteFlowStageExecutorSpec.MockPEX(
                            stageID: "009-pex",
                            layoutInput: .stageArtifact(
                                XcircuiteFlowInputReference.StageArtifact(
                                    stageID: "006-layout",
                                    artifactID: exportedLayoutArtifactID,
                                    kind: .layout,
                                    format: canonicalArtifactFormat
                                )
                            ),
                            layoutFormat: pexFormat,
                            sourceNetlistPath: "circuits/top.spice",
                            topCell: "top",
                            corners: [PEXCorner(id: "tt")],
                            technology: .inline(makePEXTechnology()),
                            tool: mockPEXContractToolSpec()
                        )
                    ),
                ]
            )
            let runtime = try spec.makeRuntime(projectRoot: root)
            let result = try await runtime.run(
                request: FlowOperationRequest(
                    projectRoot: root,
                    runID: runID,
                    intent: "Collect generated layout signoff corpus case",
                    stages: [
                        FlowStageDefinition(
                            stageID: "006-layout",
                            displayName: "Layout command",
                            requiredTool: layoutCommandRequirement()
                        ),
                        FlowStageDefinition(
                            stageID: "007-drc",
                            displayName: "DRC",
                            requiredTool: drcRequirement()
                        ),
                        FlowStageDefinition(
                            stageID: "008-lvs",
                            displayName: "LVS",
                            requiredTool: lvsRequirement()
                        ),
                        FlowStageDefinition(
                            stageID: "009-pex",
                            displayName: "PEX",
                            requiredTool: mockPEXContractRequirement(requiredLayoutFormat: canonicalArtifactFormat)
                        ),
                    ]
                )
            )
            #expect(result.status == FlowRunStatus.succeeded)
        }

        try await runGeneratedLayoutSignoffCase(
            runID: gdsRunID,
            exportedLayoutArtifactID: "layout-gds",
            exportFormat: .gds,
            artifactFormat: .gdsii,
            lvsFormat: .gds,
            pexFormat: .gds
        )
        try await runGeneratedLayoutSignoffCase(
            runID: oasisRunID,
            exportedLayoutArtifactID: "layout-oasis",
            exportFormat: .oasis,
            artifactFormat: .oasis,
            lvsFormat: .oasis,
            pexFormat: .oas
        )

        func expectedSignoffStages() -> [XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage] {
            [
                XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage(
                    stageID: "006-layout",
                    family: .layout
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage(
                    stageID: "007-drc",
                    family: .drc
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage(
                    stageID: "008-lvs",
                    family: .lvs
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage(
                    stageID: "009-pex",
                    family: .pex
                ),
            ]
        }

        func blockedOracleReadiness(
            reason: String
        ) -> [XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness] {
            [
                XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness(
                    domain: .drc,
                    backendID: "magic-drc",
                    status: .blocked,
                    reason: reason
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness(
                    domain: .lvs,
                    backendID: "netgen-lvs",
                    status: .blocked,
                    reason: reason
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness(
                    domain: .pex,
                    backendID: "magic-pex",
                    status: .blocked,
                    reason: reason
                ),
            ]
        }

        let request = XcircuiteGeneratedLayoutSignoffCorpusRequest(
            suiteID: "generated-layout-signoff-ladder",
            requiredCoverageTags: [
                "generated-layout.standard-gds.drc-lvs-pex",
                "generated-layout.standard-oasis.drc-lvs-pex",
            ],
            cases: [
                XcircuiteGeneratedLayoutSignoffCorpusRequest.CaseRequest(
                    caseID: "standard-gds-drc-lvs-pex-pass",
                    runID: gdsRunID,
                    expectedStages: expectedSignoffStages(),
                    coverageTags: [
                        "generated-layout.standard-gds.drc-lvs-pex",
                    ],
                    oracleReadiness: blockedOracleReadiness(
                        reason: "External signoff oracles are not required for this local GDS generated-layout promotion case."
                    )
                ),
                XcircuiteGeneratedLayoutSignoffCorpusRequest.CaseRequest(
                    caseID: "standard-oasis-drc-lvs-pex-pass",
                    runID: oasisRunID,
                    expectedStages: expectedSignoffStages(),
                    coverageTags: [
                        "generated-layout.standard-oasis.drc-lvs-pex",
                    ],
                    oracleReadiness: blockedOracleReadiness(
                        reason: "External signoff oracles are not required for this local OASIS generated-layout promotion case."
                    )
                ),
            ]
        )
        let collector = XcircuiteGeneratedLayoutSignoffCorpusCollector()
        let firstCase = try #require(request.cases.first)

        func expectCollectFailure(
            _ invalidRequest: XcircuiteGeneratedLayoutSignoffCorpusRequest,
            expectedError: XcircuiteGeneratedLayoutSignoffCorpusError
        ) {
            do {
                _ = try collector.collect(request: invalidRequest, projectRoot: root)
                Issue.record("Expected generated layout signoff corpus validation to fail.")
            } catch let error as XcircuiteGeneratedLayoutSignoffCorpusError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected generated layout signoff corpus error: \(error)")
            }
        }

        var duplicateCaseRequest = request
        duplicateCaseRequest.cases.append(firstCase)
        expectCollectFailure(
            duplicateCaseRequest,
            expectedError: .duplicateCaseID("standard-gds-drc-lvs-pex-pass")
        )

        var duplicateExpectedStageCase = firstCase
        duplicateExpectedStageCase.expectedStages.append(
            XcircuiteGeneratedLayoutSignoffCorpusRequest.ExpectedStage(
                stageID: "006-layout",
                family: .drc,
                expectedStatus: .failed
            )
        )
        var duplicateExpectedStageRequest = request
        duplicateExpectedStageRequest.cases = [duplicateExpectedStageCase]
        expectCollectFailure(
            duplicateExpectedStageRequest,
            expectedError: .duplicateExpectedStageID(
                caseID: "standard-gds-drc-lvs-pex-pass",
                stageID: "006-layout"
            )
        )

        var duplicateOracleReadinessCase = firstCase
        duplicateOracleReadinessCase.oracleReadiness.append(
            XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleReadiness(
                domain: .drc,
                backendID: "magic-drc",
                status: .ready,
                reason: "Conflicting readiness must not be silently ignored."
            )
        )
        var duplicateOracleReadinessRequest = request
        duplicateOracleReadinessRequest.cases = [duplicateOracleReadinessCase]
        expectCollectFailure(
            duplicateOracleReadinessRequest,
            expectedError: .duplicateOracleReadinessDomain(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc
            )
        )

        var emptyExpectedStagesCase = firstCase
        emptyExpectedStagesCase.expectedStages = []
        var emptyExpectedStagesRequest = request
        emptyExpectedStagesRequest.cases = [emptyExpectedStagesCase]
        expectCollectFailure(
            emptyExpectedStagesRequest,
            expectedError: .emptyExpectedStages(caseID: "standard-gds-drc-lvs-pex-pass")
        )

        var emptyCoverageTagsCase = firstCase
        emptyCoverageTagsCase.coverageTags = []
        var emptyCoverageTagsRequest = request
        emptyCoverageTagsRequest.cases = [emptyCoverageTagsCase]
        expectCollectFailure(
            emptyCoverageTagsRequest,
            expectedError: .emptyCoverageTags(caseID: "standard-gds-drc-lvs-pex-pass")
        )

        var emptyOracleReasonCase = firstCase
        emptyOracleReasonCase.oracleReadiness[0].reason = " "
        var emptyOracleReasonRequest = request
        emptyOracleReasonRequest.cases = [emptyOracleReasonCase]
        expectCollectFailure(
            emptyOracleReasonRequest,
            expectedError: .invalidOracleReadiness(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                field: "reason",
                value: " ",
                reason: "reason must not be empty"
            )
        )

        var invalidEvidencePathCase = firstCase
        invalidEvidencePathCase.oracleReadiness[0].evidenceRefs = [
            XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
                role: "oracle-report",
                path: "../oracle/report.json",
                kind: "report",
                format: "JSON",
                sha256: String(repeating: "a", count: 64),
                byteCount: 128
            ),
        ]
        var invalidEvidencePathRequest = request
        invalidEvidencePathRequest.cases = [invalidEvidencePathCase]
        expectCollectFailure(
            invalidEvidencePathRequest,
            expectedError: .invalidOracleEvidenceReference(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                path: "../oracle/report.json",
                field: "path",
                value: "../oracle/report.json",
                reason: "path must not contain '.' or '..' components"
            )
        )

        var invalidEvidenceHashCase = firstCase
        invalidEvidenceHashCase.oracleReadiness[0].evidenceRefs = [
            XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
                role: "oracle-report",
                path: ".xcircuite/oracle/report.json",
                kind: "report",
                format: "JSON",
                sha256: "not-a-sha256",
                byteCount: 128
            ),
        ]
        var invalidEvidenceHashRequest = request
        invalidEvidenceHashRequest.cases = [invalidEvidenceHashCase]
        expectCollectFailure(
            invalidEvidenceHashRequest,
            expectedError: .invalidOracleEvidenceReference(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                path: ".xcircuite/oracle/report.json",
                field: "sha256",
                value: "not-a-sha256",
                reason: "sha256 must be a 64-character hex digest when present"
            )
        )

        var invalidEvidenceByteCountCase = firstCase
        invalidEvidenceByteCountCase.oracleReadiness[0].evidenceRefs = [
            XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
                role: "oracle-report",
                path: ".xcircuite/oracle/report.json",
                kind: "report",
                format: "JSON",
                sha256: String(repeating: "a", count: 64),
                byteCount: 0
            ),
        ]
        var invalidEvidenceByteCountRequest = request
        invalidEvidenceByteCountRequest.cases = [invalidEvidenceByteCountCase]
        expectCollectFailure(
            invalidEvidenceByteCountRequest,
            expectedError: .invalidOracleEvidenceReference(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                path: ".xcircuite/oracle/report.json",
                field: "byteCount",
                value: "0",
                reason: "byteCount must be positive when present"
            )
        )

        let duplicateEvidenceReference = XcircuiteGeneratedLayoutSignoffCorpusRequest.OracleEvidenceReference(
            role: "oracle-report",
            path: ".xcircuite/oracle/report.json",
            kind: "report",
            format: "JSON",
            sha256: String(repeating: "a", count: 64),
            byteCount: 128
        )
        var duplicateEvidenceCase = firstCase
        duplicateEvidenceCase.oracleReadiness[0].evidenceRefs = [
            duplicateEvidenceReference,
            duplicateEvidenceReference,
        ]
        var duplicateEvidenceRequest = request
        duplicateEvidenceRequest.cases = [duplicateEvidenceCase]
        expectCollectFailure(
            duplicateEvidenceRequest,
            expectedError: .duplicateOracleEvidenceReference(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                role: "oracle-report",
                path: ".xcircuite/oracle/report.json"
            )
        )

        let report = try collector.collectAndPersist(request: request, projectRoot: root)

        #expect(report.status == .passed)
        #expect(report.summary.caseCount == 2)
        #expect(report.summary.passedCaseCount == 2)
        #expect(report.summary.missingCoverageTags.isEmpty)
        #expect(report.summary.oracleReadinessDeclaredCaseCount == 2)
        #expect(report.summary.stageFamilyCounts["layout"] == 2)
        #expect(report.summary.stageFamilyCounts["drc"] == 2)
        #expect(report.summary.stageFamilyCounts["lvs"] == 2)
        #expect(report.summary.stageFamilyCounts["pex"] == 2)
        #expect(report.suiteSpecArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-suite.json")
        #expect(report.reportArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report.json")
        #expect((report.reportArtifact?.byteCount ?? 0) > 0)

        let gdsCaseResult = try #require(report.caseResults.first {
            $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })
        let oasisCaseResult = try #require(report.caseResults.first {
            $0.caseID == "standard-oasis-drc-lvs-pex-pass"
        })
        #expect(report.caseResults.allSatisfy { $0.runStatusMatches })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.stageResults.allSatisfy { $0.statusMatches }
        })
        #expect(gdsCaseResult.sourceArtifactRefs.contains {
            $0.artifactID == "layout-gds"
                && $0.format == "GDSII"
                && $0.sha256 != nil
                && ($0.byteCount ?? 0) > 0
        })
        #expect(oasisCaseResult.sourceArtifactRefs.contains {
            $0.artifactID == "layout-oasis"
                && $0.format == "OASIS"
                && $0.sha256 != nil
                && ($0.byteCount ?? 0) > 0
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.sourceArtifactRefs.contains {
                $0.artifactID == "drc-layout"
                    && $0.format == "JSON"
                    && $0.sha256 != nil
                    && ($0.byteCount ?? 0) > 0
            }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.signoffArtifactRefs.contains { $0.artifactID == "drc-summary" }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.signoffArtifactRefs.contains { $0.artifactID == "lvs-summary" }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.signoffArtifactRefs.contains { $0.artifactID == "pex-summary" }
        })
        #expect(gdsCaseResult.sourceArtifactRefs.contains {
            $0.artifactID == "drc-layout"
                && $0.format == "JSON"
                && $0.sha256 != nil
                && ($0.byteCount ?? 0) > 0
        })

        let requestURL = root.appending(path: "generated-layout-signoff-corpus-request.json")
        try writeJSON(request, to: requestURL)
        let duplicateExpectedStageRequestURL = root.appending(
            path: "generated-layout-signoff-corpus-duplicate-stage-request.json"
        )
        try writeJSON(duplicateExpectedStageRequest, to: duplicateExpectedStageRequestURL)
        await #expect(throws: XcircuiteGeneratedLayoutSignoffCorpusError.self) {
            try await XcircuiteFlowCLICommand.run(arguments: [
                "collect-generated-layout-signoff-corpus",
                "--project-root",
                root.path(percentEncoded: false),
                "--request",
                duplicateExpectedStageRequestURL.path(percentEncoded: false),
                "--pretty",
            ])
        }
        let cliJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "collect-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--request",
            requestURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliData = try #require(cliJSON.data(using: .utf8))
        let cliReport = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusReport.self,
            from: cliData
        )
        #expect(cliReport.status == .passed)
        #expect(cliReport.reportArtifact?.artifactID == "generated-layout-signoff-corpus-report")

        let qualifier = XcircuiteGeneratedLayoutSignoffCorpusQualifier()
        let strictQualification = try qualifier.qualify(
            report: report,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(strictQualification.status == .failed)
        #expect(strictQualification.failures.contains {
            $0.code == "oracle-readiness-not-accepted"
                && $0.family == .drc
                && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })

        let localQualificationPolicy = XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy(
            policyID: "local-generated-layout-signoff-corpus-policy",
            requiredCoverageTags: request.requiredCoverageTags,
            acceptedOracleReadinessStatuses: [.ready, .blocked]
        )
        let qualification = try qualifier.qualifyAndPersist(
            report: report,
            policy: localQualificationPolicy,
            projectRoot: root
        )
        #expect(qualification.status == .qualified)
        #expect(qualification.summary.missingCoverageTags.isEmpty)
        #expect(qualification.summary.missingStageFamilies.isEmpty)
        #expect(qualification.summary.artifactWithoutHashCount == 0)
        #expect(qualification.summary.artifactWithoutByteCount == 0)
        #expect(qualification.summary.acceptedOracleReadinessCaseCount == 2)
        #expect(qualification.policyArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-qualification-policy.json")
        #expect(qualification.qualificationArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-qualification.json")

        let policyURL = root.appending(path: "generated-layout-signoff-corpus-policy.json")
        try writeJSON(localQualificationPolicy, to: policyURL)
        let reportPath = try #require(report.reportArtifact?.path)
        let reportURL = root.appending(path: reportPath)
        let cliQualificationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "qualify-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            reportURL.path(percentEncoded: false),
            "--policy",
            policyURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliQualificationData = try #require(cliQualificationJSON.data(using: .utf8))
        let cliQualification = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.self,
            from: cliQualificationData
        )
        #expect(cliQualification.status == .qualified)
        #expect(cliQualification.qualificationArtifact?.artifactID == "generated-layout-signoff-corpus-qualification")

        let retainedSignoffReportURL = workspaceRoot()
            .appending(path: "docs/contract-fixtures/signoff-retained-report-v1.json")
        #expect(FileManager.default.fileExists(atPath: retainedSignoffReportURL.path(percentEncoded: false)))
        let retainedSignoffReportData = try Data(contentsOf: retainedSignoffReportURL)
        let retainedSignoffReport = try JSONDecoder().decode(
            XcircuiteRetainedSignoffReport.self,
            from: retainedSignoffReportData
        )
        var readyWithoutEvidenceReport = report
        readyWithoutEvidenceReport.caseResults = report.caseResults.map { caseResult in
            var updatedCaseResult = caseResult
            updatedCaseResult.oracleReadiness = caseResult.oracleReadiness.map { readiness in
                var updatedReadiness = readiness
                updatedReadiness.status = .ready
                updatedReadiness.reason = "External oracle lane passed but case-level evidence refs were not attached."
                updatedReadiness.evidenceRefs = []
                return updatedReadiness
            }
            return updatedCaseResult
        }
        let readyWithoutEvidenceQualification = try qualifier.qualify(
            report: readyWithoutEvidenceReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(readyWithoutEvidenceQualification.status == .failed)
        #expect(readyWithoutEvidenceQualification.failures.contains {
            $0.code == "ready-oracle-evidence-missing"
                && $0.family == .drc
                && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })

        let readyAttachment = try XcircuiteGeneratedLayoutReadyOracleEvidenceAttacher()
            .attach(
                report: readyWithoutEvidenceReport,
                retainedSignoffReport: retainedSignoffReport,
                retainedSignoffReportURL: retainedSignoffReportURL
            )
        #expect(readyAttachment.status == .attached)
        #expect(readyAttachment.summary.updatedReadinessCount == 6)
        #expect(readyAttachment.summary.evidenceRefCount == 12)
        #expect(readyAttachment.summary.missingDomains.isEmpty)
        let readyWithEvidenceReport = readyAttachment.updatedReport
        let readyWithEvidenceQualification = try qualifier.qualify(
            report: readyWithEvidenceReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(readyWithEvidenceQualification.status == .qualified)
        #expect(readyWithEvidenceQualification.summary.caseCount == 2)
        #expect(readyWithEvidenceQualification.summary.reportedCaseCount == 2)
        #expect(readyWithEvidenceQualification.summary.uniqueCaseCount == 2)
        #expect(readyWithEvidenceQualification.summary.duplicateCaseCount == 0)
        #expect(readyWithEvidenceQualification.summary.sourceArtifactCount == report.summary.standardLayoutArtifactCount)
        #expect(
            readyWithEvidenceQualification.summary.reportedSourceArtifactCount ==
                report.summary.standardLayoutArtifactCount
        )
        #expect(readyWithEvidenceQualification.summary.signoffArtifactCount == report.summary.signoffArtifactCount)
        #expect(
            readyWithEvidenceQualification.summary.reportedSignoffArtifactCount ==
                report.summary.signoffArtifactCount
        )
        #expect(readyWithEvidenceQualification.summary.readyOracleEvidenceRefCount == 12)
        #expect(readyWithEvidenceQualification.summary.readyOracleReadinessWithoutEvidenceCount == 0)
        var staleQualificationReport = readyWithEvidenceReport
        let staleQualificationCase = try #require(readyWithEvidenceReport.caseResults.first {
            $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })
        staleQualificationReport.caseResults = [staleQualificationCase]
        staleQualificationReport.summary.caseCount = 2
        staleQualificationReport.summary.passedCaseCount = 2
        staleQualificationReport.summary.failedCaseCount = 0
        staleQualificationReport.summary.coveredCoverageTags = request.requiredCoverageTags
        staleQualificationReport.summary.missingCoverageTags = []
        staleQualificationReport.summary.standardLayoutArtifactCount = 999
        staleQualificationReport.summary.signoffArtifactCount = 999
        let staleQualification = try qualifier.qualify(
            report: staleQualificationReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(staleQualification.status == .failed)
        #expect(staleQualification.summary.caseCount == 1)
        #expect(staleQualification.summary.reportedCaseCount == 2)
        #expect(staleQualification.summary.uniqueCaseCount == 1)
        #expect(staleQualification.summary.duplicateCaseCount == 0)
        #expect(staleQualification.summary.sourceArtifactCount < staleQualification.summary.reportedSourceArtifactCount)
        #expect(staleQualification.summary.signoffArtifactCount < staleQualification.summary.reportedSignoffArtifactCount)
        #expect(staleQualification.failures.contains {
            $0.code == "case-count-mismatch"
        })
        #expect(staleQualification.failures.contains {
            $0.code == "missing-coverage-tag"
                && $0.coverageTag == "generated-layout.standard-oasis.drc-lvs-pex"
        })
        #expect(staleQualification.failures.contains {
            $0.code == "source-artifact-count-mismatch"
        })
        #expect(staleQualification.failures.contains {
            $0.code == "signoff-artifact-count-mismatch"
        })
        var duplicateQualificationReport = readyWithEvidenceReport
        duplicateQualificationReport.caseResults.append(staleQualificationCase)
        duplicateQualificationReport.summary.caseCount = duplicateQualificationReport.caseResults.count
        let duplicateQualificationPolicy = XcircuiteGeneratedLayoutSignoffCorpusQualificationPolicy(
            minimumCaseCount: 3,
            requiredCoverageTags: request.requiredCoverageTags
        )
        let duplicateQualification = try qualifier.qualify(
            report: duplicateQualificationReport,
            policy: duplicateQualificationPolicy
        )
        #expect(duplicateQualification.status == .failed)
        #expect(duplicateQualification.summary.caseCount == 3)
        #expect(duplicateQualification.summary.reportedCaseCount == 3)
        #expect(duplicateQualification.summary.uniqueCaseCount == 2)
        #expect(duplicateQualification.summary.duplicateCaseCount == 1)
        #expect(duplicateQualification.failures.contains {
            $0.code == "duplicate-case" && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })
        #expect(duplicateQualification.failures.contains {
            $0.code == "minimum-case-count-not-met"
        })
        let productionReadyAssessment = try XcircuiteGeneratedLayoutSignoffPromotionAssessor()
            .assess(
                request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                    promotionID: "generated-layout-signoff-promotion-assessment"
                ),
                qualification: readyWithEvidenceQualification,
                retainedSignoffReport: retainedSignoffReport,
                retainedSignoffReportURL: retainedSignoffReportURL
        )
        #expect(productionReadyAssessment.status == .productionReady)

        func expectPromotionAssessmentFailure(
            _ invalidRequest: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
            qualification: XcircuiteGeneratedLayoutSignoffCorpusQualificationResult = readyWithEvidenceQualification,
            retainedReport: XcircuiteRetainedSignoffReport? = nil,
            retainedReportURL: URL? = nil,
            expectedError: XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
        ) {
            do {
                _ = try XcircuiteGeneratedLayoutSignoffPromotionAssessor()
                    .assess(
                        request: invalidRequest,
                        qualification: qualification,
                        retainedSignoffReport: retainedReport,
                        retainedSignoffReportURL: retainedReportURL
                    )
                Issue.record("Expected generated layout signoff promotion assessment validation to fail.")
            } catch let error as XcircuiteGeneratedLayoutSignoffPromotionAssessmentError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected generated layout signoff promotion assessment error: \(error)")
            }
        }

        expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: []
            ),
            expectedError: .emptyRequiredExternalOracleDomains
        )
        expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: [.drc, .drc]
            ),
            expectedError: .duplicateRequiredExternalOracleDomain(.drc)
        )
        expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: [.layout]
            ),
            expectedError: .unsupportedRequiredExternalOracleDomain(.layout)
        )
        expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment"
            ),
            retainedReport: retainedSignoffReport,
            retainedReportURL: nil,
            expectedError: .retainedSignoffReportArtifactMissing
        )
        expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment"
            ),
            retainedReport: nil,
            retainedReportURL: retainedSignoffReportURL,
            expectedError: .retainedSignoffReportArtifactWithoutReport
        )

        let validPromotionArtifactSHA256 = String(repeating: "a", count: 64)
        func expectPromotionArtifactReferenceFailure(
            path: String = "retained-signoff-report.json",
            sha256: String = validPromotionArtifactSHA256,
            byteCount: Int64 = 128,
            expectedError: XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
        ) {
            do {
                _ = try XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactReference(
                    path: path,
                    sha256: sha256,
                    byteCount: byteCount
                )
                Issue.record("Expected generated layout signoff promotion artifact validation to fail.")
            } catch let error as XcircuiteGeneratedLayoutSignoffPromotionAssessmentError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected generated layout signoff promotion artifact error: \(error)")
            }
        }

        expectPromotionArtifactReferenceFailure(
            path: " ",
            expectedError: .invalidRetainedSignoffReportArtifactPath(" ")
        )
        expectPromotionArtifactReferenceFailure(
            sha256: "not-a-sha256",
            expectedError: .invalidRetainedSignoffReportArtifactSHA256(
                path: "retained-signoff-report.json",
                sha256: "not-a-sha256"
            )
        )
        expectPromotionArtifactReferenceFailure(
            byteCount: 0,
            expectedError: .invalidRetainedSignoffReportArtifactByteCount(
                path: "retained-signoff-report.json",
                byteCount: 0
            )
        )
        let invalidPromotionArtifactJSON = Data(
            """
            {
              "path": "retained-signoff-report.json",
              "sha256": "not-a-sha256",
              "byteCount": 128
            }
            """.utf8
        )
        do {
            _ = try JSONDecoder().decode(
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactReference.self,
                from: invalidPromotionArtifactJSON
            )
            Issue.record("Expected generated layout signoff promotion artifact decode to fail.")
        } catch let error as XcircuiteGeneratedLayoutSignoffPromotionAssessmentError {
            #expect(error == .invalidRetainedSignoffReportArtifactSHA256(
                path: "retained-signoff-report.json",
                sha256: "not-a-sha256"
            ))
        } catch {
            Issue.record("Unexpected generated layout signoff promotion artifact decode error: \(error)")
        }

        let readyWithoutEvidenceReportURL = root.appending(path: "ready-without-evidence-report.json")
        try writeJSON(readyWithoutEvidenceReport, to: readyWithoutEvidenceReportURL)
        let staleQualificationReportURL = root.appending(path: "stale-qualification-report.json")
        try writeJSON(staleQualificationReport, to: staleQualificationReportURL)
        let cliStaleQualificationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "qualify-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            staleQualificationReportURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliStaleQualificationData = try #require(cliStaleQualificationJSON.data(using: .utf8))
        let cliStaleQualification = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.self,
            from: cliStaleQualificationData
        )
        #expect(cliStaleQualification.status == .failed)
        #expect(cliStaleQualification.failures.contains { $0.code == "case-count-mismatch" })
        #expect(cliStaleQualification.failures.contains { $0.code == "missing-coverage-tag" })
        let cliReadyAttachmentJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "attach-generated-layout-ready-oracle-evidence",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            readyWithoutEvidenceReportURL.path(percentEncoded: false),
            "--retained-signoff-report",
            retainedSignoffReportURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliReadyAttachmentData = try #require(cliReadyAttachmentJSON.data(using: .utf8))
        let cliReadyAttachment = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutReadyOracleEvidenceAttachmentResult.self,
            from: cliReadyAttachmentData
        )
        #expect(cliReadyAttachment.status == .attached)
        #expect(cliReadyAttachment.reportArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report-ready-oracle-evidence.json")
        #expect(cliReadyAttachment.summary.evidenceRefCount == 12)
        let cliReadyReportPath = try #require(cliReadyAttachment.reportArtifact?.path)
        let cliReadyReportURL = root.appending(path: cliReadyReportPath)
        let cliReadyQualificationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "qualify-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            cliReadyReportURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliReadyQualificationData = try #require(cliReadyQualificationJSON.data(using: .utf8))
        let cliReadyQualification = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusQualificationResult.self,
            from: cliReadyQualificationData
        )
        #expect(cliReadyQualification.status == .qualified)
        #expect(cliReadyQualification.summary.readyOracleEvidenceRefCount == 12)

        let expansionAuditPolicy = XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditPolicy(
            policyID: "generated-layout-standard-format-expansion-policy",
            minimumCaseCount: 2,
            requiredCoverageTags: [
                "generated-layout.standard-gds.drc-lvs-pex",
                "generated-layout.standard-oasis.drc-lvs-pex",
            ],
            requiredSourceArtifactFormats: [
                "GDSII",
                "OASIS",
            ],
            requiredSignoffArtifactIDs: [
                "drc-summary",
                "lvs-summary",
                "pex-summary",
            ],
            requiredStageFamilies: [
                .layout,
                .drc,
                .lvs,
                .pex,
            ],
            requireReadyOracleEvidence: true
        )
        let coverageAuditor = XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditor()
        let blockedExpansionAudit = try coverageAuditor.audit(report: report, policy: expansionAuditPolicy)
        #expect(blockedExpansionAudit.status == .incomplete)
        #expect(blockedExpansionAudit.missingRequirements.contains {
            $0.kind == "ready-oracle-evidence"
        })
        #expect(!blockedExpansionAudit.missingRequirements.contains {
            $0.kind == "case-count"
        })
        #expect(!blockedExpansionAudit.missingRequirements.contains {
            $0.kind == "source-artifact-format"
        })
        #expect(blockedExpansionAudit.suggestedActions.contains {
            $0.actionKind == "attach-generated-layout-ready-oracle-evidence"
        })

        var duplicateCasePolicy = expansionAuditPolicy
        duplicateCasePolicy.minimumCaseCount = 3
        var duplicateCaseReport = readyWithEvidenceReport
        duplicateCaseReport.caseResults.append(try #require(readyWithEvidenceReport.caseResults.first))
        duplicateCaseReport.summary.caseCount = duplicateCaseReport.caseResults.count
        let duplicateCaseAudit = try coverageAuditor.audit(
            report: duplicateCaseReport,
            policy: duplicateCasePolicy
        )
        #expect(duplicateCaseAudit.status == .incomplete)
        #expect(duplicateCaseAudit.summary.caseCount == 3)
        #expect(duplicateCaseAudit.summary.reportedCaseCount == 3)
        #expect(duplicateCaseAudit.summary.uniqueCaseCount == 2)
        #expect(duplicateCaseAudit.summary.duplicateCaseCount == 1)
        #expect(duplicateCaseAudit.missingRequirements.contains {
            $0.kind == "duplicate-case" && $0.identifier == "standard-gds-drc-lvs-pex-pass"
        })
        #expect(duplicateCaseAudit.missingRequirements.contains {
            $0.kind == "case-count" && $0.identifier == "minimum-case-count"
        })
        #expect(duplicateCaseAudit.suggestedActions.contains {
            $0.actionKind == "remove-duplicate-generated-layout-corpus-case"
                && $0.targetIdentifier == "standard-gds-drc-lvs-pex-pass"
        })

        var staleSummaryReport = readyWithEvidenceReport
        staleSummaryReport.summary.caseCount = 99
        let staleSummaryAudit = try coverageAuditor.audit(
            report: staleSummaryReport,
            policy: expansionAuditPolicy
        )
        #expect(staleSummaryAudit.status == .incomplete)
        #expect(staleSummaryAudit.summary.caseCount == 2)
        #expect(staleSummaryAudit.summary.reportedCaseCount == 99)
        #expect(staleSummaryAudit.summary.uniqueCaseCount == 2)
        #expect(staleSummaryAudit.summary.duplicateCaseCount == 0)
        #expect(staleSummaryAudit.missingRequirements.contains {
            $0.kind == "case-count-mismatch" && $0.identifier == "summary-case-count"
        })
        #expect(staleSummaryAudit.suggestedActions.contains {
            $0.actionKind == "regenerate-generated-layout-signoff-corpus-report"
                && $0.targetIdentifier == "summary-case-count"
        })

        let expansionPolicyURL = root.appending(path: "generated-layout-coverage-audit-policy.json")
        try writeJSON(expansionAuditPolicy, to: expansionPolicyURL)
        let staleSummaryReportURL = root.appending(path: "generated-layout-stale-summary-report.json")
        try writeJSON(staleSummaryReport, to: staleSummaryReportURL)
        let cliStaleSummaryAuditJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "audit-generated-layout-signoff-corpus-coverage",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            staleSummaryReportURL.path(percentEncoded: false),
            "--policy",
            expansionPolicyURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliStaleSummaryAuditData = try #require(cliStaleSummaryAuditJSON.data(using: .utf8))
        let cliStaleSummaryAudit = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.self,
            from: cliStaleSummaryAuditData
        )
        #expect(cliStaleSummaryAudit.status == .incomplete)
        #expect(cliStaleSummaryAudit.missingRequirements.contains {
            $0.kind == "case-count-mismatch" && $0.identifier == "summary-case-count"
        })
        let cliCoverageAuditJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "audit-generated-layout-signoff-corpus-coverage",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            cliReadyReportURL.path(percentEncoded: false),
            "--policy",
            expansionPolicyURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliCoverageAuditData = try #require(cliCoverageAuditJSON.data(using: .utf8))
        let cliCoverageAudit = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusCoverageAudit.self,
            from: cliCoverageAuditData
        )
        #expect(cliCoverageAudit.status == .satisfied)
        #expect(cliCoverageAudit.summary.caseCount == 2)
        #expect(cliCoverageAudit.summary.reportedCaseCount == 2)
        #expect(cliCoverageAudit.summary.uniqueCaseCount == 2)
        #expect(cliCoverageAudit.summary.duplicateCaseCount == 0)
        #expect(cliCoverageAudit.summary.readyOracleEvidenceRefCount == 12)
        #expect(cliCoverageAudit.summary.missingCoverageTags.isEmpty)
        #expect(cliCoverageAudit.summary.missingSourceArtifactFormats.isEmpty)
        #expect(!cliCoverageAudit.missingRequirements.contains {
            $0.kind == "case-count" && $0.identifier == "minimum-case-count"
        })
        #expect(!cliCoverageAudit.missingRequirements.contains {
            $0.kind == "ready-oracle-evidence"
        })
        #expect(cliCoverageAudit.suggestedActions.isEmpty)
        #expect(cliCoverageAudit.auditArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit.json")

        let promotionAssessment = try XcircuiteGeneratedLayoutSignoffPromotionAssessor()
            .assessAndPersist(
                request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                    promotionID: "generated-layout-signoff-promotion-assessment"
                ),
                qualification: qualification,
                retainedSignoffReport: retainedSignoffReport,
                retainedSignoffReportURL: retainedSignoffReportURL,
                projectRoot: root
            )
        #expect(promotionAssessment.status == .readyForExternalCaseExpansion)
        #expect(!promotionAssessment.summary.generatedLayoutOracleReady)
        #expect(promotionAssessment.summary.externalOracleInfrastructureReady)
        #expect(promotionAssessment.summary.passedExternalOracleLaneCount == 3)
        #expect(promotionAssessment.blockers.contains {
            $0.code == "generated-layout-oracle-readiness-not-ready"
        })
        #expect(promotionAssessment.suggestedActions.contains {
            $0.actionKind == "run-generated-layout-external-oracle-cases"
        })
        #expect(promotionAssessment.assessmentArtifact?.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/promotion-assessment.json")

        let qualificationPath = try #require(qualification.qualificationArtifact?.path)
        let qualificationURL = root.appending(path: qualificationPath)
        let cliAssessmentJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "assess-generated-layout-signoff-promotion",
            "--project-root",
            root.path(percentEncoded: false),
            "--qualification",
            qualificationURL.path(percentEncoded: false),
            "--retained-signoff-report",
            retainedSignoffReportURL.path(percentEncoded: false),
            "--promotion-id",
            "generated-layout-signoff-promotion-assessment",
            "--persist",
            "--pretty",
        ])
        let cliAssessmentData = try #require(cliAssessmentJSON.data(using: .utf8))
        let cliAssessment = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffPromotionAssessment.self,
            from: cliAssessmentData
        )
        #expect(cliAssessment.status == .readyForExternalCaseExpansion)
        #expect(cliAssessment.assessmentArtifact?.artifactID == "generated-layout-signoff-promotion-assessment")

        let manifest = try XcircuitePackageStore().loadManifest(forProjectAt: root)
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-suite"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-suite.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-report"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-qualification-policy"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-qualification-policy.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-qualification"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-qualification.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-ready-oracle-corpus-report"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report-ready-oracle-evidence.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-coverage-audit-policy"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit-policy.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-coverage-audit"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-promotion-assessment"
                && $0.path == ".xcircuite/qualification/generated-layout-signoff/generated-layout-signoff-ladder/promotion-assessment.json"
        })
    }

    @Test func generatedLayoutFailureLadderRetainsFirstFailingGateAndActions() async throws {
        let root = try makeTemporaryRoot("generated-layout-failure-ladder")
        defer { removeTemporaryRoot(root) }
        let runID = "generated-layout-drc-failure-run"
        try writeLayoutCommandRequest(root: root)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            rules: [
                                NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 20.0),
                            ]
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "drc-layout",
                                kind: .layout,
                                format: .json
                            )
                        ),
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
            ]
        )
        let runtime = try spec.makeRuntime(projectRoot: root)
        let result = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: runID,
                intent: "Capture generated layout DRC failure ladder",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )
        #expect(result.status == .failed)
        #expect(result.stages.map(\.stageID) == ["006-layout", "007-drc"])

        let request = XcircuiteGeneratedLayoutFailureLadderRequest(
            ladderID: "generated-layout-drc-failure",
            runID: runID,
            expectedStageFamilies: [
                "006-layout": .layout,
                "007-drc": .drc,
            ]
        )
        let collector = XcircuiteGeneratedLayoutFailureLadderCollector()
        let report = try collector.collectAndPersist(request: request, projectRoot: root)

        #expect(report.runStatus == .failed)
        #expect(report.summary.stageCount == 2)
        #expect(report.summary.failingStageCount == 1)
        #expect(report.summary.firstFailingStageID == "007-drc")
        #expect(report.summary.firstFailingGateID == "drc")
        #expect(report.summary.firstFailingFamily == .drc)
        #expect(report.summary.diagnosticCount > 0)
        #expect(report.summary.suggestedActionCount >= 2)
        #expect(
            report.reportArtifact?.path ==
                ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure.json"
        )
        #expect(report.reportArtifact?.artifactID == "generated-layout-drc-failure")
        #expect((report.reportArtifact?.byteCount ?? 0) > 0)

        let drcNode = try #require(report.stageNodes.first { $0.stageID == "007-drc" })
        #expect(drcNode.isFirstFailure)
        #expect(drcNode.family == .drc)
        #expect(drcNode.gates.contains { $0.gateID == "drc" && $0.status == .failed })
        #expect(drcNode.artifactRefs.contains {
            $0.artifactID == "drc-summary"
                && $0.format == "JSON"
                && $0.sha256 != nil
                && ($0.byteCount ?? 0) > 0
        })
        #expect(report.suggestedActions.contains {
            $0.stageID == "007-drc"
                && $0.actionKind == "inspect-drc-summary"
                && $0.evidenceArtifactIDs.contains("drc-summary")
        })
        #expect(report.suggestedActions.contains {
            $0.stageID == "007-drc" && $0.actionKind == "repair-layout-geometry"
        })

        let alternateReport = try collector.collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-drc-failure-alternate",
                runID: runID,
                expectedStageFamilies: [
                    "006-layout": .layout,
                    "007-drc": .drc,
                ]
            ),
            projectRoot: root
        )
        #expect(
            alternateReport.reportArtifact?.path ==
                ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure-alternate.json"
        )
        #expect(alternateReport.reportArtifact?.artifactID == "generated-layout-drc-failure-alternate")
        let storedPrimaryPath = try #require(report.reportArtifact?.path)
        let storedAlternatePath = try #require(alternateReport.reportArtifact?.path)
        let storedPrimaryURL = root.appending(path: storedPrimaryPath)
        let storedAlternateURL = root.appending(path: storedAlternatePath)
        let storedPrimaryReport = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutFailureLadderReport.self,
            from: Data(contentsOf: storedPrimaryURL)
        )
        let storedAlternateReport = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutFailureLadderReport.self,
            from: Data(contentsOf: storedAlternateURL)
        )
        #expect(storedPrimaryReport.ladderID == "generated-layout-drc-failure")
        #expect(storedAlternateReport.ladderID == "generated-layout-drc-failure-alternate")
        #expect(storedPrimaryReport.reportArtifact == nil)
        #expect(storedAlternateReport.reportArtifact == nil)

        let cliJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "collect-generated-layout-failure-ladder",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--ladder-id",
            "generated-layout-drc-failure-cli",
            "--persist",
            "--pretty",
        ])
        let cliData = try #require(cliJSON.data(using: .utf8))
        let cliReport = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutFailureLadderReport.self,
            from: cliData
        )
        #expect(cliReport.summary.firstFailingStageID == "007-drc")
        #expect(cliReport.reportArtifact?.artifactID == "generated-layout-drc-failure-cli")
        #expect(
            cliReport.reportArtifact?.path ==
                ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure-cli.json"
        )

        let manifest = try XcircuitePackageStore().loadManifest(forProjectAt: root)
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-drc-failure"
                && $0.path == ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-drc-failure-alternate"
                && $0.path == ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure-alternate.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-drc-failure-cli"
                && $0.path == ".xcircuite/runs/\(runID)/reports/generated-layout-failure-ladder-generated-layout-drc-failure-cli.json"
        })
    }

    @Test func generatedLayoutFailureLadderCapturesRetryExhaustionAndArtifactIntegrityIssues() async throws {
        let retryRoot = try makeTemporaryRoot("generated-layout-retry-exhaustion-ladder")
        defer { removeTemporaryRoot(retryRoot) }
        let retryRunID = "generated-layout-retry-exhausted-run"
        let layoutURL = try writeLayout(cleanLayout(), root: retryRoot)
        let runtime = QualifiedToolFixtures.runtime(
            executors: [
                DRCFlowStageExecutor(
                    stageID: "007-drc",
                    toolID: "native-drc",
                    request: DRCRequest(
                        layoutURL: layoutURL,
                        topCell: "TOP",
                        backendSelection: DRCBackendSelection(backendID: "native")
                    ),
                    engine: AlwaysFailingDRCEngine()
                ),
            ],
            descriptors: [SignoffToolDescriptors.nativeDRC(level: .productionEligible)]
        )

        let retryResult = try await runtime.run(
            request: FlowOperationRequest(
                projectRoot: retryRoot,
                runID: retryRunID,
                intent: "Capture generated layout retry exhaustion ladder",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        retryPolicy: FlowStageRetryPolicy(
                            maxAttempts: 2,
                            retryableDiagnosticCodes: ["DRC_EXECUTION_ERROR"]
                        )
                    ),
                ]
            )
        )
        #expect(retryResult.status == .failed)

        let retryReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-retry-exhausted",
                runID: retryRunID,
                expectedStageFamilies: ["007-drc": .drc]
            ),
            projectRoot: retryRoot
        )
        let retryNode = try #require(retryReport.stageNodes.first { $0.stageID == "007-drc" })
        #expect(retryNode.attempts.map(\.attemptIndex) == [1, 2])
        #expect(retryNode.attempts[0].shouldRetry)
        #expect(retryNode.attempts[0].retryReason == .retryableDiagnosticMatched)
        #expect(retryNode.attempts[0].matchedDiagnosticCodes == ["DRC_EXECUTION_ERROR"])
        #expect(!retryNode.attempts[1].shouldRetry)
        #expect(retryNode.attempts[1].retryReason == .maxAttemptsReached)
        #expect(retryReport.suggestedActions.contains {
            $0.stageID == "007-drc" && $0.actionKind == "inspect-tool-health"
        })

        let staleRoot = try makeTemporaryRoot("generated-layout-stale-artifact-ladder")
        defer { removeTemporaryRoot(staleRoot) }
        let staleRunID = "generated-layout-stale-artifact-run"
        try writeLayoutCommandRequest(root: staleRoot)
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            rules: [
                                NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 20.0),
                            ]
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "drc-layout",
                                kind: .layout,
                                format: .json
                            )
                        ),
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
            ]
        )
        let staleResult = try await spec.makeRuntime(projectRoot: staleRoot).run(
            request: FlowOperationRequest(
                projectRoot: staleRoot,
                runID: staleRunID,
                intent: "Capture generated layout stale artifact ladder",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )
        #expect(staleResult.status == .failed)

        let staleSummaryURL = staleRoot.appending(
            path: ".xcircuite/runs/\(staleRunID)/stages/007-drc/raw/drc-summary.json"
        )
        try Data(#"{"tampered":true}"#.utf8).write(to: staleSummaryURL, options: [.atomic])

        let staleReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-stale-artifact",
                runID: staleRunID,
                expectedStageFamilies: [
                    "006-layout": .layout,
                    "007-drc": .drc,
                ]
            ),
            projectRoot: staleRoot
        )
        #expect(staleReport.summary.artifactIssueCount > 0)
        let staleNode = try #require(staleReport.stageNodes.first { $0.stageID == "007-drc" })
        let staleStatuses = Set(["byteCountMismatch", "sha256Mismatch"])
        #expect(staleNode.artifactIssues.contains {
            $0.artifactID == "drc-summary" && staleStatuses.contains($0.status)
        })
        #expect(staleNode.artifactRefs.contains {
            $0.artifactID == "drc-summary"
                && $0.integrityStatus.map { staleStatuses.contains($0) } == true
        })
        #expect(staleReport.suggestedActions.contains {
            $0.stageID == "007-drc" && $0.actionKind == "inspect-artifact-integrity"
        })
    }

    @Test func generatedLayoutFailureLadderClassifiesLVSPEXAndPostLayoutFailures() async throws {
        func assertFailure(
            _ report: XcircuiteGeneratedLayoutFailureLadderReport,
            stageID: String,
            family: XcircuiteGeneratedLayoutSignoffStageFamily,
            actionKind: String
        ) throws {
            #expect(report.runStatus == .failed)
            #expect(report.summary.firstFailingStageID == stageID)
            #expect(report.summary.firstFailingFamily == family)
            #expect(report.summary.suggestedActionCount > 0)
            let node = try #require(report.stageNodes.first { $0.stageID == stageID })
            #expect(node.isFirstFailure)
            #expect(node.family == family)
            #expect(report.suggestedActions.contains {
                $0.stageID == stageID && $0.family == family && $0.actionKind == actionKind
            })
        }

        let drcRoot = try makeTemporaryRoot("generated-layout-drc-coverage-failure-ladder")
        defer { removeTemporaryRoot(drcRoot) }
        try writeLayoutCommandRequest(root: drcRoot)
        let drcSpec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        drcExport: LayoutCommandDRCExportSpec(
                            technologyID: "flow-test",
                            topCell: "top",
                            rules: [
                                NativeDRCRule(id: "M1.width", kind: .minimumWidth, layer: "M1", value: 20.0),
                            ]
                        ),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "drc-layout",
                                kind: .layout,
                                format: .json
                            )
                        ),
                        topCell: "top",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
            ]
        )
        let drcRunID = "generated-layout-drc-coverage-failure-run"
        let drcResult = try await drcSpec.makeRuntime(projectRoot: drcRoot).run(
            request: FlowOperationRequest(
                projectRoot: drcRoot,
                runID: drcRunID,
                intent: "Capture generated layout DRC failure ladder coverage case",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement()
                    ),
                ]
            )
        )
        #expect(drcResult.status == .failed)
        let drcReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-drc-coverage-failure",
                runID: drcRunID,
                expectedStageFamilies: [
                    "006-layout": .layout,
                    "007-drc": .drc,
                ]
            ),
            projectRoot: drcRoot
        )
        try assertFailure(
            drcReport,
            stageID: "007-drc",
            family: .drc,
            actionKind: "repair-layout-geometry"
        )

        let lvsRoot = try makeTemporaryRoot("generated-layout-lvs-failure-ladder")
        defer { removeTemporaryRoot(lvsRoot) }
        try writeLayoutCommandRequest(root: lvsRoot)
        try writeStandardLayoutTechnology(root: lvsRoot)
        let lvsSpec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .nativeLVS(
                    XcircuiteFlowStageExecutorSpec.NativeLVS(
                        stageID: "008-lvs",
                        layoutGDSInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        schematicNetlistPath: "circuits/missing.spice",
                        topCell: "top",
                        technologyPath: "tech/process.json",
                        tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                    )
                ),
            ]
        )
        let lvsRunID = "generated-layout-lvs-failure-run"
        let lvsResult = try await lvsSpec.makeRuntime(projectRoot: lvsRoot).run(
            request: FlowOperationRequest(
                projectRoot: lvsRoot,
                runID: lvsRunID,
                intent: "Capture generated layout LVS failure ladder",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "008-lvs",
                        displayName: "LVS",
                        requiredTool: lvsRequirement()
                    ),
                ]
            )
        )
        #expect(lvsResult.status == .failed)
        let lvsReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-lvs-failure",
                runID: lvsRunID,
                expectedStageFamilies: [
                    "006-layout": .layout,
                    "008-lvs": .lvs,
                ]
            ),
            projectRoot: lvsRoot
        )
        try assertFailure(
            lvsReport,
            stageID: "008-lvs",
            family: .lvs,
            actionKind: "compare-layout-and-schematic-netlists"
        )

        let pexRoot = try makeTemporaryRoot("generated-layout-pex-failure-ladder")
        defer { removeTemporaryRoot(pexRoot) }
        try writeLayoutCommandRequest(root: pexRoot)
        try writeStandardLayoutTechnology(root: pexRoot)
        let pexSpec = XcircuiteFlowRuntimeSpec(
            executors: [
                .layoutCommand(
                    XcircuiteFlowStageExecutorSpec.LayoutCommand(
                        stageID: "006-layout",
                        requestPath: "layout-command-request.json",
                        standardLayoutExports: [
                            LayoutCommandStandardLayoutExportSpec(
                                artifactID: "layout-gds",
                                format: .gds,
                                technologyInput: .path("tech/process.json")
                            ),
                        ],
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked)
                    )
                ),
                .mockPEX(
                    XcircuiteFlowStageExecutorSpec.MockPEX(
                        stageID: "009-pex",
                        layoutInput: .stageArtifact(
                            XcircuiteFlowInputReference.StageArtifact(
                                stageID: "006-layout",
                                artifactID: "layout-gds",
                                kind: .layout,
                                format: .gdsii
                            )
                        ),
                        layoutFormat: .gds,
                        sourceNetlistPath: "circuits/missing.spice",
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        tool: mockPEXContractToolSpec()
                    )
                ),
            ]
        )
        let pexRunID = "generated-layout-pex-failure-run"
        let pexResult = try await pexSpec.makeRuntime(projectRoot: pexRoot).run(
            request: FlowOperationRequest(
                projectRoot: pexRoot,
                runID: pexRunID,
                intent: "Capture generated layout PEX failure ladder",
                stages: [
                    FlowStageDefinition(
                        stageID: "006-layout",
                        displayName: "Layout command",
                        requiredTool: layoutCommandRequirement()
                    ),
                    FlowStageDefinition(
                        stageID: "009-pex",
                        displayName: "PEX",
                        requiredTool: mockPEXContractRequirement()
                    ),
                ]
            )
        )
        #expect(pexResult.status == .failed)
        let pexReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-pex-failure",
                runID: pexRunID,
                expectedStageFamilies: [
                    "006-layout": .layout,
                    "009-pex": .pex,
                ]
            ),
            projectRoot: pexRoot
        )
        try assertFailure(
            pexReport,
            stageID: "009-pex",
            family: .pex,
            actionKind: "review-parasitic-technology-inputs"
        )

        let postLayoutRoot = try makeTemporaryRoot("generated-layout-post-layout-failure-ladder")
        defer { removeTemporaryRoot(postLayoutRoot) }
        let preWaveform = try writeNetlist(
            """
            time,V(out)
            0,0
            1e-9,1
            """,
            name: "waveforms/pre.csv",
            root: postLayoutRoot
        )
        let postWaveform = try writeNetlist(
            """
            time,V(out)
            0,0
            1e-9,1
            """,
            name: "waveforms/post.csv",
            root: postLayoutRoot
        )
        let postLayoutRunID = "generated-layout-post-layout-failure-run"
        let postLayoutResult = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: postLayoutRoot,
                runID: postLayoutRunID,
                intent: "Capture generated layout post-layout comparison failure",
                stages: [
                    FlowStageDefinition(stageID: "030-compare", displayName: "Post-layout comparison"),
                ]
            ),
            toolRegistry: ToolRegistry(),
            healthResults: [:],
            executors: [
                PostLayoutComparisonFlowStageExecutor(
                    stageID: "030-compare",
                    preLayoutWaveformURL: preWaveform,
                    postLayoutWaveformURL: postWaveform,
                    options: PostLayoutComparisonOptions(requiredPostVariables: ["V(out_pex)"])
                ),
            ]
        )
        #expect(postLayoutResult.status == .failed)
        let postLayoutReport = try XcircuiteGeneratedLayoutFailureLadderCollector().collectAndPersist(
            request: XcircuiteGeneratedLayoutFailureLadderRequest(
                ladderID: "generated-layout-post-layout-failure",
                runID: postLayoutRunID
            ),
            projectRoot: postLayoutRoot
        )
        try assertFailure(
            postLayoutReport,
            stageID: "030-compare",
            family: .postLayout,
            actionKind: "inspect-post-layout-comparison"
        )
        let postLayoutNode = try #require(postLayoutReport.stageNodes.first { $0.stageID == "030-compare" })
        #expect(postLayoutNode.artifactRefs.contains {
            $0.artifactID == "post-layout-comparison"
                && $0.format == "JSON"
                && $0.sha256 != nil
                && ($0.byteCount ?? 0) > 0
        })
        #expect(postLayoutReport.suggestedActions.contains {
            $0.actionKind == "inspect-post-layout-comparison"
                && $0.evidenceArtifactIDs.contains("post-layout-comparison")
        })

        let coveragePolicy = XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy(
            auditID: "generated-layout-failure-ladder-local-coverage",
            minimumReportCount: 4,
            requiredFirstFailingFamilies: [
                .drc,
                .lvs,
                .pex,
                .postLayout,
            ],
            requiredSuggestedActionKinds: [
                "repair-layout-geometry",
                "compare-layout-and-schematic-netlists",
                "review-parasitic-technology-inputs",
                "inspect-post-layout-comparison",
            ],
            requiredEvidenceArtifactIDs: [
                "drc-summary",
                "post-layout-comparison",
            ],
            requireDiagnosticCodes: true
        )
        let coverageAudit = try XcircuiteGeneratedLayoutFailureLadderCoverageAuditor().audit(
            reports: [
                drcReport,
                lvsReport,
                pexReport,
                postLayoutReport,
            ],
            policy: coveragePolicy
        )
        #expect(coverageAudit.status == .satisfied)
        #expect(coverageAudit.summary.reportCount == 4)
        #expect(coverageAudit.summary.missingFirstFailingFamilies.isEmpty)
        #expect(coverageAudit.summary.missingSuggestedActionKinds.isEmpty)
        #expect(coverageAudit.summary.missingEvidenceArtifactIDs.isEmpty)
        #expect(coverageAudit.summary.diagnosticCodeCount > 0)

        let duplicateCoveragePolicy = XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy(
            auditID: "generated-layout-failure-ladder-duplicate-coverage",
            minimumReportCount: 2,
            requiredFirstFailingFamilies: [.drc],
            requireDiagnosticCodes: true
        )
        let duplicateCoverageAudit = try XcircuiteGeneratedLayoutFailureLadderCoverageAuditor().audit(
            reports: [
                drcReport,
                drcReport,
            ],
            policy: duplicateCoveragePolicy
        )
        #expect(duplicateCoverageAudit.status == .incomplete)
        #expect(duplicateCoverageAudit.summary.reportCount == 2)
        #expect(duplicateCoverageAudit.summary.uniqueReportCount == 1)
        #expect(duplicateCoverageAudit.summary.duplicateReportCount == 1)
        #expect(duplicateCoverageAudit.missingRequirements.contains {
            $0.kind == "duplicate-report"
                && $0.identifier == "\(drcRunID):generated-layout-drc-coverage-failure"
        })
        #expect(duplicateCoverageAudit.missingRequirements.contains {
            $0.kind == "report-count" && $0.identifier == "minimum-report-count"
        })
        #expect(duplicateCoverageAudit.suggestedActions.contains {
            $0.actionKind == "remove-duplicate-failure-ladder-report"
                && $0.targetIdentifier == "\(drcRunID):generated-layout-drc-coverage-failure"
        })

        let blockedCoveragePolicy = XcircuiteGeneratedLayoutFailureLadderCoverageAuditPolicy(
            auditID: "generated-layout-failure-ladder-blocked-coverage",
            minimumReportCount: 5,
            requiredFirstFailingFamilies: [
                .drc,
                .lvs,
                .pex,
                .postLayout,
                .simulation,
            ],
            requiredSuggestedActionKinds: [
                "inspect-simulation-summary",
            ],
            requiredEvidenceArtifactIDs: [
                "simulation-summary",
            ],
            requireDiagnosticCodes: true
        )
        let blockedCoverageAudit = try XcircuiteGeneratedLayoutFailureLadderCoverageAuditor().audit(
            reports: [
                drcReport,
                lvsReport,
                pexReport,
                postLayoutReport,
            ],
            policy: blockedCoveragePolicy
        )
        #expect(blockedCoverageAudit.status == .incomplete)
        #expect(blockedCoverageAudit.missingRequirements.contains {
            $0.kind == "first-failing-family" && $0.identifier == "simulation"
        })
        #expect(blockedCoverageAudit.missingRequirements.contains {
            $0.kind == "suggested-action-kind" && $0.identifier == "inspect-simulation-summary"
        })
        #expect(blockedCoverageAudit.suggestedActions.contains {
            $0.actionKind == "add-generated-layout-failure-case"
                && $0.targetIdentifier == "simulation"
        })

        let coveragePolicyURL = postLayoutRoot.appending(path: "failure-ladder-coverage-policy.json")
        try writeJSON(coveragePolicy, to: coveragePolicyURL)
        let duplicateCoveragePolicyURL = postLayoutRoot.appending(path: "failure-ladder-duplicate-coverage-policy.json")
        try writeJSON(duplicateCoveragePolicy, to: duplicateCoveragePolicyURL)
        let drcReportURL = drcRoot.appending(
            path: ".xcircuite/runs/\(drcRunID)/reports/generated-layout-failure-ladder-generated-layout-drc-coverage-failure.json"
        )
        let lvsReportURL = lvsRoot.appending(
            path: ".xcircuite/runs/\(lvsRunID)/reports/generated-layout-failure-ladder-generated-layout-lvs-failure.json"
        )
        let pexReportURL = pexRoot.appending(
            path: ".xcircuite/runs/\(pexRunID)/reports/generated-layout-failure-ladder-generated-layout-pex-failure.json"
        )
        let postLayoutReportURL = postLayoutRoot.appending(
            path: ".xcircuite/runs/\(postLayoutRunID)/reports/generated-layout-failure-ladder-generated-layout-post-layout-failure.json"
        )
        let cliCoverageAuditJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "audit-generated-layout-failure-ladder-coverage",
            "--project-root",
            postLayoutRoot.path(percentEncoded: false),
            "--policy",
            coveragePolicyURL.path(percentEncoded: false),
            "--report",
            drcReportURL.path(percentEncoded: false),
            "--report",
            lvsReportURL.path(percentEncoded: false),
            "--report",
            pexReportURL.path(percentEncoded: false),
            "--report",
            postLayoutReportURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliCoverageAuditData = try #require(cliCoverageAuditJSON.data(using: .utf8))
        let cliCoverageAudit = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutFailureLadderCoverageAudit.self,
            from: cliCoverageAuditData
        )
        #expect(cliCoverageAudit.status == .satisfied)
        #expect(cliCoverageAudit.auditArtifact?.path == ".xcircuite/qualification/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit.json")

        let cliDuplicateCoverageAuditJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "audit-generated-layout-failure-ladder-coverage",
            "--project-root",
            postLayoutRoot.path(percentEncoded: false),
            "--policy",
            duplicateCoveragePolicyURL.path(percentEncoded: false),
            "--report",
            drcReportURL.path(percentEncoded: false),
            "--report",
            drcReportURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliDuplicateCoverageAuditData = try #require(cliDuplicateCoverageAuditJSON.data(using: .utf8))
        let cliDuplicateCoverageAudit = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutFailureLadderCoverageAudit.self,
            from: cliDuplicateCoverageAuditData
        )
        #expect(cliDuplicateCoverageAudit.status == .incomplete)
        #expect(cliDuplicateCoverageAudit.summary.uniqueReportCount == 1)
        #expect(cliDuplicateCoverageAudit.missingRequirements.contains {
            $0.kind == "duplicate-report"
                && $0.identifier == "\(drcRunID):generated-layout-drc-coverage-failure"
        })

        let coverageManifest = try XcircuitePackageStore().loadManifest(forProjectAt: postLayoutRoot)
        #expect(coverageManifest.files.contains {
            $0.artifactID == "generated-layout-failure-ladder-coverage-audit-policy"
                && $0.path == ".xcircuite/qualification/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit-policy.json"
        })
        #expect(coverageManifest.files.contains {
            $0.artifactID == "generated-layout-failure-ladder-coverage-audit"
                && $0.path == ".xcircuite/qualification/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit.json"
        })
    }

}
