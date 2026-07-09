import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

@Suite("op-amp design capabilities", .timeLimit(.minutes(2)))
struct OpAmpDesignFlowTests {
    @Test func topologySizingAndEvaluationAreDeveloperUsableThroughAPI() async throws {
        let spec = OpAmpSpec.makeDefault(
            specID: "api-opamp",
            supplyVoltage: 1.8,
            loadCapacitance: 1.0e-12,
            dcGainDB: 45,
            unityGainFrequencyHz: 5.0e6,
            phaseMarginDegrees: 45,
            slewRateVPerS: 1.0e6
        )

        let candidates = OpAmpTopologyLibrary().candidates(for: spec)
        let candidateKinds = Set(candidates.map(\.kind))
        #expect(candidateKinds == Set(OpAmpTopologyKind.allCases))
        #expect(candidates.allSatisfy { !$0.deviceRoles.isEmpty && !$0.layoutIntentIDs.isEmpty })

        let sizing = try OpAmpInitialSizingEngine().size(
            spec: spec,
            topologyKind: .twoStageMiller
        )
        let requiredMetricIDs = Set(spec.requirements.map(\.metricID))
        let estimatedMetricIDs = Set(sizing.estimatedMetrics.map(\.metricID))

        #expect(sizing.topology.kind == .twoStageMiller)
        #expect(sizing.devices.contains { $0.instanceName == "M1" && $0.role == "inputPair" })
        #expect(sizing.devices.contains { $0.instanceName == "M2" && $0.role == "inputPair" })
        #expect(sizing.devices.contains { $0.instanceName == "Cc" && $0.role == "compensation" })
        #expect(requiredMetricIDs.isSubset(of: estimatedMetricIDs))
        #expect(sizing.layoutConstraintPlan.constraints.contains { $0.kind == .commonCentroid })
        #expect(sizing.layoutConstraintPlan.constraints.contains { $0.kind == .guardRing })
        #expect(sizing.layoutConstraintPlan.constraints.contains { $0.kind == .shielding })
        #expect(sizing.netlist.contains(".subckt opamp_two_stage_miller"))
        let deckSet = try #require(sizing.simulationDeckSet)
        let deckIDs = Set(deckSet.decks.map(\.deckID))
        #expect(deckIDs == [
            "op-bias",
            "ac-open-loop",
            "tran-positive-step",
            "tran-negative-step",
            "noise-input-referred",
        ])
        let acDeck = try #require(deckSet.decks.first { $0.deckID == "ac-open-loop" })
        #expect(acDeck.netlist.contains(".ac dec"))
        #expect(acDeck.postProcessingMetricIDs.contains(.dcGainDB))
        #expect(acDeck.postProcessingMetricIDs.contains(.phaseMarginDegrees))
        let transientDeck = try #require(deckSet.decks.first { $0.deckID == "tran-positive-step" })
        #expect(transientDeck.netlist.contains(".tran"))
        #expect(transientDeck.directMetricIDs.contains(.outputSwingHighV))
        let deckValidation = await OpAmpSimulationDeckValidator().validate(deckSet)
        #expect(deckValidation.status == "passed")
        #expect(deckValidation.deckResults.count == deckSet.decks.count)

        let report = OpAmpMetricEvaluator().evaluate(spec: spec, sizingResult: sizing)
        #expect(report.specID == spec.specID)
        #expect(report.requirementResults.count == spec.requirements.count)
        #expect(!report.requirementResults.contains { $0.status == .missing })
    }

    @Test func opAmpCLIPersistsSpecSizingNetlistLayoutAndEvaluationArtifacts() async throws {
        let root = try makeTemporaryRoot("opamp-cli")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-cli"
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.ensureRunDirectory(for: runID, inProjectAt: root)

        let specURL = root.appending(path: "input/opamp-spec.json")
        let specOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "write-opamp-spec",
            "--out",
            specURL.path(percentEncoded: false),
            "--spec-id",
            "cli-opamp",
            "--gain-db",
            "45",
            "--ugb-hz",
            "5000000",
            "--phase-margin-deg",
            "45",
            "--slew-rate-v-per-s",
            "1000000",
            "--pretty",
        ])
        let spec = try decode(OpAmpSpec.self, from: specOutput)
        #expect(spec.specID == "cli-opamp")
        #expect(fileExists("input/opamp-spec.json", in: root))

        let topologyOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "list-opamp-topologies",
            "--spec",
            specURL.path(percentEncoded: false),
        ])
        let topologyResult = try decode(OpAmpTopologyListCLIResult.self, from: topologyOutput)
        #expect(topologyResult.specID == "cli-opamp")
        #expect(Set(topologyResult.candidates.map(\.kind)) == Set(OpAmpTopologyKind.allCases))

        let sizingOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "size-opamp",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--spec",
            specURL.path(percentEncoded: false),
            "--topology",
            "twoStageMiller",
            "--pretty",
        ])
        let sizingResult = try decode(OpAmpSizingCLIResult.self, from: sizingOutput)
        let artifactIDs = Set(sizingResult.artifactReferences.compactMap(\.artifactID))

        #expect(sizingResult.result.topology.kind == .twoStageMiller)
        #expect(artifactIDs.isSuperset(of: [
            "opamp-spec",
            "opamp-topology-candidates",
            "opamp-sizing-result",
            "opamp-netlist",
            "opamp-layout-constraints",
            "opamp-simulation-deck-set",
            "opamp-simulation-op-bias-netlist",
            "opamp-simulation-ac-open-loop-netlist",
            "opamp-simulation-tran-positive-step-netlist",
            "opamp-simulation-tran-negative-step-netlist",
            "opamp-simulation-noise-input-referred-netlist",
        ]))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/spec.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/topology-candidates.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/sizing-result.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/opamp.cir", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/layout-constraints.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation-decks.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation/ac-open-loop.cir", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation/tran-positive-step.cir", in: root))

        let evaluationURL = root.appending(path: "output/opamp-evaluation.json")
        let evaluationOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-opamp",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--spec",
            specURL.path(percentEncoded: false),
            "--sizing-result",
            root.appending(path: ".xcircuite/runs/\(runID)/opamp/sizing-result.json").path(percentEncoded: false),
            "--out",
            evaluationURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let evaluationResult = try decode(OpAmpEvaluationCLIResult.self, from: evaluationOutput)

        #expect(evaluationResult.report.specID == "cli-opamp")
        #expect(evaluationResult.artifactReference?.artifactID == "opamp-evaluation-report")
        #expect(fileExists("output/opamp-evaluation.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/evaluation-report.json", in: root))
    }

    @Test func opAmpEvaluationConsumesSimulationMeasurementArtifacts() async throws {
        let root = try makeTemporaryRoot("opamp-simulation-metrics")
        defer { removeTemporaryRoot(root) }

        let spec = OpAmpSpec.makeDefault(
            specID: "simulation-opamp",
            supplyVoltage: 1.8,
            loadCapacitance: 1.0e-12,
            dcGainDB: 45,
            unityGainFrequencyHz: 5.0e6,
            phaseMarginDegrees: 55,
            slewRateVPerS: 1.0e6
        )
        let measurements = makeSimulationMeasurements()
        let metricReport = XcircuiteSimulationMetricReport(
            status: "passed",
            source: "corespice",
            analysisLabel: "ac-tran-noise",
            expectations: [],
            measurements: measurements,
            verdicts: [],
            diagnostics: []
        )
        let runSummary = SimulationRunSummaryReport(
            stageID: "003-simulation",
            toolID: "corespice",
            summary: .init(
                status: "passed",
                analysis: "ac-tran-noise",
                measurementCount: measurements.count,
                waveformVariableCount: 2,
                expectationCount: 0,
                failedExpectationCount: 0
            ),
            measurements: measurements,
            waveformVariables: ["V(out)", "V(in)"],
            expectations: [],
            diagnostics: []
        )

        let specURL = root.appending(path: "input/spec.json")
        let metricReportURL = root.appending(path: "input/simulation-summary.json")
        let runSummaryURL = root.appending(path: "input/run-summary.json")
        let measurementsURL = root.appending(path: "input/measurements.json")
        try writeJSON(spec, to: specURL)
        try writeJSON(metricReport, to: metricReportURL)
        try writeJSON(runSummary, to: runSummaryURL)
        try writeJSON(measurements, to: measurementsURL)

        let reportResult = try await evaluateOpAmpWithSimulationInput(
            specURL: specURL,
            option: "--simulation-metric-report",
            inputURL: metricReportURL
        )
        #expect(reportResult.report.status == "passed")
        #expect(reportResult.metricExtraction?.sourceKind == "xcircuite-simulation-metric-report")
        #expect(reportResult.metricExtraction?.observedMetrics.contains { $0.metricID == .dcGainDB } == true)
        #expect(reportResult.metricExtraction?.unmappedMeasurements.count == 1)

        let summaryResult = try await evaluateOpAmpWithSimulationInput(
            specURL: specURL,
            option: "--simulation-run-summary",
            inputURL: runSummaryURL
        )
        #expect(summaryResult.report.status == "passed")
        #expect(summaryResult.report.reportID == "003-simulation-opamp-evaluation")
        #expect(summaryResult.metricExtraction?.sourceKind == "xcircuite-simulation-run-summary")

        let measurementsResult = try await evaluateOpAmpWithSimulationInput(
            specURL: specURL,
            option: "--simulation-measurements",
            inputURL: measurementsURL
        )
        #expect(measurementsResult.report.status == "passed")
        #expect(measurementsResult.metricExtraction?.sourceKind == "xcircuite-simulation-measurements")

        let verdictOnlyExtraction = OpAmpSimulationMetricExtractor().extract(from: XcircuiteSimulationMetricReport(
            status: "passed",
            source: "corespice",
            analysisLabel: "ac",
            expectations: [],
            measurements: [],
            verdicts: [
                .init(name: "gain_db", status: "passed", value: 68, target: 45, tolerance: 1),
            ],
            diagnostics: []
        ))
        #expect(verdictOnlyExtraction.observedMetrics.contains { $0.metricID == .dcGainDB && $0.unit == "dB" })
    }

    @Test func postLayoutComparisonClassifiesPEXDrivenRegressionsAndPersistsThroughCLI() async throws {
        let root = try makeTemporaryRoot("opamp-post-layout")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-post-layout"
        let packageStore = XcircuitePackageStore()
        try packageStore.createPackage(at: root)
        try packageStore.ensureRunDirectory(for: runID, inProjectAt: root)

        let spec = OpAmpSpec.makeDefault(
            specID: "post-layout-opamp",
            supplyVoltage: 1.8,
            loadCapacitance: 1.0e-12,
            dcGainDB: 50,
            unityGainFrequencyHz: 5.0e6,
            phaseMarginDegrees: 55,
            slewRateVPerS: 2.0e6
        )
        let evaluator = OpAmpMetricEvaluator()
        let preReport = evaluator.evaluate(
            spec: spec,
            observedMetrics: makeObservedMetrics(gainDB: 70, unityGainHz: 8.0e6, phaseMargin: 68, slewRate: 4.0e6),
            reportID: "pre-layout"
        )
        let postReport = evaluator.evaluate(
            spec: spec,
            observedMetrics: makeObservedMetrics(
                gainDB: 38,
                unityGainHz: 3.5e6,
                phaseMargin: 42,
                slewRate: 1.0e6,
                cmrrDB: 58,
                psrrDB: 48,
                noise: 90.0e-9,
                offset: 4.0e-3
            ),
            reportID: "post-layout"
        )
        let directComparison = OpAmpPostLayoutComparator().compare(
            spec: spec,
            preLayout: preReport,
            postLayout: postReport
        )
        #expect(preReport.status == "passed")
        #expect(postReport.status == "failed")
        #expect(directComparison.status == "failed")
        #expect(directComparison.deltas.contains {
            $0.metricID == .dcGainDB &&
                $0.status == "degraded" &&
                $0.classification == "parasitic-loading-or-output-resistance-degradation"
        })

        let specURL = root.appending(path: "input/spec.json")
        let preReportURL = root.appending(path: "input/pre-report.json")
        let postReportURL = root.appending(path: "input/post-report.json")
        let comparisonURL = root.appending(path: "output/post-layout-comparison.json")
        try writeJSON(spec, to: specURL)
        try writeJSON(preReport, to: preReportURL)
        try writeJSON(postReport, to: postReportURL)

        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "compare-opamp-post-layout",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--spec",
            specURL.path(percentEncoded: false),
            "--pre-report",
            preReportURL.path(percentEncoded: false),
            "--post-report",
            postReportURL.path(percentEncoded: false),
            "--out",
            comparisonURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let cliResult = try decode(OpAmpPostLayoutCLIResult.self, from: output)

        #expect(cliResult.report.status == "failed")
        #expect(cliResult.report.suggestedActions.contains("inspect-pex-parasitics"))
        #expect(cliResult.artifactReference?.artifactID == "opamp-post-layout-comparison")
        #expect(fileExists("output/post-layout-comparison.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/post-layout-comparison.json", in: root))
    }

    private func makeObservedMetrics(
        gainDB: Double,
        unityGainHz: Double,
        phaseMargin: Double,
        slewRate: Double,
        cmrrDB: Double = 80,
        psrrDB: Double = 72,
        noise: Double = 20.0e-9,
        offset: Double = 1.0e-3
    ) -> [OpAmpEstimatedMetric] {
        [
            OpAmpEstimatedMetric(metricID: .dcGainDB, value: gainDB, unit: "dB", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .unityGainFrequencyHz, value: unityGainHz, unit: "Hz", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .phaseMarginDegrees, value: phaseMargin, unit: "deg", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .positiveSlewRateVPerS, value: slewRate, unit: "V/s", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .negativeSlewRateVPerS, value: slewRate, unit: "V/s", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .cmrrDB, value: cmrrDB, unit: "dB", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .psrrPositiveDB, value: psrrDB, unit: "dB", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .psrrNegativeDB, value: psrrDB, unit: "dB", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .inputReferredNoiseVPerRootHz, value: noise, unit: "V/sqrt(Hz)", method: "test fixture"),
            OpAmpEstimatedMetric(metricID: .inputOffsetVoltage, value: offset, unit: "V", method: "test fixture"),
        ]
    }

    private func makeSimulationMeasurements() -> [SimulationMeasurementValue] {
        [
            SimulationMeasurementValue(name: "gain_db", value: 68, unit: "dB"),
            SimulationMeasurementValue(name: "ugf", value: 8.0e6, unit: "Hz"),
            SimulationMeasurementValue(name: "pm", value: 63, unit: "deg"),
            SimulationMeasurementValue(name: "sr_pos", value: 3.0e6, unit: "V/s"),
            SimulationMeasurementValue(name: "sr_neg", value: 2.8e6, unit: "V/s"),
            SimulationMeasurementValue(name: "cmrr", value: 78, unit: "dB"),
            SimulationMeasurementValue(name: "psrrp", value: 66, unit: "dB"),
            SimulationMeasurementValue(name: "psrrn", value: 64, unit: "dB"),
            SimulationMeasurementValue(name: "input_noise", value: 22.0e-9, unit: "V/sqrt(Hz)"),
            SimulationMeasurementValue(name: "vos", value: 1.0e-3, unit: "V"),
            SimulationMeasurementValue(name: "unrelated_probe", value: 0.5, unit: "V"),
        ]
    }

    private func evaluateOpAmpWithSimulationInput(
        specURL: URL,
        option: String,
        inputURL: URL
    ) async throws -> OpAmpEvaluationCLIResult {
        let output = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-opamp",
            "--spec",
            specURL.path(percentEncoded: false),
            option,
            inputURL.path(percentEncoded: false),
            "--pretty",
        ])
        return try decode(OpAmpEvaluationCLIResult.self, from: output)
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        let data = try #require(output.data(using: .utf8))
        return try JSONDecoder().decode(type, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "OpAmpDesignFlowTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func fileExists(_ relativePath: String, in root: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: root.appending(path: relativePath).path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }
}

private struct OpAmpTopologyListCLIResult: Sendable, Hashable, Decodable {
    var specID: String
    var candidates: [OpAmpTopologyCandidate]
}

private struct OpAmpSizingCLIResult: Sendable, Hashable, Decodable {
    var result: OpAmpSizingResult
    var artifactReferences: [XcircuiteFileReference]
}

private struct OpAmpEvaluationCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpEvaluationReport
    var artifactReference: XcircuiteFileReference?
    var metricExtraction: OpAmpSimulationMetricExtraction?
}

private struct OpAmpPostLayoutCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpPostLayoutComparisonReport
    var artifactReference: XcircuiteFileReference?
}
