import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func qualifySimulationGoldenCorpus(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var suiteURL: URL?
        var outputURL: URL?
        var artifactDirectory: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--suite":
                suiteURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--out":
                outputURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--artifact-dir":
                artifactDirectory = URL(filePath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return qualifySimulationGoldenCorpusHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let suiteURL else {
            throw XcircuiteFlowCLIError.missingOption("--suite")
        }

        let suite = try SimulationGoldenCorpusSuiteSpec.load(from: suiteURL)
        let resolvedArtifactDirectory = artifactDirectory
            ?? projectRoot
                .appending(path: ".xcircuite")
                .appending(path: "qualification")
                .appending(path: "simulation-golden")
                .appending(path: suite.suiteID)
        let report = try await SimulationGoldenCorpusRunner().run(
            suite: suite,
            projectRoot: projectRoot,
            artifactDirectory: resolvedArtifactDirectory
        )
        if let outputURL {
            try write(report, to: outputURL, pretty: pretty)
        }
        return try encode(report, pretty: pretty)
    }

    static func compareSimulationGolden(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var goldenCSVURL: URL?
        var candidateCSVURL: URL?
        var outputURL: URL?
        var maxAbsoluteDelta: Double?
        var maxRelativeDelta: Double?
        var relativeDeltaDenominatorFloor: Double?
        var requiredVariables: [String] = []
        var comparedVariables: [String] = []
        var allowInterpolation = true
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--golden-csv":
                goldenCSVURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--candidate-csv":
                candidateCSVURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--out":
                outputURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--max-absolute-delta":
                maxAbsoluteDelta = try parser.requiredDouble(after: argument)
            case "--max-relative-delta":
                maxRelativeDelta = try parser.requiredDouble(after: argument)
            case "--relative-delta-denominator-floor":
                relativeDeltaDenominatorFloor = try parser.requiredDouble(after: argument)
            case "--required-variable":
                requiredVariables.append(try parser.requiredValue(after: argument))
            case "--compare-variable":
                comparedVariables.append(try parser.requiredValue(after: argument))
            case "--no-interpolation":
                allowInterpolation = false
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return compareSimulationGoldenHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let goldenCSVURL else {
            throw XcircuiteFlowCLIError.missingOption("--golden-csv")
        }
        guard let candidateCSVURL else {
            throw XcircuiteFlowCLIError.missingOption("--candidate-csv")
        }

        let goldenCSV = try readText(at: goldenCSVURL)
        let candidateCSV = try readText(at: candidateCSVURL)
        let report = try SimulationGoldenComparisonService().compare(
            goldenCSV: goldenCSV,
            candidateCSV: candidateCSV,
            options: SimulationGoldenComparisonOptions(
                maxAbsoluteDelta: maxAbsoluteDelta,
                maxRelativeDelta: maxRelativeDelta,
                relativeDeltaDenominatorFloor: relativeDeltaDenominatorFloor,
                requiredVariables: stableUnique(requiredVariables),
                comparedVariables: stableUnique(comparedVariables),
                allowInterpolation: allowInterpolation
            )
        )
        if let outputURL {
            try write(report, to: outputURL, pretty: pretty)
        }
        return try encode(report, pretty: pretty)
    }

    private static func readText(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw XcircuiteFlowCLIError.readFailed(error.localizedDescription)
        }
    }
}
