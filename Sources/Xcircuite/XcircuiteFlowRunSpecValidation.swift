import Foundation
import DesignFlowKernel

public extension XcircuiteFlowRunSpec {
    func validate() throws {
        guard schemaVersion == 1 else {
            throw XcircuiteFlowRuntimeSpecError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.emptyRunIntent
        }
        guard !stages.isEmpty else {
            throw XcircuiteFlowRuntimeSpecError.emptyRunStageList
        }

        let validator = FlowIdentifierValidator()
        try validator.validate(runID, kind: .runID)
        var stageIDs: Set<String> = []
        for stage in stages {
            try validator.validate(stage.stageID, kind: .stageID)
            guard !stage.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw XcircuiteFlowRuntimeSpecError.emptyRunStageDisplayName(stage.stageID)
            }
            guard stageIDs.insert(stage.stageID).inserted else {
                throw XcircuiteFlowRuntimeSpecError.duplicateRunStageID(stage.stageID)
            }
        }
    }
}

public extension XcircuiteFlowRuntimeSpec {
    func validateCoverage(
        for runSpec: XcircuiteFlowRunSpec,
        projectRoot: URL? = nil
    ) throws {
        try validate(projectRoot: projectRoot)
        try runSpec.validate()

        let executorStageIDs = Set(executors.map(\.stageID))
        for stage in runSpec.stages where !executorStageIDs.contains(stage.stageID) {
            throw XcircuiteFlowRuntimeSpecError.missingRuntimeExecutorForRunStage(stage.stageID)
        }
    }
}
