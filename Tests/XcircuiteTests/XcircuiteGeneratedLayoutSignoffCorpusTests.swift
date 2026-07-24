import CircuiteFoundation
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

    @Test func generatedLayoutSignoffCorpusArtifactReferenceRejectsUnbackedVerifiedIntegrity() async throws {
        let artifactPath = ".xcircuite/runs/run-1/stages/001-drc/raw/drc-summary.json"
        #expect(
            throws: XcircuiteGeneratedLayoutSignoffCorpusReportValidationError.missingVerifiedSHA256(
                path: artifactPath
            )
        ) {
            _ = try XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactSnapshot(
                role: "stage-summary",
                artifactID: "drc-summary",
                stageID: "001-drc",
                path: artifactPath,
                kind: ArtifactKind.report.rawValue,
                format: ArtifactFormat.json.rawValue,
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
                XcircuiteGeneratedLayoutSignoffCorpusReport.ArtifactSnapshot.self,
                from: payload
            )
        }
    }

    @Test func generatedLayoutSignoffCorpusCollectsStandardArtifactRefs() async throws {
        let root = try makeTemporaryRoot("generated-layout-signoff-corpus")
        defer { removeTemporaryRoot(root) }
        let gdsRunID = "generated-layout-corpus-gds-run"
        let oasisRunID = "generated-layout-corpus-oasis-run"
        try await writeLayoutCommandRequest(root: root)
        try await writeStandardLayoutTechnology(root: root)
        let lvsExtraction = try writeStandardLVSExtractionArtifacts(to: root)
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
            artifactFormat: ArtifactFormat,
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
                            tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                            tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked)
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
                            schematicNetlistInput: .path("circuits/top.spice"),
                            topCell: "top",
                            technologyInput: .path("tech/process.json"),
                            extractionProfilePath: lvsExtraction.profilePath,
                            extractionDeckPath: lvsExtraction.deckPath,
                            processProfileID: lvsExtraction.processProfileID,
                            tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked, toolID: "native-lvs")
                        )
                    ),
                    .pex(
                        XcircuiteFlowStageExecutorSpec.PEX(
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
                            sourceNetlistInput: .path("circuits/top.spice"),
                            topCell: "top",
                            corners: [PEXCorner(id: "tt")],
                            technology: .inline(makePEXTechnology()),
                            backendSelection: PEXBackendSelection(
                                backendID: "magic",
                                executablePath: root
                                    .appending(path: "missing-magic")
                                    .path(percentEncoded: false)
                            ),
                            tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "pex-magic")
                        )
                    ),
                ]
            )
            let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)
            let result = try await runtime.run(
                request: FlowOperationRequest(
                    workspaceID: try await workspaceID(projectRoot: root),
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
                            requiredTool: pexRequirement(requiredLayoutFormat: canonicalArtifactFormat)
                        ),
                    ]
                )
            )
            #expect(result.status == FlowRunStatus.blocked)
            let pexStage = try #require(result.stages.first { $0.stageID == "009-pex" })
            #expect(pexStage.status == .blocked)
            #expect(pexStage.diagnostics.contains { $0.code == "PEX_BACKEND_UNAVAILABLE" })
            #expect(!pexStage.artifacts.contains { $0.artifactID == "pex-summary" })
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
                    family: .pex,
                    expectedStatus: .blocked
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
                    expectedRunStatus: .blocked,
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
                    expectedRunStatus: .blocked,
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
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        let collector = XcircuiteGeneratedLayoutSignoffCorpusCollector(
            ledgerLoader: workspaceStore,
            reviewBundler: reviewBundler,
            workspaceStore: workspaceStore
        )
        let firstCase = try #require(request.cases.first)

        func expectCollectFailure(
            _ invalidRequest: XcircuiteGeneratedLayoutSignoffCorpusRequest,
            expectedError: XcircuiteGeneratedLayoutSignoffCorpusError
        ) async {
            do {
                _ = try await collector.collect(request: invalidRequest, projectRoot: root)
                Issue.record("Expected generated layout signoff corpus validation to fail.")
            } catch let error as XcircuiteGeneratedLayoutSignoffCorpusError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected generated layout signoff corpus error: \(error)")
            }
        }

        var duplicateCaseRequest = request
        duplicateCaseRequest.cases.append(firstCase)
        await expectCollectFailure(
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
        await expectCollectFailure(
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
        await expectCollectFailure(
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
        await expectCollectFailure(
            emptyExpectedStagesRequest,
            expectedError: .emptyExpectedStages(caseID: "standard-gds-drc-lvs-pex-pass")
        )

        var emptyCoverageTagsCase = firstCase
        emptyCoverageTagsCase.coverageTags = []
        var emptyCoverageTagsRequest = request
        emptyCoverageTagsRequest.cases = [emptyCoverageTagsCase]
        await expectCollectFailure(
            emptyCoverageTagsRequest,
            expectedError: .emptyCoverageTags(caseID: "standard-gds-drc-lvs-pex-pass")
        )

        var emptyOracleReasonCase = firstCase
        emptyOracleReasonCase.oracleReadiness[0].reason = " "
        var emptyOracleReasonRequest = request
        emptyOracleReasonRequest.cases = [emptyOracleReasonCase]
        await expectCollectFailure(
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
        await expectCollectFailure(
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
        await expectCollectFailure(
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
        await expectCollectFailure(
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
        await expectCollectFailure(
            duplicateEvidenceRequest,
            expectedError: .duplicateOracleEvidenceReference(
                caseID: "standard-gds-drc-lvs-pex-pass",
                domain: .drc,
                role: "oracle-report",
                path: ".xcircuite/oracle/report.json"
            )
        )

        let report = try await collector.collectAndPersist(request: request, projectRoot: root)

        #expect(report.status == .passed)
        #expect(report.summary.caseCount == 2)
        #expect(report.summary.passedCaseCount == 2)
        #expect(report.summary.missingCoverageTags.isEmpty)
        #expect(report.summary.oracleReadinessDeclaredCaseCount == 2)
        #expect(report.summary.stageFamilyCounts["layout"] == 2)
        #expect(report.summary.stageFamilyCounts["drc"] == 2)
        #expect(report.summary.stageFamilyCounts["lvs"] == 2)
        #expect(report.summary.stageFamilyCounts["pex"] == 2)
        #expect(report.suiteSpecArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-suite.json")
        #expect(report.reportArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report.json")
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
        let gdsArtifact = try #require(gdsCaseResult.sourceArtifactRefs.first {
            $0.artifactID == "layout-gds"
        })
        #expect(gdsArtifact.format == .gdsii)
        #expect(!gdsArtifact.digest.hexadecimalValue.isEmpty)
        #expect(gdsArtifact.byteCount > 0)
        let oasisArtifact = try #require(oasisCaseResult.sourceArtifactRefs.first {
            $0.artifactID == "layout-oasis"
        })
        #expect(oasisArtifact.format == .oasis)
        #expect(!oasisArtifact.digest.hexadecimalValue.isEmpty)
        #expect(oasisArtifact.byteCount > 0)
        for caseResult in report.caseResults {
            let drcLayoutArtifact = try #require(caseResult.sourceArtifactRefs.first {
                $0.artifactID == "drc-layout"
            })
            #expect(drcLayoutArtifact.format == .json)
            #expect(!drcLayoutArtifact.digest.hexadecimalValue.isEmpty)
            #expect(drcLayoutArtifact.byteCount > 0)
        }
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.signoffArtifactRefs.contains { $0.artifactID == "drc-summary" }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.signoffArtifactRefs.contains { $0.artifactID == "lvs-summary" }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            caseResult.stageResults.contains {
                $0.stageID == "009-pex"
                    && $0.family == .pex
                    && $0.status == .blocked
                    && $0.statusMatches
                    && $0.diagnostics.contains { $0.code == "PEX_BACKEND_UNAVAILABLE" }
            }
        })
        #expect(report.caseResults.allSatisfy { caseResult in
            !caseResult.signoffArtifactRefs.contains { $0.artifactID == "pex-summary" }
        })
        let gdsDRCLayoutArtifact = try #require(gdsCaseResult.sourceArtifactRefs.first {
            $0.artifactID == "drc-layout"
        })
        #expect(gdsDRCLayoutArtifact.format == .json)
        #expect(!gdsDRCLayoutArtifact.digest.hexadecimalValue.isEmpty)
        #expect(gdsDRCLayoutArtifact.byteCount > 0)

        let requestURL = root.appending(path: "generated-layout-signoff-corpus-request.json")
        try await writeJSON(request, to: requestURL)
        let duplicateExpectedStageRequestURL = root.appending(
            path: "generated-layout-signoff-corpus-duplicate-stage-request.json"
        )
        try await writeJSON(duplicateExpectedStageRequest, to: duplicateExpectedStageRequestURL)
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

        let validator = XcircuiteGeneratedLayoutSignoffCorpusValidator(
            workspaceStore: workspaceStore
        )
        let strictValidation = try await validator.validate(
            report: report,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(strictValidation.status == .failed)
        #expect(strictValidation.failures.contains {
            $0.code == "oracle-readiness-not-accepted"
                && $0.family == .drc
                && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })

        let localValidationPolicy = XcircuiteGeneratedLayoutSignoffCorpusValidationPolicy(
            policyID: "local-generated-layout-signoff-corpus-policy",
            requiredCoverageTags: request.requiredCoverageTags,
            acceptedOracleReadinessStatuses: [.ready, .blocked]
        )
        let validation = try await validator.validateAndPersist(
            report: report,
            policy: localValidationPolicy,
            projectRoot: root
        )
        #expect(validation.status == .passed)
        #expect(validation.summary.missingCoverageTags.isEmpty)
        #expect(validation.summary.missingStageFamilies.isEmpty)
        #expect(validation.summary.artifactWithoutHashCount == 0)
        #expect(validation.summary.artifactWithoutByteCount == 0)
        #expect(validation.summary.acceptedOracleReadinessCaseCount == 2)
        #expect(validation.policyArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-validation-policy.json")
        #expect(validation.validationArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-validation.json")

        let policyURL = root.appending(path: "generated-layout-signoff-corpus-policy.json")
        try await writeJSON(localValidationPolicy, to: policyURL)
        let reportPath = try #require(report.reportArtifact?.path)
        let reportURL = root.appending(path: reportPath)
        let cliValidationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            reportURL.path(percentEncoded: false),
            "--policy",
            policyURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliValidationData = try #require(cliValidationJSON.data(using: .utf8))
        let cliValidation = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusValidationResult.self,
            from: cliValidationData
        )
        #expect(cliValidation.status == .passed)
        #expect(cliValidation.validationArtifact?.artifactID == "generated-layout-signoff-corpus-validation")

        func retainedLaneReport(_ domain: String) throws -> ArtifactReference {
            ArtifactReference(
                id: try ArtifactID(rawValue: "retained-\(domain)-oracle-report"),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath: "assessments/\(domain)-oracle-report.json"
                    ),
                    role: .output,
                    kind: .report,
                    format: .json
                ),
                digest: try SHA256ContentDigester().digest(data: Data(domain.utf8)),
                byteCount: 128
            )
        }
        let retainedSignoffReport = XcircuiteRetainedSignoffReport(
            schemaVersion: 4,
            kind: "retained-signoff-report",
            suiteID: "retained-signoff-test-suite",
            status: "passed",
            summary: XcircuiteRetainedSignoffReport.Summary(
                dashboardStatus: "passed",
                externalOracleStatus: "passed",
                externalOracleAssessmentStatus: "passed",
                externalOracleLaneCount: 3,
                passedExternalOracleLaneCount: 3,
                blockedExternalOracleLaneCount: 0,
                failedExternalOracleLaneCount: 0
            ),
            externalOracleResults: try ["drc", "lvs", "pex"].map { domain in
                XcircuiteRetainedSignoffReport.ExternalOracleResult(
                    domain: domain,
                    status: "passed",
                    oracleBackendID: "\(domain)-oracle",
                    assessmentPassed: true,
                    caseCount: 1,
                    passedCaseCount: 1,
                    failedCaseCount: 0,
                    passRate: 1,
                    oracleAgreementRate: 1,
                    readinessFailureCount: 0,
                    requiredProbeIDs: [],
                    report: try retainedLaneReport(domain)
                )
            },
            failures: []
        )
        let retainedSignoffReportURL = root.appending(path: "retained-signoff-report-v4.json")
        try await writeJSON(retainedSignoffReport, to: retainedSignoffReportURL)
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
        let readyWithoutEvidenceValidation = try await validator.validate(
            report: readyWithoutEvidenceReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(readyWithoutEvidenceValidation.status == .failed)
        #expect(readyWithoutEvidenceValidation.failures.contains {
            $0.code == "ready-oracle-evidence-missing"
                && $0.family == .drc
                && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })

        let readyAttachment = try await XcircuiteGeneratedLayoutReadyOracleEvidenceAttacher(
            workspaceStore: workspaceStore
        )
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
        let readyWithEvidenceValidation = try await validator.validate(
            report: readyWithEvidenceReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(readyWithEvidenceValidation.status == .passed)
        #expect(readyWithEvidenceValidation.summary.caseCount == 2)
        #expect(readyWithEvidenceValidation.summary.reportedCaseCount == 2)
        #expect(readyWithEvidenceValidation.summary.uniqueCaseCount == 2)
        #expect(readyWithEvidenceValidation.summary.duplicateCaseCount == 0)
        #expect(readyWithEvidenceValidation.summary.sourceArtifactCount == report.summary.standardLayoutArtifactCount)
        #expect(
            readyWithEvidenceValidation.summary.reportedSourceArtifactCount ==
                report.summary.standardLayoutArtifactCount
        )
        #expect(readyWithEvidenceValidation.summary.signoffArtifactCount == report.summary.signoffArtifactCount)
        #expect(
            readyWithEvidenceValidation.summary.reportedSignoffArtifactCount ==
                report.summary.signoffArtifactCount
        )
        #expect(readyWithEvidenceValidation.summary.readyOracleEvidenceRefCount == 12)
        #expect(readyWithEvidenceValidation.summary.readyOracleReadinessWithoutEvidenceCount == 0)
        var staleValidationReport = readyWithEvidenceReport
        let staleValidationCase = try #require(readyWithEvidenceReport.caseResults.first {
            $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })
        staleValidationReport.caseResults = [staleValidationCase]
        staleValidationReport.summary.caseCount = 2
        staleValidationReport.summary.passedCaseCount = 2
        staleValidationReport.summary.failedCaseCount = 0
        staleValidationReport.summary.coveredCoverageTags = request.requiredCoverageTags
        staleValidationReport.summary.missingCoverageTags = []
        staleValidationReport.summary.standardLayoutArtifactCount = 999
        staleValidationReport.summary.signoffArtifactCount = 999
        let staleValidation = try await validator.validate(
            report: staleValidationReport,
            policy: .defaultPolicy(requiredCoverageTags: request.requiredCoverageTags)
        )
        #expect(staleValidation.status == .failed)
        #expect(staleValidation.summary.caseCount == 1)
        #expect(staleValidation.summary.reportedCaseCount == 2)
        #expect(staleValidation.summary.uniqueCaseCount == 1)
        #expect(staleValidation.summary.duplicateCaseCount == 0)
        #expect(staleValidation.summary.sourceArtifactCount < staleValidation.summary.reportedSourceArtifactCount)
        #expect(staleValidation.summary.signoffArtifactCount < staleValidation.summary.reportedSignoffArtifactCount)
        #expect(staleValidation.failures.contains {
            $0.code == "case-count-mismatch"
        })
        #expect(staleValidation.failures.contains {
            $0.code == "missing-coverage-tag"
                && $0.coverageTag == "generated-layout.standard-oasis.drc-lvs-pex"
        })
        #expect(staleValidation.failures.contains {
            $0.code == "source-artifact-count-mismatch"
        })
        #expect(staleValidation.failures.contains {
            $0.code == "signoff-artifact-count-mismatch"
        })
        var duplicateValidationReport = readyWithEvidenceReport
        duplicateValidationReport.caseResults.append(staleValidationCase)
        duplicateValidationReport.summary.caseCount = duplicateValidationReport.caseResults.count
        let duplicateValidationPolicy = XcircuiteGeneratedLayoutSignoffCorpusValidationPolicy(
            minimumCaseCount: 3,
            requiredCoverageTags: request.requiredCoverageTags
        )
        let duplicateValidation = try await validator.validate(
            report: duplicateValidationReport,
            policy: duplicateValidationPolicy
        )
        #expect(duplicateValidation.status == .failed)
        #expect(duplicateValidation.summary.caseCount == 3)
        #expect(duplicateValidation.summary.reportedCaseCount == 3)
        #expect(duplicateValidation.summary.uniqueCaseCount == 2)
        #expect(duplicateValidation.summary.duplicateCaseCount == 1)
        #expect(duplicateValidation.failures.contains {
            $0.code == "duplicate-case" && $0.caseID == "standard-gds-drc-lvs-pex-pass"
        })
        #expect(duplicateValidation.failures.contains {
            $0.code == "minimum-case-count-not-met"
        })
        let promotionAssessor = XcircuiteGeneratedLayoutSignoffPromotionAssessor(
            workspaceStore: workspaceStore
        )
        let productionReadyAssessment = try await promotionAssessor
            .assess(
                request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                    promotionID: "generated-layout-signoff-promotion-assessment"
                ),
                validation: readyWithEvidenceValidation,
                retainedSignoffReport: retainedSignoffReport,
                retainedSignoffReportURL: retainedSignoffReportURL
        )
        #expect(productionReadyAssessment.status == .productionReady)

        func expectPromotionAssessmentFailure(
            _ invalidRequest: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest,
            validation: XcircuiteGeneratedLayoutSignoffCorpusValidationResult = readyWithEvidenceValidation,
            retainedReport: XcircuiteRetainedSignoffReport? = nil,
            retainedReportURL: URL? = nil,
            expectedError: XcircuiteGeneratedLayoutSignoffPromotionAssessmentError
        ) async {
            do {
                _ = try await promotionAssessor
                    .assess(
                        request: invalidRequest,
                        validation: validation,
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

        await expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: []
            ),
            expectedError: .emptyRequiredExternalOracleDomains
        )
        await expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: [.drc, .drc]
            ),
            expectedError: .duplicateRequiredExternalOracleDomain(.drc)
        )
        await expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment",
                requiredExternalOracleDomains: [.layout]
            ),
            expectedError: .unsupportedRequiredExternalOracleDomain(.layout)
        )
        await expectPromotionAssessmentFailure(
            XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                promotionID: "generated-layout-signoff-promotion-assessment"
            ),
            retainedReport: retainedSignoffReport,
            retainedReportURL: nil,
            expectedError: .retainedSignoffReportArtifactMissing
        )
        await expectPromotionAssessmentFailure(
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
                _ = try XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint(
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
                XcircuiteGeneratedLayoutSignoffPromotionAssessment.ArtifactFingerprint.self,
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
        try await writeJSON(readyWithoutEvidenceReport, to: readyWithoutEvidenceReportURL)
        let staleValidationReportURL = root.appending(path: "stale-validation-report.json")
        try await writeJSON(staleValidationReport, to: staleValidationReportURL)
        let cliStaleValidationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            staleValidationReportURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliStaleValidationData = try #require(cliStaleValidationJSON.data(using: .utf8))
        let cliStaleValidation = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusValidationResult.self,
            from: cliStaleValidationData
        )
        #expect(cliStaleValidation.status == .failed)
        #expect(cliStaleValidation.failures.contains { $0.code == "case-count-mismatch" })
        #expect(cliStaleValidation.failures.contains { $0.code == "missing-coverage-tag" })
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
        #expect(cliReadyAttachment.reportArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report-ready-oracle-evidence.json")
        #expect(cliReadyAttachment.summary.evidenceRefCount == 12)
        let cliReadyReportPath = try #require(cliReadyAttachment.reportArtifact?.path)
        let cliReadyReportURL = root.appending(path: cliReadyReportPath)
        let cliReadyValidationJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-generated-layout-signoff-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--report",
            cliReadyReportURL.path(percentEncoded: false),
            "--pretty",
        ])
        let cliReadyValidationData = try #require(cliReadyValidationJSON.data(using: .utf8))
        let cliReadyValidation = try JSONDecoder().decode(
            XcircuiteGeneratedLayoutSignoffCorpusValidationResult.self,
            from: cliReadyValidationData
        )
        #expect(cliReadyValidation.status == .passed)
        #expect(cliReadyValidation.summary.readyOracleEvidenceRefCount == 12)

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
            ],
            requiredStageFamilies: [
                .layout,
                .drc,
                .lvs,
                .pex,
            ],
            requireReadyOracleEvidence: true
        )
        let coverageAuditor = XcircuiteGeneratedLayoutSignoffCorpusCoverageAuditor(
            workspaceStore: workspaceStore
        )
        let blockedExpansionAudit = try await coverageAuditor.audit(report: report, policy: expansionAuditPolicy)
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
        let duplicateCaseAudit = try await coverageAuditor.audit(
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
        let staleSummaryAudit = try await coverageAuditor.audit(
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
        try await writeJSON(expansionAuditPolicy, to: expansionPolicyURL)
        let staleSummaryReportURL = root.appending(path: "generated-layout-stale-summary-report.json")
        try await writeJSON(staleSummaryReport, to: staleSummaryReportURL)
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
        #expect(cliCoverageAudit.auditArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit.json")

        let promotionAssessment = try await promotionAssessor
            .assessAndPersist(
                request: XcircuiteGeneratedLayoutSignoffPromotionAssessmentRequest(
                    promotionID: "generated-layout-signoff-promotion-assessment"
                ),
                validation: validation,
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
        #expect(promotionAssessment.assessmentArtifact?.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/promotion-assessment.json")

        let validationPath = try #require(validation.validationArtifact?.path)
        let validationURL = root.appending(path: validationPath)
        let cliAssessmentJSON = try await XcircuiteFlowCLICommand.run(arguments: [
            "assess-generated-layout-signoff-promotion",
            "--project-root",
            root.path(percentEncoded: false),
            "--validation",
            validationURL.path(percentEncoded: false),
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
        #expect(
            cliAssessment.assessmentArtifact?.path ==
                ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/promotion-assessment.json"
        )

        let manifest = try await workspaceStore.loadManifest()
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-suite"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-suite.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-report"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-validation-policy"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-validation-policy.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-validation"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-validation.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-ready-oracle-corpus-report"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-report-ready-oracle-evidence.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-coverage-audit-policy"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit-policy.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-corpus-coverage-audit"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/corpus-coverage-audit.json"
        })
        #expect(manifest.files.contains {
            $0.artifactID == "generated-layout-signoff-promotion-assessment"
                && $0.path == ".xcircuite/validation/generated-layout-signoff/generated-layout-signoff-ladder/promotion-assessment.json"
        })
    }

    @Test func generatedLayoutFailureLadderRetainsFirstFailingGateAndActions() async throws {
        let root = try makeTemporaryRoot("generated-layout-failure-ladder")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        let runID = "generated-layout-drc-failure-run"
        try await writeLayoutCommandRequest(root: root)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked)
                    )
                ),
            ]
        )
        let runtime = try await QualifiedToolFixtures.runtime(spec: spec, projectRoot: root)
        let result = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: root),
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
        let collector = makeGeneratedLayoutFailureLadderCollector(
            workspaceStore: workspaceStore
        )
        let report = try await collector.collectAndPersist(request: request, projectRoot: root)

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
                && $0.format == ArtifactFormat.json.rawValue
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

        let alternateReport = try await collector.collectAndPersist(
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

        let manifest = try await workspaceStore.loadManifest()
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
        let runtime = try await QualifiedToolFixtures.runtime(
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
            descriptors: [SignoffToolDescriptors.nativeDRC()],
            projectRoot: retryRoot
        )

        let retryResult = try await runtime.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: retryRoot),
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

        let retryCollector = try makeGeneratedLayoutFailureLadderCollector(projectRoot: retryRoot)
        let retryReport = try await retryCollector.collectAndPersist(
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
        try await writeLayoutCommandRequest(root: staleRoot)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked)
                    )
                ),
            ]
        )
        let staleResult = try await QualifiedToolFixtures.runtime(
            spec: spec,
            projectRoot: staleRoot
        ).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: staleRoot),
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

        let staleCollector = try makeGeneratedLayoutFailureLadderCollector(projectRoot: staleRoot)
        do {
            _ = try await staleCollector.collectAndPersist(
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
            Issue.record("Tampered retained artifacts must stop failure-ladder collection.")
        } catch let error as FlowRunLedgerPersistenceError {
            guard case .artifactIntegrityFailure(let path, let reason) = error else {
                Issue.record("Expected artifactIntegrityFailure, got \(error).")
                return
            }
            #expect(path == ".xcircuite/runs/\(staleRunID)/stages/007-drc/raw/drc-summary.json")
            #expect(reason.contains("byteCountMismatch"))
            #expect(reason.contains("digestMismatch"))
        }
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
        try await writeLayoutCommandRequest(root: drcRoot)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked)
                    )
                ),
            ]
        )
        let drcRunID = "generated-layout-drc-coverage-failure-run"
        let drcResult = try await QualifiedToolFixtures.runtime(
            spec: drcSpec,
            projectRoot: drcRoot
        ).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: drcRoot),
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
        let drcCollector = try makeGeneratedLayoutFailureLadderCollector(projectRoot: drcRoot)
        let drcReport = try await drcCollector.collectAndPersist(
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
        try await writeLayoutCommandRequest(root: lvsRoot)
        try await writeStandardLayoutTechnology(root: lvsRoot)
        let lvsExtraction = try writeStandardLVSExtractionArtifacts(to: lvsRoot)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
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
                        schematicNetlistInput: .path("circuits/missing.spice"),
                        topCell: "top",
                        technologyInput: .path("tech/process.json"),
                        extractionProfilePath: lvsExtraction.profilePath,
                        extractionDeckPath: lvsExtraction.deckPath,
                        processProfileID: lvsExtraction.processProfileID,
                        tool: QualifiedToolFixtures.toolSpec(level: .corpusChecked, toolID: "native-lvs")
                    )
                ),
            ]
        )
        let lvsRunID = "generated-layout-lvs-failure-run"
        let lvsResult = try await QualifiedToolFixtures.runtime(
            spec: lvsSpec,
            projectRoot: lvsRoot
        ).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: lvsRoot),
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
        let lvsCollector = try makeGeneratedLayoutFailureLadderCollector(projectRoot: lvsRoot)
        let lvsReport = try await lvsCollector.collectAndPersist(
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
        try await writeLayoutCommandRequest(root: pexRoot)
        try await writeStandardLayoutTechnology(root: pexRoot)
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
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "layout-command")
                    )
                ),
                .pex(
                    XcircuiteFlowStageExecutorSpec.PEX(
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
                        sourceNetlistInput: .path("circuits/missing.spice"),
                        topCell: "top",
                        corners: [PEXCorner(id: "tt")],
                        technology: .inline(makePEXTechnology()),
                        backendSelection: PEXBackendSelection(backendID: "magic"),
                        tool: QualifiedToolFixtures.toolSpec(level: .smokeChecked, toolID: "pex-magic")
                    )
                ),
            ]
        )
        let pexRunID = "generated-layout-pex-failure-run"
        let pexResult = try await QualifiedToolFixtures.runtime(
            spec: pexSpec,
            projectRoot: pexRoot
        ).run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: pexRoot),
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
                        requiredTool: pexRequirement()
                    ),
                ]
            )
        )
        #expect(pexResult.status == .failed)
        let pexCollector = try makeGeneratedLayoutFailureLadderCollector(projectRoot: pexRoot)
        let pexReport = try await pexCollector.collectAndPersist(
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
        let postLayoutStore = try XcircuiteWorkspaceStore(projectRoot: postLayoutRoot)
        let postLayoutOrchestrator = DefaultFlowOrchestrator(
            infrastructure: postLayoutStore,
            ledgerPersistence: postLayoutStore,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "XcircuiteTests",
                version: "1.0.0"
            ),
            progressStore: FlowRunProgressStore(persistence: postLayoutStore)
        )
        let postLayoutResult = try await postLayoutOrchestrator.run(
            request: FlowOperationRequest(
                workspaceID: try await workspaceID(projectRoot: postLayoutRoot),
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
        let postLayoutCollector = makeGeneratedLayoutFailureLadderCollector(
            workspaceStore: postLayoutStore
        )
        let postLayoutReport = try await postLayoutCollector.collectAndPersist(
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
                && $0.format == ArtifactFormat.json.rawValue
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
        let failureCoverageAuditor = XcircuiteGeneratedLayoutFailureLadderCoverageAuditor(
            workspaceStore: postLayoutStore
        )
        let coverageAudit = try failureCoverageAuditor.audit(
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
        let duplicateCoverageAudit = try failureCoverageAuditor.audit(
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
        let blockedCoverageAudit = try failureCoverageAuditor.audit(
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
        try await writeJSON(coveragePolicy, to: coveragePolicyURL)
        let duplicateCoveragePolicyURL = postLayoutRoot.appending(path: "failure-ladder-duplicate-coverage-policy.json")
        try await writeJSON(duplicateCoveragePolicy, to: duplicateCoveragePolicyURL)
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
        #expect(cliCoverageAudit.auditArtifact?.path == ".xcircuite/assessments/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit.json")

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

        let coverageManifest = try await postLayoutStore.loadManifest()
        #expect(coverageManifest.files.contains {
            $0.artifactID == "generated-layout-failure-ladder-coverage-audit-policy"
                && $0.path == ".xcircuite/assessments/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit-policy.json"
        })
        #expect(coverageManifest.files.contains {
            $0.artifactID == "generated-layout-failure-ladder-coverage-audit"
                && $0.path == ".xcircuite/assessments/generated-layout-failure-ladder/generated-layout-failure-ladder-local-coverage/failure-ladder-coverage-audit.json"
        })
    }

    private func makeGeneratedLayoutFailureLadderCollector(
        projectRoot: URL
    ) throws -> XcircuiteGeneratedLayoutFailureLadderCollector {
        makeGeneratedLayoutFailureLadderCollector(
            workspaceStore: try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        )
    }

    private func makeGeneratedLayoutFailureLadderCollector(
        workspaceStore: XcircuiteWorkspaceStore
    ) -> XcircuiteGeneratedLayoutFailureLadderCollector {
        let reviewBundler = DefaultFlowRunReviewBundler(
            loader: workspaceStore,
            persistence: workspaceStore
        )
        return XcircuiteGeneratedLayoutFailureLadderCollector(
            reviewBundler: reviewBundler,
            workspaceStore: workspaceStore
        )
    }

    private func workspaceID(projectRoot: URL) async throws -> FlowWorkspaceID {
        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        try await store.createWorkspace()
        let manifest = try await store.loadManifest()
        return try FlowWorkspaceID(rawValue: manifest.identity.projectID)
    }
}
