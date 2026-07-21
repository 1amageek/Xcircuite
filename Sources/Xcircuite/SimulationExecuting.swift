import CircuiteFoundation
import CoreSpice
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

/// The source and exact artifact inputs supplied to a simulation execution.
public struct SimulationExecutionRequest: Sendable {
    public let netlistSource: String
    public let fileName: String?
    public let inputs: [ArtifactReference]

    public init(
        netlistSource: String,
        fileName: String?,
        inputs: [ArtifactReference]
    ) {
        self.netlistSource = netlistSource
        self.fileName = fileName
        self.inputs = inputs
    }
}

/// What a completed simulation hands the stage: the canonical CoreSpice
/// result together with evaluated measurements and waveform data.
public struct SimulationStageOutcome: Sendable {
    public let analysisLabel: String
    public let measurements: [SimulationMeasurementValue]
    public let waveformCSV: String
    public let coreSpiceResult: CoreSpiceSimulationResult

    public init(
        analysisLabel: String,
        measurements: [SimulationMeasurementValue],
        waveformCSV: String,
        coreSpiceResult: CoreSpiceSimulationResult
    ) {
        self.analysisLabel = analysisLabel
        self.measurements = measurements
        self.waveformCSV = waveformCSV
        self.coreSpiceResult = coreSpiceResult
    }
}

/// The simulation backend the stage executor drives — CoreSpice in
/// production, injectable for tests.
public protocol SimulationExecuting: Sendable {
    func execute(_ request: SimulationExecutionRequest) async throws -> SimulationStageOutcome
}

enum SimulationArtifactLineageError: Error, LocalizedError, Equatable {
    case inputMismatch
    case producerMismatch(expected: String, actual: String)
    case outputProducerMismatch(path: String)

    var errorDescription: String? {
        switch self {
        case .inputMismatch:
            "CoreSpice execution provenance does not exactly match the persisted simulation input artifact."
        case .producerMismatch(let expected, let actual):
            "CoreSpice producer identifier mismatch: expected \(expected), received \(actual)."
        case .outputProducerMismatch(let path):
            "CoreSpice output artifact has missing or inconsistent producer lineage: \(path)."
        }
    }
}
