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
        case .logicElaboration(let spec):
            try validateInput(spec.sourceInput, stageID: spec.stageID, field: "sourceInput")
            guard !spec.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "topDesignName"
                )
            }
        case .logicLowering(let spec):
            try validateLogicInputMode(
                requestInput: spec.requestInput,
                designInput: spec.designInput,
                topDesignName: spec.topDesignName,
                stageID: spec.stageID
            )
        case .logicSimulation(let spec):
            try validateLogicInputMode(
                requestInput: spec.requestInput,
                designInput: spec.designInput,
                topDesignName: spec.topDesignName,
                stageID: spec.stageID
            )
            if let stimulusInput = spec.stimulusInput {
                try validateInput(stimulusInput, stageID: spec.stageID, field: "stimulusInput")
            }
            if spec.requestInput == nil {
                try validateInput(
                    try requiredRuntimeInput(spec.pdkInput, stageID: spec.stageID, field: "pdkInput"),
                    stageID: spec.stageID,
                    field: "pdkInput"
                )
            }
        case .powerIntent(let spec):
            try validateInput(spec.sourceInput, stageID: spec.stageID, field: "sourceInput")
            try validateInput(spec.designInput, stageID: spec.stageID, field: "designInput")
            try validateInput(spec.pdkInput, stageID: spec.stageID, field: "pdkInput")
            guard !spec.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "topDesignName"
                )
            }
        case .layoutCommand(let spec):
            try validateRequestPath(spec.requestPath, stageID: spec.stageID)
        case .nativeDRC(let spec):
            let layoutFields = [
                ("layoutPath", spec.layoutPath != nil),
                ("layoutInput", spec.layoutInput != nil),
            ].compactMap { field, isPresent in
                isPresent ? field : nil
            }
            guard layoutFields.count == 1 else {
                if layoutFields.isEmpty {
                    throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                        stageID: spec.stageID,
                        field: "layoutPath or layoutInput"
                    )
                }
                throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                    stageID: spec.stageID,
                    fields: layoutFields
                )
            }
            if let layoutPath = spec.layoutPath,
               layoutPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "layoutPath"
                )
            }
            if let layoutInput = spec.layoutInput {
                try validateInput(layoutInput, stageID: spec.stageID, field: "layoutInput")
            }
            guard !spec.topCell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "topCell"
                )
            }
            if spec.technologyPath != nil, spec.technologyInput != nil {
                throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                    stageID: spec.stageID,
                    fields: ["technologyPath", "technologyInput"]
                )
            }
            if let technologyPath = spec.technologyPath,
               technologyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "technologyPath"
                )
            }
            if let technologyInput = spec.technologyInput {
                try validateInput(technologyInput, stageID: spec.stageID, field: "technologyInput")
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
        case .coreSpiceSimulation(let spec):
            try validateInput(spec.netlistInput, stageID: spec.stageID, field: "netlistInput")
        case .rtlVerification(let spec):
            try validateInput(spec.rtlInput, stageID: spec.stageID, field: "rtlInput")
            try validateInput(spec.pdkInput, stageID: spec.stageID, field: "pdkInput")
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
        case .dftOracleCorrelation(let spec):
            try validateInput(spec.corpusInput, stageID: spec.stageID, field: "corpusInput")
            try validateInput(spec.observationsInput, stageID: spec.stageID, field: "observationsInput")
        case .processQualificationEvidenceBuild(let spec):
            try validateInput(spec.buildRequestInput, stageID: spec.stageID, field: "buildRequestInput")
        case .physicalDesign(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
            if let designInput = spec.designInput {
                try validateInput(designInput, stageID: spec.stageID, field: "designInput")
            }
            if let constraintsInput = spec.constraintsInput {
                try validateInput(constraintsInput, stageID: spec.stageID, field: "constraintsInput")
            }
            if let pdkInput = spec.pdkInput {
                try validateInput(pdkInput, stageID: spec.stageID, field: "pdkInput")
            }
            if let inputLayoutInput = spec.inputLayoutInput {
                try validateInput(inputLayoutInput, stageID: spec.stageID, field: "inputLayoutInput")
            }
            guard !spec.allowedStages.isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "allowedStages"
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
        case .timingSTA(let spec):
            try validateTimingSTAInputs(spec.inputs, stageID: spec.stageID)
        case .timingSignalIntegrity(let spec):
            try validateTimingSignalIntegrityInputs(spec.inputs, stageID: spec.stageID)
        case .pdkDiscovery(let spec):
            guard !spec.searchRoots.isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "searchRoots"
                )
            }
            for (index, input) in spec.searchRoots.enumerated() {
                try validateInput(input, stageID: spec.stageID, field: "searchRoots[\(index)]")
            }
            if let requiredProcessID = spec.requiredProcessID,
               requiredProcessID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                    stageID: spec.stageID,
                    field: "requiredProcessID"
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
        case .releaseEvidenceAssembly(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
        case .releaseAuthorization(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
        case .releaseSignoff(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
        case .releaseTapeout(let spec):
            try validateInput(spec.requestInput, stageID: spec.stageID, field: "requestInput")
            if let geometricXOR = spec.geometricXOR {
                try validateInput(
                    geometricXOR.qualificationInput,
                    stageID: spec.stageID,
                    field: "geometricXOR.qualificationInput"
                )
                guard geometricXOR.reportOutput.location.storage == .workspaceRelative,
                      geometricXOR.reportOutput.role == .output,
                      geometricXOR.reportOutput.kind == .report,
                      geometricXOR.reportOutput.format == .json else {
                    throw XcircuiteFlowRuntimeSpecError.invalidExecutorConfiguration(
                        stageID: spec.stageID,
                        reason: "geometricXOR.reportOutput must be a workspace-relative output report in JSON format"
                    )
                }
                guard geometricXOR.timeoutSeconds.isFinite,
                      geometricXOR.timeoutSeconds > 0 else {
                    throw XcircuiteFlowRuntimeSpecError.invalidExecutorConfiguration(
                        stageID: spec.stageID,
                        reason: "geometricXOR.timeoutSeconds must be finite and positive"
                    )
                }
            }
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
        }
    }

    private func requiredRuntimeInput<Value>(
        _ value: Value?,
        stageID: String,
        field: String
    ) throws -> Value {
        guard let value else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: field)
        }
        return value
    }

    func validateTimingSTAInputs(_ inputs: TimingSTAFlowInputs, stageID: String) throws {
        try validateInput(inputs.design, stageID: stageID, field: "inputs.design")
        guard !inputs.libraries.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "inputs.libraries"
            )
        }
        for (index, input) in inputs.libraries.enumerated() {
            try validateInput(input, stageID: stageID, field: "inputs.libraries[\(index)]")
        }
        try validateInput(inputs.constraints, stageID: stageID, field: "inputs.constraints")
        try validateInput(inputs.pdkManifest, stageID: stageID, field: "inputs.pdkManifest")
        if let parasitics = inputs.parasitics {
            try validateInput(parasitics, stageID: stageID, field: "inputs.parasitics")
        }
        try validateTimingIdentity(
            topDesignName: inputs.topDesignName,
            processID: inputs.processID,
            pdkVersion: inputs.pdkVersion,
            pdkDigest: inputs.pdkDigest,
            modeIDs: inputs.modeIDs,
            stageID: stageID
        )
        guard !inputs.cornerIDs.isEmpty, !inputs.analysisKinds.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "inputs.cornerIDs and inputs.analysisKinds"
            )
        }
        if inputs.requiresPostLayoutInputs, inputs.parasitics == nil {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "inputs.parasitics is required for post-layout STA"
            )
        }
    }

    func validateLogicInputMode(
        requestInput: XcircuiteFlowInputReference?,
        designInput: XcircuiteFlowInputReference?,
        topDesignName: String?,
        stageID: String
    ) throws {
        let hasRequest = requestInput != nil
        let hasDirectDesign = designInput != nil || topDesignName != nil
        guard hasRequest || hasDirectDesign else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "requestInput or designInput/topDesignName"
            )
        }
        guard !(hasRequest && hasDirectDesign) else {
            throw XcircuiteFlowRuntimeSpecError.conflictingExecutorInputs(
                stageID: stageID,
                fields: ["requestInput", "designInput/topDesignName"]
            )
        }
        if let requestInput {
            try validateInput(requestInput, stageID: stageID, field: "requestInput")
            return
        }
        guard let designInput,
              let topDesignName,
              !topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "designInput and topDesignName"
            )
        }
        try validateInput(designInput, stageID: stageID, field: "designInput")
    }

    func validateTimingSignalIntegrityInputs(_ inputs: TimingSIFlowInputs, stageID: String) throws {
        try validateInput(inputs.design, stageID: stageID, field: "inputs.design")
        try validateInput(inputs.constraints, stageID: stageID, field: "inputs.constraints")
        try validateInput(inputs.pdkManifest, stageID: stageID, field: "inputs.pdkManifest")
        try validateInput(inputs.parasitics, stageID: stageID, field: "inputs.parasitics")
        try validateTimingIdentity(
            topDesignName: inputs.topDesignName,
            processID: inputs.processID,
            pdkVersion: inputs.pdkVersion,
            pdkDigest: inputs.pdkDigest,
            modeIDs: inputs.modeIDs,
            stageID: stageID
        )
        guard inputs.maxDeltaDelay.isFinite,
              inputs.maxDeltaDelay >= 0,
              inputs.maxNoiseRatio.isFinite,
              inputs.maxNoiseRatio >= 0 else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "inputs.maxDeltaDelay and inputs.maxNoiseRatio"
            )
        }
    }

    func validateTimingIdentity(
        topDesignName: String,
        processID: String,
        pdkVersion: String,
        pdkDigest: String,
        modeIDs: [String],
        stageID: String
    ) throws {
        let requiredValues = [
            ("inputs.topDesignName", topDesignName),
            ("inputs.processID", processID),
            ("inputs.pdkVersion", pdkVersion),
            ("inputs.pdkDigest", pdkDigest),
        ]
        for (field, value) in requiredValues where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: field)
        }
        guard !modeIDs.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(stageID: stageID, field: "inputs.modeIDs")
        }
        do {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: pdkDigest)
        } catch {
            throw XcircuiteFlowRuntimeSpecError.missingExecutorInput(
                stageID: stageID,
                field: "inputs.pdkDigest must be a SHA-256 digest"
            )
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
        case .logicElaboration(let spec):
            spec.tool
        case .logicLowering(let spec):
            spec.tool
        case .logicSimulation(let spec):
            spec.tool
        case .powerIntent(let spec):
            spec.tool
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
        case .dftOracleCorrelation(let spec):
            spec.tool
        case .processQualificationEvidenceBuild(let spec):
            spec.tool
        case .physicalDesign(let spec):
            spec.tool
        case .physicalReview(let spec):
            spec.tool
        case .timingSTA(let spec):
            spec.tool
        case .timingSignalIntegrity(let spec):
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
        case .releaseEvidenceAssembly(let spec):
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
