import Foundation

public struct OpAmpSimulationMetricExtractor: Sendable {
    public init() {}

    public func extract(
        from report: XcircuiteSimulationMetricReport
    ) -> OpAmpSimulationMetricExtraction {
        let measurementNames = Set(report.measurements.map { normalizedMeasurementName($0.name) })
        let verdictMeasurements = report.verdicts.compactMap { verdict -> SimulationMeasurementValue? in
            guard let value = verdict.value,
                  !measurementNames.contains(normalizedMeasurementName(verdict.name)) else {
                return nil
            }
            return SimulationMeasurementValue(
                name: verdict.name,
                value: value,
                unit: ""
            )
        }
        return extract(
            measurements: report.measurements + verdictMeasurements,
            sourceKind: "xcircuite-simulation-metric-report",
            sourceStatus: report.status,
            sourceAnalysisLabel: report.analysisLabel
        )
    }

    public func extract(
        from report: SimulationRunSummaryReport
    ) -> OpAmpSimulationMetricExtraction {
        extract(
            measurements: report.measurements,
            sourceKind: "xcircuite-simulation-run-summary",
            sourceStatus: report.summary.status,
            sourceAnalysisLabel: report.summary.analysis
        )
    }

    public func extract(
        measurements: [SimulationMeasurementValue],
        sourceKind: String = "xcircuite-simulation-measurements",
        sourceStatus: String? = nil,
        sourceAnalysisLabel: String? = nil
    ) -> OpAmpSimulationMetricExtraction {
        var metricsByID: [OpAmpMetricID: OpAmpEstimatedMetric] = [:]
        var unmapped: [OpAmpSimulationMetricExtraction.UnmappedMeasurement] = []

        for measurement in measurements {
            guard measurement.value.isFinite else {
                unmapped.append(.init(
                    name: measurement.name,
                    value: measurement.value,
                    unit: measurement.unit
                ))
                continue
            }
            guard let metricID = metricID(for: measurement.name) else {
                unmapped.append(.init(
                    name: measurement.name,
                    value: measurement.value,
                    unit: measurement.unit
                ))
                continue
            }
            metricsByID[metricID] = OpAmpEstimatedMetric(
                metricID: metricID,
                value: measurement.value,
                unit: normalizedUnit(measurement.unit, for: metricID),
                method: "simulation measurement \(measurement.name)"
            )
        }

        let observedMetrics = metricsByID.values.sorted { $0.metricID.rawValue < $1.metricID.rawValue }
        return OpAmpSimulationMetricExtraction(
            sourceKind: sourceKind,
            sourceStatus: sourceStatus,
            sourceAnalysisLabel: sourceAnalysisLabel,
            observedMetrics: observedMetrics,
            unmappedMeasurements: unmapped,
            diagnostics: diagnostics(
                observedMetrics: observedMetrics,
                unmappedMeasurements: unmapped,
                measurementCount: measurements.count
            )
        )
    }

    private func metricID(for measurementName: String) -> OpAmpMetricID? {
        if let direct = OpAmpMetricID(rawValue: measurementName) {
            return direct
        }
        let normalized = normalizedMeasurementName(measurementName)
        if let direct = OpAmpMetricID.allCases.first(where: { normalizedMeasurementName($0.rawValue) == normalized }) {
            return direct
        }

        let aliases: [String: OpAmpMetricID] = [
            "dcgain": .dcGainDB,
            "gain": .dcGainDB,
            "gaindb": .dcGainDB,
            "aol": .dcGainDB,
            "aoldb": .dcGainDB,
            "av": .dcGainDB,
            "avdb": .dcGainDB,
            "unitygain": .unityGainFrequencyHz,
            "unitygainfrequency": .unityGainFrequencyHz,
            "unitygainfrequencyhz": .unityGainFrequencyHz,
            "ugb": .unityGainFrequencyHz,
            "ugbhz": .unityGainFrequencyHz,
            "ugf": .unityGainFrequencyHz,
            "ugfhz": .unityGainFrequencyHz,
            "phasemargin": .phaseMarginDegrees,
            "phasemargindeg": .phaseMarginDegrees,
            "pm": .phaseMarginDegrees,
            "pmdeg": .phaseMarginDegrees,
            "slewratepositive": .positiveSlewRateVPerS,
            "slewratepos": .positiveSlewRateVPerS,
            "slewrateplus": .positiveSlewRateVPerS,
            "srpositive": .positiveSlewRateVPerS,
            "srpos": .positiveSlewRateVPerS,
            "srplus": .positiveSlewRateVPerS,
            "slewratenegative": .negativeSlewRateVPerS,
            "slewrateneg": .negativeSlewRateVPerS,
            "slewrateminus": .negativeSlewRateVPerS,
            "srnegative": .negativeSlewRateVPerS,
            "srneg": .negativeSlewRateVPerS,
            "srminus": .negativeSlewRateVPerS,
            "settlingtime": .settlingTimeSeconds,
            "settlingtimes": .settlingTimeSeconds,
            "cmrr": .cmrrDB,
            "cmrrdb": .cmrrDB,
            "psrrpositive": .psrrPositiveDB,
            "psrrpos": .psrrPositiveDB,
            "psrrplus": .psrrPositiveDB,
            "psrrp": .psrrPositiveDB,
            "psrrpositivedb": .psrrPositiveDB,
            "psrrnegative": .psrrNegativeDB,
            "psrrneg": .psrrNegativeDB,
            "psrrminus": .psrrNegativeDB,
            "psrrn": .psrrNegativeDB,
            "psrrnegativedb": .psrrNegativeDB,
            "inputreferrednoise": .inputReferredNoiseVPerRootHz,
            "inputreferrednoisevperroothz": .inputReferredNoiseVPerRootHz,
            "inputnoise": .inputReferredNoiseVPerRootHz,
            "inoise": .inputReferredNoiseVPerRootHz,
            "noise": .inputReferredNoiseVPerRootHz,
            "offset": .inputOffsetVoltage,
            "offsetvoltage": .inputOffsetVoltage,
            "inputoffset": .inputOffsetVoltage,
            "inputoffsetvoltage": .inputOffsetVoltage,
            "vos": .inputOffsetVoltage,
            "staticpower": .staticPowerW,
            "staticpowerw": .staticPowerW,
            "power": .staticPowerW,
            "quiescentcurrent": .quiescentCurrentA,
            "quiescentcurrenta": .quiescentCurrentA,
            "iq": .quiescentCurrentA,
            "outputswinghigh": .outputSwingHighV,
            "outputswinghighv": .outputSwingHighV,
            "voh": .outputSwingHighV,
            "outputswinglow": .outputSwingLowV,
            "outputswinglowv": .outputSwingLowV,
            "vol": .outputSwingLowV,
            "inputcommonmodemin": .inputCommonModeMinV,
            "inputcommonmodeminv": .inputCommonModeMinV,
            "icmrmin": .inputCommonModeMinV,
            "inputcommonmodemax": .inputCommonModeMaxV,
            "inputcommonmodemaxv": .inputCommonModeMaxV,
            "icmrmax": .inputCommonModeMaxV,
        ]
        return aliases[normalized]
    }

    private func normalizedMeasurementName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func normalizedUnit(_ unit: String, for metricID: OpAmpMetricID) -> String {
        if unit.isEmpty || unit == "unknown" {
            return defaultUnit(for: metricID)
        }
        return unit
    }

    private func defaultUnit(for metricID: OpAmpMetricID) -> String {
        switch metricID {
        case .dcGainDB, .cmrrDB, .psrrPositiveDB, .psrrNegativeDB, .pexDeltaGainDB:
            "dB"
        case .unityGainFrequencyHz:
            "Hz"
        case .phaseMarginDegrees, .pexDeltaPhaseMarginDegrees:
            "deg"
        case .positiveSlewRateVPerS, .negativeSlewRateVPerS:
            "V/s"
        case .settlingTimeSeconds:
            "s"
        case .inputReferredNoiseVPerRootHz:
            "V/sqrt(Hz)"
        case .inputOffsetVoltage, .outputSwingHighV, .outputSwingLowV, .inputCommonModeMinV, .inputCommonModeMaxV:
            "V"
        case .staticPowerW:
            "W"
        case .quiescentCurrentA:
            "A"
        case .drcViolationCount:
            "count"
        case .lvsStatus:
            "status"
        }
    }

    private func diagnostics(
        observedMetrics: [OpAmpEstimatedMetric],
        unmappedMeasurements: [OpAmpSimulationMetricExtraction.UnmappedMeasurement],
        measurementCount: Int
    ) -> [OpAmpDesignDiagnostic] {
        var result: [OpAmpDesignDiagnostic] = []
        if observedMetrics.isEmpty {
            result.append(.init(
                severity: .warning,
                code: "opamp.simulation-metric-extraction.no-opamp-metrics",
                message: "No op-amp metrics could be extracted from \(measurementCount) simulation measurement(s).",
                suggestedActions: ["align-measure-names-with-opamp-metric-ids", "inspect-simulation-measurements"]
            ))
        }
        if !unmappedMeasurements.isEmpty {
            result.append(.init(
                severity: .info,
                code: "opamp.simulation-metric-extraction.unmapped-measurements",
                message: "\(unmappedMeasurements.count) simulation measurement(s) were not mapped to op-amp metrics.",
                suggestedActions: ["inspect-unmapped-measurement-names"]
            ))
        }
        return result
    }
}
