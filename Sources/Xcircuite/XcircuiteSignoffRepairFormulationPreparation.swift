import Foundation

public struct XcircuiteSignoffRepairFormulationPreparation: Sendable, Hashable {
    public let result: XcircuiteSignoffRepairFormulationResult
    public let artifacts: [XcircuitePreparedArtifact]

    public init(
        result: XcircuiteSignoffRepairFormulationResult,
        artifacts: [XcircuitePreparedArtifact]
    ) {
        self.result = result
        self.artifacts = artifacts
    }
}
