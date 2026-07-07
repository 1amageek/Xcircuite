import CoreSpiceWaveform
import Testing
@testable import Xcircuite

@Suite("Simulation waveform CSV exporter")
struct SimulationWaveformCSVExporterTests {
    @Test func exporterRejectsMissingWaveformRows() throws {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Bad waveform",
                analysisType: .transient,
                pointCount: 2,
                variableCount: 1
            ),
            sweepVariable: .time(),
            sweepValues: [0, 1],
            variables: [
                .voltage(node: "out", index: 0),
            ],
            realData: [
                [1.0],
            ]
        )

        #expect(throws: SimulationWaveformCSVExporter.ExportError.rowCountMismatch(expected: 2, actual: 1)) {
            _ = try SimulationWaveformCSVExporter().csv(from: waveform)
        }
    }

    @Test func exporterRejectsMissingWaveformColumns() throws {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Bad waveform",
                analysisType: .transient,
                pointCount: 1,
                variableCount: 2
            ),
            sweepVariable: .time(),
            sweepValues: [0],
            variables: [
                .voltage(node: "out", index: 0),
                .current(device: "V1", index: 1),
            ],
            realData: [
                [1.0],
            ]
        )

        #expect(throws: SimulationWaveformCSVExporter.ExportError.columnCountMismatch(point: 0, expected: 2, actual: 1)) {
            _ = try SimulationWaveformCSVExporter().csv(from: waveform)
        }
    }

    @Test func exporterWritesRectangularWaveformCSV() throws {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Good waveform",
                analysisType: .transient,
                pointCount: 2,
                variableCount: 1
            ),
            sweepVariable: .time(),
            sweepValues: [0, 1],
            variables: [
                .voltage(node: "out", index: 0),
            ],
            realData: [
                [1.0],
                [2.0],
            ]
        )

        let csv = try SimulationWaveformCSVExporter().csv(from: waveform)
        #expect(csv == "time,V(out)\n0.0,1.0\n1.0,2.0\n")
    }

    @Test func parametricExporterPropagatesValidationFailure() throws {
        let waveform = WaveformData(
            metadata: SimulationMetadata(
                title: "Run waveform",
                analysisType: .transient,
                pointCount: 1,
                variableCount: 1
            ),
            sweepVariable: .time(),
            sweepValues: [0],
            variables: [
                .voltage(node: "out", index: 0),
            ],
            realData: [
                [1.0],
            ]
        )
        let parametric = ParametricWaveformData(
            runs: [
                ParametricWaveformData.Run(
                    index: 0,
                    parameters: ["corner": 0],
                    waveform: waveform
                ),
                ParametricWaveformData.Run(
                    index: 1,
                    parameters: ["corner": .infinity],
                    waveform: waveform
                ),
            ],
            analysisType: .transient,
            parameterNames: ["corner"]
        )

        #expect(throws: ParametricWaveformValidationError.nonFiniteParameterValue(
            runIndex: 1,
            name: "corner",
            value: .infinity
        )) {
            _ = try SimulationWaveformCSVExporter().csv(from: parametric)
        }
    }
}
