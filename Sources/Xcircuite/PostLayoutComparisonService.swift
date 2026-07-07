import Foundation

public struct PostLayoutComparisonService: Sendable {
    private let sweepTolerance: Double
    private let defaultRelativeDeltaDenominatorFloor: Double

    public init(
        sweepTolerance: Double = 1.0e-12,
        defaultRelativeDeltaDenominatorFloor: Double = 1.0e-30
    ) {
        self.sweepTolerance = sweepTolerance
        self.defaultRelativeDeltaDenominatorFloor = defaultRelativeDeltaDenominatorFloor
    }

    public func compare(
        preLayoutCSV: String,
        postLayoutCSV: String,
        options: PostLayoutComparisonOptions = PostLayoutComparisonOptions()
    ) throws -> PostLayoutComparisonReport {
        let preLayout = try parseWaveformCSV(preLayoutCSV, label: "pre-layout")
        let postLayout = try parseWaveformCSV(postLayoutCSV, label: "post-layout")
        let postVariableMap = canonicalVariableMap(postLayout.variableNames)
        let preVariableMap = canonicalVariableMap(preLayout.variableNames)
        let commonVariables = preLayout.variableNames.filter {
            postVariableMap[canonicalVariableName($0)] != nil
        }
        var diagnostics: [String] = []

        if preLayout.sweepName != postLayout.sweepName {
            diagnostics.append("Sweep variable mismatch: \(preLayout.sweepName) vs \(postLayout.sweepName).")
        }

        let alignment = WaveformCSVGridAligner().align(
            reference: preLayout,
            candidate: postLayout,
            sweepTolerance: sweepTolerance
        )
        diagnostics.append(contentsOf: alignment.diagnostics)

        let comparedVariables: [PostLayoutVariableComparison]
        if diagnostics.contains(where: { $0.hasPrefix("Sweep variable mismatch") }) || alignment.points.isEmpty {
            comparedVariables = []
        } else {
            comparedVariables = commonVariables.map { variableName in
                compareVariable(
                    named: variableName,
                    postLayoutVariableName: postVariableMap[canonicalVariableName(variableName)] ?? variableName,
                    preLayout: preLayout,
                    postLayout: postLayout,
                    points: alignment.points,
                    denominatorFloor: normalizedFloor(options.relativeDeltaDenominatorFloor)
                )
            }
        }

        if commonVariables.isEmpty {
            diagnostics.append("No common waveform variables were available for comparison.")
        }
        if alignment.usesInterpolation {
            diagnostics.append("Post-layout waveform values were linearly interpolated onto the pre-layout sweep grid.")
        }

        let requiredResults = options.requiredPostVariables.map { variableName in
            PostLayoutRequiredVariableResult(
                variableName: variableName,
                present: postVariableMap[canonicalVariableName(variableName)] != nil
            )
        }
        let oscillationMetrics = options.oscillationLimits.map { limit in
            compareOscillation(
                limit: limit,
                preLayout: preLayout,
                postLayout: postLayout,
                preVariableMap: preVariableMap,
                postVariableMap: postVariableMap
            )
        }
        let status = comparedVariables.isEmpty ? "not-comparable" : "compared"
        let maxAbsoluteDelta = comparedVariables.map(\.maxAbsoluteDelta).max() ?? 0
        let maxRelativeDelta = comparedVariables.map(\.maxRelativeDelta).max() ?? 0
        var gateViolations: [String] = []

        if status != "compared" {
            gateViolations.append("Post-layout comparison is not comparable.")
        }
        if alignment.points.count < preLayout.pointCount {
            gateViolations.append(
                "Post-layout waveform does not cover the full pre-layout sweep: compared \(alignment.points.count) of \(preLayout.pointCount) point(s)."
            )
        }
        for missing in preLayout.variableNames where postVariableMap[canonicalVariableName(missing)] == nil {
            gateViolations.append("Post-layout waveform is missing pre-layout variable \(missing).")
        }
        let variableLimitMap = canonicalVariableLimitMap(options.variableLimits)
        // A variable with a variable-specific limit for a metric is judged by
        // that limit only; the global limit governs the remaining variables.
        if let limit = options.maxAbsoluteDelta {
            let globallyGoverned = comparedVariables.filter {
                variableLimitMap[canonicalVariableName($0.variableName)]?.maxAbsoluteDelta == nil
            }
            let globalMaxAbsoluteDelta = globallyGoverned.map(\.maxAbsoluteDelta).max() ?? 0
            if globalMaxAbsoluteDelta > limit {
                gateViolations.append(
                    "Post-layout maximum absolute delta \(globalMaxAbsoluteDelta) exceeds global limit \(limit)."
                )
            }
        }
        if let limit = options.maxRelativeDelta {
            let globallyGoverned = comparedVariables.filter {
                variableLimitMap[canonicalVariableName($0.variableName)]?.maxRelativeDelta == nil
            }
            let globalMaxRelativeDelta = globallyGoverned.map(\.maxRelativeDelta).max() ?? 0
            if globalMaxRelativeDelta > limit {
                gateViolations.append(
                    "Post-layout maximum relative delta \(globalMaxRelativeDelta) exceeds global limit \(limit)."
                )
            }
        }
        gateViolations.append(contentsOf: variableLimitViolations(
            limits: options.variableLimits,
            comparedVariables: comparedVariables
        ))
        for required in requiredResults where !required.present {
            gateViolations.append("Post-layout waveform is missing required variable \(required.variableName).")
        }
        for metric in oscillationMetrics {
            gateViolations.append(contentsOf: metric.violations)
        }

        return PostLayoutComparisonReport(
            status: status,
            preLayoutPointCount: preLayout.pointCount,
            postLayoutPointCount: postLayout.pointCount,
            sweepVariable: preLayout.sweepName,
            comparedPointCount: alignment.points.count,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            comparedVariables: comparedVariables,
            requiredPostVariables: requiredResults,
            oscillationMetrics: oscillationMetrics,
            missingInPostLayout: preLayout.variableNames.filter { postVariableMap[canonicalVariableName($0)] == nil },
            addedInPostLayout: postLayout.variableNames.filter { preVariableMap[canonicalVariableName($0)] == nil },
            diagnostics: diagnostics,
            gateStatus: gateViolations.isEmpty ? "passed" : "failed",
            gateViolations: gateViolations
        )
    }

    private func compareVariable(
        named variableName: String,
        postLayoutVariableName: String,
        preLayout: WaveformCSV,
        postLayout: WaveformCSV,
        points: [WaveformCSVAlignedPoint],
        denominatorFloor: Double
    ) -> PostLayoutVariableComparison {
        var maxAbsoluteDelta = 0.0
        var maxRelativeDelta = 0.0
        for point in points {
            guard let preValue = preLayout.value(variableName: variableName, row: point.referenceIndex),
                  let postValue = postLayout.interpolatedValue(
                    variableName: postLayoutVariableName,
                    lowerRow: point.candidateLowerIndex,
                    upperRow: point.candidateUpperIndex,
                    fraction: point.candidateFraction
                  ) else {
                continue
            }
            let absoluteDelta = abs(postValue - preValue)
            let relativeDelta = absoluteDelta / max(abs(preValue), denominatorFloor)
            maxAbsoluteDelta = max(maxAbsoluteDelta, absoluteDelta)
            maxRelativeDelta = max(maxRelativeDelta, relativeDelta)
        }
        return PostLayoutVariableComparison(
            variableName: variableName,
            pointCount: points.count,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta
        )
    }

    private func compareOscillation(
        limit: PostLayoutOscillationLimit,
        preLayout: WaveformCSV,
        postLayout: WaveformCSV,
        preVariableMap: [String: String],
        postVariableMap: [String: String]
    ) -> PostLayoutOscillationMetricComparison {
        let canonicalName = canonicalVariableName(limit.variableName)
        let preVariableName = preVariableMap[canonicalName]
        let postVariableName = postVariableMap[canonicalName]
        let preMetric = preVariableName
            .flatMap { preLayout.series(named: $0) }
            .map { metric(for: $0, sweep: preLayout.sweepValues) }
        let postMetric = postVariableName
            .flatMap { postLayout.series(named: $0) }
            .map { metric(for: $0, sweep: postLayout.sweepValues) }
        var violations: [String] = []
        if preMetric == nil {
            violations.append("Pre-layout waveform is missing oscillation variable \(limit.variableName).")
        }
        if postMetric == nil {
            violations.append("Post-layout waveform is missing oscillation variable \(limit.variableName).")
        }
        if let postMetric, let minimum = limit.minimumPostAmplitude, postMetric.amplitude < minimum {
            violations.append(
                "Post-layout \(limit.variableName) amplitude \(postMetric.amplitude) is below \(minimum)."
            )
        }
        if let postMetric, let minimum = limit.minimumPostTransitionCount, postMetric.transitionCount < minimum {
            violations.append(
                "Post-layout \(limit.variableName) transition count \(postMetric.transitionCount) is below \(minimum)."
            )
        }
        let relativeDelta: Double?
        if let preFrequency = preMetric?.frequency,
           let postFrequency = postMetric?.frequency,
           preFrequency > 0 {
            relativeDelta = abs(postFrequency - preFrequency) / preFrequency
            if let relativeDelta, let maximum = limit.maximumFrequencyRelativeDelta, relativeDelta > maximum {
                violations.append(
                    "Post-layout \(limit.variableName) frequency relative delta \(relativeDelta) exceeds \(maximum)."
                )
            }
        } else {
            relativeDelta = nil
            if limit.maximumFrequencyRelativeDelta != nil {
                violations.append("Frequency for \(limit.variableName) could not be computed.")
            }
        }
        return PostLayoutOscillationMetricComparison(
            variableName: limit.variableName,
            preLayout: preMetric,
            postLayout: postMetric,
            frequencyRelativeDelta: relativeDelta,
            violations: violations
        )
    }

    private func metric(for values: [Double], sweep: [Double]) -> PostLayoutOscillationMetric {
        guard let minValue = values.min(), let maxValue = values.max(), values.count == sweep.count else {
            return PostLayoutOscillationMetric(
                amplitude: 0,
                frequency: nil,
                averagePeriod: nil,
                transitionCount: 0,
                dutyCycle: nil
            )
        }
        let threshold = (minValue + maxValue) / 2.0
        var transitionTimes: [Double] = []
        var risingTimes: [Double] = []
        var aboveCount = values.first.map { $0 >= threshold } == true ? 1 : 0
        for index in 1..<values.count {
            if values[index] >= threshold {
                aboveCount += 1
            }
            let previous = values[index - 1]
            let current = values[index]
            let crossedUp = previous < threshold && current >= threshold
            let crossedDown = previous >= threshold && current < threshold
            guard crossedUp || crossedDown else {
                continue
            }
            let denominator = current - previous
            let fraction = denominator == 0 ? 0 : (threshold - previous) / denominator
            let time = sweep[index - 1] + fraction * (sweep[index] - sweep[index - 1])
            transitionTimes.append(time)
            if crossedUp {
                risingTimes.append(time)
            }
        }
        let averagePeriod: Double?
        let frequency: Double?
        if risingTimes.count >= 2,
           let first = risingTimes.first,
           let last = risingTimes.last,
           last > first {
            averagePeriod = (last - first) / Double(risingTimes.count - 1)
            frequency = averagePeriod.map { 1.0 / $0 }
        } else {
            averagePeriod = nil
            frequency = nil
        }
        let dutyCycle = values.isEmpty ? nil : Double(aboveCount) / Double(values.count)
        return PostLayoutOscillationMetric(
            amplitude: maxValue - minValue,
            frequency: frequency,
            averagePeriod: averagePeriod,
            transitionCount: transitionTimes.count,
            dutyCycle: dutyCycle
        )
    }

    private func variableLimitViolations(
        limits: [PostLayoutVariableComparisonLimit],
        comparedVariables: [PostLayoutVariableComparison]
    ) -> [String] {
        guard !limits.isEmpty else {
            return []
        }
        var comparisonsByCanonicalName: [String: PostLayoutVariableComparison] = [:]
        for comparison in comparedVariables {
            let canonical = canonicalVariableName(comparison.variableName)
            if comparisonsByCanonicalName[canonical] == nil {
                comparisonsByCanonicalName[canonical] = comparison
            }
        }
        var violations: [String] = []
        for limit in limits {
            guard let comparison = comparisonsByCanonicalName[canonicalVariableName(limit.variableName)] else {
                violations.append(
                    "Post-layout variable \(limit.variableName) was not compared for a variable-specific limit."
                )
                continue
            }
            if let maxAbsoluteDeltaLimit = limit.maxAbsoluteDelta,
               comparison.maxAbsoluteDelta > maxAbsoluteDeltaLimit {
                violations.append(
                    "Post-layout variable \(limit.variableName) absolute delta \(comparison.maxAbsoluteDelta) exceeds variable-specific limit \(maxAbsoluteDeltaLimit)."
                )
            }
            if let maxRelativeDeltaLimit = limit.maxRelativeDelta,
               comparison.maxRelativeDelta > maxRelativeDeltaLimit {
                violations.append(
                    "Post-layout variable \(limit.variableName) relative delta \(comparison.maxRelativeDelta) exceeds variable-specific limit \(maxRelativeDeltaLimit)."
                )
            }
        }
        return violations
    }

    private func canonicalVariableLimitMap(
        _ limits: [PostLayoutVariableComparisonLimit]
    ) -> [String: PostLayoutVariableComparisonLimit] {
        limits.reduce(into: [:]) { result, limit in
            let canonical = canonicalVariableName(limit.variableName)
            if result[canonical] == nil {
                result[canonical] = limit
            }
        }
    }

    private func normalizedFloor(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else {
            return defaultRelativeDeltaDenominatorFloor
        }
        return value
    }

    private func canonicalVariableMap(_ variables: [String]) -> [String: String] {
        variables.reduce(into: [:]) { result, variable in
            let canonical = canonicalVariableName(variable)
            if result[canonical] == nil {
                result[canonical] = variable
            }
        }
    }

    private func canonicalVariableName(_ variableName: String) -> String {
        variableName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func parseWaveformCSV(_ csv: String, label: String) throws -> WaveformCSV {
        do {
            return try WaveformCSV.parse(csv, label: label)
        } catch let error as WaveformCSVError {
            throw PostLayoutComparisonServiceError.invalidCSV(error.localizedDescription)
        }
    }
}
