import Foundation
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel

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
        let executionValidation = await OpAmpSimulationDeckValidator().validate(deckSet, mode: .executeCoreSpice)
        #expect(executionValidation.status == "passed")
        #expect(executionValidation.deckResults.allSatisfy { $0.executionStatus == "passed" })
        #expect(executionValidation.deckResults.contains {
            $0.deckID == "noise-input-referred" &&
                $0.executionContract?.coreSpiceBatchCLIRunnable == false &&
                $0.postProcessingMetricIDs.contains(.inputReferredNoiseVPerRootHz)
        })

        let report = OpAmpMetricEvaluator().evaluate(spec: spec, sizingResult: sizing)
        #expect(report.specID == spec.specID)
        #expect(report.requirementResults.count == spec.requirements.count)
        #expect(!report.requirementResults.contains { $0.status == .missing })
    }

    @Test func opAmpCLIPersistsSpecSizingNetlistLayoutAndEvaluationArtifacts() async throws {
        let root = try makeTemporaryRoot("opamp-cli")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-cli"
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: workspaceStore)

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

        let deckValidationURL = root.appending(path: "output/opamp-simulation-deck-validation.json")
        let deckValidationOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "validate-opamp-simulation-decks",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--deck-set",
            root.appending(path: ".xcircuite/runs/\(runID)/opamp/simulation-decks.json").path(percentEncoded: false),
            "--execute",
            "--out",
            deckValidationURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let deckValidationResult = try decode(OpAmpSimulationDeckValidationCLIResult.self, from: deckValidationOutput)
        #expect(deckValidationResult.report.status == "passed")
        #expect(deckValidationResult.report.validationMode == .executeCoreSpice)
        #expect(deckValidationResult.artifactReference?.artifactID == "opamp-simulation-deck-validation")
        #expect(fileExists("output/opamp-simulation-deck-validation.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation-deck-validation.json", in: root))

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

    @Test func opAmpWaveformMetricExtractionFeedsEvaluationThroughCLI() async throws {
        let root = try makeTemporaryRoot("opamp-waveform-metrics")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-waveform-metrics"
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: workspaceStore)

        let acCSV = """
        frequency,V(vout)_real,V(vout)_imag
        1,100,0
        10,10,0
        100,0,-1
        1000,0,-0.1
        """
        let acVoutpCSV = """
        frequency,V(vinp)_real,V(vinp)_imag,V(voutp)_real,V(voutp)_imag,V(vdd)_real,V(vdd)_imag
        1,1,0,100,0,0,0
        10,1,0,10,0,0,0
        100,1,0,0,-1,0,0
        1000,1,0,0,-0.1,0,0
        """
        let positiveTransientCSV = """
        time,V(vout)
        0,0
        0.000001,0.5
        0.000002,1
        0.000003,1
        """
        let negativeTransientCSV = """
        time,V(vout)
        0,1
        0.000001,0.5
        0.000002,0
        0.000003,0
        """
        let noiseCSV = """
        frequency,input_referred_noise_density,output_noise_density,integrated_output_noise
        1,1e-9,2e-9,0
        10,3e-9,4e-9,0
        """

        let extractor = OpAmpWaveformMetricExtractor()
        let acExtraction = try extractor.extract(
            analysisKind: .acOpenLoop,
            waveformCSV: acCSV,
            outputVariable: "V(vout)"
        )
        #expect(metricValue(.dcGainDB, in: acExtraction) == 40)
        #expect(metricValue(.unityGainFrequencyHz, in: acExtraction) == 100)
        #expect(metricValue(.phaseMarginDegrees, in: acExtraction) == 90)
        let autoACExtraction = try extractor.extract(
            analysisKind: .acOpenLoop,
            waveformCSV: acVoutpCSV
        )
        #expect(metricValue(.dcGainDB, in: autoACExtraction) == 40)
        #expect(metricValue(.unityGainFrequencyHz, in: autoACExtraction) == 100)

        let positiveExtraction = try extractor.extract(
            analysisKind: .transientPositiveStep,
            waveformCSV: positiveTransientCSV,
            outputVariable: "vout"
        )
        #expect(abs((metricValue(.positiveSlewRateVPerS, in: positiveExtraction) ?? 0) - 500_000) < 1)
        #expect(abs((metricValue(.settlingTimeSeconds, in: positiveExtraction) ?? 0) - 0.000002) < 1.0e-12)

        let negativeExtraction = try extractor.extract(
            analysisKind: .transientNegativeStep,
            waveformCSV: negativeTransientCSV,
            outputVariable: "vout"
        )
        #expect(abs((metricValue(.negativeSlewRateVPerS, in: negativeExtraction) ?? 0) - 500_000) < 1)

        let noiseExtraction = try extractor.extract(
            analysisKind: .noiseInputReferred,
            waveformCSV: noiseCSV
        )
        #expect(metricValue(.inputReferredNoiseVPerRootHz, in: noiseExtraction) == 3.0e-9)

        let spec = OpAmpSpec(
            specID: "waveform-opamp",
            title: "Waveform extraction op-amp spec",
            operatingPoint: .init(
                supplyVoltage: 1.8,
                inputCommonModeVoltage: 0.9,
                outputCommonModeVoltage: 0.9,
                loadCapacitance: 1.0e-12
            ),
            requirements: [
                .init(metricID: .dcGainDB, relation: .atLeast, value: 39, unit: "dB"),
                .init(metricID: .unityGainFrequencyHz, relation: .atLeast, value: 90, unit: "Hz"),
                .init(metricID: .phaseMarginDegrees, relation: .atLeast, value: 80, unit: "deg"),
            ]
        )

        let specURL = root.appending(path: "input/spec.json")
        let acWaveformURL = root.appending(path: "input/ac-waveform.csv")
        let acVoutpWaveformURL = root.appending(path: "input/ac-voutp-waveform.csv")
        let extractionURL = root.appending(path: "output/ac-extraction.json")
        let autoExtractionURL = root.appending(path: "output/ac-auto-extraction.json")
        try writeJSON(spec, to: specURL)
        try writeText(acCSV, to: acWaveformURL)
        try writeText(acVoutpCSV, to: acVoutpWaveformURL)

        let extractionOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "extract-opamp-waveform-metrics",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--analysis",
            "ac-open-loop",
            "--waveform",
            acWaveformURL.path(percentEncoded: false),
            "--output-variable",
            "V(vout)",
            "--out",
            extractionURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let extractionResult = try decode(OpAmpWaveformMetricExtractionCLIResult.self, from: extractionOutput)
        #expect(extractionResult.extraction.sourceAnalysisLabel == "ac-open-loop")
        #expect(extractionResult.artifactReference?.artifactID == "opamp-waveform-metric-extraction-ac-open-loop")
        #expect(fileExists("output/ac-extraction.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/waveform-metric-extraction-ac-open-loop.json", in: root))

        let autoExtractionOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "extract-opamp-waveform-metrics",
            "--analysis",
            "ac-open-loop",
            "--waveform",
            acVoutpWaveformURL.path(percentEncoded: false),
            "--out",
            autoExtractionURL.path(percentEncoded: false),
            "--pretty",
        ])
        let autoExtractionResult = try decode(OpAmpWaveformMetricExtractionCLIResult.self, from: autoExtractionOutput)
        #expect(metricValue(.dcGainDB, in: autoExtractionResult.extraction) == 40)
        #expect(fileExists("output/ac-auto-extraction.json", in: root))

        let evaluationOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-opamp",
            "--spec",
            specURL.path(percentEncoded: false),
            "--opamp-metric-extraction",
            extractionURL.path(percentEncoded: false),
            "--pretty",
        ])
        let evaluationResult = try decode(OpAmpEvaluationCLIResult.self, from: evaluationOutput)
        #expect(evaluationResult.report.status == "passed")
        #expect(evaluationResult.metricExtraction?.sourceKind == "xcircuite-waveform-csv")
    }

    @Test func opAmpMetricExtractionMergeCombinesArtifactsForEvaluationThroughCLI() async throws {
        let root = try makeTemporaryRoot("opamp-merged-metrics")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-merged-metrics"
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: workspaceStore)

        let spec = OpAmpSpec(
            specID: "merged-opamp",
            title: "Merged op-amp metric spec",
            operatingPoint: .init(
                supplyVoltage: 1.8,
                inputCommonModeVoltage: 0.9,
                outputCommonModeVoltage: 0.9,
                loadCapacitance: 1.0e-12
            ),
            requirements: [
                .init(metricID: .dcGainDB, relation: .atLeast, value: 40, unit: "dB"),
                .init(metricID: .unityGainFrequencyHz, relation: .atLeast, value: 90, unit: "Hz"),
                .init(metricID: .phaseMarginDegrees, relation: .atLeast, value: 80, unit: "deg"),
                .init(metricID: .positiveSlewRateVPerS, relation: .atLeast, value: 400_000, unit: "V/s"),
                .init(metricID: .negativeSlewRateVPerS, relation: .atLeast, value: 400_000, unit: "V/s"),
                .init(metricID: .inputReferredNoiseVPerRootHz, relation: .atMost, value: 5.0e-9, unit: "V/sqrt(Hz)"),
            ]
        )
        let acExtraction = OpAmpSimulationMetricExtraction(
            sourceKind: "xcircuite-waveform-csv",
            sourceStatus: "passed",
            sourceAnalysisLabel: "ac-open-loop",
            observedMetrics: [
                .init(metricID: .dcGainDB, value: 40, unit: "dB", method: "fixture ac gain"),
                .init(metricID: .unityGainFrequencyHz, value: 100, unit: "Hz", method: "fixture ac ugf"),
                .init(metricID: .phaseMarginDegrees, value: 90, unit: "deg", method: "fixture ac pm"),
            ],
            unmappedMeasurements: []
        )
        let transientExtraction = OpAmpSimulationMetricExtraction(
            sourceKind: "xcircuite-waveform-csv",
            sourceStatus: "passed",
            sourceAnalysisLabel: "tran-step",
            observedMetrics: [
                .init(metricID: .positiveSlewRateVPerS, value: 500_000, unit: "V/s", method: "fixture positive slew"),
                .init(metricID: .negativeSlewRateVPerS, value: 480_000, unit: "V/s", method: "fixture negative slew"),
            ],
            unmappedMeasurements: []
        )
        let noiseExtraction = OpAmpSimulationMetricExtraction(
            sourceKind: "xcircuite-waveform-csv",
            sourceStatus: "passed",
            sourceAnalysisLabel: "noise-input-referred",
            observedMetrics: [
                .init(metricID: .inputReferredNoiseVPerRootHz, value: 3.0e-9, unit: "V/sqrt(Hz)", method: "fixture noise"),
            ],
            unmappedMeasurements: []
        )
        let conflictingGainExtraction = OpAmpSimulationMetricExtraction(
            sourceKind: "xcircuite-simulation-measurements",
            sourceStatus: "passed",
            sourceAnalysisLabel: "direct-measurements",
            observedMetrics: [
                .init(metricID: .dcGainDB, value: 42, unit: "dB", method: "fixture direct gain"),
            ],
            unmappedMeasurements: [
                .init(name: "debug_probe", value: 0.1, unit: "V"),
            ]
        )

        let specURL = root.appending(path: "input/spec.json")
        let acURL = root.appending(path: "input/ac-extraction.json")
        let transientURL = root.appending(path: "input/transient-extraction.json")
        let noiseURL = root.appending(path: "input/noise-extraction.json")
        let conflictURL = root.appending(path: "input/conflict-extraction.json")
        let mergedURL = root.appending(path: "output/merged-extraction.json")
        try writeJSON(spec, to: specURL)
        try writeJSON(acExtraction, to: acURL)
        try writeJSON(transientExtraction, to: transientURL)
        try writeJSON(noiseExtraction, to: noiseURL)
        try writeJSON(conflictingGainExtraction, to: conflictURL)

        let directMerge = try OpAmpSimulationMetricExtractionMerger().merge([
            acExtraction,
            transientExtraction,
            noiseExtraction,
            conflictingGainExtraction,
        ])
        #expect(metricValue(.dcGainDB, in: directMerge) == 42)
        #expect(directMerge.diagnostics.contains {
            $0.code == "opamp.metric-extraction-merge.conflicting-metric" &&
                $0.relatedMetricIDs == [.dcGainDB]
        })
        #expect(directMerge.unmappedMeasurements.contains {
            $0.name == "xcircuite-simulation-measurements:direct-measurements:debug_probe"
        })

        let mergeOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "merge-opamp-metric-extractions",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--extraction",
            acURL.path(percentEncoded: false),
            "--extraction",
            transientURL.path(percentEncoded: false),
            "--extraction",
            noiseURL.path(percentEncoded: false),
            "--extraction",
            conflictURL.path(percentEncoded: false),
            "--out",
            mergedURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let mergeResult = try decode(OpAmpMetricExtractionMergeCLIResult.self, from: mergeOutput)
        #expect(mergeResult.extraction.sourceKind == "xcircuite-opamp-metric-extraction-merge")
        #expect(mergeResult.extraction.sourceStatus == "warning")
        #expect(mergeResult.extraction.observedMetrics.count == 6)
        #expect(mergeResult.artifactReference?.artifactID == "opamp-metric-extraction")
        #expect(fileExists("output/merged-extraction.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/metric-extraction.json", in: root))

        let evaluationOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-opamp",
            "--spec",
            specURL.path(percentEncoded: false),
            "--opamp-metric-extraction",
            mergedURL.path(percentEncoded: false),
            "--pretty",
        ])
        let evaluationResult = try decode(OpAmpEvaluationCLIResult.self, from: evaluationOutput)
        #expect(evaluationResult.report.status == "passed")
        #expect(evaluationResult.metricExtraction?.observedMetrics.count == 6)
    }

    @Test func opAmpSimulationDeckRunProducesWaveformAndMergedMetricArtifactsThroughCLI() async throws {
        let root = try makeTemporaryRoot("opamp-deck-run")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-deck-run"
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: workspaceStore)

        let deckSet = makeExecutableOpAmpDeckSet()
        let spec = OpAmpSpec(
            specID: "deck-run-opamp",
            title: "Deck run op-amp metric spec",
            operatingPoint: .init(
                supplyVoltage: 1.8,
                inputCommonModeVoltage: 0.9,
                outputCommonModeVoltage: 0.9,
                loadCapacitance: 1.0e-9
            ),
            requirements: [
                .init(metricID: .dcGainDB, relation: .atLeast, value: 30, unit: "dB"),
                .init(metricID: .unityGainFrequencyHz, relation: .atLeast, value: 1_000, unit: "Hz"),
                .init(metricID: .phaseMarginDegrees, relation: .atLeast, value: 10, unit: "deg"),
                .init(metricID: .positiveSlewRateVPerS, relation: .atLeast, value: 1_000, unit: "V/s"),
                .init(metricID: .negativeSlewRateVPerS, relation: .atLeast, value: 1_000, unit: "V/s"),
                .init(metricID: .outputSwingHighV, relation: .atLeast, value: 0.5, unit: "V"),
                .init(metricID: .outputSwingLowV, relation: .atMost, value: 0.5, unit: "V"),
                .init(metricID: .inputReferredNoiseVPerRootHz, relation: .atMost, value: 1.0e-3, unit: "V/sqrt(Hz)"),
            ]
        )

        let directRun = await OpAmpSimulationDeckRunner().run(deckSet, outputVariable: "V(vout)")
        #expect(directRun.report.status == "passed")
        #expect(directRun.waveforms.count == deckSet.decks.count)
        #expect(directRun.report.mergedMetricExtraction?.observedMetrics.contains {
            $0.metricID == .dcGainDB
        } == true)

        let deckSetURL = root.appending(path: "input/deck-set.json")
        let specURL = root.appending(path: "input/spec.json")
        let reportURL = root.appending(path: "output/deck-run-report.json")
        try writeJSON(deckSet, to: deckSetURL)
        try writeJSON(spec, to: specURL)

        let runOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "run-opamp-simulation-decks",
            "--project-root",
            root.path(percentEncoded: false),
            "--run-id",
            runID,
            "--deck-set",
            deckSetURL.path(percentEncoded: false),
            "--out",
            reportURL.path(percentEncoded: false),
            "--persist",
            "--pretty",
        ])
        let runResult = try decode(OpAmpSimulationDeckRunCLIResult.self, from: runOutput)
        let artifactIDs = Set(runResult.artifactReferences.compactMap(\.artifactID))
        #expect(runResult.report.status == "passed")
        #expect(runResult.report.mergedMetricExtraction?.observedMetrics.count == 9)
        #expect(artifactIDs.contains("opamp-simulation-execution-report"))
        #expect(artifactIDs.contains("opamp-metric-extraction"))
        #expect(artifactIDs.contains("opamp-simulation-ac-open-loop-waveform"))
        #expect(fileExists("output/deck-run-report.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation-execution-report.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/metric-extraction.json", in: root))
        #expect(fileExists(".xcircuite/runs/\(runID)/opamp/simulation/ac-open-loop-waveform.csv", in: root))

        let evaluationOutput = try await XcircuiteFlowCLICommand.run(arguments: [
            "evaluate-opamp",
            "--spec",
            specURL.path(percentEncoded: false),
            "--opamp-metric-extraction",
            root.appending(path: ".xcircuite/runs/\(runID)/opamp/metric-extraction.json").path(percentEncoded: false),
            "--pretty",
        ])
        let evaluationResult = try decode(OpAmpEvaluationCLIResult.self, from: evaluationOutput)
        #expect(evaluationResult.report.status == "passed")
    }

    @Test func postLayoutComparisonClassifiesPEXDrivenRegressionsAndPersistsThroughCLI() async throws {
        let root = try makeTemporaryRoot("opamp-post-layout")
        defer { removeTemporaryRoot(root) }
        let runID = "run-opamp-post-layout"
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: root)
        try await workspaceStore.ensureWorkspace()
        try await prepareTestRun(runID: runID, store: workspaceStore)

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

    private func makeExecutableOpAmpDeckSet() -> OpAmpSimulationDeckSet {
        OpAmpSimulationDeckSet(
            specID: "deck-run-opamp",
            topologyKind: .twoStageMiller,
            decks: [
                .init(
                    deckID: "ac-open-loop",
                    analysisKind: "ac",
                    title: "Fixture AC deck",
                    netlist: """
                    * Fixture AC deck
                    V1 vin 0 AC 100
                    R1 vin vout 1k
                    C1 vout 0 1u
                    .ac dec 20 1 1e6
                    .end
                    """,
                    postProcessingMetricIDs: [.dcGainDB, .unityGainFrequencyHz, .phaseMarginDegrees],
                    executionContract: .init(directMeasurementsRequired: false, waveformPostProcessingRequired: true)
                ),
                .init(
                    deckID: "tran-positive-step",
                    analysisKind: "tran",
                    title: "Fixture positive transient deck",
                    netlist: """
                    * Fixture positive transient deck
                    V1 vin 0 PULSE(0 1 0 1n 1n 10u 20u)
                    R1 vin vout 1k
                    C1 vout 0 1n
                    .tran 100n 50u
                    .meas tran outputSwingHigh MAX V(vout) FROM=10u TO=50u
                    .end
                    """,
                    directMetricIDs: [.outputSwingHighV],
                    postProcessingMetricIDs: [.positiveSlewRateVPerS, .settlingTimeSeconds],
                    measurementNames: ["outputSwingHigh"],
                    executionContract: .init(directMeasurementsRequired: true, waveformPostProcessingRequired: true)
                ),
                .init(
                    deckID: "tran-negative-step",
                    analysisKind: "tran",
                    title: "Fixture negative transient deck",
                    netlist: """
                    * Fixture negative transient deck
                    V1 vin 0 PULSE(1 0 0 1n 1n 10u 20u)
                    R1 vin vout 1k
                    C1 vout 0 1n
                    .tran 100n 50u
                    .meas tran outputSwingLow MIN V(vout) FROM=10u TO=50u
                    .end
                    """,
                    directMetricIDs: [.outputSwingLowV],
                    postProcessingMetricIDs: [.negativeSlewRateVPerS, .settlingTimeSeconds],
                    measurementNames: ["outputSwingLow"],
                    executionContract: .init(directMeasurementsRequired: true, waveformPostProcessingRequired: true)
                ),
                .init(
                    deckID: "noise-input-referred",
                    analysisKind: "noise",
                    title: "Fixture noise deck",
                    netlist: """
                    * Fixture noise deck
                    V1 vin 0 DC 0
                    R1 vin vout 1k
                    R2 vout 0 1k
                    .noise V(vout) V1 dec 5 1 1000
                    .end
                    """,
                    postProcessingMetricIDs: [.inputReferredNoiseVPerRootHz],
                    executionContract: .init(directMeasurementsRequired: false, waveformPostProcessingRequired: true)
                ),
            ]
        )
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

    private func writeText(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func metricValue(
        _ metricID: OpAmpMetricID,
        in extraction: OpAmpSimulationMetricExtraction
    ) -> Double? {
        extraction.observedMetrics.first { $0.metricID == metricID }?.value
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
    var artifactReferences: [ArtifactReference]
}

private struct OpAmpEvaluationCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpEvaluationReport
    var artifactReference: ArtifactReference?
    var metricExtraction: OpAmpSimulationMetricExtraction?
}

private struct OpAmpSimulationDeckValidationCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpSimulationDeckValidationReport
    var artifactReference: ArtifactReference?
}

private struct OpAmpSimulationDeckRunCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpSimulationDeckExecutionReport
    var artifactReferences: [ArtifactReference]
}

private struct OpAmpWaveformMetricExtractionCLIResult: Sendable, Hashable, Decodable {
    var extraction: OpAmpSimulationMetricExtraction
    var artifactReference: ArtifactReference?
}

private struct OpAmpMetricExtractionMergeCLIResult: Sendable, Hashable, Decodable {
    var extraction: OpAmpSimulationMetricExtraction
    var artifactReference: ArtifactReference?
}

private struct OpAmpPostLayoutCLIResult: Sendable, Hashable, Decodable {
    var report: OpAmpPostLayoutComparisonReport
    var artifactReference: ArtifactReference?
}
import CircuiteFoundation
