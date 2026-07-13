import Foundation
import ToolQualification

public extension XcircuiteFlowRuntimeSpec {
    func attachingEvidence(
        _ evidence: ToolEvidence,
        toStageID stageID: String
    ) throws -> XcircuiteFlowRuntimeSpec {
        try validate(requireCompleteToolEvidence: false)
        guard executors.contains(where: { $0.stageID == stageID }) else {
            throw XcircuiteFlowRuntimeSpecError.stageNotFound(stageID)
        }
        try evidence.validateForRuntimeToolSpec(stageID: stageID)
        let updatedExecutors = executors.map { executor in
            guard executor.stageID == stageID else {
                return executor
            }
            return executor.attachingEvidence(evidence)
        }

        return XcircuiteFlowRuntimeSpec(
            schemaVersion: schemaVersion,
            toolchainProfile: toolchainProfile,
            executors: updatedExecutors
        )
    }

    func attachingEvidence(
        from export: XcircuiteFlowEvidenceExport,
        toStageID stageID: String
    ) throws -> XcircuiteFlowRuntimeSpec {
        try attachingEvidence(export.toolEvidence, toStageID: stageID)
    }
}

public extension XcircuiteFlowStageExecutorSpec {
    var stageID: String {
        switch self {
        case .layoutCommand(let spec):
            spec.stageID
        case .nativeDRC(let spec):
            spec.stageID
        case .nativeLVS(let spec):
            spec.stageID
        case .pex(let spec):
            spec.stageID
        case .mockPEX(let spec):
            spec.stageID
        case .coreSpiceSimulation(let spec):
            spec.stageID
        case .postLayoutComparison(let spec):
            spec.stageID
        case .rtlVerification(let spec):
            spec.stageID
        case .logicSynthesis(let spec):
            spec.stageID
        case .logicEquivalence(let spec):
            spec.stageID
        case .logicQualification(let spec):
            spec.stageID
        case .dft(let spec):
            spec.stageID
        case .physicalReview(let spec):
            spec.stageID
        case .pdkDiscovery(let spec):
            spec.stageID
        case .pdkValidation(let spec):
            spec.stageID
        case .pdkCorpus(let spec):
            spec.stageID
        case .pdkStandardView(let spec):
            spec.stageID
        case .pdkRuleDeck(let spec):
            spec.stageID
        case .pdkOracle(let spec):
            spec.stageID
        case .pdkQualification(let spec):
            spec.stageID
        case .releaseQualification(let spec):
            spec.stageID
        case .releaseSignoff(let spec):
            spec.stageID
        case .releaseTapeout(let spec):
            spec.stageID
        case .releaseProfile(let spec):
            spec.stageID
        case .electricalStandardLayoutImport(let spec):
            spec.stageID
        case .electricalSignoff(let spec):
            spec.stageID
        case .electricalSignoffQualification(let spec):
            spec.stageID
        case .electricalSignoffProcessQualification(let spec):
            spec.stageID
        case .electricalSignoffReleaseGate(let spec):
            spec.stageID
        case .electricalRepairRevision(let spec):
            spec.stageID
        }
    }

    func attachingEvidence(_ evidence: ToolEvidence) -> XcircuiteFlowStageExecutorSpec {
        switch self {
        case .layoutCommand(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .layoutCommand(spec)
        case .nativeDRC(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .nativeDRC(spec)
        case .nativeLVS(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .nativeLVS(spec)
        case .pex(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pex(spec)
        case .mockPEX(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .mockPEX(spec)
        case .coreSpiceSimulation(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .coreSpiceSimulation(spec)
        case .postLayoutComparison(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .postLayoutComparison(spec)
        case .rtlVerification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .rtlVerification(spec)
        case .logicSynthesis(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .logicSynthesis(spec)
        case .logicEquivalence(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .logicEquivalence(spec)
        case .logicQualification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .logicQualification(spec)
        case .dft(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .dft(spec)
        case .physicalReview(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .physicalReview(spec)
        case .pdkDiscovery(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkDiscovery(spec)
        case .pdkValidation(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkValidation(spec)
        case .pdkCorpus(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkCorpus(spec)
        case .pdkStandardView(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkStandardView(spec)
        case .pdkRuleDeck(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkRuleDeck(spec)
        case .pdkOracle(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkOracle(spec)
        case .pdkQualification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .pdkQualification(spec)
        case .releaseQualification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .releaseQualification(spec)
        case .releaseSignoff(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .releaseSignoff(spec)
        case .releaseTapeout(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .releaseTapeout(spec)
        case .releaseProfile(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .releaseProfile(spec)
        case .electricalStandardLayoutImport(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalStandardLayoutImport(spec)
        case .electricalSignoff(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalSignoff(spec)
        case .electricalSignoffQualification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalSignoffQualification(spec)
        case .electricalSignoffProcessQualification(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalSignoffProcessQualification(spec)
        case .electricalSignoffReleaseGate(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalSignoffReleaseGate(spec)
        case .electricalRepairRevision(var spec):
            spec.tool = spec.tool.attachingEvidence(evidence)
            return .electricalRepairRevision(spec)
        }
    }
}

public extension XcircuiteFlowToolSpec {
    func attachingEvidence(_ evidence: ToolEvidence) -> XcircuiteFlowToolSpec {
        var updatedEvidence = self.evidence.filter { $0.evidenceID != evidence.evidenceID }
        updatedEvidence.append(evidence)
        return XcircuiteFlowToolSpec(
            qualificationLevel: qualificationLevel,
            healthStatus: healthStatus,
            evidence: updatedEvidence
        )
    }
}
