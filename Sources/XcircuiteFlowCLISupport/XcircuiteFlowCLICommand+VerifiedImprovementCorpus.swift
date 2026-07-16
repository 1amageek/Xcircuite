import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func qualifyVerifiedImprovementCorpus(arguments: [String]) async throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var projectRoot: URL?
        var suiteSpecPath: URL?
        var persist = false
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--project-root":
                projectRoot = URL(filePath: try parser.requiredValue(after: argument))
            case "--suite-spec":
                suiteSpecPath = URL(filePath: try parser.requiredValue(after: argument))
            case "--persist":
                persist = true
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return qualifyVerifiedImprovementCorpusHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        guard let projectRoot else {
            throw XcircuiteFlowCLIError.missingOption("--project-root")
        }
        guard let suiteSpecPath else {
            throw XcircuiteFlowCLIError.missingOption("--suite-spec")
        }

        let suiteSpec = try decodeJSONFile(
            XcircuiteVerifiedImprovementCorpusSuiteSpec.self,
            from: suiteSpecPath,
            option: "--suite-spec"
        )

        let store = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let qualifier = XcircuiteVerifiedImprovementCorpusQualifier(storage: store)
        let report: XcircuiteVerifiedImprovementCorpusReport
        if persist {
            report = try await qualifier.qualifyAndPersist(suiteSpec: suiteSpec)
        } else {
            report = try await qualifier.qualify(suiteSpec: suiteSpec)
        }
        return try encode(report, pretty: pretty)
    }
}
