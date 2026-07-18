import CircuiteFoundation
import DesignFlowKernel
import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport

@Suite("Xcircuite verified improvement corpus")
struct XcircuiteVerifiedImprovementCorpusTests {
    @Test func assessVerifiedImprovementCorpusCollectsDRCLVSPEXNumericCases() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let cases = [
            try await prepareCase(
                root: root,
                workspaceStore: workspaceStore,
                runID: "run-drc",
                family: .drc,
                status: "accepted",
                accepted: true,
                diagnosticCode: "drc-rule-cleared",
                gateID: "native-drc"
            ),
            try await prepareCase(
                root: root,
                workspaceStore: workspaceStore,
                runID: "run-lvs",
                family: .lvs,
                status: "rejected",
                accepted: false,
                diagnosticCode: "lvs-device-count",
                gateID: "native-lvs"
            ),
            try await prepareCase(
                root: root,
                workspaceStore: workspaceStore,
                runID: "run-pex",
                family: .pex,
                status: "accepted",
                accepted: true,
                diagnosticCode: "pex-corner-recovered",
                gateID: "post-layout-pex"
            ),
            try await prepareCase(
                root: root,
                workspaceStore: workspaceStore,
                runID: "run-numeric",
                family: .numeric,
                status: "iteration-limit-reached",
                accepted: false,
                diagnosticCode: "metric-failed",
                gateID: "simulation-metric-gate"
            ),
        ]

        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-suite",
            cases: cases
        )
        let suiteURL = root.appending(path: "verified-improvement-suite.json")
        try await writeJSON(suiteSpec, to: suiteURL)

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "assess-verified-improvement-corpus",
            "--project-root",
            root.path(percentEncoded: false),
            "--suite-spec",
            suiteURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let data = try #require(output.data(using: .utf8))
        let report = try JSONDecoder().decode(XcircuiteVerifiedImprovementCorpusReport.self, from: data)

        #expect(report.status == .passed)
        #expect(report.summary.caseCount == 4)
        #expect(report.summary.passedCaseCount == 4)
        #expect(report.summary.failedCaseCount == 0)
        #expect(report.summary.acceptedCaseCount == 2)
        #expect(report.summary.rejectedCaseCount == 2)
        #expect(report.summary.missingFamilies == [])
        #expect(report.summary.familyCounts == [
            "drc": 1,
            "lvs": 1,
            "numeric": 1,
            "pex": 1,
        ])
        #expect(report.summary.sourceDiagnosticCoverageCount == 4)
        #expect(report.summary.designDiffArtifactCount == 4)
        #expect(report.summary.verificationArtifactCount == 4)
        #expect(report.summary.improvementArtifactCount == 4)
        #expect(report.suiteSpecArtifact?.artifactID == "verified-improvement-corpus-suite")
        #expect(report.reportArtifact?.artifactID == "verified-improvement-corpus-report")
        #expect(report.reportArtifact?.path == ".xcircuite/assessments/verified-improvement/verified-improvement-suite/corpus-report.json")

        let lvsCase = try #require(report.caseResults.first { $0.caseID == "case-run-lvs" })
        #expect(lvsCase.status == .passed)
        #expect(lvsCase.observedStatus == "rejected")
        #expect(lvsCase.accepted == false)
        #expect(lvsCase.diagnosticCodes.contains("lvs-device-count"))
        #expect(lvsCase.failedGateIDs.contains("native-lvs"))
        #expect(lvsCase.missingDiagnosticCodes == [])
        #expect(lvsCase.missingFailedGateIDs == [])
        #expect(lvsCase.missingArtifactIDs == [])

        let pexCase = try #require(report.caseResults.first { $0.caseID == "case-run-pex" })
        #expect(pexCase.observedStatus == "accepted")
        #expect(pexCase.accepted == true)
        #expect(pexCase.artifactRefs.contains { $0.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID })
        #expect(pexCase.artifactRefs.contains { $0.artifactID == "planning-design-diff" })

        let projectManifest = try await workspaceStore.loadManifest()
        #expect(projectManifest.files.contains {
            $0.artifactID == "verified-improvement-corpus-suite"
        })
        #expect(projectManifest.files.contains {
            $0.artifactID == "verified-improvement-corpus-report"
        })
    }

    @Test func assessVerifiedImprovementCorpusReportsInvalidSuiteSpecPath() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-invalid-json")
        defer { removeTemporaryRoot(root) }
        let suiteURL = root.appending(path: "invalid-suite.json")
        try "{".write(to: suiteURL, atomically: true, encoding: .utf8)

        do {
            _ = try await XcircuiteFlowCLICommand.run(arguments: [
                "assess-verified-improvement-corpus",
                "--project-root",
                root.path(percentEncoded: false),
                "--suite-spec",
                suiteURL.path(percentEncoded: false),
            ])
            Issue.record("Expected invalid suite spec failure")
        } catch let error as XcircuiteFlowCLIError {
            guard case .readFailed(let reason) = error else {
                Issue.record("Expected readFailed, got \(error)")
                return
            }
            #expect(reason.contains("Invalid JSON for --suite-spec"))
            #expect(reason.contains(suiteURL.path(percentEncoded: false)))
        }
    }

    @Test func assessVerifiedImprovementCorpusReportsMissingEvidence() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-missing")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let caseSpec = try await prepareCase(
            root: root,
            workspaceStore: workspaceStore,
            runID: "run-missing",
            family: .drc,
            status: "accepted",
            accepted: true,
            diagnosticCode: "drc-rule-cleared",
            gateID: "native-drc",
            includeDesignDiff: false
        )
        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-missing-suite",
            requiredFamilies: [.drc],
            cases: [
                XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec(
                    caseID: caseSpec.caseID,
                    runID: caseSpec.runID,
                    family: caseSpec.family,
                    expectedStatus: caseSpec.expectedStatus,
                    expectedAccepted: caseSpec.expectedAccepted,
                    requiredDiagnosticCodes: ["diagnostic-not-present"],
                    requiredFailedGateIDs: [],
                    requiredArtifactIDs: ["planning-design-diff"]
                ),
            ]
        )

        let report = try await XcircuiteVerifiedImprovementCorpusAssessor(
            storage: workspaceStore
        ).assess(suiteSpec: suiteSpec)

        #expect(report.status == .failed)
        #expect(report.summary.caseCount == 1)
        #expect(report.summary.failedCaseCount == 1)
        let result = try #require(report.caseResults.first)
        #expect(result.status == .failed)
        #expect(result.missingDiagnosticCodes == ["diagnostic-not-present"])
        #expect(result.missingArtifactIDs == ["planning-design-diff"])
    }

    @Test func assessVerifiedImprovementCorpusRejectsAmbiguousCanonicalManifest() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-duplicate-artifact")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let caseSpec = try await prepareCase(
            root: root,
            workspaceStore: workspaceStore,
            runID: "run-duplicate-artifact",
            family: .drc,
            status: "accepted",
            accepted: true,
            diagnosticCode: "drc-rule-cleared",
            gateID: "native-drc"
        )
        let manifestURL = runLedgerURL(root: root, runID: caseSpec.runID)
        let manifest = try await workspaceStore.loadRunLedger(runID: caseSpec.runID).runManifest
        let numericLoopReference = try #require(
            manifest.artifacts.first {
                $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
            }
        )
        try XcircuiteRunLedgerTamper.append([numericLoopReference], to: manifestURL)

        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-duplicate-artifact-suite",
            cases: [caseSpec]
        )
        let report = try await XcircuiteVerifiedImprovementCorpusAssessor(
            storage: workspaceStore
        ).assess(suiteSpec: suiteSpec)

        #expect(report.status == .failed)
        let result = try #require(report.caseResults.first)
        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "artifact-reference-duplicate" })
        #expect(!result.artifactRefs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
        })
    }

    @Test func assessVerifiedImprovementCorpusAcceptsExplicitManifestLoopPaths() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-explicit-manifest-paths")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let caseSpec = try await prepareCase(
            root: root,
            workspaceStore: workspaceStore,
            runID: "run-explicit-manifest-paths",
            family: .drc,
            status: "accepted",
            accepted: true,
            diagnosticCode: "drc-rule-cleared",
            gateID: "native-drc"
        )
        let manifest = try await workspaceStore.loadRunLedger(runID: caseSpec.runID).runManifest
        let numericLoopReference = try #require(
            manifest.artifacts.first {
                $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
            }
        )
        let improvementLoopReference = try #require(
            manifest.artifacts.first {
                $0.artifactID == XcircuitePlanningArtifactStore.improvementLoopArtifactID
            }
        )
        let explicitCaseSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec(
            caseID: caseSpec.caseID,
            runID: caseSpec.runID,
            family: caseSpec.family,
            expectedStatus: caseSpec.expectedStatus,
            expectedAccepted: caseSpec.expectedAccepted,
            requiredDiagnosticCodes: caseSpec.requiredDiagnosticCodes,
            requiredFailedGateIDs: caseSpec.requiredFailedGateIDs,
            requiredArtifactIDs: caseSpec.requiredArtifactIDs,
            numericRepairLoopPath: numericLoopReference.path,
            improvementLoopPath: improvementLoopReference.path
        )
        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-explicit-manifest-paths-suite",
            requiredFamilies: [.drc],
            cases: [explicitCaseSpec]
        )

        let report = try await XcircuiteVerifiedImprovementCorpusAssessor(
            storage: workspaceStore
        ).assess(suiteSpec: suiteSpec)

        #expect(report.status == .passed)
        let result = try #require(report.caseResults.first)
        #expect(result.status == .passed)
        #expect(result.artifactRefs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
                && $0.path == numericLoopReference.path
        })
        #expect(result.artifactRefs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.improvementLoopArtifactID
                && $0.path == improvementLoopReference.path
        })
    }

    @Test func assessVerifiedImprovementCorpusRejectsExplicitLoopPathOutsideRunManifest() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-explicit-path-mismatch")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let caseSpec = try await prepareCase(
            root: root,
            workspaceStore: workspaceStore,
            runID: "run-explicit-path-mismatch",
            family: .drc,
            status: "accepted",
            accepted: true,
            diagnosticCode: "drc-rule-cleared",
            gateID: "native-drc"
        )
        let manifest = try await workspaceStore.loadRunLedger(runID: caseSpec.runID).runManifest
        let numericLoopReference = try #require(
            manifest.artifacts.first {
                $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
            }
        )
        let copiedNumericLoopPath = ".xcircuite/runs/\(caseSpec.runID)/planning/numeric-repair-loop-copy.json"
        let numericLoopData = try await workspaceStore.read(from: numericLoopReference.path)
        try await workspaceStore.write(numericLoopData, to: copiedNumericLoopPath)

        let explicitCaseSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec(
            caseID: caseSpec.caseID,
            runID: caseSpec.runID,
            family: caseSpec.family,
            expectedStatus: caseSpec.expectedStatus,
            expectedAccepted: caseSpec.expectedAccepted,
            requiredDiagnosticCodes: caseSpec.requiredDiagnosticCodes,
            requiredFailedGateIDs: caseSpec.requiredFailedGateIDs,
            requiredArtifactIDs: caseSpec.requiredArtifactIDs,
            numericRepairLoopPath: copiedNumericLoopPath
        )
        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-explicit-path-mismatch-suite",
            requiredFamilies: [.drc],
            cases: [explicitCaseSpec]
        )

        let report = try await XcircuiteVerifiedImprovementCorpusAssessor(
            storage: workspaceStore
        ).assess(suiteSpec: suiteSpec)

        #expect(report.status == .failed)
        let result = try #require(report.caseResults.first)
        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "artifact-reference-mismatch" })
        #expect(!result.artifactRefs.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.numericRepairLoopArtifactID
                && $0.path == copiedNumericLoopPath
        })
    }

    @Test func assessVerifiedImprovementCorpusRejectsTamperedPlanVerificationArtifact() async throws {
        let root = try makeTemporaryRoot("verified-improvement-corpus-tampered-plan-verification")
        defer { removeTemporaryRoot(root) }
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.createWorkspace()

        let caseSpec = try await prepareCase(
            root: root,
            workspaceStore: workspaceStore,
            runID: "run-tampered-verification",
            family: .pex,
            status: "accepted",
            accepted: true,
            diagnosticCode: "pex-corner-recovered",
            gateID: "post-layout-pex"
        )
        let manifest = try await workspaceStore.loadRunLedger(runID: caseSpec.runID).runManifest
        let planVerificationReference = try #require(
            manifest.artifacts.first {
                $0.artifactID == XcircuitePlanningArtifactStore.planVerificationArtifactID
            }
        )
        try Data(#"{"tampered":true}"#.utf8).write(
            to: root.appending(path: planVerificationReference.path),
            options: [.atomic]
        )

        let suiteSpec = XcircuiteVerifiedImprovementCorpusSuiteSpec(
            suiteID: "verified-improvement-tampered-artifact-suite",
            cases: [caseSpec]
        )
        let report = try await XcircuiteVerifiedImprovementCorpusAssessor(
            storage: workspaceStore
        ).assess(suiteSpec: suiteSpec)

        #expect(report.status == .failed)
        let result = try #require(report.caseResults.first)
        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "artifact-integrity-failed" })
    }

    private func prepareCase(
        root: URL,
        workspaceStore: XcircuiteWorkspaceStore,
        runID: String,
        family: XcircuiteVerifiedImprovementCorpusFamily,
        status: String,
        accepted: Bool,
        diagnosticCode: String,
        gateID: String,
        includeDesignDiff: Bool = true
    ) async throws -> XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec {
        try await prepareTestRun(runID: runID, store: workspaceStore)
        let planningStore = XcircuitePlanningArtifactStore(workspaceStore: workspaceStore)
        let candidatePlanRef = try await writePlanningArtifact(
            root: root,
            workspaceStore: workspaceStore,
            runID: runID,
            fileName: "candidate-plan.json",
            artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            kind: .other,
            value: FixtureArtifact(kind: "candidate-plan", runID: runID)
        )

        let designDiffRef: ArtifactReference?
        if includeDesignDiff {
            designDiffRef = try await writePlanningArtifact(
                root: root,
                workspaceStore: workspaceStore,
                runID: runID,
                fileName: "design-diff.json",
                artifactID: "planning-design-diff",
                kind: .designDiff,
                value: FixtureArtifact(kind: "design-diff", runID: runID)
            )
        } else {
            designDiffRef = nil
        }

        let verificationDiagnostic = XcircuitePlanVerificationDiagnostic(
            severity: accepted ? "info" : "error",
            code: diagnosticCode,
            message: "\(diagnosticCode) observed for \(runID).",
            stepID: "step-\(runID)",
            gateID: accepted ? nil : gateID
        )
        let verification = XcircuitePlanVerification(
            problemID: "problem-\(runID)",
            planID: "plan-\(runID)",
            runID: runID,
            verificationMode: "post-execution",
            candidatePlanRef: candidatePlanRef,
            stepResults: [
                XcircuitePlanVerificationStepResult(
                    stepID: "step-\(runID)",
                    order: 0,
                    actionID: "action-\(runID)",
                    domainID: family.rawValue,
                    operationID: "\(family.rawValue).repair",
                    status: accepted ? "accepted" : "rejected",
                    gateIDs: [gateID],
                    diagnostics: [verificationDiagnostic],
                    producedArtifactRefs: [designDiffRef].compactMap { $0 }
                ),
            ],
            gateResults: [
                XcircuitePlanVerificationGateResult(
                    gateID: gateID,
                    required: true,
                    status: accepted ? "passed" : "failed",
                    sourceStepIDs: ["step-\(runID)"],
                    diagnostics: accepted ? [] : [verificationDiagnostic]
                ),
            ],
            artifactRefs: [designDiffRef].compactMap { $0 },
            diagnostics: [verificationDiagnostic],
            accepted: accepted,
            nextActions: accepted ? [] : ["repair-\(gateID)"]
        )
        let verificationRef = try await planningStore.persistPlanVerification(
            verification,
            runID: runID,
            projectRoot: root
        )

        let numericLoop = XcircuiteNumericRepairLoopResult(
            status: status,
            runID: runID,
            problemID: "problem-\(runID)",
            loopArtifactPath: ".xcircuite/runs/\(runID)/planning/numeric-repair-loop.json",
            maxIterations: 1,
            iterationCount: 1,
            accepted: accepted,
            acceptedIterationIndex: accepted ? 0 : nil,
            selectedCandidateID: "candidate-\(runID)",
            finalPlanID: "plan-\(runID)",
            iterations: [
                XcircuiteNumericRepairLoopIteration(
                    iterationIndex: 0,
                    status: status,
                    candidateGenerationStrategy: "fixture-candidate-generation",
                    synthesisStrategy: "fixture-synthesis",
                    verificationMode: "post-execution",
                    candidateGenerationStatus: "generated",
                    selectedCandidateID: "candidate-\(runID)",
                    selectedCandidateRank: 1,
                    planID: "plan-\(runID)",
                    executionStatus: accepted ? "succeeded" : "completed",
                    verificationStatus: accepted ? "accepted" : "rejected",
                    accepted: accepted,
                    candidatePlanArtifact: candidatePlanRef,
                    designDiffArtifact: designDiffRef,
                    producedArtifacts: [designDiffRef].compactMap { $0 },
                    planVerificationArtifact: verificationRef,
                    diagnostics: [
                        XcircuiteNumericRepairLoopDiagnostic(
                            severity: accepted ? "info" : "warning",
                            code: diagnosticCode,
                            message: "\(diagnosticCode) observed in numeric loop.",
                            iterationIndex: 0
                        ),
                    ],
                    nextActions: accepted ? [] : ["inspect-\(gateID)"]
                ),
            ],
            diagnostics: [
                XcircuiteNumericRepairLoopDiagnostic(
                    severity: accepted ? "info" : "warning",
                    code: diagnosticCode,
                    message: "\(diagnosticCode) observed in run \(runID).",
                    iterationIndex: 0
                ),
            ],
            nextActions: accepted ? [] : ["inspect-\(gateID)"]
        )
        _ = try await planningStore.persistNumericRepairLoop(numericLoop, runID: runID, projectRoot: root)

        let improvementLoop = XcircuiteImprovementLoopResult(
            runID: runID,
            problemID: "problem-\(runID)",
            loopID: "improvement-\(runID)",
            status: status,
            iterationCount: 1,
            acceptedCandidateID: accepted ? "candidate-\(runID)" : nil,
            iterations: [
                XcircuiteImprovementLoopResult.Iteration(
                    iterationIndex: 0,
                    status: status,
                    selectedCandidateID: "candidate-\(runID)",
                    accepted: accepted,
                    producedArtifactIDs: (
                        [XcircuitePlanningArtifactStore.planVerificationArtifactID]
                            + (includeDesignDiff ? ["planning-design-diff"] : [])
                    ),
                    failedGateIDs: accepted ? [] : [gateID]
                ),
            ],
            diagnostics: [diagnosticCode],
            nextActions: accepted ? [] : ["inspect-\(gateID)"]
        )
        _ = try await planningStore.persistImprovementLoop(improvementLoop, runID: runID, projectRoot: root)

        return XcircuiteVerifiedImprovementCorpusSuiteSpec.CaseSpec(
            caseID: "case-\(runID)",
            runID: runID,
            family: family,
            expectedStatus: status,
            expectedAccepted: accepted,
            requiredDiagnosticCodes: [diagnosticCode],
            requiredFailedGateIDs: accepted ? [] : [gateID],
            requiredArtifactIDs: [
                XcircuitePlanningArtifactStore.numericRepairLoopArtifactID,
                XcircuitePlanningArtifactStore.improvementLoopArtifactID,
                XcircuitePlanningArtifactStore.planVerificationArtifactID,
                "planning-design-diff",
            ]
        )
    }

    private func writePlanningArtifact<T: Encodable>(
        root: URL,
        workspaceStore: XcircuiteWorkspaceStore,
        runID: String,
        fileName: String,
        artifactID: String,
        kind: ArtifactKind,
        value: T
    ) async throws -> ArtifactReference {
        let relativePath = ".xcircuite/runs/\(runID)/planning/\(fileName)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try await workspaceStore.persistArtifact(
            content: encoder.encode(value),
            id: ArtifactID(rawValue: artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: relativePath),
                role: .output,
                kind: kind,
                format: .json
            ),
            runID: runID,
            mode: .replaceable
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root \(root.path(percentEncoded: false)): \(error)")
        }
    }

    private func runLedgerURL(root: URL, runID: String) -> URL {
        root.appending(path: ".xcircuite/runs/\(runID)/ledger.json")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private struct FixtureArtifact: Encodable {
        var kind: String
        var runID: String
    }
}
