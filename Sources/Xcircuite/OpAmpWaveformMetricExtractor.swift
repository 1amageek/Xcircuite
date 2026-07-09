import Foundation

public struct OpAmpWaveformMetricExtractor: Sendable {
    public init() {}

    public func extract(
        analysisKind: OpAmpWaveformAnalysisKind,
        waveformCSV: String,
        outputVariable: String = "V(vout)",
        sourceKind: String = "xcircuite-waveform-csv"
    ) throws -> OpAmpSimulationMetricExtraction {
        let waveform: WaveformCSV
        do {
            waveform = try WaveformCSV.parse(waveformCSV, label: analysisKind.rawValue)
        } catch let error as WaveformCSVError {
            throw OpAmpWaveformMetricExtractionError.invalidWaveform(error.localizedDescription)
        }

        let result: ([OpAmpEstimatedMetric], [OpAmpDesignDiagnostic])
        switch analysisKind {
        case .acOpenLoop:
            result = try extractACMetrics(waveform: waveform, outputVariable: outputVariable)
        case .transientPositiveStep:
            result = try extractTransientMetrics(
                waveform: waveform,
                outputVariable: outputVariable,
                slewMetricID: .positiveSlewRateVPerS
            )
        case .transientNegativeStep:
            result = try extractTransientMetrics(
                waveform: waveform,
                outputVariable: outputVariable,
                slewMetricID: .negativeSlewRateVPerS
            )
        case .noiseInputReferred:
            result = try extractNoiseMetrics(waveform: waveform)
        }

        return OpAmpSimulationMetricExtraction(
            sourceKind: sourceKind,
            sourceStatus: "passed",
            sourceAnalysisLabel: analysisKind.rawValue,
            observedMetrics: result.0,
            unmappedMeasurements: [],
            diagnostics: result.1
        )
    }

    private func extractACMetrics(
        waveform: WaveformCSV,
        outputVariable: String
    ) throws -> ([OpAmpEstimatedMetric], [OpAmpDesignDiagnostic]) {
        guard waveform.pointCount >= 2 else {
            throw OpAmpWaveformMetricExtractionError.insufficientPoints("ac-open-loop")
        }
        let baseName = canonicalVoltageVariable(outputVariable)
        let realName = "\(baseName)_real"
        let imagName = "\(baseName)_imag"
        guard let real = waveform.series(named: realName) else {
            throw OpAmpWaveformMetricExtractionError.missingVariable(realName)
        }
        guard let imag = waveform.series(named: imagName) else {
            throw OpAmpWaveformMetricExtractionError.missingVariable(imagName)
        }
        let values = waveform.sweepValues.indices.map { index in
            ACPoint(
                frequency: waveform.sweepValues[index],
                real: real[index],
                imag: imag[index]
            )
        }
        let finiteValues = values.filter { $0.frequency.isFinite && $0.frequency > 0 && $0.magnitude.isFinite }
        guard let first = finiteValues.first else {
            throw OpAmpWaveformMetricExtractionError.noFiniteValues(baseName)
        }

        var metrics = [
            OpAmpEstimatedMetric(
                metricID: .dcGainDB,
                value: 20.0 * log10(max(first.magnitude, 1.0e-300)),
                unit: "dB",
                method: "AC waveform low-frequency magnitude at \(first.frequency) Hz"
            ),
        ]
        var diagnostics: [OpAmpDesignDiagnostic] = []

        if let crossing = unityGainCrossing(in: finiteValues) {
            metrics.append(OpAmpEstimatedMetric(
                metricID: .unityGainFrequencyHz,
                value: crossing.frequency,
                unit: "Hz",
                method: "AC waveform unity-magnitude crossing"
            ))
            metrics.append(OpAmpEstimatedMetric(
                metricID: .phaseMarginDegrees,
                value: 180.0 + crossing.phaseDegrees,
                unit: "deg",
                method: "AC waveform phase at unity-magnitude crossing"
            ))
        } else {
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.waveform-metric-extraction.no-unity-gain-crossing",
                message: "AC waveform did not cross unity magnitude; extracted DC gain only.",
                relatedMetricIDs: [.unityGainFrequencyHz, .phaseMarginDegrees],
                suggestedActions: ["extend-ac-frequency-range", "inspect-open-loop-gain-waveform"]
            ))
        }

        return (metrics, diagnostics)
    }

    private func extractTransientMetrics(
        waveform: WaveformCSV,
        outputVariable: String,
        slewMetricID: OpAmpMetricID
    ) throws -> ([OpAmpEstimatedMetric], [OpAmpDesignDiagnostic]) {
        guard waveform.pointCount >= 2 else {
            throw OpAmpWaveformMetricExtractionError.insufficientPoints("tran")
        }
        let variableName = canonicalVoltageVariable(outputVariable)
        guard let output = waveform.series(named: variableName) else {
            throw OpAmpWaveformMetricExtractionError.missingVariable(variableName)
        }

        let derivatives = slopes(x: waveform.sweepValues, y: output)
        guard !derivatives.isEmpty else {
            throw OpAmpWaveformMetricExtractionError.insufficientPoints("tran")
        }
        let slewRate: Double
        if slewMetricID == .negativeSlewRateVPerS {
            guard let minimum = derivatives.min() else {
                throw OpAmpWaveformMetricExtractionError.noFiniteValues(variableName)
            }
            slewRate = abs(minimum)
        } else {
            guard let maximum = derivatives.max() else {
                throw OpAmpWaveformMetricExtractionError.noFiniteValues(variableName)
            }
            slewRate = maximum
        }

        let settlingTime = settlingTimeSeconds(
            time: waveform.sweepValues,
            output: output,
            bandFraction: 0.02
        )
        return ([
            OpAmpEstimatedMetric(
                metricID: slewMetricID,
                value: slewRate,
                unit: "V/s",
                method: "transient waveform maximum output slope"
            ),
            OpAmpEstimatedMetric(
                metricID: .settlingTimeSeconds,
                value: settlingTime,
                unit: "s",
                method: "transient waveform 2% final-value settling"
            ),
        ], [])
    }

    private func extractNoiseMetrics(
        waveform: WaveformCSV
    ) throws -> ([OpAmpEstimatedMetric], [OpAmpDesignDiagnostic]) {
        let variableName = "input_referred_noise_density"
        guard let noise = waveform.series(named: variableName) else {
            throw OpAmpWaveformMetricExtractionError.missingVariable(variableName)
        }
        let finite = noise.filter { $0.isFinite && $0 >= 0 }
        guard let maximum = finite.max() else {
            throw OpAmpWaveformMetricExtractionError.noFiniteValues(variableName)
        }
        return ([
            OpAmpEstimatedMetric(
                metricID: .inputReferredNoiseVPerRootHz,
                value: maximum,
                unit: "V/sqrt(Hz)",
                method: "maximum input-referred noise density across waveform sweep"
            ),
        ], [])
    }

    private func canonicalVoltageVariable(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("v(") else {
            return trimmed
        }
        return "V(\(trimmed))"
    }

    private func slopes(x: [Double], y: [Double]) -> [Double] {
        guard x.count == y.count, x.count >= 2 else {
            return []
        }
        var result: [Double] = []
        result.reserveCapacity(x.count - 1)
        for index in 1..<x.count {
            let dx = x[index] - x[index - 1]
            guard dx > 0 else {
                continue
            }
            let value = (y[index] - y[index - 1]) / dx
            if value.isFinite {
                result.append(value)
            }
        }
        return result
    }

    private func settlingTimeSeconds(
        time: [Double],
        output: [Double],
        bandFraction: Double
    ) -> Double {
        guard let initial = output.first,
              let final = output.last,
              let fallback = time.last,
              time.count == output.count else {
            return 0
        }
        let tolerance = max(abs(final - initial) * bandFraction, 1.0e-12)
        for index in output.indices {
            let remainingSettled = output[index...].allSatisfy { abs($0 - final) <= tolerance }
            if remainingSettled {
                return time[index]
            }
        }
        return fallback
    }

    private func unityGainCrossing(in points: [ACPoint]) -> ACPoint? {
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            if current.magnitude == 1.0 {
                return current
            }
            let previousDelta = previous.magnitude - 1.0
            let currentDelta = current.magnitude - 1.0
            guard previousDelta == 0 || currentDelta == 0 || previousDelta.sign != currentDelta.sign else {
                continue
            }
            return interpolateUnityGain(previous: previous, current: current)
        }
        return nil
    }

    private func interpolateUnityGain(previous: ACPoint, current: ACPoint) -> ACPoint {
        let previousMagnitude = log(max(previous.magnitude, 1.0e-300))
        let currentMagnitude = log(max(current.magnitude, 1.0e-300))
        let denominator = currentMagnitude - previousMagnitude
        let fraction = denominator == 0 ? 0 : (0 - previousMagnitude) / denominator
        let logFrequency = log(previous.frequency) + fraction * (log(current.frequency) - log(previous.frequency))
        let phase = unwrap(current: current.phaseRadians, relativeTo: previous.phaseRadians)
        let interpolatedPhase = previous.phaseRadians + fraction * (phase - previous.phaseRadians)
        return ACPoint(
            frequency: exp(logFrequency),
            real: cos(interpolatedPhase),
            imag: sin(interpolatedPhase)
        )
    }

    private func unwrap(current: Double, relativeTo previous: Double) -> Double {
        var value = current
        while value - previous > .pi {
            value -= 2.0 * .pi
        }
        while value - previous < -.pi {
            value += 2.0 * .pi
        }
        return value
    }
}

private struct ACPoint: Sendable, Hashable {
    var frequency: Double
    var real: Double
    var imag: Double

    var magnitude: Double {
        sqrt(real * real + imag * imag)
    }

    var phaseRadians: Double {
        atan2(imag, real)
    }

    var phaseDegrees: Double {
        phaseRadians * 180.0 / .pi
    }
}
