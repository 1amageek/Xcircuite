import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func inspectPlatformCapabilities(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var runID = "capability-inspection"
        var generatedAt = "1970-01-01T00:00:00Z"
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--generated-at":
                generatedAt = try parser.requiredValue(after: argument)
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return inspectPlatformCapabilitiesHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        let report = try XcircuitePlatformCapabilityReadinessAssessor().assess(
            runID: runID,
            generatedAt: generatedAt
        )
        return try encode(report, pretty: pretty)
    }
}
