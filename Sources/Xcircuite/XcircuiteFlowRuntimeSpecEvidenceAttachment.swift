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
