import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite platform capability readiness")
struct XcircuitePlatformCapabilityReadinessTests {
    @Test func assessorBuildsMilestoneReadinessFromActionDomains() throws {
        let report = try XcircuitePlatformCapabilityReadinessAssessor().assess(
            runID: "capability-run",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        #expect(report.schemaVersion == 2)
        #expect(report.reportID == "xcircuite-platform-capability-readiness")
        #expect(report.actionDomainRunID == "capability-run")
        #expect(report.summary.domainCount >= 5)
        #expect(report.summary.operationCount > 0)
        #expect(report.summary.testEvidenceCount >= 8)
        #expect(report.summary.validTestEvidenceCount == report.summary.testEvidenceCount)
        #expect(report.summary.invalidTestEvidenceCount == 0)
        #expect(report.summary.testEvidenceDiagnosticCount == 0)
        #expect(report.summary.milestoneCount == 5)
        #expect(report.status == .passed)
        #expect(report.summary.failedCount == 0)
        #expect(report.summary.passedCount == 5)
        #expect(report.summary.partialCount == 0)
        #expect(report.milestones.map(\.milestoneID) == [
            "standalone-local-signoff",
            "agent-operable-design-loop",
            "human-review-audit",
            "standard-format-grounding",
            "post-layout-improvement-loop",
        ])

        let standalone = try #require(report.milestones.first { $0.milestoneID == "standalone-local-signoff" })
        #expect(standalone.status == .passed)
        #expect(standalone.requiredDomains.missing.isEmpty)
        #expect(standalone.requiredOperations.missing.isEmpty)
        #expect(standalone.requiredArtifacts.missing.isEmpty)
        #expect(standalone.requiredVerificationGates.missing.isEmpty)
        #expect(standalone.requiredTestEvidence.missing.isEmpty)
        #expect(standalone.requiredOperations.present.contains("simulation.run-analysis"))
        #expect(standalone.requiredArtifacts.present.contains("simulation-summary"))
        #expect(standalone.requiredVerificationGates.present.contains("simulation-summary"))

        let agentLoop = try #require(report.milestones.first { $0.milestoneID == "agent-operable-design-loop" })
        #expect(agentLoop.status == .passed)
        #expect(agentLoop.requiredOperations.present.contains("simulation.export-metric-report"))
        #expect(agentLoop.requiredArtifacts.present.contains("simulation-metric-report"))

        let humanReview = try #require(report.milestones.first { $0.milestoneID == "human-review-audit" })
        #expect(humanReview.status == .passed)
        #expect(humanReview.requiredOperations.missing.isEmpty)
        #expect(humanReview.requiredArtifacts.missing.isEmpty)
        #expect(humanReview.requiredVerificationGates.missing.isEmpty)
        #expect(humanReview.plannedOperations.isEmpty)
        #expect(!humanReview.nextActions.contains("implement-operation:lvs.waiver-review"))

        let standardFormats = try #require(report.milestones.first { $0.milestoneID == "standard-format-grounding" })
        #expect(standardFormats.status == .passed)
        #expect(standardFormats.requiredOperations.present.contains("simulation.import-spice"))
        #expect(standardFormats.requiredArtifacts.present.contains("simulation-netlist"))
        #expect(standardFormats.requiredOperations.present.contains("drc.import-foundry-rule-seed"))
        #expect(standardFormats.requiredArtifacts.present.contains("drc-foundry-rule-import-report"))
        #expect(standardFormats.requiredTestEvidence.present.contains("drc-foundry-rule-import-agent-envelope"))
        #expect(standardFormats.requiredTestEvidence.present.contains("xci-platform-readiness-contract"))
        #expect(standardFormats.partialOperations.isEmpty)
        #expect(standardFormats.nextActions.isEmpty)

        let postLayout = try #require(report.milestones.first { $0.milestoneID == "post-layout-improvement-loop" })
        #expect(postLayout.status == .passed)
        #expect(postLayout.requiredOperations.missing.isEmpty)
        #expect(postLayout.requiredArtifacts.missing.isEmpty)
        #expect(postLayout.requiredVerificationGates.missing.isEmpty)
        #expect(postLayout.requiredOperations.present.contains("simulation.compare-post-layout"))
        #expect(postLayout.requiredArtifacts.present.contains("post-layout-comparison"))
        #expect(postLayout.plannedOperations.isEmpty)
        #expect(!postLayout.nextActions.contains("implement-operation:pex.metric-recovery-objective"))

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(XcircuitePlatformCapabilityReadinessReport.self, from: data)
        #expect(decoded == report)
    }

    @Test func platformCapabilityCLIEmitsDecodableReadinessReport() async throws {
        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "inspect-platform-capabilities",
            "--run-id",
            "cli-capabilities",
            "--generated-at",
            "2026-06-28T01:02:03Z",
        ])
        let report = try JSONDecoder().decode(
            XcircuitePlatformCapabilityReadinessReport.self,
            from: Data(json.utf8)
        )

        #expect(report.actionDomainRunID == "cli-capabilities")
        #expect(report.actionDomainGeneratedAt == "2026-06-28T01:02:03Z")
        #expect(report.summary.milestoneCount == 5)
        #expect(report.status == .passed)
        #expect(report.summary.failedCount == 0)
        #expect(report.summary.passedCount == 5)
        #expect(report.summary.partialCount == 0)
        #expect(report.summary.testEvidenceCount >= 8)
        #expect(report.summary.validTestEvidenceCount == report.summary.testEvidenceCount)
        #expect(report.summary.invalidTestEvidenceCount == 0)
        #expect(report.summary.testEvidenceDiagnosticCount == 0)
        #expect(json.contains(#""validTestEvidenceCount""#))
        #expect(json.contains(#""invalidTestEvidenceCount""#))
        #expect(report.testEvidence.contains {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
                && $0.packagePath == "DRCEngine"
                && $0.testFilter == "DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope"
        })
        #expect(report.nextActions.isEmpty)
        #expect(report.milestones.allSatisfy { !$0.requiredOperations.required.isEmpty })
        #expect(report.milestones.allSatisfy { !$0.requiredTestEvidence.required.isEmpty })
    }

    @Test func assessorKeepsMilestonePartialWhenRequiredOperationIsPartial() throws {
        let snapshot = try snapshotWithOperation(
            "drc.import-foundry-rule-seed",
            maturity: "partial"
        )

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(actionDomainSnapshot: snapshot)
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .partial)
        #expect(report.summary.passedCount == 4)
        #expect(report.summary.partialCount == 1)
        #expect(report.summary.failedCount == 0)
        #expect(standardFormats.status == .partial)
        #expect(standardFormats.requiredOperations.missing.isEmpty)
        #expect(standardFormats.requiredArtifacts.missing.isEmpty)
        #expect(standardFormats.requiredVerificationGates.missing.isEmpty)
        #expect(standardFormats.partialOperations == ["drc.import-foundry-rule-seed"])
        #expect(standardFormats.diagnostics.contains {
            $0.severity == "warning"
                && $0.code == "required-operation-partial"
                && $0.nextActions.contains("complete-operation:drc.import-foundry-rule-seed")
                && $0.nextActions.contains("qualify-operation:drc.import-foundry-rule-seed")
        })
        #expect(report.nextActions.contains("complete-operation:drc.import-foundry-rule-seed"))
        #expect(report.nextActions.contains("qualify-operation:drc.import-foundry-rule-seed"))
    }

    @Test func assessorKeepsMilestonePartialWhenRequiredOperationIsPlanned() throws {
        let snapshot = try snapshotWithOperation(
            "pex.metric-recovery-objective",
            maturity: "planned"
        )

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(actionDomainSnapshot: snapshot)
        let postLayout = try #require(report.milestones.first {
            $0.milestoneID == "post-layout-improvement-loop"
        })

        #expect(report.status == .partial)
        #expect(report.summary.passedCount == 4)
        #expect(report.summary.partialCount == 1)
        #expect(report.summary.failedCount == 0)
        #expect(postLayout.status == .partial)
        #expect(postLayout.requiredOperations.missing.isEmpty)
        #expect(postLayout.requiredArtifacts.missing.isEmpty)
        #expect(postLayout.requiredVerificationGates.missing.isEmpty)
        #expect(postLayout.plannedOperations == ["pex.metric-recovery-objective"])
        #expect(postLayout.diagnostics.contains {
            $0.severity == "warning"
                && $0.code == "required-operation-planned"
                && $0.nextActions.contains("implement-operation:pex.metric-recovery-objective")
                && $0.nextActions.contains("add-regression-test:pex.metric-recovery-objective")
        })
        #expect(report.nextActions.contains("implement-operation:pex.metric-recovery-objective"))
        #expect(report.nextActions.contains("add-regression-test:pex.metric-recovery-objective"))
    }

    @Test func assessorFailsMilestoneWhenRequiredTestEvidenceIsMissing() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        let reducedEvidence = baseline.testEvidence.filter {
            $0.evidenceID != "drc-foundry-rule-import-agent-envelope"
        }
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: reducedEvidence
        )
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .failed)
        #expect(report.summary.passedCount == 4)
        #expect(report.summary.failedCount == 1)
        #expect(standardFormats.status == .failed)
        #expect(standardFormats.requiredOperations.missing.isEmpty)
        #expect(standardFormats.requiredArtifacts.missing.isEmpty)
        #expect(standardFormats.requiredVerificationGates.missing.isEmpty)
        #expect(standardFormats.requiredTestEvidence.missing == [
            "drc-foundry-rule-import-agent-envelope",
        ])
        #expect(report.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "required-test-evidence-missing"
                && $0.milestoneID == "standard-format-grounding"
                && $0.nextActions.contains("add-test-evidence:drc-foundry-rule-import-agent-envelope")
                && $0.nextActions.contains("add-regression-test:drc-foundry-rule-import-agent-envelope")
        })
        #expect(report.nextActions.contains("add-test-evidence:drc-foundry-rule-import-agent-envelope"))
        #expect(report.nextActions.contains("add-regression-test:drc-foundry-rule-import-agent-envelope"))
    }

    @Test func assessorFailsMilestoneWhenRequiredTestEvidenceDoesNotCoverMilestone() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var mismatchedEvidence = baseline.testEvidence
        let evidenceIndex = try #require(mismatchedEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        mismatchedEvidence[evidenceIndex].coveredMilestoneIDs = ["agent-operable-design-loop"]
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-mismatch",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: mismatchedEvidence
        )
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .failed)
        #expect(report.summary.invalidTestEvidenceCount == 0)
        #expect(report.summary.testEvidenceDiagnosticCount == 0)
        #expect(standardFormats.status == .failed)
        #expect(standardFormats.requiredTestEvidence.missing == [
            "drc-foundry-rule-import-agent-envelope",
        ])
        #expect(report.diagnostics.contains {
            $0.code == "required-test-evidence-missing"
                && $0.milestoneID == "standard-format-grounding"
        })
    }

    @Test func assessorRejectsRequiredTestEvidenceWithoutExecutableCommand() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var invalidEvidence = baseline.testEvidence
        let evidenceIndex = try #require(invalidEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        invalidEvidence[evidenceIndex].command = []
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-command-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: invalidEvidence
        )
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .failed)
        #expect(report.summary.invalidTestEvidenceCount == 1)
        #expect(report.summary.testEvidenceDiagnosticCount == 1)
        #expect(standardFormats.status == .failed)
        #expect(standardFormats.requiredTestEvidence.missing == [
            "drc-foundry-rule-import-agent-envelope",
        ])
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-command-missing"
                && $0.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope")
        })
        #expect(report.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope"))
    }

    @Test func assessorRejectsRequiredTestEvidenceWhenCommandDoesNotRunDeclaredFilter() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var invalidEvidence = baseline.testEvidence
        let evidenceIndex = try #require(invalidEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        invalidEvidence[evidenceIndex].command = [
            "perl", "-e", "alarm shift; exec @ARGV", "180",
            "xcodebuild", "test",
            "-scheme", "DRCEngine-Package",
            "-destination", "platform=macOS",
            "-only-testing:DRCEngineTests/DRCCLIOptionsTests/otherTest",
        ]
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-filter-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: invalidEvidence
        )
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .failed)
        #expect(report.summary.invalidTestEvidenceCount == 1)
        #expect(report.summary.testEvidenceDiagnosticCount == 1)
        #expect(standardFormats.status == .failed)
        #expect(standardFormats.requiredTestEvidence.missing == [
            "drc-foundry-rule-import-agent-envelope",
        ])
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-command-filter-mismatch"
                && $0.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope")
        })
        #expect(report.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope"))
    }

    @Test func assessorRejectsRequiredTestEvidenceWithoutTimeoutWrapper() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var invalidEvidence = baseline.testEvidence
        let evidenceIndex = try #require(invalidEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        invalidEvidence[evidenceIndex].command = [
            "xcodebuild", "test",
            "-scheme", "DRCEngine-Package",
            "-destination", "platform=macOS",
            "-only-testing:DRCEngineTests/DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope",
        ]
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-timeout-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: invalidEvidence
        )

        #expect(report.status == .failed)
        #expect(report.summary.invalidTestEvidenceCount == 1)
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-command-timeout-missing"
                && $0.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope")
        })
    }

    @Test func assessorRejectsRequiredTestEvidenceWithoutXcodebuildRunner() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var invalidEvidence = baseline.testEvidence
        let evidenceIndex = try #require(invalidEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        invalidEvidence[evidenceIndex].command = [
            "perl", "-e", "alarm shift; exec @ARGV", "180",
            "swift", "test", "--filter",
            "DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope",
        ]
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-runner-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: invalidEvidence
        )

        #expect(report.status == .failed)
        #expect(report.summary.invalidTestEvidenceCount == 1)
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-command-runner-invalid"
                && $0.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope")
        })
    }

    @Test func assessorRejectsRequiredTestEvidenceWithoutArtifactCoverage() throws {
        let assessor = XcircuitePlatformCapabilityReadinessAssessor()
        let baseline = try assessor.assess(
            runID: "test-evidence-baseline",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        var invalidEvidence = baseline.testEvidence
        let evidenceIndex = try #require(invalidEvidence.firstIndex {
            $0.evidenceID == "drc-foundry-rule-import-agent-envelope"
        })
        invalidEvidence[evidenceIndex].evidenceArtifacts = []
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "test-evidence-artifact-gap",
            generatedAt: "2026-06-28T00:00:00Z"
        )

        let report = assessor.assess(
            actionDomainSnapshot: snapshot,
            testEvidence: invalidEvidence
        )
        let standardFormats = try #require(report.milestones.first {
            $0.milestoneID == "standard-format-grounding"
        })

        #expect(report.status == .failed)
        #expect(standardFormats.status == .failed)
        #expect(standardFormats.requiredTestEvidence.missing == [
            "drc-foundry-rule-import-agent-envelope",
        ])
        #expect(report.diagnostics.contains {
            $0.code == "test-evidence-artifact-missing"
                && $0.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope")
        })
        #expect(report.nextActions.contains("fix-test-evidence:drc-foundry-rule-import-agent-envelope"))
    }

    @Test func legacyPlatformCapabilitySummaryDecodesWithoutEvidenceAuditCounts() throws {
        let json = """
        {
          "schemaVersion": 2,
          "reportID": "xcircuite-platform-capability-readiness",
          "status": "passed",
          "actionDomainRunID": "legacy-readiness",
          "actionDomainGeneratedAt": "2026-06-28T00:00:00Z",
          "summary": {
            "milestoneCount": 0,
            "passedCount": 0,
            "partialCount": 0,
            "failedCount": 0,
            "domainCount": 0,
            "operationCount": 0,
            "implementedOperationCount": 0,
            "testEvidenceCount": 3
          },
          "milestones": [],
          "testEvidence": [],
          "diagnostics": [],
          "nextActions": []
        }
        """

        let report = try JSONDecoder().decode(
            XcircuitePlatformCapabilityReadinessReport.self,
            from: Data(json.utf8)
        )

        #expect(report.summary.testEvidenceCount == 3)
        #expect(report.summary.validTestEvidenceCount == 3)
        #expect(report.summary.invalidTestEvidenceCount == 0)
        #expect(report.summary.testEvidenceDiagnosticCount == 0)
    }

    @Test func platformCapabilityCLIPrettyOutputPreservesContract() async throws {
        let json = try await XcircuiteFlowCLICommand.run(arguments: [
            "inspect-platform-capabilities",
            "--run-id",
            "pretty-capabilities",
            "--generated-at",
            "2026-06-28T03:04:05Z",
            "--pretty",
        ])
        let report = try JSONDecoder().decode(
            XcircuitePlatformCapabilityReadinessReport.self,
            from: Data(json.utf8)
        )

        #expect(json.contains("\n"))
        #expect(json.contains(#""testEvidence""#))
        #expect(report.actionDomainRunID == "pretty-capabilities")
        #expect(report.summary.failedCount == 0)
        #expect(!report.nextActions.contains("implement-operation:lvs.waiver-review"))
        #expect(!report.nextActions.contains("implement-operation:pex.metric-recovery-objective"))
        #expect(!report.nextActions.contains("complete-operation:drc.import-foundry-rule-seed"))
        #expect(report.nextActions.isEmpty)
    }

    @Test func platformCapabilityCLIRejectsUnknownOption() async throws {
        await #expect(throws: XcircuiteFlowCLIError.self) {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "inspect-platform-capabilities",
                "--unknown",
            ])
        }
    }

    @Test func platformCapabilityCommandIsExposedInHelpText() async throws {
        let commandHelp = try await XcircuiteFlowCLICommand.run(arguments: [
            "inspect-platform-capabilities",
            "--help",
        ])
        let globalHelp = try await XcircuiteFlowCLICommand.run(arguments: ["--help"])

        #expect(commandHelp.contains("inspect-platform-capabilities"))
        #expect(commandHelp.contains("standalone signoff"))
        #expect(globalHelp.contains("inspect-platform-capabilities"))
    }

    @Test func assessorReportsMissingDomainOperationArtifactAndGate() throws {
        let snapshot = XcircuitePlanningActionDomainSnapshot(
            runID: "minimal-run",
            generatedAt: "2026-06-28T00:00:00Z",
            domains: [
                XcircuiteActionDomain(
                    domainID: "drc-signoff",
                    ownerPackages: ["DRCEngine"],
                    operations: [
                        XcircuiteActionDomainOperation(
                            operationID: "drc.run-native",
                            maturity: "implemented",
                            inputRefs: ["layout-ref"],
                            preconditions: ["layout-readable"],
                            effects: ["drc-result-produced"],
                            producedArtifacts: ["drc-report"],
                            verificationGates: ["artifact-integrity"],
                            reversible: true
                        ),
                    ]
                ),
            ]
        )

        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(actionDomainSnapshot: snapshot)
        let standalone = try #require(report.milestones.first { $0.milestoneID == "standalone-local-signoff" })

        #expect(report.status == .failed)
        #expect(standalone.status == .failed)
        #expect(standalone.requiredDomains.missing.contains("layout-edit"))
        #expect(standalone.requiredOperations.missing.contains("simulation.run-analysis"))
        #expect(standalone.requiredArtifacts.missing.contains("simulation-summary"))
        #expect(standalone.requiredVerificationGates.missing.contains("simulation-summary"))
        #expect(report.diagnostics.contains {
            $0.code == "required-domain-missing"
                && $0.milestoneID == "standalone-local-signoff"
                && $0.nextActions.contains("add-domain:layout-edit")
        })
        #expect(report.nextActions.contains("add-operation:simulation.run-analysis"))
        #expect(report.nextActions.contains("add-artifact:simulation-summary"))
        #expect(report.nextActions.contains("add-verification-gate:simulation-summary"))
    }

    @Test func actionDomainSnapshotExposesSimulationContractsUsedByReadiness() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "action-domain-contract",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        let simulation = try #require(snapshot.domains.first { $0.domainID == "simulation-analysis" })
        let operationIDs = Set(simulation.operations.map(\.operationID))

        #expect(simulation.ownerPackages.contains("CoreSpice"))
        #expect(simulation.ownerPackages.contains("Xcircuite"))
        #expect(operationIDs.isSuperset(of: [
            "simulation.import-spice",
            "simulation.run-analysis",
            "simulation.export-metric-report",
            "simulation.summarize-run",
            "simulation.metric-improvement-objective",
            "simulation.compare-post-layout",
        ]))
        #expect(simulation.operations.flatMap(\.producedArtifacts).contains("post-layout-comparison"))
        #expect(simulation.operations.flatMap(\.verificationGates).contains("human-review"))
        let metricImprovement = try #require(simulation.operations.first {
            $0.operationID == "simulation.metric-improvement-objective"
        })
        #expect(metricImprovement.maturity == "implemented")
        #expect(metricImprovement.inputRefs.contains("post-layout-metric-report"))
        #expect(metricImprovement.inputRefs.contains("source-netlist-ref"))
        #expect(metricImprovement.inputRefs.contains("optional-rejected-plan-history"))
        #expect(metricImprovement.producedArtifacts.contains("parameter-candidates"))
        #expect(metricImprovement.producedArtifacts.contains("candidate-plan"))
        #expect(metricImprovement.producedArtifacts.contains("numeric-repair-loop"))
        #expect(metricImprovement.verificationGates.contains("candidate-plan-verification"))
        #expect(metricImprovement.verificationGates.contains("simulation-metric-gate"))

        let pex = try #require(snapshot.domains.first { $0.domainID == "pex-extraction" })
        #expect(pex.ownerPackages.contains("PEXEngine"))
        #expect(pex.ownerPackages.contains("Xcircuite"))
        let metricRecovery = try #require(pex.operations.first {
            $0.operationID == "pex.metric-recovery-objective"
        })
        #expect(metricRecovery.maturity == "implemented")
        #expect(metricRecovery.inputRefs.contains("post-layout-metric-report"))
        #expect(metricRecovery.inputRefs.contains("pex-technology-ref"))
        #expect(metricRecovery.producedArtifacts.contains("planning-problem"))
        #expect(metricRecovery.verificationGates.contains("simulation-metric-gate"))
        #expect(metricRecovery.verificationGates.contains("native-drc"))

        let drc = try #require(snapshot.domains.first { $0.domainID == "drc-signoff" })
        let ruleSeedImport = try #require(drc.operations.first {
            $0.operationID == "drc.import-foundry-rule-seed"
        })
        #expect(ruleSeedImport.maturity == "implemented")
        #expect(ruleSeedImport.producedArtifacts.contains("layout-tech-database"))
        #expect(ruleSeedImport.producedArtifacts.contains("drc-foundry-rule-import-report"))
        #expect(ruleSeedImport.verificationGates.contains("deck-readiness"))
        #expect(ruleSeedImport.verificationGates.contains("import-coverage"))
    }

    private func snapshotWithOperation(
        _ operationID: String,
        maturity: String
    ) throws -> XcircuitePlanningActionDomainSnapshot {
        var snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "maturity-regression",
            generatedAt: "2026-06-28T00:00:00Z"
        )
        let domainIndex = try #require(snapshot.domains.firstIndex { domain in
            domain.operations.contains { $0.operationID == operationID }
        })
        let operationIndex = try #require(snapshot.domains[domainIndex].operations.firstIndex {
            $0.operationID == operationID
        })
        snapshot.domains[domainIndex].operations[operationIndex].maturity = maturity
        return snapshot
    }
}
