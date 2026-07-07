import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import XcircuitePackage

extension XcircuiteCandidatePlanExecutor {
    func lvsPolicyRepairKind(from step: XcircuiteCandidatePlanStep) throws -> String {
        if let explicit = normalizedPolicyKind(nonEmptyStringHintIfPresent("policyKind", step: step)) {
            return explicit
        }
        if nonEmptyStringHintIfPresent("terminalKind", step: step) != nil
            || nonEmptyStringHintIfPresent("terminalModel", step: step) != nil
            || step.parameterHints["equivalentPinGroups"] != nil {
            return "terminal-equivalence"
        }
        let normalized = [
            stringHint("ruleID", step: step),
            stringHint("category", step: step),
            stringHint("componentSignature", step: step),
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if normalized.contains("terminal") || normalized.contains("pin-swap") || normalized.contains("pin swap") {
            return "terminal-equivalence"
        }
        return "model-equivalence"
    }

    func normalizedPolicyKind(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "model", "model-equivalence", "model_equivalence":
            return "model-equivalence"
        case "terminal", "terminal-equivalence", "terminal_equivalence":
            return "terminal-equivalence"
        default:
            return nil
        }
    }

    func modelEquivalencePolicy(from step: XcircuiteCandidatePlanStep) throws -> LVSModelEquivalencePolicy {
        let schematicModel = try nonEmptyStringHint("schematicModel", step: step)
        let layoutModel = try nonEmptyStringHint("layoutModel", step: step)
        let canonicalModel = nonEmptyStringHintIfPresent("canonicalModel", step: step) ?? schematicModel
        let aliases = unique(([layoutModel] + stringArrayHint("modelAliases", step: step)))
            .filter { !sameIdentifier($0, canonicalModel) }
        guard !aliases.isEmpty else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "layoutModel",
                expected: "model alias different from canonicalModel"
            )
        }
        return LVSModelEquivalencePolicy(
            groups: [
                LVSModelEquivalenceGroup(
                    canonicalModel: canonicalModel,
                    aliases: aliases
                ),
            ]
        )
    }

    func terminalEquivalencePolicy(
        from step: XcircuiteCandidatePlanStep
    ) throws -> (policy: LVSTerminalEquivalencePolicy, rule: LVSTerminalEquivalenceRule) {
        let kind = try terminalKind(from: step)
        let model = nonEmptyStringHintIfPresent("terminalModel", step: step)
        let pinCount = try optionalIntHint("terminalPinCount", step: step)
            ?? optionalIntHint("pinCount", step: step)
            ?? inferredPinCount(from: step)
        let groups = try terminalEquivalentPinGroups(from: step)
        let rule = LVSTerminalEquivalenceRule(
            kind: kind,
            model: model,
            pinCount: pinCount,
            equivalentPinGroups: groups
        )
        return (
            policy: LVSTerminalEquivalencePolicy(rules: [rule]),
            rule: rule
        )
    }

    func terminalKind(from step: XcircuiteCandidatePlanStep) throws -> String {
        if let kind = nonEmptyStringHintIfPresent("terminalKind", step: step)
            ?? nonEmptyStringHintIfPresent("deviceKind", step: step)
            ?? nonEmptyStringHintIfPresent("primitiveKind", step: step) {
            return kind
        }
        if let componentSignature = nonEmptyStringHintIfPresent("componentSignature", step: step),
           let first = componentSignature.split(separator: "|").first,
           let kind = nonEmpty(String(first)) {
            return kind
        }
        if let model = nonEmptyStringHintIfPresent("layoutModel", step: step)
            ?? nonEmptyStringHintIfPresent("schematicModel", step: step) {
            return model
        }
        throw XcircuiteCandidatePlanExecutionError.invalidHint(
            stepID: step.stepID,
            key: "terminalKind",
            expected: "non-empty terminal primitive kind"
        )
    }

    func terminalEquivalentPinGroups(from step: XcircuiteCandidatePlanStep) throws -> [[Int]] {
        if case .string? = step.parameterHints["equivalentPinGroups"] {
            if let encoded = nonEmptyStringHintIfPresent("equivalentPinGroups", step: step),
               let data = encoded.data(using: .utf8) {
                return try JSONDecoder().decode([[Int]].self, from: data)
            }
        } else if let groups: [[Int]] = try decodedHint("equivalentPinGroups", from: step) {
            return groups
        }
        let layoutPorts = stringArrayHint("layoutPorts", step: step)
        let schematicPorts = stringArrayHint("schematicPorts", step: step)
        if layoutPorts.count == schematicPorts.count,
           Set(layoutPorts) == Set(schematicPorts),
           layoutPorts != schematicPorts {
            let swappedIndexes = layoutPorts.indices.filter { layoutPorts[$0] != schematicPorts[$0] }
            if swappedIndexes.count >= 2 {
                return [Array(swappedIndexes)]
            }
        }
        throw XcircuiteCandidatePlanExecutionError.invalidHint(
            stepID: step.stepID,
            key: "equivalentPinGroups",
            expected: "array of terminal index groups or inferable swapped terminal order"
        )
    }

    func inferredPinCount(from step: XcircuiteCandidatePlanStep) -> Int? {
        let layoutPorts = stringArrayHint("layoutPorts", step: step)
        if !layoutPorts.isEmpty {
            return layoutPorts.count
        }
        let schematicPorts = stringArrayHint("schematicPorts", step: step)
        return schematicPorts.isEmpty ? nil : schematicPorts.count
    }

    func optionalIntHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) throws -> Int? {
        guard let value = step.parameterHints[key] else {
            return nil
        }
        switch value {
        case .number(let number) where number.isFinite && number.rounded() == number:
            return Int(number)
        case .string(let string):
            guard let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw XcircuiteCandidatePlanExecutionError.invalidHint(
                    stepID: step.stepID,
                    key: key,
                    expected: "integer"
                )
            }
            return int
        default:
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "integer"
            )
        }
    }

    func nonEmptyStringHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) throws -> String {
        guard let value = nonEmptyStringHintIfPresent(key, step: step) else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "non-empty string"
            )
        }
        return value
    }

    func nonEmptyStringHintIfPresent(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> String? {
        guard let value = stringHint(key, step: step) else {
            return nil
        }
        return nonEmpty(value)
    }

    func stringArrayHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> [String] {
        guard case .array(let values) = step.parameterHints[key] else {
            return []
        }
        return values.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return nonEmpty(string)
        }
    }

    func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
