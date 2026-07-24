import Foundation

public struct XcircuiteRepairPlanFormulationPreparation: Sendable, Hashable {
    public let result: XcircuiteRepairPlanFormulationCompilationResult
    public let artifacts: [XcircuitePreparedArtifact]

    public init(
        result: XcircuiteRepairPlanFormulationCompilationResult,
        artifacts: [XcircuitePreparedArtifact]
    ) {
        self.result = result
        self.artifacts = artifacts
    }
}
