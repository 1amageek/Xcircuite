import DesignFlowKernel
import Foundation
import Testing
import ToolQualification
import Xcircuite
import XcircuitePackage

@Suite("Post-layout comparison flow stage executor", .timeLimit(.minutes(1)))
struct PostLayoutComparisonFlowStageExecutorTests {
    @Test func comparisonReportArtifactAndGatePass() async throws {
        let root = try makeTemporaryRoot("comparison-pass")
        defer { removeTemporaryRoot(root) }
        let preWaveform = try writeText(
            """
            time,V(out)
            0,0
            1e-9,1
            2e-9,0
            3e-9,1
            4e-9,0
            """,
            name: "pre.csv",
            root: root
        )
        let postWaveform = try writeText(
            """
            time,V(out),V(out_pex)
            0,0,0
            1e-9,0.98,0.97
            2e-9,0.02,0.03
            3e-9,1.01,1
            4e-9,0.01,0.02
            """,
            name: "post.csv",
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-comparison",
                intent: "Compare post-layout waveform",
                stages: [
                    FlowStageDefinition(
                        stageID: "030-compare",
                        displayName: "Post-layout comparison",
                        requiredTool: comparisonRequirement()
                    ),
                ]
            ),
            toolRegistry: ToolRegistry(descriptors: [
                SignoffToolDescriptors.postLayoutComparison(level: .smokeChecked),
            ]),
            healthResults: [
                "post-layout-comparison": QualifiedToolFixtures.health(
                    toolID: "post-layout-comparison",
                    level: .smokeChecked
                ),
            ],
            executors: [
                PostLayoutComparisonFlowStageExecutor(
                    stageID: "030-compare",
                    preLayoutWaveformURL: preWaveform,
                    postLayoutWaveformURL: postWaveform,
                    options: PostLayoutComparisonOptions(
                        maxAbsoluteDelta: 0.05,
                        requiredPostVariables: ["V(out_pex)"],
                        oscillationLimits: [
                            PostLayoutOscillationLimit(
                                variableName: "V(out)",
                                minimumPostAmplitude: 0.9,
                                minimumPostTransitionCount: 3
                            ),
                        ]
                    )
                ),
            ]
        )

        let stage = result.stages[0]
        if result.status != .succeeded {
            Issue.record("Unexpected comparison failure diagnostics: \(stage.diagnostics)")
        }
        #expect(result.status == .succeeded)
        #expect(stage.gates.contains { $0.gateID == "tool-trust" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "comparison" && $0.status == .passed })
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        let reportArtifact = try #require(stage.artifacts.first { $0.kind == .report && $0.format == .json })
        #expect(reportArtifact.artifactID == "post-layout-comparison")
        #expect(reportArtifact.sha256?.isEmpty == false)
        #expect((reportArtifact.byteCount ?? 0) > 0)
        #expect(reportArtifact.path.contains(".xcircuite/runs/run-comparison/stages/030-compare/raw"))
        let reportURL = root.appending(path: reportArtifact.path)
        let report = try JSONDecoder().decode(
            PostLayoutComparisonReport.self,
            from: Data(contentsOf: reportURL)
        )
        #expect(report.gateStatus == "passed")
        #expect(report.requiredPostVariables.contains { $0.variableName == "V(out_pex)" && $0.present })
        #expect(report.oscillationMetrics.first?.postLayout?.transitionCount == 4)
    }

    @Test func missingRequiredVariableFailsGate() async throws {
        let root = try makeTemporaryRoot("comparison-fail")
        defer { removeTemporaryRoot(root) }
        let preWaveform = try writeText(
            """
            time,V(out)
            0,0
            1e-9,1
            """,
            name: "pre.csv",
            root: root
        )
        let postWaveform = try writeText(
            """
            time,V(out)
            0,0
            1e-9,1
            """,
            name: "post.csv",
            root: root
        )

        let result = try await DefaultFlowOrchestrator().run(
            request: FlowOperationRequest(
                projectRoot: root,
                runID: "run-comparison-fail",
                intent: "Compare post-layout waveform",
                stages: [FlowStageDefinition(stageID: "030-compare", displayName: "Post-layout comparison")]
            ),
            toolRegistry: ToolRegistry(descriptors: []),
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

        let stage = result.stages[0]
        #expect(stage.status == .failed)
        #expect(stage.gates.first?.status == .failed)
        #expect(stage.gates.contains { $0.gateID == "artifact-integrity" && $0.status == .passed })
        #expect(stage.diagnostics.contains { $0.code == "POST_LAYOUT_COMPARISON_GATE_VIOLATION" })
        #expect(stage.artifacts.contains {
            $0.artifactID == "post-layout-comparison"
                && $0.sha256?.isEmpty == false
                && ($0.byteCount ?? 0) > 0
        })
    }

    @Test func serviceFailsGateForPartialPostLayoutSweepCoverageByDefault() throws {
        let preLayout = """
        time,V(out)
        0,0
        1e-9,1
        2e-9,0
        """
        let postLayout = """
        time,V(out)
        0,0
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout
        )

        #expect(report.gateStatus == "failed")
        #expect(report.comparedPointCount < report.preLayoutPointCount)
        #expect(report.gateViolations.contains { $0.contains("does not cover the full pre-layout sweep") })
        #expect(report.diagnostics.contains { $0.contains("Candidate sweep has insufficient increasing points") })
    }

    @Test func serviceFailsGateForMissingPreLayoutVariableByDefault() throws {
        let preLayout = """
        time,V(out),I(vdd)
        0,0,0
        1e-9,1,-0.001
        """
        let postLayout = """
        time,V(out)
        0,0
        1e-9,1
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout
        )

        #expect(report.gateStatus == "failed")
        #expect(report.missingInPostLayout == ["I(vdd)"])
        #expect(report.gateViolations.contains { $0.contains("missing pre-layout variable I(vdd)") })
    }

    @Test func serviceMatchesPostLayoutVariablesCaseInsensitively() throws {
        let preLayout = """
        time,V(out)
        0,0
        1e-9,1
        """
        let postLayout = """
        time,v(out)
        0,0
        1e-9,1
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout
        )

        #expect(report.status == "compared")
        #expect(report.gateStatus == "passed")
        #expect(report.comparedVariables.map(\.variableName) == ["V(out)"])
    }

    @Test func serviceMatchesOscillationVariablesCaseInsensitively() throws {
        let preLayout = """
        time,V(out)
        0,0
        1e-9,1
        2e-9,0
        3e-9,1
        4e-9,0
        """
        let postLayout = """
        time,v(out)
        0,0
        1e-9,1
        2e-9,0
        3e-9,1
        4e-9,0
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                oscillationLimits: [
                    PostLayoutOscillationLimit(
                        variableName: "V(out)",
                        minimumPostAmplitude: 0.9,
                        minimumPostTransitionCount: 3
                    ),
                ]
            )
        )

        #expect(report.gateStatus == "passed")
        #expect(report.oscillationMetrics.first?.postLayout?.transitionCount == 4)
        #expect(report.oscillationMetrics.first?.violations.isEmpty == true)
    }

    @Test func variableLimitTighterThanGlobalGatesOnlyThatVariable() throws {
        let preLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1,1
        2e-9,0,0
        """
        // V(vout) delta 0.03 and V(nmir) delta 0.04 both pass the global 0.05,
        // but V(vout) carries a tighter variable-specific limit of 0.02.
        let postLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1.03,1.04
        2e-9,0,0
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                maxAbsoluteDelta: 0.05,
                variableLimits: [
                    // Lowercase on purpose: matching must be case-insensitive.
                    PostLayoutVariableComparisonLimit(variableName: "v(vout)", maxAbsoluteDelta: 0.02),
                ]
            )
        )

        #expect(report.gateStatus == "failed")
        #expect(report.gateViolations.contains {
            $0.contains("v(vout)") && $0.contains("variable-specific limit")
        })
        #expect(!report.gateViolations.contains { $0.contains("nmir") })
        #expect(!report.gateViolations.contains { $0.contains("global limit") })
    }

    @Test func variableLimitLooserThanGlobalAllowsVariableWhileOthersStayOnGlobal() throws {
        let preLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1,1
        2e-9,0,0
        """
        // V(nmir) has a legitimate 0.13 edge transient allowed by its own
        // 0.2 limit; V(vout) exceeds the global 0.05 and must still be gated.
        let postLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1.08,1.13
        2e-9,0,0
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                maxAbsoluteDelta: 0.05,
                variableLimits: [
                    PostLayoutVariableComparisonLimit(variableName: "V(nmir)", maxAbsoluteDelta: 0.2),
                ]
            )
        )

        #expect(report.gateStatus == "failed")
        let globalViolation = report.gateViolations.first { $0.contains("global limit") }
        #expect(globalViolation != nil)
        // The global gate must exclude V(nmir): its 0.13 delta may not leak
        // into the globally governed maximum.
        #expect(globalViolation?.contains("0.13") != true)
        #expect(!report.gateViolations.contains { $0.contains("variable-specific limit") })
    }

    @Test func variableLimitLooserThanGlobalPassesWhenOthersAreWithinGlobal() throws {
        let preLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1,1
        2e-9,0,0
        """
        let postLayout = """
        time,V(vout),V(nmir)
        0,0,0
        1e-9,1.02,1.13
        2e-9,0,0
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                maxAbsoluteDelta: 0.05,
                variableLimits: [
                    PostLayoutVariableComparisonLimit(variableName: "V(nmir)", maxAbsoluteDelta: 0.2),
                ]
            )
        )

        #expect(report.gateStatus == "passed")
        #expect(report.gateViolations.isEmpty)
    }

    @Test func variableLimitOverridesOnlyItsOwnMetric() throws {
        let preLayout = """
        time,V(vout)
        0,0
        1e-9,1
        2e-9,0
        """
        let postLayout = """
        time,V(vout)
        0,0
        1e-9,1.1
        2e-9,0
        """

        // The variable limit only overrides the absolute metric; the relative
        // metric stays governed by the global limit.
        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                maxRelativeDelta: 0.05,
                variableLimits: [
                    PostLayoutVariableComparisonLimit(variableName: "V(vout)", maxAbsoluteDelta: 1.0),
                ]
            )
        )

        #expect(report.gateStatus == "failed")
        #expect(report.gateViolations.contains {
            $0.contains("relative delta") && $0.contains("global limit")
        })
    }

    @Test func variableLimitForUncomparedVariableFailsGate() throws {
        let preLayout = """
        time,V(vout)
        0,0
        1e-9,1
        """
        let postLayout = """
        time,V(vout)
        0,0
        1e-9,1
        """

        let report = try PostLayoutComparisonService().compare(
            preLayoutCSV: preLayout,
            postLayoutCSV: postLayout,
            options: PostLayoutComparisonOptions(
                variableLimits: [
                    PostLayoutVariableComparisonLimit(variableName: "V(missing)", maxAbsoluteDelta: 0.05),
                ]
            )
        )

        #expect(report.gateStatus == "failed")
        #expect(report.gateViolations.contains {
            $0.contains("V(missing)") && $0.contains("was not compared for a variable-specific limit")
        })
    }

    @Test func optionsRejectMissingRequiredLimitCollections() throws {
        let json = """
        {"maxAbsoluteDelta":0.05,"requiredPostVariables":["V(out)"]}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                PostLayoutComparisonOptions.self,
                from: Data(json.utf8)
            )
        }
    }

    @Test func optionsWithVariableLimitsRoundTripThroughCodable() throws {
        let options = PostLayoutComparisonOptions(
            maxAbsoluteDelta: 0.05,
            variableLimits: [
                PostLayoutVariableComparisonLimit(
                    variableName: "V(nmir)",
                    maxAbsoluteDelta: 0.2,
                    maxRelativeDelta: 0.5
                ),
            ]
        )
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(PostLayoutComparisonOptions.self, from: data)
        #expect(decoded == options)
    }

    private func comparisonRequirement() -> ToolTrustRequirement {
        ToolTrustRequirement(
            kind: .simulation,
            operationID: "compare-waveforms",
            minimumLevel: .smokeChecked,
            requiredInputFormats: [.csv],
            requiredOutputFormats: [.json]
        )
    }

    private func writeText(_ text: String, name: String, root: URL) throws -> URL {
        let url = root.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
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
