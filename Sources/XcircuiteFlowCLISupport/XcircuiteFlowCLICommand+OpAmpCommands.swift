import Foundation
import Xcircuite
import DesignFlowKernel

extension XcircuiteFlowCLICommand {
    static func writeOpAmpSpec(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return writeOpAmpSpecHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var outURL: URL?
        var specID = "opamp-spec"
        var supplyVoltage = 1.8
        var loadCapacitance = 1.0e-12
        var gainDB = 60.0
        var unityGainFrequency = 10.0e6
        var phaseMargin = 60.0
        var slewRate = 5.0e6
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--spec-id":
                specID = try parser.requiredValue(after: argument)
            case "--supply-v":
                supplyVoltage = try parser.requiredDouble(after: argument)
            case "--load-cap-f":
                loadCapacitance = try parser.requiredDouble(after: argument)
            case "--gain-db":
                gainDB = try parser.requiredDouble(after: argument)
            case "--ugb-hz":
                unityGainFrequency = try parser.requiredDouble(after: argument)
            case "--phase-margin-deg":
                phaseMargin = try parser.requiredDouble(after: argument)
            case "--slew-rate-v-per-s":
                slewRate = try parser.requiredDouble(after: argument)
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let outURL else {
            throw XcircuiteFlowCLIError.missingOption("--out")
        }
        let spec = OpAmpSpec.makeDefault(
            specID: specID,
            supplyVoltage: supplyVoltage,
            loadCapacitance: loadCapacitance,
            dcGainDB: gainDB,
            unityGainFrequencyHz: unityGainFrequency,
            phaseMarginDegrees: phaseMargin,
            slewRateVPerS: slewRate
        )
        try write(spec, to: outURL, pretty: pretty)
        return try encode(spec, pretty: pretty)
    }

    static func listOpAmpTopologies(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return listOpAmpTopologiesHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var specURL: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--spec":
                specURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let specURL else {
            throw XcircuiteFlowCLIError.missingOption("--spec")
        }
        let spec = try decodeJSONFile(OpAmpSpec.self, from: specURL, option: "--spec")
        let candidates = OpAmpTopologyLibrary().candidates(for: spec)
        return try encode(OpAmpTopologyListCLIResult(specID: spec.specID, candidates: candidates), pretty: pretty)
    }

    static func sizeOpAmp(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return sizeOpAmpHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var specURL: URL?
        var technologyURL: URL?
        var topologyKind: OpAmpTopologyKind?
        var persist = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--spec":
                specURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--technology":
                technologyURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--topology":
                topologyKind = try parseOpAmpTopologyKind(try parser.requiredValue(after: argument), option: argument)
            case "--no-persist":
                persist = false
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let specURL else {
            throw XcircuiteFlowCLIError.missingOption("--spec")
        }
        let spec = try decodeJSONFile(OpAmpSpec.self, from: specURL, option: "--spec")
        let technology = try technologyURL.map {
            try decodeJSONFile(OpAmpSizingTechnologyModel.self, from: $0, option: "--technology")
        } ?? OpAmpSizingTechnologyModel.genericCMOS180()
        let result = try OpAmpInitialSizingEngine().size(
            spec: spec,
            topologyKind: topologyKind,
            technology: technology
        )
        var artifacts: [XcircuiteFileReference] = []
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            let store = OpAmpDesignArtifactStore()
            artifacts.append(try store.persistSpec(spec, runID: runID, projectRoot: projectRoot))
            artifacts.append(try store.persistTopologyCandidates(
                OpAmpTopologyLibrary().candidates(for: spec),
                runID: runID,
                projectRoot: projectRoot
            ))
            artifacts.append(contentsOf: try store.persistSizingResult(result, runID: runID, projectRoot: projectRoot))
        }
        return try encode(OpAmpSizingCLIResult(result: result, artifactReferences: artifacts), pretty: pretty)
    }

    static func validateOpAmpSimulationDecks(arguments: [String]) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return validateOpAmpSimulationDecksHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var deckSetURL: URL?
        var mode = OpAmpSimulationDeckValidationMode.parseOnly
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--deck-set":
                deckSetURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--mode":
                mode = try parseOpAmpSimulationDeckValidationMode(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--execute":
                mode = .executeCoreSpice
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let deckSetURL else {
            throw XcircuiteFlowCLIError.missingOption("--deck-set")
        }
        let deckSet = try decodeJSONFile(
            OpAmpSimulationDeckSet.self,
            from: deckSetURL,
            option: "--deck-set"
        )
        let report = await OpAmpSimulationDeckValidator().validate(deckSet, mode: mode)
        if let outURL {
            try write(report, to: outURL, pretty: pretty)
        }
        var artifact: XcircuiteFileReference?
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            artifact = try OpAmpDesignArtifactStore().persistSimulationDeckValidationReport(
                report,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        return try encode(
            OpAmpSimulationDeckValidationCLIResult(report: report, artifactReference: artifact),
            pretty: pretty
        )
    }

    static func runOpAmpSimulationDecks(arguments: [String]) async throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return runOpAmpSimulationDecksHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var deckSetURL: URL?
        var outputVariable = "auto"
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--deck-set":
                deckSetURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--output-variable":
                outputVariable = try parser.requiredValue(after: argument)
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let deckSetURL else {
            throw XcircuiteFlowCLIError.missingOption("--deck-set")
        }
        let deckSet = try decodeJSONFile(
            OpAmpSimulationDeckSet.self,
            from: deckSetURL,
            option: "--deck-set"
        )
        let runResult = await OpAmpSimulationDeckRunner().run(
            deckSet,
            outputVariable: outputVariable
        )
        if let outURL {
            try write(runResult.report, to: outURL, pretty: pretty)
        }
        var artifacts: [XcircuiteFileReference] = []
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            let store = OpAmpDesignArtifactStore()
            for waveform in runResult.waveforms {
                artifacts.append(try store.persistSimulationDeckWaveform(
                    waveform.waveformCSV,
                    deckID: waveform.deckID,
                    runID: runID,
                    projectRoot: projectRoot
                ))
            }
            if let merged = runResult.report.mergedMetricExtraction {
                artifacts.append(try store.persistMergedMetricExtraction(
                    merged,
                    runID: runID,
                    projectRoot: projectRoot
                ))
            }
            artifacts.append(try store.persistSimulationDeckExecutionReport(
                runResult.report,
                runID: runID,
                projectRoot: projectRoot
            ))
        }
        return try encode(
            OpAmpSimulationDeckRunCLIResult(
                report: runResult.report,
                artifactReferences: artifacts
            ),
            pretty: pretty
        )
    }

    static func extractOpAmpWaveformMetrics(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return extractOpAmpWaveformMetricsHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var analysisKind: OpAmpWaveformAnalysisKind?
        var waveformURL: URL?
        var outputVariable = "auto"
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--analysis":
                analysisKind = try parseOpAmpWaveformAnalysisKind(
                    try parser.requiredValue(after: argument),
                    option: argument
                )
            case "--waveform":
                waveformURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--output-variable":
                outputVariable = try parser.requiredValue(after: argument)
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let analysisKind else {
            throw XcircuiteFlowCLIError.missingOption("--analysis")
        }
        guard let waveformURL else {
            throw XcircuiteFlowCLIError.missingOption("--waveform")
        }
        let waveformCSV = try String(contentsOf: waveformURL, encoding: .utf8)
        let extraction = try OpAmpWaveformMetricExtractor().extract(
            analysisKind: analysisKind,
            waveformCSV: waveformCSV,
            outputVariable: outputVariable,
            sourceKind: "xcircuite-waveform-csv"
        )
        if let outURL {
            try write(extraction, to: outURL, pretty: pretty)
        }
        var artifact: XcircuiteFileReference?
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            artifact = try OpAmpDesignArtifactStore().persistWaveformMetricExtraction(
                extraction,
                analysisKind: analysisKind,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        return try encode(
            OpAmpWaveformMetricExtractionCLIResult(
                extraction: extraction,
                artifactReference: artifact
            ),
            pretty: pretty
        )
    }

    static func mergeOpAmpMetricExtractions(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return mergeOpAmpMetricExtractionsHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var extractionURLs: [URL] = []
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--extraction":
                extractionURLs.append(URL(filePath: try parser.requiredValue(after: argument)))
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard !extractionURLs.isEmpty else {
            throw XcircuiteFlowCLIError.missingOption("--extraction")
        }
        let extractions = try extractionURLs.map {
            try decodeJSONFile(
                OpAmpSimulationMetricExtraction.self,
                from: $0,
                option: "--extraction"
            )
        }
        let merged = try OpAmpSimulationMetricExtractionMerger().merge(extractions)
        if let outURL {
            try write(merged, to: outURL, pretty: pretty)
        }
        var artifact: XcircuiteFileReference?
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            artifact = try OpAmpDesignArtifactStore().persistMergedMetricExtraction(
                merged,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        return try encode(
            OpAmpMetricExtractionMergeCLIResult(
                extraction: merged,
                artifactReference: artifact
            ),
            pretty: pretty
        )
    }

    static func evaluateOpAmp(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return evaluateOpAmpHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var specURL: URL?
        var crossArtifactURL: URL?
        var sizingResultURL: URL?
        var simulationMetricReportURL: URL?
        var simulationRunSummaryURL: URL?
        var simulationMeasurementsURL: URL?
        var opAmpMetricExtractionURL: URL?
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--spec":
                specURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--cross-artifact-evaluation":
                crossArtifactURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--sizing-result":
                sizingResultURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--simulation-metric-report":
                simulationMetricReportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--simulation-run-summary":
                simulationRunSummaryURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--simulation-measurements":
                simulationMeasurementsURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--opamp-metric-extraction":
                opAmpMetricExtractionURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let specURL else {
            throw XcircuiteFlowCLIError.missingOption("--spec")
        }
        let inputCount = [
            crossArtifactURL,
            sizingResultURL,
            simulationMetricReportURL,
            simulationRunSummaryURL,
            simulationMeasurementsURL,
            opAmpMetricExtractionURL,
        ].compactMap { $0 }.count
        guard inputCount > 0 else {
            throw XcircuiteFlowCLIError.missingOption(
                "--cross-artifact-evaluation, --sizing-result, --simulation-metric-report, --simulation-run-summary, --simulation-measurements, or --opamp-metric-extraction"
            )
        }
        guard inputCount == 1 else {
            throw XcircuiteFlowCLIError.invalidValue(option: "--evaluation-input", value: "multiple")
        }
        let spec = try decodeJSONFile(OpAmpSpec.self, from: specURL, option: "--spec")
        let evaluator = OpAmpMetricEvaluator()
        let report: OpAmpEvaluationReport
        let metricExtraction: OpAmpSimulationMetricExtraction?
        if let crossArtifactURL {
            let evaluation = try decodeJSONFile(
                XcircuiteCrossArtifactEvaluation.self,
                from: crossArtifactURL,
                option: "--cross-artifact-evaluation"
            )
            report = evaluator.evaluate(spec: spec, crossArtifactEvaluation: evaluation)
            metricExtraction = nil
        } else if let sizingResultURL {
            let sizing = try decodeJSONFile(OpAmpSizingResult.self, from: sizingResultURL, option: "--sizing-result")
            report = evaluator.evaluate(spec: spec, sizingResult: sizing)
            metricExtraction = nil
        } else if let simulationMetricReportURL {
            let source = try decodeJSONFile(
                XcircuiteSimulationMetricReport.self,
                from: simulationMetricReportURL,
                option: "--simulation-metric-report"
            )
            let extraction = OpAmpSimulationMetricExtractor().extract(from: source)
            metricExtraction = extraction
            report = evaluationReport(
                spec: spec,
                extraction: extraction,
                reportID: "\(spec.specID)-simulation-metric-evaluation"
            )
        } else if let simulationRunSummaryURL {
            let source = try decodeJSONFile(
                SimulationRunSummaryReport.self,
                from: simulationRunSummaryURL,
                option: "--simulation-run-summary"
            )
            let extraction = OpAmpSimulationMetricExtractor().extract(from: source)
            metricExtraction = extraction
            report = evaluationReport(
                spec: spec,
                extraction: extraction,
                reportID: "\(source.stageID)-opamp-evaluation"
            )
        } else if let simulationMeasurementsURL {
            let measurements = try decodeJSONFile(
                [SimulationMeasurementValue].self,
                from: simulationMeasurementsURL,
                option: "--simulation-measurements"
            )
            let extraction = OpAmpSimulationMetricExtractor().extract(measurements: measurements)
            metricExtraction = extraction
            report = evaluationReport(
                spec: spec,
                extraction: extraction,
                reportID: "\(spec.specID)-simulation-measurement-evaluation"
            )
        } else if let opAmpMetricExtractionURL {
            let extraction = try decodeJSONFile(
                OpAmpSimulationMetricExtraction.self,
                from: opAmpMetricExtractionURL,
                option: "--opamp-metric-extraction"
            )
            metricExtraction = extraction
            report = evaluationReport(
                spec: spec,
                extraction: extraction,
                reportID: "\(spec.specID)-opamp-waveform-evaluation"
            )
        } else {
            throw XcircuiteFlowCLIError.missingOption(
                "--cross-artifact-evaluation, --sizing-result, --simulation-metric-report, --simulation-run-summary, --simulation-measurements, or --opamp-metric-extraction"
            )
        }

        if let outURL {
            try write(report, to: outURL, pretty: pretty)
        }
        var artifact: XcircuiteFileReference?
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            artifact = try OpAmpDesignArtifactStore().persistEvaluationReport(
                report,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        return try encode(
            OpAmpEvaluationCLIResult(
                report: report,
                artifactReference: artifact,
                metricExtraction: metricExtraction
            ),
            pretty: pretty
        )
    }

    static func compareOpAmpPostLayout(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return compareOpAmpPostLayoutHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var specURL: URL?
        var preReportURL: URL?
        var postReportURL: URL?
        var outURL: URL?
        var projectRoot: URL?
        var runID: String?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--spec":
                specURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--pre-report":
                preReportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--post-report":
                postReportURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--out":
                outURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let specURL else {
            throw XcircuiteFlowCLIError.missingOption("--spec")
        }
        guard let preReportURL else {
            throw XcircuiteFlowCLIError.missingOption("--pre-report")
        }
        guard let postReportURL else {
            throw XcircuiteFlowCLIError.missingOption("--post-report")
        }
        let spec = try decodeJSONFile(OpAmpSpec.self, from: specURL, option: "--spec")
        let preReport = try decodeJSONFile(OpAmpEvaluationReport.self, from: preReportURL, option: "--pre-report")
        let postReport = try decodeJSONFile(OpAmpEvaluationReport.self, from: postReportURL, option: "--post-report")
        let report = OpAmpPostLayoutComparator().compare(spec: spec, preLayout: preReport, postLayout: postReport)
        if let outURL {
            try write(report, to: outURL, pretty: pretty)
        }
        var artifact: XcircuiteFileReference?
        if persist {
            guard let projectRoot else {
                throw XcircuiteFlowCLIError.missingOption("--project-root")
            }
            guard let runID else {
                throw XcircuiteFlowCLIError.missingOption("--run-id")
            }
            artifact = try OpAmpDesignArtifactStore().persistPostLayoutComparison(
                report,
                runID: runID,
                projectRoot: projectRoot
            )
        }
        return try encode(OpAmpPostLayoutCLIResult(report: report, artifactReference: artifact), pretty: pretty)
    }

    private static func parseOpAmpTopologyKind(_ value: String, option: String) throws -> OpAmpTopologyKind {
        guard let kind = OpAmpTopologyKind(rawValue: value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return kind
    }

    private static func parseOpAmpSimulationDeckValidationMode(
        _ value: String,
        option: String
    ) throws -> OpAmpSimulationDeckValidationMode {
        guard let mode = OpAmpSimulationDeckValidationMode(rawValue: value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return mode
    }

    private static func parseOpAmpWaveformAnalysisKind(
        _ value: String,
        option: String
    ) throws -> OpAmpWaveformAnalysisKind {
        guard let kind = OpAmpWaveformAnalysisKind(rawValue: value) else {
            throw XcircuiteFlowCLIError.invalidValue(option: option, value: value)
        }
        return kind
    }

    private static func evaluationReport(
        spec: OpAmpSpec,
        extraction: OpAmpSimulationMetricExtraction,
        reportID: String
    ) -> OpAmpEvaluationReport {
        var report = OpAmpMetricEvaluator().evaluate(
            spec: spec,
            observedMetrics: extraction.observedMetrics,
            sourceChannelIDs: Dictionary(uniqueKeysWithValues: extraction.observedMetrics.map {
                ($0.metricID, [extraction.sourceKind])
            }),
            reportID: reportID
        )
        report.diagnostics.append(contentsOf: extraction.diagnostics)
        return report
    }
}

private struct OpAmpTopologyListCLIResult: Sendable, Hashable, Codable {
    var specID: String
    var candidates: [OpAmpTopologyCandidate]
}

private struct OpAmpSizingCLIResult: Sendable, Hashable, Codable {
    var result: OpAmpSizingResult
    var artifactReferences: [XcircuiteFileReference]
}

private struct OpAmpEvaluationCLIResult: Sendable, Hashable, Codable {
    var report: OpAmpEvaluationReport
    var artifactReference: XcircuiteFileReference?
    var metricExtraction: OpAmpSimulationMetricExtraction?
}

private struct OpAmpSimulationDeckValidationCLIResult: Sendable, Hashable, Codable {
    var report: OpAmpSimulationDeckValidationReport
    var artifactReference: XcircuiteFileReference?
}

private struct OpAmpSimulationDeckRunCLIResult: Sendable, Hashable, Codable {
    var report: OpAmpSimulationDeckExecutionReport
    var artifactReferences: [XcircuiteFileReference]
}

private struct OpAmpWaveformMetricExtractionCLIResult: Sendable, Hashable, Codable {
    var extraction: OpAmpSimulationMetricExtraction
    var artifactReference: XcircuiteFileReference?
}

private struct OpAmpMetricExtractionMergeCLIResult: Sendable, Hashable, Codable {
    var extraction: OpAmpSimulationMetricExtraction
    var artifactReference: XcircuiteFileReference?
}

private struct OpAmpPostLayoutCLIResult: Sendable, Hashable, Codable {
    var report: OpAmpPostLayoutComparisonReport
    var artifactReference: XcircuiteFileReference?
}
