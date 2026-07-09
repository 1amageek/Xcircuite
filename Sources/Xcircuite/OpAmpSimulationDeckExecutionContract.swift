import Foundation

public struct OpAmpSimulationDeckExecutionContract: Sendable, Hashable, Codable {
    public var coreSpiceEngineRunnable: Bool
    public var coreSpiceBatchCLIRunnable: Bool
    public var directMeasurementsRequired: Bool
    public var waveformPostProcessingRequired: Bool
    public var expectedArtifactKinds: [String]
    public var limitations: [String]

    public init(
        coreSpiceEngineRunnable: Bool = true,
        coreSpiceBatchCLIRunnable: Bool = true,
        directMeasurementsRequired: Bool = false,
        waveformPostProcessingRequired: Bool = false,
        expectedArtifactKinds: [String] = ["waveformCSV", "measurementsJSON"],
        limitations: [String] = []
    ) {
        self.coreSpiceEngineRunnable = coreSpiceEngineRunnable
        self.coreSpiceBatchCLIRunnable = coreSpiceBatchCLIRunnable
        self.directMeasurementsRequired = directMeasurementsRequired
        self.waveformPostProcessingRequired = waveformPostProcessingRequired
        self.expectedArtifactKinds = expectedArtifactKinds
        self.limitations = limitations
    }
}
