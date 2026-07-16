import CircuiteFoundation

public extension XcircuiteFlowRuntimeSpec {
    func attachingQualificationRecord(
        _ reference: ArtifactReference,
        toStageID stageID: String
    ) throws -> XcircuiteFlowRuntimeSpec {
        try validate()
        guard executors.contains(where: { $0.stageID == stageID }) else {
            throw XcircuiteFlowRuntimeSpecError.missingRuntimeExecutorForRunStage(stageID)
        }
        let updatedExecutors = executors.map { executor in
            guard executor.stageID == stageID else {
                return executor
            }
            return executor.attachingQualificationRecord(reference)
        }
        return XcircuiteFlowRuntimeSpec(
            schemaVersion: schemaVersion,
            toolchainProfile: toolchainProfile,
            executors: updatedExecutors
        )
    }
}

public extension XcircuiteFlowStageExecutorSpec {
    var stageID: String {
        switch self {
        case .layoutCommand(let spec): spec.stageID
        case .nativeDRC(let spec): spec.stageID
        case .nativeLVS(let spec): spec.stageID
        case .pex(let spec): spec.stageID
        case .coreSpiceSimulation(let spec): spec.stageID
        case .postLayoutComparison(let spec): spec.stageID
        case .rtlVerification(let spec): spec.stageID
        case .logicSynthesis(let spec): spec.stageID
        case .logicEquivalence(let spec): spec.stageID
        case .logicEvidenceValidation(let spec): spec.stageID
        case .dft(let spec): spec.stageID
        case .physicalReview(let spec): spec.stageID
        case .pdkDiscovery(let spec): spec.stageID
        case .pdkValidation(let spec): spec.stageID
        case .pdkCorpus(let spec): spec.stageID
        case .pdkStandardView(let spec): spec.stageID
        case .pdkRuleDeck(let spec): spec.stageID
        case .pdkOracle(let spec): spec.stageID
        case .releaseAuthorization(let spec): spec.stageID
        case .releaseSignoff(let spec): spec.stageID
        case .releaseTapeout(let spec): spec.stageID
        case .electricalStandardLayoutImport(let spec): spec.stageID
        case .electricalSignoff(let spec): spec.stageID
        case .electricalSignoffCorpus(let spec): spec.stageID
        case .electricalRepairRevision(let spec): spec.stageID
        }
    }

    func attachingQualificationRecord(_ reference: ArtifactReference) -> Self {
        switch self {
        case .layoutCommand(var spec): spec.tool.qualificationRecord = reference; return .layoutCommand(spec)
        case .nativeDRC(var spec): spec.tool.qualificationRecord = reference; return .nativeDRC(spec)
        case .nativeLVS(var spec): spec.tool.qualificationRecord = reference; return .nativeLVS(spec)
        case .pex(var spec): spec.tool.qualificationRecord = reference; return .pex(spec)
        case .coreSpiceSimulation(var spec): spec.tool.qualificationRecord = reference; return .coreSpiceSimulation(spec)
        case .postLayoutComparison(var spec): spec.tool.qualificationRecord = reference; return .postLayoutComparison(spec)
        case .rtlVerification(var spec): spec.tool.qualificationRecord = reference; return .rtlVerification(spec)
        case .logicSynthesis(var spec): spec.tool.qualificationRecord = reference; return .logicSynthesis(spec)
        case .logicEquivalence(var spec): spec.tool.qualificationRecord = reference; return .logicEquivalence(spec)
        case .logicEvidenceValidation(var spec): spec.tool.qualificationRecord = reference; return .logicEvidenceValidation(spec)
        case .dft(var spec): spec.tool.qualificationRecord = reference; return .dft(spec)
        case .physicalReview(var spec): spec.tool.qualificationRecord = reference; return .physicalReview(spec)
        case .pdkDiscovery(var spec): spec.tool.qualificationRecord = reference; return .pdkDiscovery(spec)
        case .pdkValidation(var spec): spec.tool.qualificationRecord = reference; return .pdkValidation(spec)
        case .pdkCorpus(var spec): spec.tool.qualificationRecord = reference; return .pdkCorpus(spec)
        case .pdkStandardView(var spec): spec.tool.qualificationRecord = reference; return .pdkStandardView(spec)
        case .pdkRuleDeck(var spec): spec.tool.qualificationRecord = reference; return .pdkRuleDeck(spec)
        case .pdkOracle(var spec): spec.tool.qualificationRecord = reference; return .pdkOracle(spec)
        case .releaseAuthorization(var spec): spec.tool.qualificationRecord = reference; return .releaseAuthorization(spec)
        case .releaseSignoff(var spec): spec.tool.qualificationRecord = reference; return .releaseSignoff(spec)
        case .releaseTapeout(var spec): spec.tool.qualificationRecord = reference; return .releaseTapeout(spec)
        case .electricalStandardLayoutImport(var spec): spec.tool.qualificationRecord = reference; return .electricalStandardLayoutImport(spec)
        case .electricalSignoff(var spec): spec.tool.qualificationRecord = reference; return .electricalSignoff(spec)
        case .electricalSignoffCorpus(var spec): spec.tool.qualificationRecord = reference; return .electricalSignoffCorpus(spec)
        case .electricalRepairRevision(var spec): spec.tool.qualificationRecord = reference; return .electricalRepairRevision(spec)
        }
    }
}
