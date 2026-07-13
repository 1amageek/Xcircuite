import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanVerifier {
    func decodedHint<T: Decodable>(
        _ key: String,
        from step: XcircuiteCandidatePlanStep
    ) throws -> T? {
        guard let value = step.parameterHints[key] else {
            return nil
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func stringHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> String? {
        guard case .string(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

    func stringArrayHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> [String]? {
        guard case .array(let values) = step.parameterHints[key] else {
            return nil
        }
        let strings = values.compactMap { value -> String? in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
        return strings.isEmpty ? nil : strings
    }

    func intHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> Int? {
        guard case .number(let value) = step.parameterHints[key] else {
            return nil
        }
        guard value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(value)
    }

    func boolHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> Bool? {
        guard case .bool(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

    func uniqueArtifactRefs(
        _ references: [XcircuiteFileReference]
    ) -> [XcircuiteFileReference] {
        var seen: Set<String> = []
        return references.filter { reference in
            let key = reference.artifactID ?? reference.path
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}
