import CircuiteFoundation
import Foundation
import ToolQualification
import DesignFlowKernel

public extension XcircuiteFlowRuntimeSpec {
    func validate(
        projectRoot: URL? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
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

        let validator = FlowIdentifierValidator()
        var stageIDs: Set<String> = []
        for executor in executors {
            try validator.validate(executor.stageID, kind: .stageID)
            try executor.validateRequiredInputs(toolchainProfile: toolchainProfile)
            try executor.validateToolSpec()
            guard stageIDs.insert(executor.stageID).inserted else {
                throw XcircuiteFlowRuntimeSpecError.duplicateExecutorStageID(executor.stageID)
            }
        }
        _ = try makeUnqualifiedToolBindings()
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
            try spec.validateExtractionInputs(toolchainProfile: toolchainProfile)
        case .pex(let spec):
            try spec.validateLayoutInputs()
            try spec.validateSourceNetlistInputs()
            try spec.validateTechnologyInput(toolchainProfile: toolchainProfile)
            try spec.validateTechnologyByCornerInput(toolchainProfile: toolchainProfile)
            try spec.validateBackendSelection()
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
            if let evidenceInput = spec.evidenceInput {
                try validateInput(evidenceInput, stageID: spec.stageID, field: "evidenceInput")
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
            if let oracleTool = spec.oracleTool {
                try validateOracleTool(
                    oracleTool,
                    stageID: spec.stageID
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
        case .logicEvidenceValidation(let spec):
            guard !spec.reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "reportPath"
                )
            }
        case .dftExecution(let spec):
            guard !spec.requestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "requestPath"
                )
            }
        case .dftQualification(let spec):
            try validateInput(spec.corpusInput, stageID: spec.stageID, field: "corpusInput")
            try validateInput(spec.observationsInput, stageID: spec.stageID, field: "observationsInput")
            if let buildInput = spec.processQualificationEvidenceBuildInput {
                try validateInput(
                    buildInput,
                    stageID: spec.stageID,
                    field: "processQualificationEvidenceBuildInput"
                )
            }
        case .physicalReview(let spec):
            try validateInput(spec.manifestInput, stageID: spec.stageID, field: "manifestInput")
            guard !spec.reviewScope.isEmpty,
                  Set(spec.reviewScope).count == spec.reviewScope.count else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "reviewScope"
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
        case .releaseAuthorization(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .releaseSignoff(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .releaseTapeout(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .electricalStandardLayoutImport(let spec):
            try validateElectricalInput(spec.layoutInput, stageID: spec.stageID, field: "layoutInput")
            try validateElectricalInput(spec.technologyInput, stageID: spec.stageID, field: "technologyInput")
            if let technologyLayerMappingInput = spec.technologyLayerMappingInput {
                try validateElectricalInput(
                    technologyLayerMappingInput,
                    stageID: spec.stageID,
                    field: "technologyLayerMappingInput"
                )
            }
            if spec.technologyFormat == .lef, spec.technologyLayerMappingInput == nil {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "technologyLayerMappingInput is required for LEF technology"
                )
            }
            if let connectivityInput = spec.connectivityInput {
                try validateElectricalInput(connectivityInput, stageID: spec.stageID, field: "connectivityInput")
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
        case .electricalSignoffCorpus(let spec):
            try validateRequestPath(spec.specPath, stageID: spec.stageID)
            if let oraclePath = spec.oraclePath,
               oraclePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "oraclePath"
                )
            }
            if spec.oraclePath != nil, spec.oracleProcess != nil {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "oraclePath and oracleProcess are mutually exclusive"
                )
            }
            try spec.oracleProcess?.validate()
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

    func validateReleaseGateInput(
        _ input: XcircuiteFlowInputReference,
        stageID: String,
        field: String
    ) throws {
        switch input {
        case .artifact:
            break
        case .stageArtifact(let selector):
            guard selector.artifactID != nil else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: stageID,
                    field: "\(field) must select an artifactID"
                )
            }
        case .path, .stageRawArtifact:
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "\(field) must be a digest-bound artifact or stageArtifact reference"
            )
        }
    }

    func validateElectricalInput(
        _ input: XcircuiteFlowInputReference,
        stageID: String,
        field: String
    ) throws {
        switch input {
        case .artifact:
            break
        case .stageArtifact(let selector):
            guard selector.artifactID != nil else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: stageID,
                    field: "\(field) must select an artifactID"
                )
            }
        case .path, .stageRawArtifact:
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "\(field) must be a digest-bound artifact or stageArtifact reference"
            )
        }
    }

    func validateRequestPath(_ path: String, stageID: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "requestPath")
        }
    }

    func validateToolSpec() throws {
        try validateQualificationRecord(toolSpec.qualificationRecord, stageID: stageID)
        if case .rtlVerification(let spec) = self,
           let oracleTool = spec.oracleTool {
            try validateOracleTool(oracleTool, stageID: spec.stageID)
        }
    }

    func validateOracleTool(
        _ oracleTool: RTLVerificationOracleToolSpec,
        stageID: String,
    ) throws {
        try FlowIdentifierValidator().validate(oracleTool.toolID, kind: .toolID)
        guard !oracleTool.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "oracleTool.executablePath"
            )
        }
        guard !oracleTool.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "oracleTool.version"
            )
        }
        guard oracleTool.timeoutSeconds.isFinite, oracleTool.timeoutSeconds > 0 else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "oracleTool.timeoutSeconds"
            )
        }
        try validateQualificationRecord(
            oracleTool.tool.qualificationRecord,
            stageID: "\(stageID).oracle"
        )
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
        case .logicEvidenceValidation(let spec):
            spec.tool
        case .dftExecution(let spec):
            spec.tool
        case .dftQualification(let spec):
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
        case .releaseAuthorization(let spec):
            spec.tool
        case .releaseSignoff(let spec):
            spec.tool
        case .releaseTapeout(let spec):
            spec.tool
        case .electricalStandardLayoutImport(let spec):
            spec.tool
        case .electricalSignoff(let spec):
            spec.tool
        case .electricalSignoffCorpus(let spec):
            spec.tool
        case .electricalRepairRevision(let spec):
            spec.tool
        }
    }

    func validateQualificationRecord(
        _ record: ArtifactReference?,
        stageID: String
    ) throws {
        guard let record else { return }
        guard record.format == .json,
              record.locator.location.storage == .workspaceRelative,
              record.producer != nil else {
            throw XcircuiteFlowRuntimeSpecError.invalidQualificationRecord(
                toolID: stageID,
                reason: "record must be a producer-bound workspace-relative JSON artifact"
            )
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

    func validateExtractionInputs(toolchainProfile: XcircuiteFlowToolchainProfile?) throws {
        let profileFields = presentFields([
            ("extractionProfilePath", extractionProfilePath != nil),
            ("extractionProfileInput", extractionProfileInput != nil),
        ])
        guard profileFields.count <= 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: profileFields
            )
        }
        let deckFields = presentFields([
            ("extractionDeckPath", extractionDeckPath != nil),
            ("extractionDeckInput", extractionDeckInput != nil),
        ])
        guard deckFields.count <= 1 else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: deckFields
            )
        }
        guard layoutGDSPath != nil || layoutGDSInput != nil else {
            return
        }
        guard resolvedExtractionProfileInput(toolchainProfile: toolchainProfile) != nil else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "extractionProfilePath/extractionProfileInput or toolchainProfile.lvsExtractionArtifacts.profileInput"
            )
        }
        guard resolvedExtractionDeckInput(toolchainProfile: toolchainProfile) != nil else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "extractionDeckPath/extractionDeckInput or toolchainProfile.lvsExtractionArtifacts.deckInput"
            )
        }
        guard let profileID = resolvedProcessProfileID(toolchainProfile: toolchainProfile),
              !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "processProfileID or toolchainProfile.lvsExtractionArtifacts.processProfileID"
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
        try FlowIdentifierValidator().validate(
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
