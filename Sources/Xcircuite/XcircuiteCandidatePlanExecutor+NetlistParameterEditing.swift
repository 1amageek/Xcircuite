import CoreSpiceIO
import Foundation
import LayoutCommands
import LayoutCore
import LayoutIO
import LayoutTech
import LVSEngine
import DesignFlowKernel

extension XcircuiteCandidatePlanExecutor {
    func parameterAssignments(step: XcircuiteCandidatePlanStep) throws -> [XcircuiteParameterAssignment] {
        guard case .parameterAssignments(let assignments) = step.parameterHints["assignments"] else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: "assignments",
                expected: "array of assignment objects"
            )
        }
        return try assignments.enumerated().map { index, assignment in
            guard !assignment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteCandidatePlanExecutionError.invalidHint(
                    stepID: step.stepID,
                    key: "assignments[\(index)].name",
                    expected: "non-empty string"
                )
            }
            guard assignment.value.isFinite else {
                throw XcircuiteCandidatePlanExecutionError.invalidHint(
                    stepID: step.stepID,
                    key: "assignments[\(index)].value",
                    expected: "finite number"
                )
            }
            return assignment
        }
    }

    func applyParameterAssignments(
        _ assignments: [XcircuiteParameterAssignment],
        to netlist: ParsedNetlist,
        stepID: String
    ) throws -> EditedNetlist {
        var components = netlist.components
        var subcircuits = netlist.subcircuits
        var parameterDefinitions = netlist.parameterDefinitions
        var parameters = netlist.parameters
        var edits: [XcircuiteNetlistParameterEdit] = []

        for assignment in assignments {
            if let explicitTarget = explicitComponentTarget(assignment.name) {
                if let edit = updateComponentParameter(
                    componentName: explicitTarget.component,
                    parameterName: explicitTarget.parameter,
                    assignment: assignment,
                    components: &components
                ) {
                    edits.append(edit)
                    continue
                }
                if let edit = updateSubcircuitComponentParameter(
                    componentName: explicitTarget.component,
                    parameterName: explicitTarget.parameter,
                    assignment: assignment,
                    subcircuits: &subcircuits
                ) {
                    edits.append(edit)
                    continue
                }
            }
            if let edit = updateComponentPrimaryParameter(
                componentName: assignment.name,
                assignment: assignment,
                components: &components
            ) {
                edits.append(edit)
                continue
            }
            if let edit = updateSubcircuitComponentPrimaryParameter(
                componentName: assignment.name,
                assignment: assignment,
                subcircuits: &subcircuits
            ) {
                edits.append(edit)
                continue
            }
            if let edit = updateGlobalParameter(
                parameterName: assignment.name,
                assignment: assignment,
                parameterDefinitions: &parameterDefinitions,
                parameters: &parameters
            ) {
                edits.append(edit)
                continue
            }
            throw XcircuiteCandidatePlanExecutionError.unresolvedParameterAssignment(
                stepID: stepID,
                assignmentName: assignment.name
            )
        }

        return EditedNetlist(
            netlist: ParsedNetlist(
                title: netlist.title,
                components: components,
                models: netlist.models,
                subcircuits: subcircuits,
                analyses: netlist.analyses,
                controls: netlist.controls,
                parameterDefinitions: parameterDefinitions,
                parameters: parameters,
                preprocessingEvents: netlist.preprocessingEvents,
                initialConditions: netlist.initialConditions,
                nodeSets: netlist.nodeSets,
                globalNodes: netlist.globalNodes,
                pvtCorners: netlist.pvtCorners,
                mcVariations: netlist.mcVariations,
                sourcePath: netlist.sourcePath
            ),
            edits: edits
        )
    }

    func explicitComponentTarget(_ assignmentName: String) -> (component: String, parameter: String)? {
        for separator in [".", ":", "/"] {
            let parts = assignmentName.split(separator: Character(separator), maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            let component = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let parameter = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !component.isEmpty, !parameter.isEmpty {
                return (component, parameter)
            }
        }
        return nil
    }

    func updateComponentPrimaryParameter(
        componentName: String,
        assignment: XcircuiteParameterAssignment,
        components: inout [ParsedComponent]
    ) -> XcircuiteNetlistParameterEdit? {
        guard let index = components.firstIndex(where: { sameIdentifier($0.name, componentName) }) else {
            return nil
        }
        let component = components[index]
        let parameterName: String
        if component.parameters.count == 1, let existing = component.parameters.keys.first {
            parameterName = existing
        } else if let primary = primaryParameterName(for: component.type) {
            parameterName = primary
        } else {
            return nil
        }
        return updateComponentParameter(
            componentName: component.name,
            parameterName: parameterName,
            assignment: assignment,
            components: &components
        )
    }

    func updateSubcircuitComponentPrimaryParameter(
        componentName: String,
        assignment: XcircuiteParameterAssignment,
        subcircuits: inout [ParsedSubcircuit],
        scope: [String] = []
    ) -> XcircuiteNetlistParameterEdit? {
        for index in subcircuits.indices {
            let subcircuit = subcircuits[index]
            var components = subcircuit.body.components
            if var edit = updateComponentPrimaryParameter(
                componentName: componentName,
                assignment: assignment,
                components: &components
            ) {
                edit.targetKind = "subcircuit-component-parameter"
                edit.targetName = scopedTargetName(scope + [subcircuit.name], componentName: edit.targetName)
                subcircuits[index] = subcircuit.replacingBody(components: components)
                return edit
            }

            var nestedSubcircuits = subcircuit.body.subcircuits
            if let edit = updateSubcircuitComponentPrimaryParameter(
                componentName: componentName,
                assignment: assignment,
                subcircuits: &nestedSubcircuits,
                scope: scope + [subcircuit.name]
            ) {
                subcircuits[index] = subcircuit.replacingBody(subcircuits: nestedSubcircuits)
                return edit
            }
        }
        return nil
    }

    func updateSubcircuitComponentParameter(
        componentName: String,
        parameterName: String,
        assignment: XcircuiteParameterAssignment,
        subcircuits: inout [ParsedSubcircuit],
        scope: [String] = []
    ) -> XcircuiteNetlistParameterEdit? {
        for index in subcircuits.indices {
            let subcircuit = subcircuits[index]
            var components = subcircuit.body.components
            if var edit = updateComponentParameter(
                componentName: componentName,
                parameterName: parameterName,
                assignment: assignment,
                components: &components
            ) {
                edit.targetKind = "subcircuit-component-parameter"
                edit.targetName = scopedTargetName(scope + [subcircuit.name], componentName: edit.targetName)
                subcircuits[index] = subcircuit.replacingBody(components: components)
                return edit
            }

            var nestedSubcircuits = subcircuit.body.subcircuits
            if let edit = updateSubcircuitComponentParameter(
                componentName: componentName,
                parameterName: parameterName,
                assignment: assignment,
                subcircuits: &nestedSubcircuits,
                scope: scope + [subcircuit.name]
            ) {
                subcircuits[index] = subcircuit.replacingBody(subcircuits: nestedSubcircuits)
                return edit
            }
        }
        return nil
    }

    func updateComponentParameter(
        componentName: String,
        parameterName: String,
        assignment: XcircuiteParameterAssignment,
        components: inout [ParsedComponent]
    ) -> XcircuiteNetlistParameterEdit? {
        guard let index = components.firstIndex(where: { sameIdentifier($0.name, componentName) }) else {
            return nil
        }
        let component = components[index]
        let resolvedParameterName = parameterName.lowercased()
        var parameters = component.parameters
        parameters[resolvedParameterName] = .numeric(assignment.value)
        components[index] = ParsedComponent(
            name: component.name,
            type: component.type,
            nodes: component.nodes,
            modelName: component.modelName,
            parameters: parameters,
            location: component.location
        )
        return XcircuiteNetlistParameterEdit(
            assignmentName: assignment.name,
            targetKind: "component-parameter",
            targetName: component.name,
            parameterName: resolvedParameterName,
            value: assignment.value,
            unit: assignment.unit
        )
    }

    func updateGlobalParameter(
        parameterName: String,
        assignment: XcircuiteParameterAssignment,
        parameterDefinitions: inout [ParsedParameterDefinition],
        parameters: inout [String: ParsedExpression]
    ) -> XcircuiteNetlistParameterEdit? {
        if let index = parameterDefinitions.firstIndex(where: { sameIdentifier($0.name, parameterName) }) {
            let original = parameterDefinitions[index]
            parameterDefinitions[index] = ParsedParameterDefinition(
                name: original.name,
                value: .literal(assignment.value),
                location: original.location
            )
            parameters[matchingParameterKey(original.name, in: parameters) ?? original.name.lowercased()] = .literal(assignment.value)
            return globalEdit(assignment: assignment, targetName: original.name)
        }
        guard let key = matchingParameterKey(parameterName, in: parameters) else {
            return nil
        }
        parameters[key] = .literal(assignment.value)
        if !parameterDefinitions.isEmpty {
            parameterDefinitions.append(ParsedParameterDefinition(
                name: key,
                value: .literal(assignment.value)
            ))
        }
        return globalEdit(assignment: assignment, targetName: key)
    }

    func matchingParameterKey(
        _ parameterName: String,
        in parameters: [String: ParsedExpression]
    ) -> String? {
        parameters.keys.first { sameIdentifier($0, parameterName) }
    }

    func globalEdit(
        assignment: XcircuiteParameterAssignment,
        targetName: String
    ) -> XcircuiteNetlistParameterEdit {
        XcircuiteNetlistParameterEdit(
            assignmentName: assignment.name,
            targetKind: "global-parameter",
            targetName: targetName,
            parameterName: targetName,
            value: assignment.value,
            unit: assignment.unit
        )
    }

    func scopedTargetName(_ scope: [String], componentName: String) -> String {
        (scope + [componentName]).joined(separator: "/")
    }

    func primaryParameterName(for type: ComponentType) -> String? {
        switch type {
        case .resistor:
            return "r"
        case .capacitor:
            return "c"
        case .inductor:
            return "l"
        case .voltageSource:
            return "v"
        case .currentSource:
            return "i"
        case .vcvs:
            return "e"
        case .vccs:
            return "g"
        case .cccs:
            return "f"
        case .ccvs:
            return "h"
        default:
            return nil
        }
    }

    func sameIdentifier(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    func boolHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> Bool? {
        guard case .boolean(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

    func fallbackUUID(_ index: Int) -> UUID {
        let suffix = UInt64(bitPattern: Int64(index)) & 0x0000_FFFF_FFFF_FFFF
        return UUID(uuid: (
            0x10, 0x00, 0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            UInt8((suffix >> 40) & 0xFF),
            UInt8((suffix >> 32) & 0xFF),
            UInt8((suffix >> 24) & 0xFF),
            UInt8((suffix >> 16) & 0xFF),
            UInt8((suffix >> 8) & 0xFF),
            UInt8(suffix & 0xFF)
        ))
    }

    func stringHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep
    ) -> String? {
        guard case .text(let value) = step.parameterHints[key] else {
            return nil
        }
        return value
    }

    func numberHint(
        _ key: String,
        step: XcircuiteCandidatePlanStep,
        defaultValue: Double
    ) throws -> Double {
        guard let value = step.parameterHints[key] else {
            return defaultValue
        }
        guard case .scalar(let number) = value, number.isFinite else {
            throw XcircuiteCandidatePlanExecutionError.invalidHint(
                stepID: step.stepID,
                key: key,
                expected: "finite number"
            )
        }
        return number
    }
}
