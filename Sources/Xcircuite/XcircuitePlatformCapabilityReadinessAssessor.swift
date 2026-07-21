import Foundation
import CircuiteFoundation

public struct XcircuitePlatformCapabilityReadinessAssessor: Sendable {
    public init() {}

    public func assess(
        actionDomainSnapshot: XcircuitePlanningActionDomainSnapshot,
        testEvidence: [XcircuitePlatformCapabilityTestEvidence]? = nil,
        evidenceRoot: URL? = nil,
        verifications: [XcircuitePlatformCapabilityTestEvidenceVerification] = []
    ) -> XcircuitePlatformCapabilityReadinessReport {
        let effectiveTestEvidence = testEvidence ?? defaultTestEvidence()
        let verificationIndex = Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: verifications, by: \.evidenceID)
                .compactMap { evidenceID, values in
                    values.count == 1 ? (evidenceID, values[0]) : nil
                }
        )
        let specs = milestoneSpecs()
        let evidenceAudit = audit(
            testEvidence: effectiveTestEvidence,
            milestoneIDs: Set(specs.map(\.milestoneID)),
            evidenceRoot: evidenceRoot,
            verifications: verificationIndex
        )
        let milestones = specs.map { spec in
            readiness(
                for: spec,
                snapshot: actionDomainSnapshot,
                validTestEvidenceIDs: evidenceAudit.validEvidenceIDsByMilestone[spec.milestoneID, default: []],
                testEvidenceDiagnostics: evidenceAudit.milestoneDiagnosticsByMilestone[spec.milestoneID, default: []]
            )
        }
        let executionStatusCounts = Dictionary(
            grouping: effectiveTestEvidence.map {
                retainedExecutionStatus(
                    for: $0,
                    evidenceRoot: evidenceRoot,
                    verification: verificationIndex[$0.evidenceID]
                )
            },
            by: { $0 }
        )
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
                implementedOperationCount: operations.filter { $0.maturity == .implemented }.count,
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

    public func assess(
        runID: String,
        generatedAt: String,
        evidenceRoot: URL? = nil
    ) throws -> XcircuitePlatformCapabilityReadinessReport {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(runID: runID, generatedAt: generatedAt)
        return assess(actionDomainSnapshot: snapshot, evidenceRoot: evidenceRoot)
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
            .filter { $0.maturity == .planned }
            .map(\.operationID)
            .sorted()
        let partialOperations = presentOperations
            .filter { $0.maturity != .implemented && $0.maturity != .planned }
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
                nextActions: ["complete-operation:\(operation)", "validate-operation:\(operation)"]
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
        milestoneIDs: Set<String>,
        evidenceRoot: URL?,
        verifications: [String: XcircuitePlatformCapabilityTestEvidenceVerification]
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
            if evidence.coveredArtifactKinds.isEmpty
                || evidence.coveredArtifactKinds.contains(where: \.isEmpty)
                || Set(evidence.coveredArtifactKinds).count != evidence.coveredArtifactKinds.count {
                appendDiagnostic(
                    code: "test-evidence-artifact-missing",
                    message: "Test evidence artifact coverage must be non-empty and unique: \(subject)."
                )
            }
            let retainedStatus: XcircuitePlatformCapabilityTestEvidenceExecutionStatus
            if isValid {
                retainedStatus = retainedExecutionStatus(
                    for: evidence,
                    evidenceRoot: evidenceRoot,
                    verification: verifications[evidence.evidenceID],
                    appendDiagnostic: appendDiagnostic
                )
            } else {
                retainedStatus = evidence.executionStatus
            }
            switch retainedStatus {
            case .passed:
                break
            case .unverified:
                isValid = false
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

    private func retainedExecutionStatus(
        for evidence: XcircuitePlatformCapabilityTestEvidence,
        evidenceRoot: URL?,
        verification: XcircuitePlatformCapabilityTestEvidenceVerification?
    ) -> XcircuitePlatformCapabilityTestEvidenceExecutionStatus {
        retainedExecutionStatus(
            for: evidence,
            evidenceRoot: evidenceRoot,
            verification: verification
        ) { _, _ in }
    }

    private func retainedExecutionStatus(
        for evidence: XcircuitePlatformCapabilityTestEvidence,
        evidenceRoot: URL?,
        verification: XcircuitePlatformCapabilityTestEvidenceVerification?,
        appendDiagnostic: (String, String) -> Void
    ) -> XcircuitePlatformCapabilityTestEvidenceExecutionStatus {
        guard evidence.executionStatus != .unverified else {
            return .unverified
        }
        guard let evidenceRoot else {
            appendDiagnostic(
                "test-evidence-root-missing",
                "A retained evidence root is required to verify test evidence: \(evidence.evidenceID)."
            )
            return evidence.executionStatus == .failed ? .failed : .unverified
        }
        guard let resultArtifact = evidence.resultArtifact,
              let provenance = evidence.provenance,
              let exitStatus = evidence.exitStatus else {
            appendDiagnostic(
                "test-evidence-retained-contract-missing",
                "Test evidence must retain a result ArtifactReference, ExecutionProvenance, and exit status: \(evidence.evidenceID)."
            )
            return .unverified
        }
        guard let verification,
              verification.evidenceID == evidence.evidenceID,
              verification.resultArtifactID == resultArtifact.id,
              verification.resultDigest == resultArtifact.digest,
              verification.exitStatus == exitStatus else {
            appendDiagnostic(
                "test-evidence-independent-verification-required",
                "Persisted test evidence requires an in-process receipt from XcircuitePlatformCapabilityTestRunner: \(evidence.evidenceID)."
            )
            return .unverified
        }
        let encodedEvidenceDigest: ContentDigest
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encodedEvidenceDigest = try SHA256ContentDigester().digest(
                data: encoder.encode(evidence),
                using: .sha256
            )
        } catch {
            appendDiagnostic(
                "test-evidence-receipt-binding-failed",
                "Test evidence could not be bound to its runner receipt: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard verification.evidenceDigest == encodedEvidenceDigest else {
            appendDiagnostic(
                "test-evidence-receipt-mismatch",
                "Test evidence was modified after its runner receipt was issued: \(evidence.evidenceID)."
            )
            return .failed
        }
        let artifacts = [resultArtifact] + evidence.retainedArtifacts
        guard artifacts.allSatisfy({ $0.locator.location.storage == .workspaceRelative }) else {
            appendDiagnostic(
                "test-evidence-artifact-location-invalid",
                "Retained test evidence artifacts must be workspace-relative: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard evidence.retainedArtifacts.allSatisfy({ $0.locator.role == .output }) else {
            appendDiagnostic(
                "test-evidence-artifact-role-invalid",
                "Retained test outputs must use the output artifact role: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard artifacts.allSatisfy({
            $0.digest.algorithm == .sha256
                && $0.digest.hexadecimalValue.count == 64
                && $0.byteCount > 0
        }) else {
            appendDiagnostic(
                "test-evidence-artifact-reference-invalid",
                "Retained test evidence must use non-empty SHA-256-bound artifact references: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard artifacts.allSatisfy({ LocalArtifactVerifier().verify($0, relativeTo: evidenceRoot).isVerified }) else {
            appendDiagnostic(
                "test-evidence-artifact-integrity-failed",
                "Retained test evidence digest or byte count verification failed: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard let resultProducer = resultArtifact.producer,
              resultProducer == provenance.producer else {
            appendDiagnostic(
                "test-evidence-producer-mismatch",
                "Retained test evidence producer identity does not match execution provenance: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard let invocation = provenance.invocation,
              invocation.mode == .externalProcess,
              invocationContainsBoundedXcodebuildTest(invocation, filter: evidence.testFilter) else {
            appendDiagnostic(
                "test-evidence-invocation-invalid",
                "Execution provenance must retain the bounded xcodebuild test invocation and declared filter: \(evidence.evidenceID)."
            )
            return .failed
        }
        let resultURL: URL
        do {
            resultURL = try resultArtifact.locator.location.resolvedFileURL(relativeTo: evidenceRoot)
        } catch {
            appendDiagnostic(
                "test-evidence-result-location-invalid",
                "Retained test evidence result could not be resolved: \(evidence.evidenceID)."
            )
            return .failed
        }
        let record: XcircuitePlatformCapabilityTestExecutionRecord
        do {
            let data = try Data(contentsOf: resultURL, options: [.mappedIfSafe])
            record = try JSONDecoder().decode(XcircuitePlatformCapabilityTestExecutionRecord.self, from: data)
        } catch {
            appendDiagnostic(
                "test-evidence-result-invalid",
                "Retained test evidence result is not a valid execution record: \(evidence.evidenceID)."
            )
            return .failed
        }
        guard record.evidenceID == evidence.evidenceID,
              record.testFilter == evidence.testFilter,
              record.command == evidence.command,
              record.startedAt == provenance.startedAt,
              record.completedAt == provenance.completedAt,
              record.exitStatus == exitStatus,
              record.transcriptArtifact.producer == provenance.producer,
              evidence.retainedArtifacts == [record.transcriptArtifact],
              provenance.inputs.isEmpty else {
            appendDiagnostic(
                "test-evidence-result-binding-mismatch",
                "Retained execution record does not bind the declared evidence identity, command, timing, transcript, and exit status: \(evidence.evidenceID)."
            )
            return .failed
        }
        return exitStatus == 0 ? .passed : .failed
    }

    private func invocationContainsBoundedXcodebuildTest(
        _ invocation: ExecutionInvocation,
        filter: String
    ) -> Bool {
        guard let executable = invocation.executable else { return false }
        let command = [URL(fileURLWithPath: executable).lastPathComponent] + invocation.arguments
        return usesTimeoutWrapper(command)
            && usesXcodebuildTest(command)
            && self.command(command, containsTestFilter: filter)
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
        guard let xcodebuildIndex = command.firstIndex(where: { argument in
            URL(fileURLWithPath: argument).lastPathComponent == "xcodebuild"
        }) else { return false }
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
                    "dft",
                    "drc-signoff",
                    "electrical-signoff",
                    "layout-edit",
                    "logic-design",
                    "logic-execution",
                    "lvs-signoff",
                    "pex-extraction",
                    "physical-design",
                    "release",
                    "rtl-verification",
                    "simulation-analysis",
                    "timing-signoff",
                ],
                requiredOperations: [
                    "dft.scan",
                    "drc.run-native",
                    "electrical.signoff",
                    "layout-command-replay",
                    "logic.elaborate",
                    "logic.lower",
                    "logic.simulate",
                    "logic.synthesize",
                    "lvs.run-native",
                    "pex.extract",
                    "physical.floorplan",
                    "physical.place",
                    "physical.detailed-route",
                    "release.authorization",
                    "release.signoff",
                    "release.tapeout",
                    "rtl.lint",
                    "simulation.run-analysis",
                    "timing.signal-integrity",
                    "timing.sta",
                ],
                requiredArtifacts: [
                    "electrical-signoff-report",
                    "drc-artifact-manifest",
                    "layout-command-manifest",
                    "logic-execution-design",
                    "logic-simulation-report",
                    "mapped-design",
                    "lvs-artifact-manifest",
                    "parasitic-ir",
                    "physical-design",
                    "rtl-lint-report",
                    "simulation-summary",
                    "signoff-bundle",
                    "tapeout-release",
                    "test-design",
                    "timing-signal-integrity-result",
                    "timing-sta-result",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "drc-artifacts",
                    "electrical.signoff",
                    "execution-provenance",
                    "logic.elaborate",
                    "logic.lower",
                    "logic.simulate",
                    "logic.synthesize",
                    "lvs-artifacts",
                    "pex-flow-artifacts",
                    "physical.floorplan",
                    "physical.place",
                    "physical.detailed-route",
                    "release.authorization",
                    "release.signoff",
                    "release.tapeout",
                    "rtl.lint",
                    "simulation-summary",
                    "timing.signal-integrity",
                    "timing.sta",
                ],
                requiredTestEvidence: [
                    "xci-dft-stage-evidence",
                    "xci-electrical-signoff-stage-evidence",
                    "xci-logic-stage-evidence",
                    "xci-physical-stage-evidence",
                    "xci-release-stage-evidence",
                    "xci-rtl-verification-stage-evidence",
                    "xci-runtime-local-signoff-flow",
                    "xci-signoff-stage-artifact-gates",
                    "xci-timing-stage-evidence",
                    "production-qualified-release-flow",
                ]
            ),
            MilestoneSpec(
                milestoneID: "agent-operable-design-loop",
                title: "Agent-readable planning, command, evidence, and repair loop",
                requiredDomains: [
                    "electrical-signoff",
                    "drc-signoff",
                    "layout-edit",
                    "logic-design",
                    "logic-execution",
                    "lvs-signoff",
                    "pex-extraction",
                    "physical-design",
                    "rtl-verification",
                    "simulation-analysis",
                    "timing-signoff",
                ],
                requiredOperations: [
                    "drc.export-repair-hints",
                    "electrical.signoff",
                    "layout-command-replay",
                    "logic.elaborate",
                    "logic.lower",
                    "logic.simulate",
                    "logic.synthesize",
                    "lvs.export-repair-hints",
                    "pex.export-evidence-packet",
                    "physical.eco",
                    "rtl.lint",
                    "simulation.export-metric-report",
                    "timing.sta",
                ],
                requiredArtifacts: [
                    "drc-repair-hints",
                    "electrical-signoff-report",
                    "layout-command-result",
                    "logic-execution-design",
                    "logic-simulation-report",
                    "lvs-repair-hints",
                    "mapped-design",
                    "pex-evidence-packet",
                    "physical-design-diff",
                    "rtl-lint-report",
                    "simulation-metric-report",
                    "timing-sta-result",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "execution-provenance",
                    "logic.elaborate",
                    "logic.lower",
                    "logic.simulate",
                    "logic.synthesize",
                    "native-drc",
                    "native-lvs",
                    "physical.eco",
                    "rtl.lint",
                    "schema-validation",
                    "simulation-metric-gate",
                    "timing.sta",
                ],
                requiredTestEvidence: [
                    "xci-candidate-plan-verification-contract",
                    "xci-logic-stage-evidence",
                    "xci-numeric-repair-loop-feedback",
                    "xci-physical-stage-evidence",
                    "xci-rtl-verification-stage-evidence",
                    "xci-timing-stage-evidence",
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
                    "release",
                    "simulation-analysis",
                ],
                requiredOperations: [
                    "drc.waiver-review",
                    "layout-command-replay",
                    "lvs.waiver-review",
                    "pex.summarize-run",
                    "release.authorization",
                    "release.signoff",
                    "release.tapeout",
                    "simulation.summarize-run",
                ],
                requiredArtifacts: [
                    "drc-summary",
                    "layout-command-result",
                    "lvs-summary",
                    "pex-summary",
                    "release-authorization-decision",
                    "simulation-summary",
                    "signoff-bundle",
                    "tapeout-release",
                ],
                requiredVerificationGates: [
                    "approval-gate",
                    "artifact-integrity",
                    "human-review",
                    "pex-flow-artifacts",
                    "release.authorization",
                    "release.signoff",
                    "release.tapeout",
                    "simulation-summary",
                ],
                requiredTestEvidence: [
                    "xci-candidate-plan-verification-contract",
                    "xci-release-stage-evidence",
                    "xci-risk-approval-review-contract",
                    "production-qualified-release-flow",
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
                    "timing-signoff",
                ],
                requiredOperations: [
                    "drc.import-foundry-rule-seed",
                    "layout-command-replay",
                    "pex.parse-spef",
                    "simulation.import-spice",
                    "timing.sta",
                ],
                requiredArtifacts: [
                    "drc-foundry-rule-import-report",
                    "layout-document",
                    "parasitic-ir",
                    "simulation-netlist",
                    "timing-sta-result",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "deck-readiness",
                    "import-coverage",
                    "schema-validation",
                    "timing.sta",
                ],
                requiredTestEvidence: [
                    "drc-foundry-rule-import-agent-envelope",
                    "xci-platform-readiness-contract",
                    "xci-timing-stage-evidence",
                ]
            ),
            MilestoneSpec(
                milestoneID: "post-layout-improvement-loop",
                title: "Post-layout degradation analysis and improvement planning",
                requiredDomains: [
                    "electrical-signoff",
                    "layout-edit",
                    "pex-extraction",
                    "physical-design",
                    "simulation-analysis",
                    "timing-signoff",
                ],
                requiredOperations: [
                    "layout-command-replay",
                    "electrical.signoff",
                    "pex.metric-recovery-objective",
                    "physical.eco",
                    "simulation.compare-post-layout",
                    "timing.signal-integrity",
                    "timing.sta",
                ],
                requiredArtifacts: [
                    "layout-command-result",
                    "electrical-signoff-report",
                    "parasitic-ir",
                    "planning-problem",
                    "post-layout-comparison",
                    "physical-design-diff",
                    "timing-signal-integrity-result",
                    "timing-sta-result",
                ],
                requiredVerificationGates: [
                    "artifact-integrity",
                    "pex-flow-artifacts",
                    "physical.eco",
                    "simulation-metric-gate",
                    "timing.signal-integrity",
                    "timing.sta",
                ],
                requiredTestEvidence: [
                    "xci-post-layout-comparison-gate",
                    "xci-numeric-repair-loop-feedback",
                    "xci-electrical-signoff-stage-evidence",
                    "xci-physical-stage-evidence",
                    "xci-timing-stage-evidence",
                ]
            ),
        ]
    }

    private func defaultTestEvidence() -> [XcircuitePlatformCapabilityTestEvidence] {
        [
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-logic-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/LogicEngineFlowStageExecutorTests"
                ),
                testFilter: "LogicEngineFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "agent-operable-design-loop"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["logic-execution-design", "logic-simulation-report", "mapped-design", "logic-equivalence-evidence"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-rtl-verification-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/RTLVerificationFlowStageExecutorTests"
                ),
                testFilter: "RTLVerificationFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "agent-operable-design-loop"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["rtl-lint-report", "rtl-verification-evidence"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-dft-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/DFTFlowStageExecutorTests"
                ),
                testFilter: "DFTFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["test-design", "scan-report", "dft-oracle-correlation"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-physical-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/PhysicalDesignFlowStageExecutorTests"
                ),
                testFilter: "PhysicalDesignFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "agent-operable-design-loop", "post-layout-improvement-loop"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["physical-design", "physical-report", "physical-design-review-packet"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-timing-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/TimingHeadlessFlowTests"
                ),
                testFilter: "TimingHeadlessFlowTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "agent-operable-design-loop", "standard-format-grounding", "post-layout-improvement-loop"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["timing-sta-result", "timing-signal-integrity-result"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-electrical-signoff-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/ElectricalSignoffFlowStageExecutorTests"
                ),
                testFilter: "ElectricalSignoffFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "post-layout-improvement-loop"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate"],
                coveredArtifactKinds: ["electrical-signoff-report", "electrical-corpus-report"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-release-stage-evidence",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/ReleaseFlowStageExecutorTests"
                ),
                testFilter: "ReleaseFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff", "human-review-audit"],
                coveredRequirementKinds: ["successful-stage-execution", "artifact", "execution-provenance", "verification-gate", "human-review"],
                coveredArtifactKinds: ["release-authorization-decision", "signoff-bundle", "tapeout-release"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-runtime-local-signoff-flow",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteFlowRuntimeTests/runtimeProgressFollowStreamsLayoutDRCLVSPEXStages()"
                ),
                testFilter: "XcircuiteFlowRuntimeTests/runtimeProgressFollowStreamsLayoutDRCLVSPEXStages()",
                coveredMilestoneIDs: ["standalone-local-signoff"],
                coveredRequirementKinds: ["operation", "artifact", "verification-gate"],
                coveredArtifactKinds: ["run-manifest", "progress-events", "stage-artifacts"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-signoff-stage-artifact-gates",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/SignoffFlowStageExecutorTests"
                ),
                testFilter: "SignoffFlowStageExecutorTests",
                coveredMilestoneIDs: ["standalone-local-signoff"],
                coveredRequirementKinds: ["artifact", "verification-gate"],
                coveredArtifactKinds: ["drc-summary", "lvs-summary", "artifact-manifest"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-candidate-plan-verification-contract",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteCandidatePlanVerifierTests/verifyCandidatePlanCLIWritesPlanVerificationAndActionRecord()"
                ),
                testFilter: "XcircuiteCandidatePlanVerifierTests/verifyCandidatePlanCLIWritesPlanVerificationAndActionRecord()",
                coveredMilestoneIDs: ["agent-operable-design-loop", "human-review-audit"],
                coveredRequirementKinds: ["operation", "artifact", "verification-gate", "human-review"],
                coveredArtifactKinds: ["planning/plan-verification/<sha256>.json", "actions.jsonl"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-risk-approval-review-contract",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteCandidatePlanVerifierTests/recordedRiskApprovalPassesSyntheticApprovalGate()"
                ),
                testFilter: "XcircuiteCandidatePlanVerifierTests/recordedRiskApprovalPassesSyntheticApprovalGate()",
                coveredMilestoneIDs: ["human-review-audit"],
                coveredRequirementKinds: ["approval-gate", "human-review"],
                coveredArtifactKinds: ["approval-record", "planning/plan-verification/<sha256>.json"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "drc-foundry-rule-import-agent-envelope",
                packagePath: "DRCEngine",
                invocation: xcodebuildTestInvocation(
                    scheme: "DRCEngine-Package",
                    onlyTesting: "DRCCLICoreTests/DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope()"
                ),
                testFilter: "DRCCLIOptionsTests/foundryRuleImportCLIEmitsDecodableAgentEnvelope()",
                coveredMilestoneIDs: ["standard-format-grounding"],
                coveredRequirementKinds: ["standard-format", "artifact", "cli-json"],
                coveredArtifactKinds: ["layout-tech-database", "drc-foundry-rule-import-report"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-platform-readiness-contract",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuitePlatformCapabilityReadinessTests"
                ),
                testFilter: "XcircuitePlatformCapabilityReadinessTests",
                coveredMilestoneIDs: ["standard-format-grounding"],
                coveredRequirementKinds: ["readiness", "cli-json", "regression-gate"],
                coveredArtifactKinds: ["platform-capability-readiness-report"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-post-layout-comparison-gate",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/PostLayoutComparisonFlowStageExecutorTests/comparisonReportArtifactAndGatePass()"
                ),
                testFilter: "PostLayoutComparisonFlowStageExecutorTests/comparisonReportArtifactAndGatePass()",
                coveredMilestoneIDs: ["post-layout-improvement-loop"],
                coveredRequirementKinds: ["post-layout", "artifact", "verification-gate"],
                coveredArtifactKinds: ["post-layout-comparison"]
            ),
            XcircuitePlatformCapabilityTestEvidence(
                evidenceID: "xci-numeric-repair-loop-feedback",
                packagePath: "Xcircuite",
                invocation: xcodebuildTestInvocation(
                    scheme: "Xcircuite-Package",
                    onlyTesting: "XcircuiteTests/XcircuiteNumericRepairLoopRunnerTests/numericRepairLoopCLIExecutesRejectedFeedbackLoopUntilSimulationMetricPasses()"
                ),
                testFilter: "XcircuiteNumericRepairLoopRunnerTests/numericRepairLoopCLIExecutesRejectedFeedbackLoopUntilSimulationMetricPasses()",
                coveredMilestoneIDs: ["agent-operable-design-loop", "post-layout-improvement-loop"],
                coveredRequirementKinds: ["repair-loop", "feedback", "simulation-metric-gate"],
                coveredArtifactKinds: ["planning/numeric-repair-loop.json", "planning/rejected-plans.jsonl"]
            ),
        ]
    }

    private func xcodebuildTestInvocation(
        timeoutSeconds: Int = 120,
        scheme: String,
        onlyTesting: String
    ) -> XcircuiteXcodebuildTestInvocation {
        XcircuiteXcodebuildTestInvocation(
            timeoutSeconds: timeoutSeconds,
            scheme: scheme,
            onlyTesting: onlyTesting
        )
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
