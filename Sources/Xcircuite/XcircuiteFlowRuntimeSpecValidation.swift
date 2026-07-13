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
            try spec.validateTechnologyByCornerInput(toolchainProfile: toolchainProfile)
            try spec.validateBackendSelection()
        case .mockPEX(let spec):
            try spec.validateLayoutInputs()
            try spec.validateSourceNetlistInputs()
            try spec.validateTechnologyInput(toolchainProfile: toolchainProfile)
            try spec.validateTechnologyByCornerInput(toolchainProfile: toolchainProfile)
        case .postLayoutComparison(let spec):
            try spec.validatePreLayoutWaveformInputs()
            try spec.validatePostLayoutWaveformInputs()
        case .rtlVerification(let spec):
            try validateInput(spec.rtlInput, stageID: spec.stageID, field: "rtlInput")
            for (index, input) in spec.additionalRTLInputs.enumerated() {
                try validateInput(input, stageID: spec.stageID, field: "additionalRTLInputs[\(index)]")
            }
            if let referenceInput = spec.referenceInput {
                try validateInput(referenceInput, stageID: spec.stageID, field: "referenceInput")
            }
            for (index, input) in spec.additionalReferenceInputs.enumerated() {
                try validateInput(input, stageID: spec.stageID, field: "additionalReferenceInputs[\(index)]")
            }
            if let constraintsInput = spec.constraintsInput {
                try validateInput(constraintsInput, stageID: spec.stageID, field: "constraintsInput")
            }
            if let qualificationInput = spec.qualificationInput {
                try validateInput(qualificationInput, stageID: spec.stageID, field: "qualificationInput")
            }
            guard !spec.topModuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "topModuleName"
                )
            }
            guard spec.stageID == spec.analysis.stageID else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "stageID matching analysis.stageID (\(spec.analysis.stageID))"
                )
            }
        case .logicSynthesis(let spec):
            guard !spec.requestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "requestPath"
                )
            }
        case .logicEquivalence(let spec):
            guard !spec.requestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "requestPath"
                )
            }
        case .logicQualification(let spec):
            guard !spec.reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "reportPath"
                )
            }
            if let processEvidencePath = spec.processEvidencePath,
               processEvidencePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "processEvidencePath"
                )
            }
            if let releaseApprovalPath = spec.releaseApprovalPath,
               releaseApprovalPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "releaseApprovalPath"
                )
            }
        case .dft(let spec):
            guard !spec.requestPath.isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "requestPath"
                )
            }
            let qualificationPaths = [
                spec.qualificationCorpusPath,
                spec.qualificationObservationsPath,
            ]
            if qualificationPaths.contains(where: { $0 != nil }) {
                guard let corpusPath = spec.qualificationCorpusPath,
                      !corpusPath.isEmpty else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "qualificationCorpusPath"
                    )
                }
                guard let observationsPath = spec.qualificationObservationsPath,
                      !observationsPath.isEmpty else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "qualificationObservationsPath"
                    )
                }
                if let evidencePath = spec.qualificationEvidencePath,
                   evidencePath.isEmpty {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "qualificationEvidencePath"
                    )
                }
                guard spec.releaseResultPath == nil,
                      spec.releaseDownstreamEvidencePath == nil,
                      spec.releaseApprovalPath == nil else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "qualification and release inputs are mutually exclusive"
                    )
                }
            } else if spec.qualificationEvidencePath != nil {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "qualificationCorpusPath"
                )
            } else if spec.releaseResultPath != nil {
                guard let downstreamEvidencePath = spec.releaseDownstreamEvidencePath,
                      !downstreamEvidencePath.isEmpty else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "releaseDownstreamEvidencePath"
                    )
                }
                guard !spec.releaseResultPath!.isEmpty else {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "releaseResultPath"
                    )
                }
                if let approvalPath = spec.releaseApprovalPath, approvalPath.isEmpty {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "releaseApprovalPath"
                    )
                }
            } else if spec.releaseDownstreamEvidencePath != nil || spec.releaseApprovalPath != nil {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "releaseResultPath"
                )
            }
        case .physicalReview(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            guard !spec.decisionScope.isEmpty,
                  Set(spec.decisionScope).count == spec.decisionScope.count else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "decisionScope"
                )
            }
        case .pdkDiscovery(let spec):
            guard !spec.searchRoots.isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "searchRoots"
                )
            }
        case .pdkValidation(let spec):
            return try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
        case .pdkCorpus(let spec):
            try validateInput(spec.suiteInput, stageID: spec.stageID, field: "suiteInput")
            try validateInput(spec.rootInput, stageID: spec.stageID, field: "rootInput")
        case .pdkStandardView(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            if let externalProcess = spec.externalProcess {
                try externalProcess.validate()
            }
            guard !spec.assetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "assetID"
                )
            }
        case .pdkRuleDeck(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            if let externalProcess = spec.externalProcess {
                try externalProcess.validate()
            }
            guard !spec.assetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "assetID"
                )
            }
        case .pdkOracle(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            try validateInput(spec.oracleInput, stageID: spec.stageID, field: "oracleInput")
        case .pdkQualification(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            try validateInput(spec.corpusInput, stageID: spec.stageID, field: "corpusInput")
            try validateInput(spec.oracleInput, stageID: spec.stageID, field: "oracleInput")
        case .releaseQualification(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .releaseSignoff(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .releaseTapeout(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .releaseProfile(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .electricalStandardLayoutImport(let spec):
            try validateInput(spec.layoutInput, stageID: spec.stageID, field: "layoutInput")
            try validateInput(spec.technologyInput, stageID: spec.stageID, field: "technologyInput")
            if let connectivityInput = spec.connectivityInput {
                try validateInput(connectivityInput, stageID: spec.stageID, field: "connectivityInput")
            }
            guard [.gds, .oasis, .def].contains(spec.layoutFormat) else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "layoutFormat must be gds, oasis or def"
                )
            }
            guard spec.technologyFormat == .lef || spec.technologyFormat == .json else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "technologyFormat must be lef or json"
                )
            }
            if spec.connectivityInput != nil, spec.connectivityFormat != .def {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "connectivityFormat must be def"
                )
            }
        case .electricalSignoff(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
            guard !spec.axes.isEmpty,
                  spec.axes.allSatisfy({ $0 != .aggregate }),
                  Set(spec.axes).count == spec.axes.count else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "axes must be unique and cannot contain aggregate"
                )
            }
        case .electricalSignoffQualification(let spec):
            try validateRequestPath(spec.specPath, stageID: spec.stageID)
            if let oraclePath = spec.oraclePath,
               oraclePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "oraclePath"
                )
            }
            guard spec.qualificationScope.isComplete else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "qualificationScope"
                )
            }
        case .electricalSignoffReleaseGate(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
            try validateInput(spec.runResultInput, stageID: spec.stageID, field: "runResultInput")
            try validateInput(spec.qualificationSpecInput, stageID: spec.stageID, field: "qualificationSpecInput")
            try validateInput(spec.qualificationReportInput, stageID: spec.stageID, field: "qualificationReportInput")
            try validateInput(spec.policyInput, stageID: spec.stageID, field: "policyInput")
        case .electricalRepairRevision(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .layoutCommand, .coreSpiceSimulation:
            return
        }
    }

    func validateInput(
        _ input: XcircuiteFlowInputReference,
        stageID: String,
        field: String
    ) throws {
        if case .path(let path) = input,
           path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: field
            )
        }
    }

    func validateRequestPath(_ path: String, stageID: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "requestPath")
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
        case .rtlVerification(let spec):
            spec.tool
        case .logicSynthesis(let spec):
            spec.tool
        case .logicEquivalence(let spec):
            spec.tool
        case .logicQualification(let spec):
            spec.tool
        case .dft(let spec):
            spec.tool
        case .physicalReview(let spec):
            spec.tool
        case .pdkDiscovery(let spec):
            spec.tool
        case .pdkValidation(let spec):
            spec.tool
        case .pdkCorpus(let spec):
            spec.tool
        case .pdkStandardView(let spec):
            spec.tool
        case .pdkRuleDeck(let spec):
            spec.tool
        case .pdkOracle(let spec):
            spec.tool
        case .pdkQualification(let spec):
            spec.tool
        case .releaseQualification(let spec):
            spec.tool
        case .releaseSignoff(let spec):
            spec.tool
        case .releaseTapeout(let spec):
            spec.tool
        case .releaseProfile(let spec):
            spec.tool
        case .electricalStandardLayoutImport(let spec):
            spec.tool
        case .electricalSignoff(let spec):
            spec.tool
        case .electricalSignoffQualification(let spec):
            spec.tool
        case .electricalSignoffReleaseGate(let spec):
            spec.tool
        case .electricalRepairRevision(let spec):
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

    func validateTechnologyByCornerInput(
        toolchainProfile: XcircuiteFlowToolchainProfile?
    ) throws {
        var values = toolchainProfile?.pexTechnologyByCorner ?? [:]
        for (cornerID, technology) in technologyByCorner {
            values[cornerID] = technology
        }
        let cornerIDs = Set(corners.map { $0.id.value })
        for cornerID in values.keys.sorted() {
            guard !cornerID.isEmpty,
                  cornerID == cornerID.trimmingCharacters(in: .whitespacesAndNewlines),
                  cornerIDs.contains(cornerID) else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: stageID,
                    field: "technologyByCorner[\(cornerID)] must match a declared corner ID"
                )
            }
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

    func validateTechnologyByCornerInput(
        toolchainProfile: XcircuiteFlowToolchainProfile?
    ) throws {
        var values = toolchainProfile?.pexTechnologyByCorner ?? [:]
        for (cornerID, technology) in technologyByCorner {
            values[cornerID] = technology
        }
        let cornerIDs = Set(corners.map { $0.id.value })
        for cornerID in values.keys.sorted() {
            guard !cornerID.isEmpty,
                  cornerID == cornerID.trimmingCharacters(in: .whitespacesAndNewlines),
                  cornerIDs.contains(cornerID) else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: stageID,
                    field: "technologyByCorner[\(cornerID)] must match a declared corner ID"
                )
            }
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
