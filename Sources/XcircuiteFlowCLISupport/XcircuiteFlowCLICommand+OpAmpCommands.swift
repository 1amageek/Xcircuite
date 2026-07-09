import Foundation
import Xcircuite
import XcircuitePackage

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

    static func evaluateOpAmp(arguments: [String]) throws -> String {
        if arguments.contains("--help") || arguments.contains("-h") {
            return evaluateOpAmpHelpText
        }
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var specURL: URL?
        var crossArtifactURL: URL?
        var sizingResultURL: URL?
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
        let spec = try decodeJSONFile(OpAmpSpec.self, from: specURL, option: "--spec")
        let report: OpAmpEvaluationReport
        if let crossArtifactURL {
            let evaluation = try decodeJSONFile(
                XcircuiteCrossArtifactEvaluation.self,
                from: crossArtifactURL,
                option: "--cross-artifact-evaluation"
            )
            report = OpAmpMetricEvaluator().evaluate(spec: spec, crossArtifactEvaluation: evaluation)
        } else if let sizingResultURL {
            let sizing = try decodeJSONFile(OpAmpSizingResult.self, from: sizingResultURL, option: "--sizing-result")
            report = OpAmpMetricEvaluator().evaluate(spec: spec, sizingResult: sizing)
        } else {
            throw XcircuiteFlowCLIError.missingOption("--cross-artifact-evaluation or --sizing-result")
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
        return try encode(OpAmpEvaluationCLIResult(report: report, artifactReference: artifact), pretty: pretty)
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
}

private struct OpAmpPostLayoutCLIResult: Sendable, Hashable, Codable {
    var report: OpAmpPostLayoutComparisonReport
    var artifactReference: XcircuiteFileReference?
}
