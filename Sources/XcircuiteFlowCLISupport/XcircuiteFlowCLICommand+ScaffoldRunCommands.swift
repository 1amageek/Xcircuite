import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func scaffoldRun(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var runID: String?
        var runSpecURL: URL?
        var runtimeConfigURL: URL?
        var stageKinds: [XcircuiteFlowRunScaffolder.StageKind] = []
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--out-run-spec":
                runSpecURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--out-runtime-config":
                runtimeConfigURL = URL(filePath: try parser.requiredValue(after: argument))
            case "--stage":
                let rawValue = try parser.requiredValue(after: argument)
                for rawKind in rawValue.split(separator: ",").map(String.init) {
                    guard let kind = XcircuiteFlowRunScaffolder.StageKind(rawValue: rawKind) else {
                        throw XcircuiteFlowCLIError.invalidValue(option: argument, value: rawKind)
                    }
                    stageKinds.append(kind)
                }
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return scaffoldRunHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let runID else {
            throw XcircuiteFlowCLIError.missingOption("--run-id")
        }
        guard let runSpecURL else {
            throw XcircuiteFlowCLIError.missingOption("--out-run-spec")
        }
        guard let runtimeConfigURL else {
            throw XcircuiteFlowCLIError.missingOption("--out-runtime-config")
        }
        if stageKinds.isEmpty {
            stageKinds = XcircuiteFlowRunScaffolder.defaultStageKinds
        }

        let scaffold = try XcircuiteFlowRunScaffolder(
            runID: runID,
            stageKinds: stageKinds
        ).make()

        // Validation gate before writing: the exact bytes that reach disk
        // must decode through the real spec types and pass the same
        // coverage validation `xcircuite-flow validate` applies.
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let runSpecData: Data
        let runtimeConfigData: Data
        let decodedRunSpec: XcircuiteFlowRunSpec
        let decodedRuntimeSpec: XcircuiteFlowRuntimeSpec
        do {
            runSpecData = try encoder.encode(scaffold.runSpec)
            runtimeConfigData = try encoder.encode(scaffold.runtimeSpec)
            decodedRunSpec = try JSONDecoder().decode(XcircuiteFlowRunSpec.self, from: runSpecData)
            decodedRuntimeSpec = try JSONDecoder().decode(
                XcircuiteFlowRuntimeSpec.self,
                from: runtimeConfigData
            )
        } catch {
            throw XcircuiteFlowCLIError.encodeFailed(
                "Scaffolded specs failed to round-trip through the spec types: \(error.localizedDescription)"
            )
        }
        try decodedRuntimeSpec.validateCoverage(
            for: decodedRunSpec,
            projectRoot: projectRoot
        )

        try writeScaffoldData(runSpecData, to: runSpecURL)
        try writeScaffoldData(runtimeConfigData, to: runtimeConfigURL)

        let runSpecPath = runSpecURL.path(percentEncoded: false)
        let runtimeConfigPath = runtimeConfigURL.path(percentEncoded: false)
        return try encode(
            ScaffoldRunOutput(
                status: "scaffolded",
                runID: runID,
                runSpecPath: runSpecPath,
                runtimeConfigPath: runtimeConfigPath,
                stageIDs: scaffold.stageIDs,
                placeholderPaths: scaffold.placeholderPaths,
                nextActions: [
                    "Replace the placeholder input paths (\(scaffold.placeholderPaths.joined(separator: ", "))) with real artifacts relative to your project root.",
                    "Attach retained ToolQualification evidence and raise each tool requirement only to the verified qualification level.",
                    "Validate: xcircuite-flow validate --project-root \(projectRoot.path(percentEncoded: false)) --run-spec \(runSpecPath) --runtime-config \(runtimeConfigPath)",
                    "Run: xcircuite-flow run --project-root <path> --run-spec \(runSpecPath) --runtime-config \(runtimeConfigPath)",
                ]
            ),
            pretty: pretty
        )
    }

    private static func writeScaffoldData(_ data: Data, to url: URL) throws {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw XcircuiteFlowCLIError.writeFailed(error.localizedDescription)
        }
    }

    struct ScaffoldRunOutput: Sendable, Hashable, Codable {
        var status: String
        var runID: String
        var runSpecPath: String
        var runtimeConfigPath: String
        var stageIDs: [String]
        var placeholderPaths: [String]
        var nextActions: [String]
    }
}
