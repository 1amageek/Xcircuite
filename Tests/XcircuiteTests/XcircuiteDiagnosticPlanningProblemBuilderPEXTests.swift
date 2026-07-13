import Foundation
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

@Suite("Xcircuite diagnostic planning problem builder PEX")
struct XcircuiteDiagnosticPlanningProblemBuilderPEXTests {
    @Test func pexSummaryCreatesMetricRecoveryProblem() throws {
        let summary = makePEXSummary()
        let metricReport = makePostLayoutMetricReport()

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makePEXRecoveryProblem(
            runID: "run-3",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-3/stages/009-pex/raw/pex-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-3/stages/006-layout/raw/layout.gds",
            sourceNetlistPath: "circuits/top.postpex.spice",
            technologyArtifactPath: "tech/pex-technology.json",
            metricReportPath: "reports/post-layout-metrics.json",
            metricReport: metricReport
        )

        #expect(problem.problemID == "run-3-pex-recovery-problem")
        #expect(problem.actionDomainRefs == [
            "pex-extraction",
            "simulation-analysis",
            "layout-edit",
            "drc-signoff",
            "lvs-signoff",
        ])
        #expect(problem.sourceRefs.first?.metadata["pexRunID"] == .string("pex-run-1"))
        #expect(problem.initialStateRefs.contains {
            $0.refID == "source-netlist-ref" && $0.path == "circuits/top.postpex.spice"
        })
        #expect(problem.initialStateRefs.contains {
            $0.refID == "pex-technology-ref" && $0.path == "tech/pex-technology.json"
        })
        #expect(problem.sourceRefs.contains {
            $0.refID == "post-layout-metric-report" && $0.path == "reports/post-layout-metrics.json"
        })
        #expect(!problem.initialStateRefs.contains {
            $0.refID == "post-layout-metric-report"
        })
        let metricRef = try #require(problem.sourceRefs.first {
            $0.refID == "post-layout-metric-report"
        })
        #expect(metricRef.metadata["gateStatus"] == .string("failed"))
        #expect(metricRef.metadata["gateViolationCount"] == .number(1))
        #expect(problem.objectives.contains {
            $0.target == "reduce-parasitic-hotspot"
                && $0.evidence["netName"] == .string("OUT")
                && $0.currentValue == .number(3.0e-12)
        })
        #expect(problem.objectives.contains {
            $0.target == "resolve-pex-summary-diagnostic"
                && $0.evidence["code"] == .string("PEX_WARN_COUPLING")
        })
        #expect(problem.objectives.contains {
            $0.target == "post-layout-metric-gate-passed"
                && $0.sourceRefIDs == ["post-layout-metric-report"]
                && $0.currentValue == .string("failed")
                && $0.requiredValue == .string("passed")
        })
        #expect(problem.objectives.contains {
            $0.target == "reduce-post-layout-waveform-delta"
                && $0.evidence["variableName"] == .string("vout")
                && $0.currentValue == .number(0.30)
                && $0.unit == "ratio"
        })
        #expect(problem.objectives.contains {
            $0.target == "restore-required-post-layout-variable"
                && $0.evidence["variableName"] == .string("clk")
                && $0.evidence["present"] == .bool(false)
        })
        #expect(problem.objectives.contains {
            $0.target == "recover-post-layout-oscillation-metric"
                && $0.evidence["variableName"] == .string("vout")
                && $0.evidence["frequencyRelativeDelta"] == .number(0.18)
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "pex-extraction"
                && $0.operationID == "pex.metric-recovery-objective"
                && $0.maturity == "implemented"
                && $0.requiredInputRefs.contains("post-layout-metric-report")
                && $0.requiredInputRefs.contains("pex-technology-ref")
        })
        #expect(problem.candidateActions.contains {
            guard case .object(let inputs) = $0.parameterHints["pexInputs"] else {
                return false
            }
            return inputs["technologyRef"] == .string("pex-technology-ref")
                && inputs["backendID"] == .string("mock-pex")
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "simulation-analysis"
                && $0.operationID == "simulation.metric-improvement-objective"
                && $0.maturity == "implemented"
                && $0.requiredInputRefs == ["post-layout-metric-report", "source-netlist-ref"]
                && $0.verificationGates.contains("simulation-metric-gate")
        })
        #expect(problem.constraints.contains {
            $0.constraintID == "post-layout-metric-must-pass"
        })
        #expect(problem.verificationGates.contains {
            $0.gateID == "simulation-metric-gate" && $0.required
        })
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-3/planning/problem.json")
    }

    @Test func generatePlanningProblemCLIReadsPEXSummaryFromRunManifest() async throws {
        let root = try makeTemporaryRoot("pex-planning-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-3", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-3/stages/009-pex/raw/pex-summary.json"
        let layoutPath = ".xcircuite/runs/run-3/stages/006-layout/raw/layout.gds"
        let technologyPath = "tech/pex-technology.json"
        try registerJSONArtifact(
            makePEXSummary(),
            artifactID: "pex-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-3"
        )
        try registerDataArtifact(
            Data("GDS payload\n".utf8),
            artifactID: "layout-gds",
            path: layoutPath,
            kind: .layout,
            format: .gdsii,
            root: root,
            runID: "run-3"
        )
        try registerDataArtifact(
            Data(#"{"processName":"test_process","stack":[],"logicalToPhysicalLayerMap":{},"vias":[],"defaultExtractionRules":{"reductionPolicy":"none"},"backendHints":{}}"#.utf8),
            artifactID: "pex-technology",
            path: technologyPath,
            kind: .technology,
            format: .json,
            root: root,
            runID: "run-3"
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "reports"),
            withIntermediateDirectories: true
        )
        try store.writeJSON(
            makePostLayoutMetricReport(),
            to: root.appending(path: "reports/post-layout-metrics.json"),
            forProjectAt: root
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-3",
                "--source",
                "pex-summary",
                "--layout-artifact-id",
                "layout-gds",
                "--source-netlist-path",
                "circuits/top.postpex.spice",
                "--technology-artifact-id",
                "pex-technology",
                "--metric-report-path",
                "reports/post-layout-metrics.json",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuitePlanningProblemGenerationResult.self, from: data)

        #expect(result.status == "generated")
        #expect(result.source == .pexSummary)
        #expect(result.problemID == "run-3-pex-recovery-problem")
        #expect(result.summaryPath == summaryPath)
        #expect(result.layoutPath == layoutPath)
        #expect(result.sourceNetlistPath == "circuits/top.postpex.spice")
        #expect(result.technologyPath == technologyPath)
        #expect(result.metricReportPath == "reports/post-layout-metrics.json")

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: result.problemArtifact.path)
        )
        #expect(problem.sourceRefs.first?.path == summaryPath)
        #expect(problem.initialStateRefs.contains {
            $0.refID == "layout-ref" && $0.path == layoutPath
        })
        #expect(problem.initialStateRefs.contains {
            $0.refID == "pex-technology-ref" && $0.path == technologyPath
        })
        #expect(problem.objectives.contains {
            $0.target == "reduce-parasitic-hotspot" && $0.evidence["netName"] == .string("OUT")
        })
        #expect(problem.objectives.contains {
            $0.target == "post-layout-metric-gate-passed"
                && $0.currentValue == .string("failed")
        })
        #expect(problem.objectives.contains {
            $0.target == "reduce-post-layout-waveform-delta"
                && $0.evidence["variableName"] == .string("vout")
        })
        #expect(problem.candidateActions.contains {
            $0.operationID == "pex.metric-recovery-objective"
                && $0.maturity == "implemented"
        })
    }

    @Test func generatePlanningProblemRejectsMissingExplicitMetricReport() throws {
        let root = try makeTemporaryRoot("pex-planning-missing-metric-report")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-missing-metric", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-missing-metric/stages/009-pex/raw/pex-summary.json"
        try registerJSONArtifact(
            makePEXSummary(),
            artifactID: "pex-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-missing-metric"
        )

        #expect(throws: XcircuitePlanningProblemGenerationError.explicitPathNotFound(
            path: "reports/missing-post-layout-metrics.json"
        )) {
            _ = try XcircuitePlanningProblemGenerator().generateRepairProblem(
                request: XcircuitePlanningProblemGenerationRequest(
                    runID: "run-missing-metric",
                    source: .pexSummary,
                    metricReportPath: "reports/missing-post-layout-metrics.json"
                ),
                projectRoot: root
            )
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteDiagnosticPlanningProblemBuilderPEXTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {}
    }

    private func makePEXSummary() -> PEXRunSummaryReport {
        PEXRunSummaryReport(
            manifestURL: URL(filePath: "/tmp/pex-manifest.json"),
            completeness: PEXArtifactCompletenessReport(status: .complete, issues: []),
            summary: PEXRunSummary(
                runID: "pex-run-1",
                status: "success",
                backendID: "mock-pex",
                corners: [
                    PEXCornerParasiticSummary(
                        cornerID: "tt",
                        status: "success",
                        netCount: 2,
                        elementCount: 4,
                        topNets: [
                            PEXNetParasiticSummary(
                                name: "OUT",
                                groundCapF: 2.0e-12,
                                couplingCapF: 1.0e-12,
                                resistanceOhm: 42,
                                nodeCount: 3
                            ),
                        ],
                        diagnostics: [
                            PEXRunSummaryDiagnostic(
                                severity: "warning",
                                code: "PEX_WARN_COUPLING",
                                message: "Coupling capacitance is concentrated on OUT."
                            ),
                        ]
                    ),
                ]
            )
        )
    }

    private func makePostLayoutMetricReport() -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "completed",
            preLayoutPointCount: 100,
            postLayoutPointCount: 100,
            sweepVariable: "time",
            comparedPointCount: 100,
            maxAbsoluteDelta: 0.15,
            maxRelativeDelta: 0.30,
            comparedVariables: [
                PostLayoutVariableComparison(
                    variableName: "vout",
                    pointCount: 100,
                    maxAbsoluteDelta: 0.15,
                    maxRelativeDelta: 0.30
                ),
            ],
            requiredPostVariables: [
                PostLayoutRequiredVariableResult(variableName: "vout", present: true),
                PostLayoutRequiredVariableResult(variableName: "clk", present: false),
            ],
            oscillationMetrics: [
                PostLayoutOscillationMetricComparison(
                    variableName: "vout",
                    preLayout: PostLayoutOscillationMetric(
                        amplitude: 1.0,
                        frequency: 1_000_000,
                        averagePeriod: 1.0e-6,
                        transitionCount: 10,
                        dutyCycle: 0.50
                    ),
                    postLayout: PostLayoutOscillationMetric(
                        amplitude: 0.82,
                        frequency: 820_000,
                        averagePeriod: 1.22e-6,
                        transitionCount: 8,
                        dutyCycle: 0.57
                    ),
                    frequencyRelativeDelta: 0.18,
                    violations: ["frequency-relative-delta"]
                ),
            ],
            missingInPostLayout: ["clk"],
            addedInPostLayout: [],
            diagnostics: ["post-layout waveform delta exceeded tolerance"],
            gateStatus: "failed",
            gateViolations: ["vout relative delta exceeded tolerance"]
        )
    }

    private func expectValidPlanningProblem(
        _ problem: XcircuiteCircuitPlanningProblem,
        problemPath: String
    ) throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: problem.runID,
            generatedAt: "2026-06-21T00:00:00Z"
        )
        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: problemPath,
            actionDomainSnapshot: snapshot
        )
        #expect(validation.status == "valid")
        #expect(validation.diagnostics == [])
    }

    private func registerJSONArtifact<T: Encodable>(
        _ value: T,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(value, to: url, forProjectAt: root)
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }

    private func registerDataArtifact(
        _ data: Data,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }
}
