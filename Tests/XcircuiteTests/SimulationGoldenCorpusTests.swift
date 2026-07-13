import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Simulation golden corpus", .timeLimit(.minutes(1)))
struct SimulationGoldenCorpusTests {
    @Test func runnerExecutesCheckedInGoldenCorpusAndPersistsCaseArtifacts() async throws {
        let packageRoot = packageRoot()
        let artifactDirectory = try makeTemporaryRoot("simulation-golden-corpus-runner")
        defer { removeTemporaryRoot(artifactDirectory) }
        let suite = try SimulationGoldenCorpusSuiteSpec.load(from: suiteURL(packageRoot: packageRoot))

        let report = try await SimulationGoldenCorpusRunner().run(
            suite: suite,
            projectRoot: packageRoot,
            artifactDirectory: artifactDirectory
        )

        #expect(report.status == "passed")
        #expect(report.summary.caseCount == 5)
        #expect(report.summary.passedCaseCount == 5)
        #expect(report.coverageTags.contains("simulation.analysis.dc"))
        #expect(report.coverageTags.contains("simulation.analysis.ac"))
        #expect(report.coverageTags.contains("simulation.analysis.tran"))
        #expect(report.coverageTags.contains("simulation.diagnostic.parser"))
        #expect(report.coverageTags.contains("simulation.diagnostic.model"))
        #expect(report.coverageTags.contains("simulation.failure.expected"))
        #expect(report.coverageTags.contains("simulation.waveform.branch-current"))
        #expect(report.coverageTags.contains("simulation.waveform.complex-frequency"))
        #expect(report.coverageTags.contains("simulation.waveform.semantic-node"))
        #expect(report.coverageTags.contains("simulation.waveform.time-domain"))

        let caseByID = Dictionary(uniqueKeysWithValues: report.cases.map { ($0.caseID, $0) })
        let dcCase = try #require(caseByID["dc-resistor-sweep"])
        let acCase = try #require(caseByID["ac-rc-low-pass"])
        let transientCase = try #require(caseByID["tran-rc-step"])
        let parserFailureCase = try #require(caseByID["parser-undefined-parameter"])
        let modelFailureCase = try #require(caseByID["model-missing-subcircuit"])

        #expect(dcCase.analysisLabel == "dc")
        #expect(acCase.analysisLabel == "ac")
        #expect(transientCase.analysisLabel == "tran")
        #expect(parserFailureCase.observedGateStatus == "failed")
        #expect(parserFailureCase.diagnostics.contains { $0.contains("Undefined parameter") })
        #expect(modelFailureCase.observedGateStatus == "failed")
        #expect(modelFailureCase.diagnostics.contains { $0.contains("Undefined subcircuit") })
        #expect(dcCase.comparison?.comparedVariables.map(\.variableName) == ["V(in)", "I(v1)"])
        #expect(acCase.comparison?.comparedVariables.map(\.variableName) == [
            "V(in)_real",
            "V(in)_imag",
            "V(out)_real",
            "V(out)_imag",
            "I(v1)_real",
            "I(v1)_imag",
        ])
        #expect(transientCase.comparison?.comparedVariables.map(\.variableName) == ["V(in)", "V(out)", "I(v1)"])

        for caseResult in report.cases {
            #expect(caseResult.status == "passed")
            if caseResult.expectedGateStatus == "passed" {
                #expect(caseResult.observedGateStatus == "passed")
                #expect(caseResult.comparison?.gateStatus == "passed")
                let waveformArtifact = try #require(caseResult.candidateWaveformArtifact)
                let comparisonArtifact = try #require(caseResult.comparisonArtifact)
                #expect(waveformArtifact.sha256.count == 64)
                #expect(comparisonArtifact.sha256.count == 64)
                #expect(waveformArtifact.byteCount > 0)
                #expect(comparisonArtifact.byteCount > 0)
                #expect(FileManager.default.fileExists(atPath: waveformArtifact.path))
                #expect(FileManager.default.fileExists(atPath: comparisonArtifact.path))
            } else {
                #expect(caseResult.observedGateStatus == "failed")
                #expect(caseResult.candidateWaveformArtifact == nil)
                #expect(caseResult.comparisonArtifact == nil)
                #expect(!caseResult.diagnostics.isEmpty)
            }
        }
    }

    @Test func runnerRejectsUnsafeCaseIDBeforeArtifactWrite() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-unsafe-case")
        let artifactRoot = try makeTemporaryRoot("simulation-golden-unsafe-case-artifacts")
        defer {
            removeTemporaryRoot(projectRoot)
            removeTemporaryRoot(artifactRoot)
        }
        try writeMinimalCorpusInputs(projectRoot: projectRoot)
        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "unsafe-case-suite",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "../escape",
                    netlistPath: "fixtures/input.cir",
                    goldenWaveformPath: "fixtures/golden.csv",
                    expectedGateStatus: "passed"
                ),
            ]
        )

        await #expect(throws: SimulationGoldenCorpusRunnerError.invalidIdentifier(
            kind: "caseID",
            value: "../escape"
        )) {
            _ = try await SimulationGoldenCorpusRunner().run(
                suite: suite,
                projectRoot: projectRoot,
                artifactDirectory: artifactRoot
            )
        }
        let escapedPath = artifactRoot
            .deletingLastPathComponent()
            .appending(path: "escape")
            .path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: escapedPath))
    }

    @Test func runnerRejectsAbsoluteCorpusPathBeforeExpectedFailureEvaluation() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-absolute-path")
        let artifactRoot = try makeTemporaryRoot("simulation-golden-absolute-path-artifacts")
        defer {
            removeTemporaryRoot(projectRoot)
            removeTemporaryRoot(artifactRoot)
        }
        try writeMinimalCorpusInputs(projectRoot: projectRoot)
        let absoluteNetlistPath = projectRoot
            .appending(path: "fixtures")
            .appending(path: "input.cir")
            .path(percentEncoded: false)
        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "absolute-path-suite",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "absolute-path-case",
                    netlistPath: absoluteNetlistPath,
                    goldenWaveformPath: "fixtures/golden.csv",
                    expectedGateStatus: "failed",
                    expectedDiagnosticSubstrings: ["project-relative"]
                ),
            ]
        )

        await #expect(throws: SimulationGoldenCorpusRunnerError.invalidProjectRelativePath(
            absoluteNetlistPath
        )) {
            _ = try await SimulationGoldenCorpusRunner().run(
                suite: suite,
                projectRoot: projectRoot,
                artifactDirectory: artifactRoot
            )
        }
    }

    @Test func runnerRejectsDottedCorpusPathBeforeExecution() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-dotted-path")
        let artifactRoot = try makeTemporaryRoot("simulation-golden-dotted-path-artifacts")
        defer {
            removeTemporaryRoot(projectRoot)
            removeTemporaryRoot(artifactRoot)
        }
        try writeMinimalCorpusInputs(projectRoot: projectRoot)
        let dottedNetlistPath = "fixtures/./input.cir"
        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "dotted-path-suite",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "dotted-path-case",
                    netlistPath: dottedNetlistPath,
                    goldenWaveformPath: "fixtures/golden.csv",
                    expectedGateStatus: "failed",
                    expectedDiagnosticSubstrings: ["project-relative"]
                ),
            ]
        )

        await #expect(throws: SimulationGoldenCorpusRunnerError.pathEscapesProjectRoot(
            dottedNetlistPath
        )) {
            _ = try await SimulationGoldenCorpusRunner().run(
                suite: suite,
                projectRoot: projectRoot,
                artifactDirectory: artifactRoot
            )
        }
    }

    @Test func runnerRejectsExpectedFailureWithoutDiagnosticContract() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-vacuous-expected-failure")
        defer { removeTemporaryRoot(projectRoot) }
        try writeMinimalCorpusInputs(projectRoot: projectRoot)
        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "vacuous-expected-failure-suite",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "vacuous-expected-failure",
                    netlistPath: "fixtures/input.cir",
                    goldenWaveformPath: "fixtures/golden.csv",
                    expectedGateStatus: "failed"
                ),
            ]
        )

        await #expect(throws: SimulationGoldenCorpusRunnerError.expectedFailureRequiresDiagnostics(
            caseID: "vacuous-expected-failure"
        )) {
            _ = try await SimulationGoldenCorpusRunner().run(
                suite: suite,
                projectRoot: projectRoot
            )
        }
    }

    @Test func runnerDoesNotAcceptMissingGoldenFileAsExpectedFailure() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-missing-golden")
        defer { removeTemporaryRoot(projectRoot) }
        try writeText(
            """
            * minimal simulation golden corpus fixture
            V1 in 0 0
            R1 in 0 1k
            .dc V1 0 1 1
            .end
            """,
            toProjectPath: "fixtures/input.cir",
            projectRoot: projectRoot
        )
        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "missing-golden-suite",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "missing-golden",
                    netlistPath: "fixtures/input.cir",
                    goldenWaveformPath: "fixtures/missing-golden.csv",
                    expectedGateStatus: "failed",
                    expectedDiagnosticSubstrings: [
                        "Simulation golden corpus infrastructure error",
                    ]
                ),
            ]
        )

        let report = try await SimulationGoldenCorpusRunner().run(
            suite: suite,
            projectRoot: projectRoot
        )
        let caseResult = try #require(report.cases.first)

        #expect(report.status == "failed")
        #expect(report.summary.failedCaseCount == 1)
        #expect(caseResult.status == "failed")
        #expect(caseResult.observedGateStatus == "failed")
        #expect(caseResult.comparison == nil)
        #expect(caseResult.candidateWaveformArtifact == nil)
        #expect(caseResult.comparisonArtifact == nil)
        #expect(caseResult.diagnostics.contains {
            $0.contains("Simulation golden corpus infrastructure error prevented expected-failure acceptance")
        })
    }

    @Test func cliQualifiesCheckedInGoldenCorpusAndWritesReport() async throws {
        let packageRoot = packageRoot()
        let artifactDirectory = try makeTemporaryRoot("simulation-golden-corpus-cli-artifacts")
        let outputRoot = try makeTemporaryRoot("simulation-golden-corpus-cli-report")
        defer {
            removeTemporaryRoot(artifactDirectory)
            removeTemporaryRoot(outputRoot)
        }
        let outputURL = outputRoot.appending(path: "simulation-golden-corpus-report.json")

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "qualify-simulation-golden-corpus",
            "--project-root", packageRoot.path(percentEncoded: false),
            "--suite", suiteURL(packageRoot: packageRoot).path(percentEncoded: false),
            "--artifact-dir", artifactDirectory.path(percentEncoded: false),
            "--out", outputURL.path(percentEncoded: false),
            "--pretty",
        ])
        let stdoutReport = try JSONDecoder().decode(
            SimulationGoldenCorpusReport.self,
            from: Data(output.utf8)
        )
        let persistedReport = try JSONDecoder().decode(
            SimulationGoldenCorpusReport.self,
            from: Data(contentsOf: outputURL)
        )

        #expect(stdoutReport == persistedReport)
        #expect(stdoutReport.status == "passed")
        #expect(stdoutReport.summary.caseCount == 5)
        #expect(stdoutReport.coverageTags.contains("simulation.analysis.ac"))
        #expect(stdoutReport.coverageTags.contains("simulation.analysis.tran"))
        #expect(stdoutReport.coverageTags.contains("simulation.failure.expected"))
        #expect(stdoutReport.coverageTags.contains("simulation.waveform.semantic-node"))
        #expect(stdoutReport.cases.allSatisfy { $0.status == "passed" })
        #expect(stdoutReport.cases.filter { $0.expectedGateStatus == "passed" }.allSatisfy {
            $0.comparison?.gateStatus == "passed" && $0.candidateWaveformArtifact?.sha256.count == 64
        })
        #expect(stdoutReport.cases.filter { $0.expectedGateStatus == "failed" }.allSatisfy {
            $0.observedGateStatus == "failed" && !$0.diagnostics.isEmpty
        })
    }

    @Test func sourcePreservingNetlistEditFeedsGoldenCorpusQualification() async throws {
        let projectRoot = try makeTemporaryRoot("simulation-golden-source-edit")
        defer { removeTemporaryRoot(projectRoot) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: projectRoot)
        try store.createRunDirectory(for: "run-source-edit", inProjectAt: projectRoot)

        let sourceNetlistPath = "circuits/source-edit.spice"
        try writeText(
            """
            * source preserving edit fixture
            V1 in 0 0
            R1 in 0 1k
            .dc V1 0 1 0.5
            .end
            """,
            toProjectPath: sourceNetlistPath,
            projectRoot: projectRoot
        )
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            sourcePreservingEditPlan(sourceNetlistPath: sourceNetlistPath),
            runID: "run-source-edit",
            projectRoot: projectRoot
        )

        let executionResult = try await XcircuiteCandidatePlanExecutor().executeCandidatePlan(
            request: XcircuiteCandidatePlanExecutionRequest(runID: "run-source-edit"),
            projectRoot: projectRoot
        )
        #expect(executionResult.status == "executed")
        let execution = try store.readJSON(
            XcircuiteCandidatePlanExecution.self,
            from: projectRoot.appending(path: executionResult.planExecutionArtifact.path)
        )
        let stepResult = try #require(execution.stepResults.first)
        let editReportRef = try #require(stepResult.artifactRefs.first {
            $0.artifactID == "candidate-step-1-netlist-parameter-edit-report"
        })
        let editReport = try store.readJSON(
            XcircuiteNetlistParameterEditReport.self,
            from: projectRoot.appending(path: editReportRef.path)
        )

        #expect(editReport.sourceNetlistPath == sourceNetlistPath)
        #expect(editReport.outputNetlistPath != sourceNetlistPath)
        let edit = try #require(editReport.edits.first)
        #expect(edit.assignmentName == "R1")
        #expect(edit.targetKind == "component-parameter")
        #expect(edit.targetName == "r1")
        #expect(edit.value == 2000)
        #expect(edit.unit == nil)

        let editedNetlist = try String(
            contentsOf: projectRoot.appending(path: editReport.outputNetlistPath),
            encoding: .utf8
        )
        #expect(editedNetlist.contains("r1"))
        #expect(editedNetlist.contains("2.0k"))

        let goldenPath = "golden/edited-resistor-golden.csv"
        try writeText(
            """
            v1,V(in),I(v1)
            0.0,0.0,0.0
            0.5,0.5000000000000002,-0.00025000000050000017
            1.0,1.0000000000000004,-0.0005000000010000003
            """,
            toProjectPath: goldenPath,
            projectRoot: projectRoot
        )

        let suite = SimulationGoldenCorpusSuiteSpec(
            suiteID: "source-preserving-edit-corpus-v1",
            description: "Source-preserving netlist edit corpus fixture.",
            cases: [
                SimulationGoldenCorpusCaseSpec(
                    caseID: "edited-resistor-dc",
                    description: "Edited netlist should remain directly simulatable and comparable.",
                    netlistPath: editReport.outputNetlistPath,
                    goldenWaveformPath: goldenPath,
                    options: SimulationGoldenComparisonOptions(
                        maxAbsoluteDelta: 1.0e-9,
                        maxRelativeDelta: 1.0e-9,
                        requiredVariables: ["V(in)", "I(v1)"],
                        comparedVariables: ["V(in)", "I(v1)"],
                        allowInterpolation: false
                    ),
                    coverageTags: [
                        "simulation.source-edit.parameter",
                        "simulation.source-edit.artifact-ref",
                        "simulation.waveform.branch-current",
                    ],
                    expectedGateStatus: "passed"
                ),
            ]
        )
        let report = try await SimulationGoldenCorpusRunner().run(
            suite: suite,
            projectRoot: projectRoot,
            artifactDirectory: projectRoot.appending(path: "artifacts/source-edit-corpus")
        )

        #expect(report.status == "passed")
        #expect(report.summary.caseCount == 1)
        let caseResult = try #require(report.cases.first)
        #expect(caseResult.caseID == "edited-resistor-dc")
        #expect(caseResult.comparison?.gateStatus == "passed")
        #expect(caseResult.candidateWaveformArtifact?.sha256.count == 64)
        #expect(caseResult.comparisonArtifact?.sha256.count == 64)
    }

    @Test func actionDomainSnapshotIncludesGoldenCorpusQualificationOperation() throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: "simulation-golden-corpus-action-domain",
            generatedAt: "2026-06-29T00:00:00Z"
        )
        let simulation = try #require(snapshot.domains.first { $0.domainID == "simulation-analysis" })
        let operation = try #require(simulation.operations.first {
            $0.operationID == "simulation.qualify-golden-corpus"
        })

        #expect(operation.maturity == "implemented")
        #expect(operation.inputRefs.contains("simulation-golden-corpus-suite-ref"))
        #expect(operation.producedArtifacts.contains("simulation-golden-corpus-report"))
        #expect(operation.verificationGates.contains("simulation-metric-gate"))
    }

    private func suiteURL(packageRoot: URL) -> URL {
        packageRoot
            .appending(path: "Tests")
            .appending(path: "XcircuiteTests")
            .appending(path: "Fixtures")
            .appending(path: "SimulationGoldenCorpus")
            .appending(path: "simulation-golden-suite.json")
    }

    private func packageRoot() -> URL {
        var current = URL(filePath: #filePath).deletingLastPathComponent()
        while current.path(percentEncoded: false) != "/" {
            let packageManifest = current.appending(path: "Package.swift")
            let sources = current.appending(path: "Sources").appending(path: "Xcircuite")
            if FileManager.default.fileExists(atPath: packageManifest.path(percentEncoded: false)),
               FileManager.default.fileExists(atPath: sources.path(percentEncoded: false)) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return URL(filePath: "/Users/1amageek/Desktop/LSI/Xcircuite")
    }

    private func sourcePreservingEditPlan(sourceNetlistPath: String) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "source-preserving-edit-plan",
            problemID: "source-preserving-edit-problem",
            runID: "run-source-edit",
            strategy: "source-preserving-edit-corpus",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/run-source-edit/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-source-edit",
                    order: 1,
                    actionID: "edit-r1",
                    domainID: "simulation-and-pex-improvement",
                    operationID: "simulation.set-netlist-parameters",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["source-preserving-edit"],
                    requiredInputRefs: ["source-netlist"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "simulation-golden-corpus"],
                    reason: "Materialize a source-preserving parameter edit and re-run simulation golden qualification.",
                    parameterHints: [
                        "netlistPath": .string(sourceNetlistPath),
                        "assignments": .array([
                            .object([
                                "name": .string("R1"),
                                "value": .number(2000),
                            ]),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    private func writeText(
        _ text: String,
        toProjectPath path: String,
        projectRoot: URL
    ) throws {
        let url = projectRoot.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMinimalCorpusInputs(projectRoot: URL) throws {
        try writeText(
            """
            * minimal simulation golden corpus fixture
            V1 in 0 0
            R1 in 0 1k
            .dc V1 0 1 1
            .end
            """,
            toProjectPath: "fixtures/input.cir",
            projectRoot: projectRoot
        )
        try writeText(
            """
            v1,V(in),I(v1)
            0.0,0.0,0.0
            1.0,1.0000000000000004,-0.0010000000020000005
            """,
            toProjectPath: "fixtures/golden.csv",
            projectRoot: projectRoot
        )
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "xcircuite-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }
}
