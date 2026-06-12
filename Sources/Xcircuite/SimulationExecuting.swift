import Foundation

/// A measurement the simulation stage must satisfy: the netlist's
/// `.measure` named `name` must evaluate within `tolerance` of `target`.
public struct SimulationMeasurementExpectation: Sendable, Codable, Hashable {
    public var name: String
    public var target: Double
    /// Absolute tolerance around `target`.
    public var tolerance: Double

    public init(name: String, target: Double, tolerance: Double) {
        self.name = name
        self.target = target
        self.tolerance = tolerance
    }
}

/// One evaluated `.measure` result.
public struct SimulationMeasurementValue: Sendable, Codable, Hashable {
    public var name: String
    public var value: Double
    public var unit: String

    public init(name: String, value: Double, unit: String) {
        self.name = name
        self.value = value
        self.unit = unit
    }
}

/// What a completed simulation hands the stage: the analysis that ran,
/// the evaluated measurements, and the waveform as CSV text.
public struct SimulationStageOutcome: Sendable {
    public var analysisLabel: String
    public var measurements: [SimulationMeasurementValue]
    public var waveformCSV: String

    public init(
        analysisLabel: String,
        measurements: [SimulationMeasurementValue],
        waveformCSV: String
    ) {
        self.analysisLabel = analysisLabel
        self.measurements = measurements
        self.waveformCSV = waveformCSV
    }
}

/// The simulation backend the stage executor drives — CoreSpice in
/// production, injectable for tests.
public protocol SimulationExecuting: Sendable {
    func run(netlistSource: String, fileName: String?) async throws -> SimulationStageOutcome
}
