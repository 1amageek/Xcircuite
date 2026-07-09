import Foundation
import Xcircuite

extension XcircuiteFlowCLICommand {
    static func inspectPlatformCapabilities(arguments: [String]) throws -> String {
        var parser = XcircuiteFlowCLIArgumentParser(arguments: arguments)
        var runID = "capability-inspection"
        var generatedAt = "1970-01-01T00:00:00Z"
        var testEvidenceURL: URL?
        var pretty = false

        while let argument = parser.next() {
            switch argument {
            case "--run-id":
                runID = try parser.requiredValue(after: argument)
            case "--generated-at":
                generatedAt = try parser.requiredValue(after: argument)
            case "--test-evidence":
                testEvidenceURL = URL(fileURLWithPath: try parser.requiredValue(after: argument))
            case "--pretty":
                pretty = true
            case "--help", "-h":
                return inspectPlatformCapabilitiesHelpText
            default:
                throw XcircuiteFlowCLIError.unknownOption(argument)
            }
        }

        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: runID,
            generatedAt: generatedAt
        )
        let testEvidence = try testEvidenceURL.map { try loadPlatformCapabilityTestEvidence(from: $0) }
        let report = XcircuitePlatformCapabilityReadinessAssessor().assess(
            actionDomainSnapshot: snapshot,
            testEvidence: testEvidence
        )
        return try encode(report, pretty: pretty)
    }

    private static func loadPlatformCapabilityTestEvidence(
        from url: URL
    ) throws -> [XcircuitePlatformCapabilityTestEvidence] {
        let data = try readInputFileData(from: url, option: "--test-evidence")
        let decoder = JSONDecoder()
        do {
            let evidence = try decoder.decode([XcircuitePlatformCapabilityTestEvidence].self, from: data)
            return evidence
        } catch {
            do {
                let report = try decoder.decode(XcircuitePlatformCapabilityReadinessReport.self, from: data)
                return report.testEvidence
            } catch {
                throw XcircuiteFlowCLIError.readFailed(
                    "Invalid JSON for --test-evidence at \(url.path(percentEncoded: false)): expected a test evidence array or platform capability readiness report."
                )
            }
        }
    }
}
