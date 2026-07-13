import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func actionDomainPath(runID: String) -> String {
        "\(XcircuitePackage.directoryName)/runs/\(runID)/\(XcircuitePlanningArtifactStore.actionDomainRelativePath)"
    }

    func identifier(_ rawValue: String) throws -> String {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowedScalars.contains(scalar)
                ? String(scalar)
                : "-"
        }
        let collapsed = sanitizedScalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(collapsed.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        let value = trimmed.isEmpty ? "planning-id" : trimmed
        try XcircuiteIdentifierValidator().validate(value, kind: .artifactID)
        return value
    }

    func insertOptional(
        _ value: String?,
        key: String,
        into dictionary: inout [String: XcircuiteJSONValue]
    ) {
        guard let value else {
            return
        }
        dictionary[key] = .string(value)
    }

    func insertOptional(
        _ value: Double?,
        key: String,
        into dictionary: inout [String: XcircuiteJSONValue]
    ) {
        guard let value else {
            return
        }
        dictionary[key] = .number(value)
    }

    func insertOptional(
        _ value: Int?,
        key: String,
        into dictionary: inout [String: XcircuiteJSONValue]
    ) {
        guard let value else {
            return
        }
        dictionary[key] = .number(Double(value))
    }
}
