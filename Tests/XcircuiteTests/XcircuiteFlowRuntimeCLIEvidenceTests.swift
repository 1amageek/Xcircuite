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
import XcircuitePackage

extension XcircuiteFlowRuntimeTests {
    @Test func resumeRunCLIUsesRuntimeConfig() async throws {
        let root = try makeTemporaryRoot("runtime-cli-resume")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        let specURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: QualifiedToolFixtures.toolSpec(level: .productionEligible)
                        )
                    ),
                ]
            ),
            root: root
        )
        let runSpecURL = try writeRunSpec(
            XcircuiteFlowRunSpec(
                runID: "run-1",
                intent: "Run DRC with approval",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(),
                        requiresApproval: true
                    ),
                ]
            ),
            root: root
        )

        let initialJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                runSpecURL.path(percentEncoded: false),
                "--runtime-config",
                specURL.path(percentEncoded: false),
            ]
        )
        let initialData = try #require(initialJSON.data(using: .utf8))
        let initial = try JSONDecoder().decode(FlowRunResult.self, from: initialData)
        #expect(initial.status == .blocked)

        _ = try DefaultFlowGateApprovalRecorder().recordApproval(
            FlowGateApprovalRequest(
                projectRoot: root,
                runID: "run-1",
                stageID: "007-drc",
                verdict: .approved,
                reviewer: "reviewer-1"
            )
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "resume-run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--runtime-config",
                specURL.path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResumeResult.self, from: data)

        #expect(result.result.status == .succeeded)
        #expect(result.summary.status == .succeeded)
        #expect(result.summary.nextActions.map(\.kind) == ["archiveOrContinue"])
    }

    @Test func runCLIUsesQualifiedEvidenceFromRuntimeConfig() async throws {
        let root = try makeTemporaryRoot("runtime-cli-qualified-evidence")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        let specURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: XcircuiteFlowToolSpec(
                                qualificationLevel: .corpusChecked,
                                healthStatus: .passed,
                                evidence: [
                                    ToolEvidence(
                                        evidenceID: "drc-corpus-2026-06-18",
                                        kind: .corpus,
                                        qualification: ToolEvidenceQualificationSummary(
                                            qualified: true,
                                            policyID: "strict",
                                            observedMetrics: [
                                                "durationBudgetPassRate": 1,
                                                "passRate": 1,
                                            ],
                                            observedCounts: ["caseCount": 5]
                                        )
                                    ),
                                ]
                            )
                        )
                    ),
                ]
            ),
            root: root
        )
        let runSpecURL = try writeRunSpec(
            XcircuiteFlowRunSpec(
                runID: "run-1",
                intent: "Run DRC with qualified corpus evidence",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredQualifiedEvidenceKinds: [.corpus])
                    ),
                ]
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                runSpecURL.path(percentEncoded: false),
                "--runtime-config",
                specURL.path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResult.self, from: data)

        #expect(result.status == .succeeded)
        let toolchain = try readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(record.selectedToolID == "native-drc")
        #expect(record.selectedDecision?.status == .eligible)
        let evidence = try #require(record.selectedHealth?.evidence.first)
        #expect(evidence.evidenceID == "drc-corpus-2026-06-18")
        #expect(evidence.kind == .corpus)
        #expect(evidence.qualification?.qualified == true)
        #expect(evidence.qualification?.observedMetrics["passRate"] == 1)
        #expect(evidence.qualification?.observedCounts["caseCount"] == 5)
    }

    @Test func runCLIAcceptsQualifiedEvidenceFixtureContracts() async throws {
        let root = try makeTemporaryRoot("runtime-cli-qualified-fixture")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                fixtureURL("qualified-evidence-run.json").path(percentEncoded: false),
                "--runtime-config",
                fixtureURL("qualified-evidence-runtime.json").path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResult.self, from: data)

        #expect(result.status == .succeeded)
        let toolchain = try readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(record.requiredTool?.maximumEvidenceAgeSeconds == 4_102_444_800)
        #expect(record.selectedToolID == "native-drc")
        #expect(record.selectedDecision?.status == .eligible)
        let evidence = try #require(record.selectedHealth?.evidence.first)
        #expect(evidence.evidenceID == "drc-corpus-2026-06-18")
        #expect(evidence.qualification?.policyID == "strict")
        #expect(evidence.qualification?.qualified == true)
        #expect(evidence.qualification?.failureCodes.isEmpty == true)
        #expect(evidence.checkedAt?.timeIntervalSince1970 == 1_781_740_800)
    }

    @Test func runCLIBlocksQualifiedSignoffFixtureWhenPEXIsMock() async throws {
        let root = try makeTemporaryRoot("runtime-cli-qualified-signoff-fixture")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        _ = try writeNetlist(matchingLVSNetlist(), name: "layout.spice", root: root)
        _ = try writeNetlist(matchingLVSNetlist(), name: "schematic.spice", root: root)
        _ = try writeNetlist("mock gds payload\n", name: "layout.gds", root: root)
        _ = try writeNetlist(".subckt TOP in out vdd vss\n.ends TOP\n", name: "source.cir", root: root)
        let updatedRuntimeURL = root.appending(path: "qualified-signoff-runtime-with-evidence.json")

        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "attach-evidence",
                "--runtime-config",
                fixtureURL("qualified-signoff-runtime.json").path(percentEncoded: false),
                "--stage-id",
                "007-drc",
                "--evidence",
                fixtureURL("drc-tool-evidence-export.json").path(percentEncoded: false),
                "--out",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )
        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "attach-evidence",
                "--runtime-config",
                updatedRuntimeURL.path(percentEncoded: false),
                "--stage-id",
                "008-lvs",
                "--evidence",
                fixtureURL("lvs-tool-evidence-export.json").path(percentEncoded: false),
                "--out",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )
        _ = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "attach-evidence",
                "--runtime-config",
                updatedRuntimeURL.path(percentEncoded: false),
                "--stage-id",
                "009-pex",
                "--evidence",
                fixtureURL("pex-tool-evidence-export.json").path(percentEncoded: false),
                "--out",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )

        let validationJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "validate",
                "--run-spec",
                fixtureURL("qualified-signoff-run.json").path(percentEncoded: false),
                "--runtime-config",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )
        let validationData = try #require(validationJSON.data(using: .utf8))
        let validation = try JSONDecoder().decode(ValidationOutput.self, from: validationData)
        #expect(validation.status == "valid")
        #expect(validation.runStageCount == 3)
        #expect(validation.runtimeExecutorCount == 3)

        let runJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                fixtureURL("qualified-signoff-run.json").path(percentEncoded: false),
                "--runtime-config",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )
        let runData = try #require(runJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResult.self, from: runData)

        #expect(result.status == .blocked)
        let blockedStage = try #require(result.stages.first { $0.stageID == "009-pex" })
        #expect(blockedStage.status == .blocked)
        #expect(blockedStage.gates.contains(where: { $0.gateID == "tool-trust" && $0.status == .failed }))
        let toolchain = try readToolchainManifest(in: root, runID: "signoff-run-1")
        #expect(toolchain.stages.count == 3)
        let drcRecord = try #require(toolchain.stages.first { $0.stageID == "007-drc" })
        let lvsRecord = try #require(toolchain.stages.first { $0.stageID == "008-lvs" })
        let pexRecord = try #require(toolchain.stages.first { $0.stageID == "009-pex" })
        #expect(drcRecord.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(lvsRecord.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(pexRecord.requiredTool?.requiredQualifiedEvidenceKinds == [.corpus])
        #expect(drcRecord.selectedToolID == "native-drc")
        #expect(lvsRecord.selectedToolID == "native-lvs")
        #expect(pexRecord.selectedToolID == nil)
        #expect(drcRecord.selectedDecision?.status == .eligible)
        #expect(lvsRecord.selectedDecision?.status == .eligible)
        #expect(pexRecord.evaluations.contains {
            $0.descriptor.toolID == "mock-pex"
                && $0.decision.status == .rejected
                && $0.decision.diagnostics.contains { $0.code == "INSUFFICIENT_TRUST_LEVEL" }
        })
        let drcEvidence = try #require(drcRecord.selectedHealth?.evidence.first)
        let lvsEvidence = try #require(lvsRecord.selectedHealth?.evidence.first)
        #expect(drcEvidence.evidenceID == "drc-corpus-2026-06-18")
        #expect(lvsEvidence.evidenceID == "lvs-corpus-2026-06-18")
        #expect(drcEvidence.qualification?.qualified == true)
        #expect(lvsEvidence.qualification?.qualified == true)
        #expect(drcEvidence.artifact?.path == "qualification/drc-corpus-report.json")
        #expect(lvsEvidence.artifact?.path == "qualification/lvs-corpus-report.json")
        #expect(drcEvidence.qualification?.observedCounts["coveredRequiredCoverageTagCount"] == 32)
        #expect(lvsEvidence.qualification?.observedCounts["coveredRequiredCoverageTagCount"] == 32)
    }

    @Test func attachEvidenceCLIProducesRunnableQualifiedRuntimeConfig() async throws {
        let root = try makeTemporaryRoot("runtime-cli-attach-evidence")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        let initialRuntimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: XcircuiteFlowToolSpec(
                                qualificationLevel: .corpusChecked,
                                healthStatus: .passed
                            )
                        )
                    ),
                ]
            ),
            root: root
        )
        let updatedRuntimeURL = root.appending(path: "runtime-with-evidence.json")

        let attachJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "attach-evidence",
                "--runtime-config",
                initialRuntimeURL.path(percentEncoded: false),
                "--stage-id",
                "007-drc",
                "--evidence",
                fixtureURL("drc-tool-evidence-export.json").path(percentEncoded: false),
                "--out",
                updatedRuntimeURL.path(percentEncoded: false),
                "--pretty",
            ]
        )
        let attachData = try #require(attachJSON.data(using: .utf8))
        let attachOutput = try JSONDecoder().decode(EvidenceAttachmentOutput.self, from: attachData)

        #expect(attachOutput.status == "attached")
        #expect(attachOutput.stageID == "007-drc")
        #expect(attachOutput.evidenceID == "drc-corpus-2026-06-18")
        #expect(attachOutput.evidenceKind == "corpus")
        #expect(attachOutput.outputPath == updatedRuntimeURL.path(percentEncoded: false))

        let updatedSpec = try XcircuiteFlowRuntimeSpec.load(from: updatedRuntimeURL)
        guard case .nativeDRC(let drcSpec) = try #require(updatedSpec.executors.first) else {
            Issue.record("Expected a DRC executor")
            return
        }
        let attachedEvidence = try #require(drcSpec.tool.evidence.first)
        #expect(attachedEvidence.evidenceID == "drc-corpus-2026-06-18")
        #expect(attachedEvidence.artifact?.sha256 == "1111111111111111111111111111111111111111111111111111111111111111")
        #expect(attachedEvidence.qualification?.observedMetrics["oracleAgreementRate"] == 1)

        let runJSON = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                fixtureURL("qualified-evidence-run.json").path(percentEncoded: false),
                "--runtime-config",
                updatedRuntimeURL.path(percentEncoded: false),
            ]
        )
        let runData = try #require(runJSON.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResult.self, from: runData)

        #expect(result.status == .succeeded)
        let toolchain = try readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        let evidence = try #require(record.selectedHealth?.evidence.first)
        #expect(evidence.evidenceID == "drc-corpus-2026-06-18")
        #expect(evidence.artifact?.path == "qualification/drc-corpus-report.json")
        #expect(evidence.artifact?.sha256 == "1111111111111111111111111111111111111111111111111111111111111111")
        #expect(evidence.qualification?.qualified == true)
    }

    @Test func evidenceExportRejectsUnsupportedSchemaVersion() throws {
        let root = try makeTemporaryRoot("runtime-evidence-schema")
        defer { removeTemporaryRoot(root) }
        let exportURL = root.appending(path: "evidence.json")
        try writeJSON(
            XcircuiteFlowEvidenceExport(
                schemaVersion: 2,
                toolEvidence: ToolEvidence(evidenceID: "drc-corpus", kind: .corpus)
            ),
            to: exportURL
        )

        do {
            _ = try XcircuiteFlowEvidenceExport.load(from: exportURL)
            Issue.record("Expected unsupported schema version error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .unsupportedEvidenceExportSchemaVersion(2))
        } catch {
            throw error
        }
    }

    @Test func attachEvidenceCLIRejectsFailedEvidenceExportStatus() async throws {
        let root = try makeTemporaryRoot("runtime-evidence-failed-status")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: XcircuiteFlowToolSpec(
                                qualificationLevel: .corpusChecked,
                                healthStatus: .passed
                            )
                        )
                    ),
                ]
            ),
            root: root
        )
        let evidenceURL = root.appending(path: "failed-evidence.json")
        try writeJSON(
            XcircuiteFlowEvidenceExport(
                status: "failed",
                reportPath: "qualification/drc-corpus-report.json",
                reportSHA256: String(repeating: "1", count: 64),
                toolEvidence: ToolEvidence(
                    evidenceID: "drc-corpus-failed",
                    kind: .corpus,
                    artifact: XcircuiteFileReference(
                        path: "qualification/drc-corpus-report.json",
                        kind: .report,
                        format: .json,
                        sha256: String(repeating: "1", count: 64)
                    ),
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: false,
                        policyID: "strict",
                        failureCodes: ["case-failed"]
                    )
                )
            ),
            to: evidenceURL
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "attach-evidence",
                    "--runtime-config",
                    runtimeURL.path(percentEncoded: false),
                    "--stage-id",
                    "007-drc",
                    "--evidence",
                    evidenceURL.path(percentEncoded: false),
                ]
            )
            Issue.record("Expected failed evidence export status to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidEvidenceExport(
                field: "status",
                reason: "status must be passed or qualified before it can be attached as runtime trust evidence"
            ))
        } catch {
            throw error
        }
    }

    @Test func attachEvidenceCLIRejectsMismatchedEvidenceReportDigest() async throws {
        let root = try makeTemporaryRoot("runtime-evidence-digest-mismatch")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: XcircuiteFlowToolSpec(
                                qualificationLevel: .corpusChecked,
                                healthStatus: .passed
                            )
                        )
                    ),
                ]
            ),
            root: root
        )
        let evidenceURL = root.appending(path: "mismatched-evidence.json")
        try writeJSON(
            XcircuiteFlowEvidenceExport(
                status: "passed",
                reportPath: "qualification/drc-corpus-report.json",
                reportSHA256: String(repeating: "2", count: 64),
                toolEvidence: ToolEvidence(
                    evidenceID: "drc-corpus-mismatch",
                    kind: .corpus,
                    artifact: XcircuiteFileReference(
                        path: "qualification/drc-corpus-report.json",
                        kind: .report,
                        format: .json,
                        sha256: String(repeating: "1", count: 64)
                    ),
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: true,
                        policyID: "strict",
                        observedMetrics: ["passRate": 1],
                        observedCounts: ["caseCount": 24]
                    )
                )
            ),
            to: evidenceURL
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "attach-evidence",
                    "--runtime-config",
                    runtimeURL.path(percentEncoded: false),
                    "--stage-id",
                    "007-drc",
                    "--evidence",
                    evidenceURL.path(percentEncoded: false),
                ]
            )
            Issue.record("Expected mismatched evidence report digest to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidEvidenceExport(
                field: "reportSHA256",
                reason: "reportSHA256 must match toolEvidence.artifact.sha256"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecValidationRejectsEmptyExecutorList() throws {
        let spec = XcircuiteFlowRuntimeSpec(executors: [])

        do {
            try spec.validate()
            Issue.record("Expected empty executor list error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .emptyExecutorList)
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecValidationRejectsUnqualifiedCorpusEvidence() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout.json",
                        topCell: "TOP",
                        tool: XcircuiteFlowToolSpec(
                            qualificationLevel: .productionEligible,
                            evidence: [
                                ToolEvidence(
                                    evidenceID: "drc-corpus-unqualified",
                                    kind: .corpus,
                                    qualification: ToolEvidenceQualificationSummary(
                                        qualified: false,
                                        policyID: "strict",
                                        failureCodes: ["case-failed"]
                                    )
                                ),
                            ]
                        )
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected unqualified corpus evidence to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolEvidence(
                stageID: "007-drc",
                evidenceID: "drc-corpus-unqualified",
                reason: "corpus evidence must be qualified before runtime attachment"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecValidationRejectsBareQualifiedCorpusEvidence() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout.json",
                        topCell: "TOP",
                        tool: XcircuiteFlowToolSpec(
                            qualificationLevel: .corpusChecked,
                            evidence: [
                                ToolEvidence(
                                    evidenceID: "drc-corpus-bare",
                                    kind: .corpus,
                                    qualification: ToolEvidenceQualificationSummary(qualified: true)
                                ),
                            ]
                        )
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected bare qualified corpus evidence to be rejected")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .invalidToolEvidence(
                stageID: "007-drc",
                evidenceID: "drc-corpus-bare",
                reason: "qualified evidence must include artifact, policyID, observedMetrics, or observedCounts"
            ))
        } catch {
            throw error
        }
    }

    @Test func runtimeSpecValidationRejectsDuplicateExecutorStageIDs() throws {
        let spec = XcircuiteFlowRuntimeSpec(
            executors: [
                .nativeDRC(
                    XcircuiteFlowStageExecutorSpec.NativeDRC(
                        stageID: "007-drc",
                        layoutPath: "layout.json",
                        topCell: "TOP"
                    )
                ),
                .coreSpiceSimulation(
                    XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                        stageID: "007-drc",
                        netlistPath: "osc.spice"
                    )
                ),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected duplicate stage ID error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .duplicateExecutorStageID("007-drc"))
        } catch {
            throw error
        }
    }

    @Test func attachEvidenceCLIRejectsDuplicateExecutorStageIDs() async throws {
        let root = try makeTemporaryRoot("runtime-cli-attach-duplicate")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP"
                        )
                    ),
                    .coreSpiceSimulation(
                        XcircuiteFlowStageExecutorSpec.CoreSpiceSimulation(
                            stageID: "007-drc",
                            netlistPath: "osc.spice"
                        )
                    ),
                ]
            ),
            root: root
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "attach-evidence",
                    "--runtime-config",
                    runtimeURL.path(percentEncoded: false),
                    "--stage-id",
                    "007-drc",
                    "--evidence",
                    fixtureURL("drc-tool-evidence-export.json").path(percentEncoded: false),
                ]
            )
            Issue.record("Expected duplicate stage ID error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .duplicateExecutorStageID("007-drc"))
        } catch {
            throw error
        }
    }

    @Test func runSpecValidationRejectsEmptyStageList() throws {
        let spec = XcircuiteFlowRunSpec(
            runID: "run-1",
            intent: "Run nothing",
            stages: []
        )

        do {
            try spec.validate()
            Issue.record("Expected empty run stage list error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .emptyRunStageList)
        } catch {
            throw error
        }
    }

    @Test func runSpecValidationRejectsDuplicateStageIDs() throws {
        let spec = XcircuiteFlowRunSpec(
            runID: "run-1",
            intent: "Run duplicate stages",
            stages: [
                FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                FlowStageDefinition(stageID: "007-drc", displayName: "DRC again"),
            ]
        )

        do {
            try spec.validate()
            Issue.record("Expected duplicate run stage ID error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .duplicateRunStageID("007-drc"))
        } catch {
            throw error
        }
    }

    @Test func validateCLIReportsRunRuntimeAndCoverage() async throws {
        let root = try makeTemporaryRoot("runtime-cli-validate")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP"
                        )
                    ),
                ]
            ),
            root: root
        )
        let runURL = try writeRunSpec(
            XcircuiteFlowRunSpec(
                runID: "run-1",
                intent: "Validate DRC run",
                stages: [FlowStageDefinition(stageID: "007-drc", displayName: "DRC")]
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "validate",
                "--run-spec",
                runURL.path(percentEncoded: false),
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let output = try JSONDecoder().decode(ValidationOutput.self, from: data)

        #expect(output.status == "valid")
        #expect(output.validated == ["runSpec", "runtimeConfig", "coverage"])
        #expect(output.runSpecPath == runURL.path(percentEncoded: false))
        #expect(output.runtimeConfigPath == runtimeURL.path(percentEncoded: false))
        #expect(output.runStageCount == 1)
        #expect(output.runtimeExecutorCount == 1)
    }

    @Test func validateCLIRejectsMissingRuntimeExecutorForRunStage() async throws {
        let root = try makeTemporaryRoot("runtime-cli-validate-missing")
        defer { removeTemporaryRoot(root) }
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP"
                        )
                    ),
                ]
            ),
            root: root
        )
        let runURL = try writeRunSpec(
            XcircuiteFlowRunSpec(
                runID: "run-1",
                intent: "Validate missing simulation executor",
                stages: [
                    FlowStageDefinition(stageID: "007-drc", displayName: "DRC"),
                    FlowStageDefinition(stageID: "010-sim", displayName: "Simulation"),
                ]
            ),
            root: root
        )

        do {
            _ = try await XcircuiteFlowCLICommand.run(
                arguments: [
                    "validate",
                    "--run-spec",
                    runURL.path(percentEncoded: false),
                    "--runtime-config",
                    runtimeURL.path(percentEncoded: false),
                ]
            )
            Issue.record("Expected missing runtime executor error")
        } catch let error as XcircuiteFlowRuntimeSpecError {
            #expect(error == .missingRuntimeExecutorForRunStage("010-sim"))
        } catch {
            throw error
        }
    }

    @Test func runCLIBlocksMissingQualifiedEvidenceBeforeExecution() async throws {
        let root = try makeTemporaryRoot("runtime-cli-missing-qualified-evidence")
        defer { removeTemporaryRoot(root) }
        _ = try writeLayout(cleanLayout(), root: root)
        let runtimeURL = try writeRuntimeSpec(
            XcircuiteFlowRuntimeSpec(
                executors: [
                    .nativeDRC(
                        XcircuiteFlowStageExecutorSpec.NativeDRC(
                            stageID: "007-drc",
                            layoutPath: "layout.json",
                            topCell: "TOP",
                            tool: XcircuiteFlowToolSpec(
                                qualificationLevel: .corpusChecked,
                                healthStatus: .passed
                            )
                        )
                    ),
                ]
            ),
            root: root
        )
        let runURL = try writeRunSpec(
            XcircuiteFlowRunSpec(
                runID: "run-1",
                intent: "Require qualified DRC corpus evidence",
                stages: [
                    FlowStageDefinition(
                        stageID: "007-drc",
                        displayName: "DRC",
                        requiredTool: drcRequirement(requiredQualifiedEvidenceKinds: [.corpus])
                    ),
                ]
            ),
            root: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "run",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-spec",
                runURL.path(percentEncoded: false),
                "--runtime-config",
                runtimeURL.path(percentEncoded: false),
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(FlowRunResult.self, from: data)

        #expect(result.status == .blocked)
        let stage = try #require(result.stages.first)
        #expect(stage.status == .blocked)
        #expect(stage.gates.contains {
            $0.gateID == "tool-trust"
                && $0.status == .failed
                && $0.diagnostics.contains { $0.code == "MISSING_REQUIRED_EVIDENCE" }
        })

        let toolchain = try readToolchainManifest(in: root, runID: "run-1")
        let record = try #require(toolchain.stages.first)
        #expect(record.selectedToolID == nil)
        #expect(record.evaluations.first?.decision.status == .rejected)
        #expect(record.evaluations.first?.decision.diagnostics.contains {
            $0.code == "MISSING_REQUIRED_EVIDENCE"
        } == true)
    }

}
