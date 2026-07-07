import Foundation
import ToolQualification
import XcircuitePackage

public extension XcircuiteFlowRuntimeSpec {
    func validate(
        projectRoot: URL? = nil,
        requireCompleteToolEvidence: Bool = true
    ) throws {
        guard schemaVersion == 1 else {
            throw XcircuiteFlowRuntimeSpecError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !executors.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.emptyExecutorList
        }
        if let toolchainProfile {
            try XcircuiteFlowToolchainProfileReadinessValidator().validate(
                toolchainProfile,
                projectRoot: projectRoot
            )
        }

        let validator = XcircuiteIdentifierValidator()
        var stageIDs: Set<String> = []
        for executor in executors {
            try validator.validate(executor.stageID, kind: .stageID)
            try executor.validateRequiredInputs(toolchainProfile: toolchainProfile)
            try executor.validateToolSpec(requireCompleteEvidence: requireCompleteToolEvidence)
            guard stageIDs.insert(executor.stageID).inserted else {
                throw XcircuiteFlowRuntimeSpecError.duplicateExecutorStageID(executor.stageID)
            }
        }
        _ = try makeToolBindings()
    }
}

private extension XcircuiteFlowStageExecutorSpec {
    func validateRequiredInputs(toolchainProfile: XcircuiteFlowToolchainProfile?) throws {
        switch self {
        case .nativeDRC(let spec):
            if spec.layoutPath == nil && spec.layoutInput == nil {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "layoutPath or layoutInput"
                )
            }
        case .nativeLVS(let spec):
            try spec.validateLayoutInputs()
            try spec.validateSchematicInputs()
            try spec.validateTechnologyInputs()
        case .pex(let spec):
            try spec.validateLayoutInputs()
            try spec.validateSourceNetlistInputs()
            try spec.validateTechnologyInput(toolchainProfile: toolchainProfile)
            try spec.validateBackendSelection()
        case .mockPEX(let spec):
            try spec.validateLayoutInputs()
            try spec.validateSourceNetlistInputs()
            try spec.validateTechnologyInput(toolchainProfile: toolchainProfile)
        case .postLayoutComparison(let spec):
            try spec.validatePreLayoutWaveformInputs()
            try spec.validatePostLayoutWaveformInputs()
        case .layoutCommand, .coreSpiceSimulation:
            return
        }
    }

    func validateToolSpec(requireCompleteEvidence: Bool) throws {
        let toolSpec = toolSpec
        if case .mockPEX(let spec) = self,
           spec.tool.qualificationLevel != .unknown {
            throw XcircuiteFlowRuntimeSpecError.mockExecutorCannotDeclareQualifiedTool(
                stageID: spec.stageID,
                level: spec.tool.qualificationLevel.rawValue
            )
        }
        for evidence in toolSpec.evidence {
            try evidence.validateForRuntimeToolSpec(stageID: stageID)
        }

        guard requireCompleteEvidence else {
            return
        }

        for requiredKind in requiredQualifiedEvidenceKinds(for: toolSpec.qualificationLevel) {
            guard toolSpec.evidence.contains(where: { evidence in
                evidence.kind == requiredKind && evidence.hasPassingQualificationSupport
            }) else {
                throw XcircuiteFlowRuntimeSpecError.missingToolQualificationEvidence(
                    stageID: stageID,
                    kind: requiredKind.rawValue,
                    level: toolSpec.qualificationLevel.rawValue
                )
            }
        }
    }

    var toolSpec: XcircuiteFlowToolSpec {
        switch self {
        case .layoutCommand(let spec):
            spec.tool
        case .nativeDRC(let spec):
            spec.tool
        case .nativeLVS(let spec):
            spec.tool
        case .pex(let spec):
            spec.tool
        case .mockPEX(let spec):
            spec.tool
        case .coreSpiceSimulation(let spec):
            spec.tool
        case .postLayoutComparison(let spec):
            spec.tool
        }
    }

    func requiredQualifiedEvidenceKinds(for level: ToolQualificationLevel) -> [ToolEvidenceKind] {
        switch level {
        case .unknown:
            []
        case .smokeChecked:
            [.smoke]
        case .corpusChecked:
            [.corpus]
        case .oracleChecked:
            [.corpus, .oracle]
        case .productionEligible:
            [.corpus, .oracle, .productionApproval]
        }
    }
}

private extension XcircuiteFlowStageExecutorSpec.PostLayoutComparison {
    func validatePreLayoutWaveformInputs() throws {
        let fields = presentFields([
            ("preLayoutWaveformPath", preLayoutWaveformPath != nil),
            ("preLayoutWaveformInput", preLayoutWaveformInput != nil),
        ])
        guard !fields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "preLayoutWaveformPath or preLayoutWaveformInput"
            )
        }
        guard fields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: fields
            )
        }
    }

    func validatePostLayoutWaveformInputs() throws {
        let fields = presentFields([
            ("postLayoutWaveformPath", postLayoutWaveformPath != nil),
            ("postLayoutWaveformInput", postLayoutWaveformInput != nil),
        ])
        guard !fields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "postLayoutWaveformPath or postLayoutWaveformInput"
            )
        }
        guard fields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: fields
            )
        }
    }

    func presentFields(_ fields: [(String, Bool)]) -> [String] {
        fields.compactMap { field in
            field.1 ? field.0 : nil
        }
    }
}

private extension XcircuiteFlowStageExecutorSpec.NativeLVS {
    func validateLayoutInputs() throws {
        let layoutFields = presentFields([
            ("layoutNetlistPath", layoutNetlistPath != nil),
            ("layoutNetlistInput", layoutNetlistInput != nil),
            ("layoutGDSPath", layoutGDSPath != nil),
            ("layoutGDSInput", layoutGDSInput != nil),
        ])
        guard !layoutFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "layoutNetlistPath/layoutNetlistInput or layoutGDSPath/layoutGDSInput"
            )
        }
        guard layoutFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: layoutFields
            )
        }
    }

    func validateSchematicInputs() throws {
        let schematicFields = presentFields([
            ("schematicNetlistPath", schematicNetlistPath != nil),
            ("schematicNetlistInput", schematicNetlistInput != nil),
        ])
        guard !schematicFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "schematicNetlistPath or schematicNetlistInput"
            )
        }
        guard schematicFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: schematicFields
            )
        }
    }

    func validateTechnologyInputs() throws {
        let technologyFields = presentFields([
            ("technologyPath", technologyPath != nil),
            ("technologyInput", technologyInput != nil),
        ])
        guard technologyFields.count <= 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: technologyFields
            )
        }
    }

    func presentFields(_ fields: [(String, Bool)]) -> [String] {
        fields.compactMap { field in
            field.1 ? field.0 : nil
        }
    }
}

private extension XcircuiteFlowStageExecutorSpec.MockPEX {
    func validateLayoutInputs() throws {
        let layoutFields = presentFields([
            ("layoutPath", layoutPath != nil),
            ("layoutInput", layoutInput != nil),
        ])
        guard !layoutFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "layoutPath or layoutInput"
            )
        }
        guard layoutFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: layoutFields
            )
        }
    }

    func validateSourceNetlistInputs() throws {
        let sourceNetlistFields = presentFields([
            ("sourceNetlistPath", sourceNetlistPath != nil),
            ("sourceNetlistInput", sourceNetlistInput != nil),
        ])
        guard !sourceNetlistFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "sourceNetlistPath or sourceNetlistInput"
            )
        }
        guard sourceNetlistFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: sourceNetlistFields
            )
        }
    }

    func validateTechnologyInput(toolchainProfile: XcircuiteFlowToolchainProfile?) throws {
        guard technology != nil || toolchainProfile?.pexTechnology != nil else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "technology or toolchainProfile.pexTechnology"
            )
        }
    }

    func presentFields(_ fields: [(String, Bool)]) -> [String] {
        fields.compactMap { field in
            field.1 ? field.0 : nil
        }
    }
}

private extension XcircuiteFlowStageExecutorSpec.PEX {
    func validateLayoutInputs() throws {
        let layoutFields = presentFields([
            ("layoutPath", layoutPath != nil),
            ("layoutInput", layoutInput != nil),
        ])
        guard !layoutFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "layoutPath or layoutInput"
            )
        }
        guard layoutFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: layoutFields
            )
        }
    }

    func validateSourceNetlistInputs() throws {
        let sourceNetlistFields = presentFields([
            ("sourceNetlistPath", sourceNetlistPath != nil),
            ("sourceNetlistInput", sourceNetlistInput != nil),
        ])
        guard !sourceNetlistFields.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "sourceNetlistPath or sourceNetlistInput"
            )
        }
        guard sourceNetlistFields.count == 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: sourceNetlistFields
            )
        }
    }

    func validateTechnologyInput(toolchainProfile: XcircuiteFlowToolchainProfile?) throws {
        guard technology != nil || toolchainProfile?.pexTechnology != nil else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "technology or toolchainProfile.pexTechnology"
            )
        }
    }

    func validateBackendSelection() throws {
        let backendID = backendSelection.backendID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !backendID.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "backendSelection.backendID"
            )
        }
        if backendID.lowercased().hasPrefix("mock") {
            throw XcircuiteFlowRuntimeSpecError.mockPEXBackendNotAllowed(
                stageID: stageID,
                backendID: backendID
            )
        }
        try XcircuiteIdentifierValidator().validate(
            SignoffToolDescriptors.pexToolID(backendID: backendID),
            kind: .toolID
        )
    }

    func presentFields(_ fields: [(String, Bool)]) -> [String] {
        fields.compactMap { field in
            field.1 ? field.0 : nil
        }
    }
}
