import Foundation

public struct XcircuitePlatformCapabilityReadinessAssessor: Sendable {
    public init() {}

    public func assess(
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        testEvidence: [XcircuitePlatformCapabilityTestEvidence]? = nil
    ) -> XcircuitePlatformCapabilityReadinessReport {
        let effectiveTestEvidence = testEvidence ?? defaultTestEvidence()
        let specs = milestoneSpecs()
        let evidenceAudit = audit(
            testEvidence: effectiveTestEvidence,
            milestoneIDs: Set(specs.map(\.milestoneID))
        )
        let milestones = specs.map { spec in
            readiness(
                for: spec,
                snapshot: actionDomainSnapshot,
                validTestEvidenceIDs: evidenceAudit.validEvidenceIDsByMilestone[spec.milestoneID, default: []],
                testEvidenceDiagnostics: evidenceAudit.milestoneDiagnosticsByMilestone[spec.milestoneID, default: []]
            )
        }
        let executionStatusCounts = Dictionary(grouping: effectiveTestEvidence.map(\.executionStatus), by: { $0 })
            .mapValues(\.count)
        let diagnostics = evidenceAudit.diagnostics + milestones.flatMap(\.diagnostics)
        let status = reportStatus(from: milestones, diagnostics: diagnostics)
        let operations = actionDomainSnapshot.domains.flatMap(\.operations)
        return XcircuitePlatformCapabilityReadinessReport(
            status: status,
            actionDomainRunID: actionDomainSnapshot.runID,
            actionDomainGeneratedAt: actionDomainSnapshot.generatedAt,
            summary: XcircuitePlatformCapabilityReadinessReport.Summary(
                milestoneCount: milestones.count,
                passedCount: milestones.filter { $0.status == .passed }.count,
                partialCount: milestones.filter { $0.status == .partial }.count,
                failedCount: milestones.filter { $0.status == .failed }.count,
                domainCount: actionDomainSnapshot.domains.count,
                operationCount: operations.count,
                implementedOperationCount: operations.filter { $0.maturity == "implemented" }.count,
                testEvidenceCount: effectiveTestEvidence.count,
                validTestEvidenceCount: evidenceAudit.validEvidenceCount,
                invalidTestEvidenceCount: effectiveTestEvidence.count - evidenceAudit.validEvidenceCount,
                passedTestEvidenceCount: executionStatusCounts[.passed, default: 0],
                unverifiedTestEvidenceCount: executionStatusCounts[.unverified, default: 0],
                failedTestEvidenceCount: executionStatusCounts[.failed, default: 0],
                testEvidenceDiagnosticCount: evidenceAudit.diagnosticCount
            ),
            milestones: milestones,
            testEvidence: effectiveTestEvidence,
            diagnostics: diagnostics,
            nextActions: stableUnique(diagnostics.flatMap(\.nextActions))
        )
    }

    public func assess(runID: String, generatedAt: String) throws -> XcircuitePlatformCapabilityReadinessReport {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(runID: runID, generatedAt: generatedAt)
        return assess(actionDomainSnapshot: snapshot)
    }

    private func readiness(
        for spec: MilestoneSpec,
        snapshot: XcircuitePlanningActionDomainSnapshot,
        validTestEvidenceIDs: Set<String>,
        testEvidenceDiagnostics: [XcircuitePlatformCapabilityDiagnostic]
    ) -> XcircuitePlatformCapabilityMilestoneReadiness {
        let domainIDs = Set(snapshot.domains.map(\.domainID))
        let operationPairs = operationIndex(snapshot)
        let artifacts = Set(snapshot.domains.flatMap { domain in domain.operations.flatMap(\.producedArtifacts) })
        let gates = Set(snapshot.domains.flatMap { domain in domain.operations.flatMap(\.verificationGates) })

        let domainCoverage = coverage(required: spec.requiredDomains, present: domainIDs)
        let operationCoverage = coverage(required: spec.requiredOperations, present: Set(operationPairs.keys))
        let artifactCoverage = coverage(required: spec.requiredArtifacts, present: artifacts)
        let gateCoverage = coverage(required: spec.requiredVerificationGates, present: gates)
        let testEvidenceCoverage = coverage(required: spec.requiredTestEvidence, present: validTestEvidenceIDs)

        let presentOperations = spec.requiredOperations.compactMap { operationPairs[$0] }
        let plannedOperations = presentOperations
            .filter { $0.maturity == "planned" }
            .map(\.operationID)
            .sorted()
        let partialOperations = presentOperations
            .filter { $0.maturity == "partial" }
            .map(\.operationID)
            .sorted()

        let diagnostics = diagnostics(
            spec: spec,
            domainCoverage: domainCoverage,
            operationCoverage: operationCoverage,
            artifactCoverage: artifactCoverage,
            gateCoverage: gateCoverage,
            testEvidenceCoverage: testEvidenceCoverage,
            testEvidenceDiagnostics: testEvidenceDiagnostics,
            plannedOperations: plannedOperations,
            partialOperations: partialOperations
        )
        let status: XcircuitePlatformCapabilityReadinessStatus
        if diagnostics.contains(where: { $0.severity == "error" }) {
            status = .failed
        } else if diagnostics.contains(where: { $0.severity == "warning" }) {
            status = .partial
        } else {
            status = .passed
        }

        return XcircuitePlatformCapabilityMilestoneReadiness(
            milestoneID: spec.milestoneID,
            title: spec.title,
            status: status,
            requiredDomains: domainCoverage,
            requiredOperations: operationCoverage,
            requiredArtifacts: artifactCoverage,
            requiredVerificationGates: gateCoverage,
            requiredTestEvidence: testEvidenceCoverage,
            plannedOperations: plannedOperations,
            partialOperations: partialOperations,
            diagnostics: diagnostics,
            nextActions: stableUnique(diagnostics.flatMap(\.nextActions))
        )
    }

    private func diagnostics(
        spec: MilestoneSpec,
        domainCoverage: XcircuitePlatformCapabilityRequirementCoverage,
        operationCoverage: XcircuitePlatformCapabilityRequirementCoverage,
        artifactCoverage: XcircuitePlatformCapabilityRequirementCoverage,
        gateCoverage: XcircuitePlatformCapabilityRequirementCoverage,
        testEvidenceCoverage: XcircuitePlatformCapabilityRequirementCoverage,
        testEvidenceDiagnostics: [XcircuitePlatformCapabilityDiagnostic],
        plannedOperations: [String],
        partialOperations: [String]
    ) -> [XcircuitePlatformCapabilityDiagnostic] {
        var values = testEvidenceDiagnostics
        appendMissingDiagnostics(
            &values,
            milestoneID: spec.milestoneID,
            kind: "domain",
            code: "required-domain-missing",
            coverage: domainCoverage
        )
        appendMissingDiagnostics(
            &values,
            milestoneID: spec.milestoneID,
            kind: "operation",
            code: "required-operation-missing",
            coverage: operationCoverage
        )
        appendMissingDiagnostics(
            &values,
            milestoneID: spec.milestoneID,
            kind: "artifact",
            code: "required-artifact-missing",
            coverage: artifactCoverage
        )
        appendMissingDiagnostics(
            &values,
            milestoneID: spec.milestoneID,
            kind: "verification-gate",
            code: "required-verification-gate-missing",
            coverage: gateCoverage
        )
        appendMissingDiagnostics(
            &values,
            milestoneID: spec.milestoneID,
            kind: "test-evidence",
            code: "required-test-evidence-missing",
            coverage: testEvidenceCoverage
        )
        for operation in plannedOperations {
            values.append(XcircuitePlatformCapabilityDiagnostic(
                severity: "warning",
                code: "required-operation-planned",
                message: "Required operation is declared but still planned: \(operation).",
                milestoneID: spec.milestoneID,
                nextActions: ["implement-operation:\(operation)", "add-regression-test:\(operation)"]
            ))
        }
        for operation in partialOperations {
            values.append(XcircuitePlatformCapabilityDiagnostic(
                severity: "warning",
                code: "required-operation-partial",
                message: "Required operation is declared but only partially implemented: \(operation).",
                milestoneID: spec.milestoneID,
                nextActions: ["complete-operation:\(operation)", "qualify-operation:\(operation)"]
            ))
        }
        return values
    }

    private func appendMissingDiagnostics(
        _ diagnostics: inout [XcircuitePlatformCapabilityDiagnostic],
        milestoneID: String,
        kind: String,
        code: String,
        coverage: XcircuitePlatformCapabilityRequirementCoverage
    ) {
        for missing in coverage.missing {
            diagnostics.append(XcircuitePlatformCapabilityDiagnostic(
                severity: "error",
                code: code,
                message: "Required \(kind) is missing: \(missing).",
                milestoneID: milestoneID,
                nextActions: ["add-\(kind):\(missing)", "add-regression-test:\(missing)"]
            ))
        }
    }

    private func coverage(
        required: [String],
        present: Set<String>
    ) -> XcircuitePlatformCapabilityRequirementCoverage {
        let requiredValues = stableUnique(required).sorted()
        let presentValues = requiredValues.filter { present.contains($0) }
        let missingValues = requiredValues.filter { !present.contains($0) }
        return XcircuitePlatformCapabilityRequirementCoverage(
            required: requiredValues,
            present: presentValues,
            missing: missingValues
        )
    }

    private func operationIndex(
        _ snapshot: XcircuitePlanningActionDomainSnapshot
    ) -> [String: XcircuiteActionDomainOperation] {
        var values: [String: XcircuiteActionDomainOperation] = [:]
        for domain in snapshot.domains {
            for operation in domain.operations {
                values["\(domain.domainID)/\(operation.operationID)"] = operation
                values[operation.operationID] = operation
            }
        }
        return values
    }

    private func reportStatus(
        from milestones: [XcircuitePlatformCapabilityMilestoneReadiness],
        diagnostics: [XcircuitePlatformCapabilityDiagnostic]
    ) -> XcircuitePlatformCapabilityReadinessStatus {
        if diagnostics.contains(where: { $0.severity == "error" })
            || milestones.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if diagnostics.contains(where: { $0.severity == "warning" })
            || milestones.contains(where: { $0.status == .partial }) {
            return .partial
        }
        return .passed
    }

    private func audit(
        testEvidence: [XcircuitePlatformCapabilityTestEvidence],
        milestoneIDs: Set<String>
    ) -> TestEvidenceAudit {
        let evidenceIDCounts = Dictionary(grouping: testEvidence.map(\.evidenceID), by: { $0 })
            .mapValues(\.count)
        var diagnostics: [XcircuitePlatformCapabilityDiagnostic] = []
        var milestoneDiagnosticsByMilestone: [String: [XcircuitePlatformCapabilityDiagnostic]] = [:]
        var validEvidenceIDsByMilestone: [String: Set<String>] = [:]
        var validEvidenceCount = 0
        var diagnosticCount = 0

        for evidence in testEvidence {
            var isValid = true
            let evidenceID = evidence.evidenceID
            let subject = evidenceID.isEmpty ? "unknown-test-evidence" : evidenceID

            func appendDiagnostic(code: String, message: String) {
                isValid = false
                diagnosticCount += 1
                diagnostics.append(XcircuitePlatformCapabilityDiagnostic(
                    severity: "error",
                    code: code,
                    message: message,
                    milestoneID: nil,
                    nextActions: ["fix-test-evidence:\(subject)"]
                ))
            }

            if evidenceID.isEmpty {
                appendDiagnostic(
                    code: "test-evidence-id-missing",
                    message: "Test evidence ID is missing."
                )
            } else if evidenceIDCounts[evidenceID, default: 0] > 1 {
                appendDiagnostic(
                    code: "test-evidence-id-duplicate",
                    message: "Test evidence ID is duplicated: \(evidenceID)."
                )
            }
            if evidence.packagePath.isEmpty {
                appendDiagnostic(
                    code: "test-evidence-package-missing",
                    message: "Test evidence package path is missing: \(subject)."
                )
            }
            if evidence.command.isEmpty || evidence.command.contains(where: \.isEmpty) {
                appendDiagnostic(
                    code: "test-evidence-command-missing",
                    message: "Test evidence command is missing: \(subject)."
                )
            } else {
                if !usesTimeoutWrapper(evidence.command) {
                    appendDiagnostic(
                        code: "test-evidence-command-timeout-missing",
                        message: "Test evidence command must use a timeout wrapper bounded to 120 seconds: \(subject)."
                    )
                }
                if !usesXcodebuildTest(evidence.command) {
                    appendDiagnostic(
                        code: "test-evidence-command-runner-invalid",
                        message: "Test evidence command must use xcodebuild test: \(subject)."
                    )
                }
            }
            if evidence.testFilter.isEmpty {
                appendDiagnostic(
                    code: "test-evidence-filter-missing",
                    message: "Test evidence filter is missing: \(subject)."
                )
            } else if !evidence.command.isEmpty
                && evidence.command.allSatisfy({ !$0.isEmpty })
                && !command(evidence.command, containsTestFilter: evidence.testFilter) {
                appendDiagnostic(
                    code: "test-evidence-command-filter-mismatch",
                    message: "Test evidence command does not contain its test filter: \(subject)."
                )
            }
            if evidence.coveredMilestoneIDs.isEmpty || evidence.coveredMilestoneIDs.contains(where: \.isEmpty) {
                appendDiagnostic(
                    code: "test-evidence-milestone-coverage-missing",
                    message: "Test evidence milestone coverage is missing: \(subject)."
                )
            }
            for milestoneID in evidence.coveredMilestoneIDs where !milestoneIDs.contains(milestoneID) {
                appendDiagnostic(
                    code: "test-evidence-unknown-milestone",
                    message: "Test evidence references an unknown milestone: \(milestoneID)."
                )
            }
            if evidence.coveredRequirementKinds.isEmpty || evidence.coveredRequirementKinds.contains(where: \.isEmpty) {
                appendDiagnostic(
                    code: "test-evidence-requirement-kind-missing",
                    message: "Test evidence requirement kind coverage is missing: \(subject)."
                )
            }
            if evidence.evidenceArtifacts.isEmpty || evidence.evidenceArtifacts.contains(where: \.isEmpty) {
                appendDiagnostic(
                    code: "test-evidence-artifact-missing",
                    message: "Test evidence artifact coverage is missing: \(subject)."
                )
            }
            switch evidence.executionStatus {
            case .passed:
                break
            case .unverified:
                appendExecutionDiagnostics(
                    severity: "warning",
                    code: "test-evidence-execution-unverified",
                    message: "Test evidence execution is unverified: \(subject).",
                    nextActions: ["run-test-evidence:\(subject)"],
                    evidence: evidence,
                    milestoneIDs: milestoneIDs,
                    diagnosticsByMilestone: &milestoneDiagnosticsByMilestone,
                    diagnosticCount: &diagnosticCount
                )
            case .failed:
                isValid = false
                appendExecutionDiagnostics(
                    severity: "error",
                    code: "test-evidence-execution-failed",
                    message: "Test evidence execution failed: \(subject).",
                    nextActions: ["rerun-test-evidence:\(subject)", "fix-regression:\(subject)"],
                    evidence: evidence,
                    milestoneIDs: milestoneIDs,
                    diagnosticsByMilestone: &milestoneDiagnosticsByMilestone,
                    diagnosticCount: &diagnosticCount
                )
            }

            guard isValid else { continue }
            validEvidenceCount += 1
            for milestoneID in evidence.coveredMilestoneIDs where milestoneIDs.contains(milestoneID) {
                validEvidenceIDsByMilestone[milestoneID, default: []].insert(evidenceID)
            }
        }

        return TestEvidenceAudit(
            validEvidenceIDsByMilestone: validEvidenceIDsByMilestone,
            validEvidenceCount: validEvidenceCount,
            diagnostics: diagnostics,
            milestoneDiagnosticsByMilestone: milestoneDiagnosticsByMilestone,
            diagnosticCount: diagnosticCount
        )
    }

    private func appendExecutionDiagnostics(
        severity: String,
        code: String,
        message: String,
        nextActions: [String],
        evidence: XcircuitePlatformCapabilityTestEvidence,
        milestoneIDs: Set<String>,
        diagnosticsByMilestone: inout [String: [XcircuitePlatformCapabilityDiagnostic]],
        diagnosticCount: inout Int
    ) {
        let coveredKnownMilestoneIDs = evidence.coveredMilestoneIDs.filter { milestoneIDs.contains($0) }
        for milestoneID in coveredKnownMilestoneIDs {
            diagnosticCount += 1
            diagnosticsByMilestone[milestoneID, default: []].append(XcircuitePlatformCapabilityDiagnostic(
                severity: severity,
                code: code,
                message: message,
                milestoneID: milestoneID,
                nextActions: nextActions
            ))
        }
    }

    private func usesTimeoutWrapper(_ command: [String]) -> Bool {
        guard command.count >= 5 else { return false }
        guard command[0] == "perl", command[1] == "-e" else { return false }
        guard command[2].contains("alarm shift"), command[2].contains("exec @ARGV") else { return false }
        guard let timeout = Int(command[3]), timeout > 0, timeout <= 120 else { return false }
        return true
    }

    private func usesXcodebuildTest(_ command: [String]) -> Bool {
        guard let xcodebuildIndex = command.firstIndex(of: "xcodebuild") else { return false }
        return command[(xcodebuildIndex + 1)...].contains("test")
    }

    private func command(_ command: [String], containsTestFilter testFilter: String) -> Bool {
        command.contains { argument in
            argument == testFilter
                || argument == "-only-testing:\(testFilter)"
                || argument.hasSuffix("/\(testFilter)")
        }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func milestoneSpecs() -> [MilestoneSpec] {
        [
            MilestoneSpec(
                milestoneID: "standalone-local-signoff",
                title: "Standalone local simulation, layout, DRC, LVS, and PEX execution",
                requiredDomains: [
                    "drc-signoff",
                    "layout-edit",
                    "lvs-signoff",
                    "pex-extraction",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "drc.run-native",
                    "layout-command-replay",
                    "lvs.run-native",
                    "pex.extract",
                    "simulation.run-analysis",
                ],
                requiredArtifacts: [
                    "drc-artifact-manifest",
                    "layout-command-manifest",
                    "lvs-artifact-manifest",
                    "parasitic-ir",
                    "simulation-summary",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "drc-artifacts",
                    "lvs-artifacts",
                    "pex-flow-artifacts",
                    "simulation-summary",
                ],
                requiredTestEvidence: [
                    "xci-runtime-local-signoff-flow",
                    "xci-signoff-stage-artifact-gates",
                ]
            ),
            MilestoneSpec(
                milestoneID: "agent-operable-design-loop",
                title: "Agent-readable planning, command, evidence, and repair loop",
                requiredDomains: [
                    "drc-signoff",
                    "layout-edit",
                    "lvs-signoff",
                    "pex-extraction",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "drc.export-repair-hints",
                    "layout-command-replay",
                    "lvs.export-repair-hints",
                    "pex.export-evidence-packet",
                    "simulation.export-metric-report",
                ],
                requiredArtifacts: [
                    "drc-repair-hints",
                    "layout-command-result",
                    "lvs-repair-hints",
                    "pex-evidence-packet",
                    "simulation-metric-report",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "native-drc",
                    "native-lvs",
                    "schema-validation",
                    "simulation-metric-gate",
                ],
                requiredTestEvidence: [
                    "xci-candidate-plan-verification-contract",
                    "xci-numeric-repair-loop-feedback",
                ]
            ),
            MilestoneSpec(
                milestoneID: "human-review-audit",
                title: "Human review, artifact audit, approval, and resume material",
                requiredDomains: [
                    "drc-signoff",
                    "layout-edit",
                    "lvs-signoff",
                    "pex-extraction",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "drc.waiver-review",
                    "layout-command-replay",
                    "lvs.waiver-review",
                    "pex.summarize-run",
                    "simulation.summarize-run",
                ],
                requiredArtifacts: [
                    "drc-summary",
                    "layout-command-result",
                    "lvs-summary",
                    "pex-summary",
                    "simulation-summary",
                ],
                requiredVerificationGates: [
                    "approval-gate",
                    "artifact-integrity",
                    "human-review",
                    "pex-flow-artifacts",
                    "simulation-summary",
                ],
                requiredTestEvidence: [
                    "xci-candidate-plan-verification-contract",
                    "xci-risk-approval-review-contract",
                ]
            ),
            MilestoneSpec(
                milestoneID: "standard-format-grounding",
                title: "Standard format import/export and canonical artifact grounding",
                requiredDomains: [
                    "drc-signoff",
                    "layout-edit",
                    "pex-extraction",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "drc.import-foundry-rule-seed",
                    "layout-command-replay",
                    "pex.parse-spef",
                    "simulation.import-spice",
                ],
                requiredArtifacts: [
                    "drc-foundry-rule-import-report",
                    "layout-document",
                    "parasitic-ir",
                    "simulation-netlist",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "deck-readiness",
                    "import-coverage",
                    "schema-validation",
                ],
                requiredTestEvidence: [
                    "drc-foundry-rule-import-agent-envelope",
                    "xci-platform-readiness-contract",
                ]
            ),
            MilestoneSpec(
                milestoneID: "post-layout-improvement-loop",
                title: "Post-layout degradation analysis and improvement planning",
                requiredDomains: [
                    "layout-edit",
                    "pex-extraction",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "layout-command-replay",
                    "pex.metric-recovery-objective",
                    "simulation.compare-post-layout",
                ],
                requiredArtifacts: [
                    "layout-command-result",
                    "parasitic-ir",
                    "planning-problem",
                    "post-layout-comparison",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "pex-flow-artifacts",
                    "simulation-metric-gate",
                ],
                requiredTestEvidence: [
                    "xci-post-layout-comparison-gate",
                    "xci-numeric-repair-loop-feedback",
                ]
            ),
        ]
    }

    private func defaultTestEvidence() -> [XcircuitePlatformCapabilityTestEvidence] {
        [
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-runtime-local-signoff-flow",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteFlowRuntimeTests/runtimeProgressFollowStreamsLayoutDRCLVSPEXStages()"
                ),
                testFilter: "XcircuiteFlowRuntimeTests/runtimeProgressFollowStreamsLayoutDRCLVSPEXStages()",
                coveredMilestoneIDs: ["standalone-local-signoff"],
                coveredRequirementKinds: ["operation", "artifact", "verification-gate"],
                evidenceArtifacts: ["run-manifest", "progress-events", "stage-artifacts"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-signoff-stage-artifact-gates",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/SignoffFlowStageExecutorTests"
                ),
                testFilter: "SignoffFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff"],
                coveredRequirementKinds: ["artifact", "verification-gate"],
                evidenceArtifacts: ["drc-summary", "lvs-summary", "artifact-manifest"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-candidate-plan-verification-contract",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteCandidatePlanVerifierTests/verifyCandidatePlanCLIWritesPlanVerificationAndActionRecord()"
                ),
                testFilter: "XcircuiteCandidatePlanVerifierTests/verifyCandidatePlanCLIWritesPlanVerificationAndActionRecord()",
                coveredMilestoneIDs: ["agent-operable-design-loop", "human-review-audit"],
                coveredRequirementKinds: ["operation", "artifact", "verification-gate", "human-review"],
                evidenceArtifacts: ["planning/plan-verification.json", "actions.jsonl"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-risk-approval-review-contract",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteCandidatePlanVerifierTests/recordedRiskApprovalPassesSyntheticApprovalGate()"
                ),
                testFilter: "XcircuiteCandidatePlanVerifierTests/recordedRiskApprovalPassesSyntheticApprovalGate()",
                coveredMilestoneIDs: ["human-review-audit"],
                coveredRequirementKinds: ["approval-gate", "human-review"],
                evidenceArtifacts: ["approval-record", "planning/plan-verification.json"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "drc-foundry-rule-import-agent-envelope",
                packagePath: "DRCEngine",
                command: xcodebuildTestCommand(
                    scheme: "DRCEngine-Package",
                    onlyTesting: "DRCCLICoreTests/DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope()"
                ),
                testFilter: "DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope()",
                coveredMilestoneIDs: ["standard-format-grounding"],
                coveredRequirementKinds: ["standard-format", "artifact", "cli-json"],
                evidenceArtifacts: ["layout-tech-database", "drc-foundry-rule-import-report"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-platform-readiness-contract",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuitePlatformCapabilityReadinessTests"
                ),
                testFilter: "XcircuitePlatformCapabilityReadinessTests",
                coveredMilestoneIDs: ["standard-format-grounding"],
                coveredRequirementKinds: ["readiness", "cli-json", "regression-gate"],
                evidenceArtifacts: ["platform-capability-readiness-report"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-post-layout-comparison-gate",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/PostLayoutComparisonFlowStageExecutorTests/comparisonReportArtifactAndGatePass()"
                ),
                testFilter: "PostLayoutComparisonFlowStageExecutorTests/comparisonReportArtifactAndGatePass()",
                coveredMilestoneIDs: ["post-layout-improvement-loop"],
                coveredRequirementKinds: ["post-layout", "artifact", "verification-gate"],
                evidenceArtifacts: ["post-layout-comparison"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-numeric-repair-loop-feedback",
                packagePath: "Xcircuite",
                command: xcodebuildTestCommand(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteNumericRepairLoopRunnerTests/numericRepairLoopCLIExecutesRejectedFeedbackLoopUntilSimulationMetricPasses()"
                ),
                testFilter: "XcircuiteNumericRepairLoopRunnerTests/numericRepairLoopCLIExecutesRejectedFeedbackLoopUntilSimulationMetricPasses()",
                coveredMilestoneIDs: ["agent-operable-design-loop", "post-layout-improvement-loop"],
                coveredRequirementKinds: ["repair-loop", "feedback", "simulation-metric-gate"],
                evidenceArtifacts: ["planning/numeric-repair-loop.json", "planning/rejected-plans.jsonl"]
            ),
        ]
    }

    private func xcodebuildTestCommand(
        timeoutSeconds: Int = 120,
        scheme: String,
        onlyTesting: String
    ) -> [String] {
        [
            "perl", "-e", "alarm shift; exec @ARGV", "\(timeoutSeconds)",
            "xcodebuild", "test",
            "-scheme", scheme,
            "-destination", "platform=macOS",
            "-only-testing:\(onlyTesting)",
        ]
    }

    private struct MilestoneSpec: Sendable, Hashable {
        var milestoneID: String
        var title: String
        var requiredDomains: [String]
        var requiredOperations: [String]
        var requiredArtifacts: [String]
        var requiredVerificationGates: [String]
        var requiredTestEvidence: [String]
    }

    private struct TestEvidenceAudit: Sendable, Hashable {
        var validEvidenceIDsByMilestone: [String: Set<String>]
        var validEvidenceCount: Int
        var diagnostics: [XcircuitePlatformCapabilityDiagnostic]
        var milestoneDiagnosticsByMilestone: [String: [XcircuitePlatformCapabilityDiagnostic]]
        var diagnosticCount: Int
    }
}
