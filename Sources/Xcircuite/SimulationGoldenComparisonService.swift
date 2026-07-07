import Foundation

public struct SimulationGoldenComparisonService: Sendable {
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
        goldenCSV: String,
        candidateCSV: String,
        options: SimulationGoldenComparisonOptions = SimulationGoldenComparisonOptions()
    ) throws -> SimulationGoldenComparisonReport {
        let golden = try WaveformCSV.parse(goldenCSV, label: "golden")
        let candidate = try WaveformCSV.parse(candidateCSV, label: "candidate")
        let candidateVariableMap = canonicalVariableMap(candidate.variableNames)
        let goldenVariableMap = canonicalVariableMap(golden.variableNames)
        let commonVariables = golden.variableNames.filter {
            candidateVariableMap[canonicalVariableName($0)] != nil
        }
        let selectedVariables = selectedComparedVariables(
            options: options,
            goldenVariables: golden.variableNames,
            candidateVariableMap: candidateVariableMap
        )
        var diagnostics: [String] = []
        var gateViolations: [String] = []

        if golden.sweepName != candidate.sweepName {
            diagnostics.append("Sweep variable mismatch: \(golden.sweepName) vs \(candidate.sweepName).")
        }

        let alignment = WaveformCSVGridAligner().align(
            reference: golden,
            candidate: candidate,
            sweepTolerance: sweepTolerance
        )
        diagnostics.append(contentsOf: alignment.diagnostics)
        if alignment.usesInterpolation && !options.allowInterpolation {
            diagnostics.append("Candidate waveform requires interpolation, but interpolation is disabled.")
        }

        for variableName in options.comparedVariables where goldenVariableMap[canonicalVariableName(variableName)] == nil {
            gateViolations.append("Golden waveform is missing requested comparison variable \(variableName).")
        }
        for variableName in options.comparedVariables where candidateVariableMap[canonicalVariableName(variableName)] == nil {
            gateViolations.append("Candidate waveform is missing requested comparison variable \(variableName).")
        }

        let structurallyComparable = golden.sweepName == candidate.sweepName
            && !alignment.points.isEmpty
            && (options.allowInterpolation || !alignment.usesInterpolation)
            && !selectedVariables.isEmpty

        let comparedVariables: [SimulationGoldenVariableComparison]
        if structurallyComparable {
            comparedVariables = selectedVariables.map { variableName in
                compareVariable(
                    named: variableName,
                    candidateVariableName: candidateVariableMap[canonicalVariableName(variableName)] ?? variableName,
                    golden: golden,
                    candidate: candidate,
                    points: alignment.points,
                    denominatorFloor: normalizedFloor(options.relativeDeltaDenominatorFloor)
                )
            }
        } else {
            comparedVariables = []
        }

        if commonVariables.isEmpty {
            diagnostics.append("No common waveform variables were available for comparison.")
        }
        if selectedVariables.isEmpty {
            diagnostics.append("No selected waveform variables were available for comparison.")
        }
        if alignment.usesInterpolation && options.allowInterpolation {
            diagnostics.append("Candidate waveform values were linearly interpolated onto the golden sweep grid.")
        }

        let requiredResults = options.requiredVariables.map { variableName in
            SimulationGoldenRequiredVariableResult(
                variableName: variableName,
                present: candidateVariableMap[canonicalVariableName(variableName)] != nil
            )
        }
        let maxAbsoluteDelta = comparedVariables.map(\.maxAbsoluteDelta).max() ?? 0
        let maxRelativeDelta = comparedVariables.map(\.maxRelativeDelta).max() ?? 0

        if !structurallyComparable {
            gateViolations.append("Simulation golden comparison is not comparable.")
        }
        if alignment.points.count < golden.pointCount {
            gateViolations.append(
                "Candidate waveform does not cover the full golden sweep: compared \(alignment.points.count) of \(golden.pointCount) point(s)."
            )
        }
        if options.maxAbsoluteDelta == nil && options.maxRelativeDelta == nil {
            gateViolations.append("Simulation golden comparison requires maxAbsoluteDelta or maxRelativeDelta.")
        }
        for missing in golden.variableNames where candidateVariableMap[canonicalVariableName(missing)] == nil {
            gateViolations.append("Candidate waveform is missing golden variable \(missing).")
        }
        if let limit = options.maxAbsoluteDelta, maxAbsoluteDelta > limit {
            gateViolations.append("Simulation maximum absolute delta \(maxAbsoluteDelta) exceeds limit \(limit).")
        }
        if let limit = options.maxRelativeDelta, maxRelativeDelta > limit {
            gateViolations.append("Simulation maximum relative delta \(maxRelativeDelta) exceeds limit \(limit).")
        }
        for required in requiredResults where !required.present {
            gateViolations.append("Candidate waveform is missing required variable \(required.variableName).")
        }

        return SimulationGoldenComparisonReport(
            status: structurallyComparable ? "compared" : "not-comparable",
            goldenPointCount: golden.pointCount,
            candidatePointCount: candidate.pointCount,
            sweepVariable: golden.sweepName,
            comparedPointCount: structurallyComparable ? alignment.points.count : 0,
            usesInterpolation: structurallyComparable && alignment.usesInterpolation,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            comparedVariables: comparedVariables,
            requiredVariables: requiredResults,
            missingInCandidate: golden.variableNames.filter { candidateVariableMap[canonicalVariableName($0)] == nil },
            addedInCandidate: candidate.variableNames.filter { goldenVariableMap[canonicalVariableName($0)] == nil },
            diagnostics: diagnostics,
            gateStatus: gateViolations.isEmpty ? "passed" : "failed",
            gateViolations: stableUnique(gateViolations)
        )
    }

    private func selectedComparedVariables(
        options: SimulationGoldenComparisonOptions,
        goldenVariables: [String],
        candidateVariableMap: [String: String]
    ) -> [String] {
        guard !options.comparedVariables.isEmpty else {
            return goldenVariables.filter { candidateVariableMap[canonicalVariableName($0)] != nil }
        }
        let goldenVariableMap = canonicalVariableMap(goldenVariables)
        return options.comparedVariables.compactMap {
            goldenVariableMap[canonicalVariableName($0)]
        }
    }

    private func compareVariable(
        named variableName: String,
        candidateVariableName: String,
        golden: WaveformCSV,
        candidate: WaveformCSV,
        points: [WaveformCSVAlignedPoint],
        denominatorFloor: Double
    ) -> SimulationGoldenVariableComparison {
        var maxAbsoluteDelta = 0.0
        var maxRelativeDelta = 0.0
        var worstPoint: SimulationGoldenVariableComparison.WorstPoint?

        for point in points {
            guard let goldenValue = golden.value(variableName: variableName, row: point.referenceIndex),
                  let candidateValue = candidate.interpolatedValue(
                    variableName: candidateVariableName,
                    lowerRow: point.candidateLowerIndex,
                    upperRow: point.candidateUpperIndex,
                    fraction: point.candidateFraction
                  ) else {
                continue
            }
            let absoluteDelta = abs(candidateValue - goldenValue)
            let relativeDelta = absoluteDelta / max(abs(goldenValue), denominatorFloor)
            if absoluteDelta > maxAbsoluteDelta {
                maxAbsoluteDelta = absoluteDelta
            }
            if relativeDelta > maxRelativeDelta {
                maxRelativeDelta = relativeDelta
            }
            if worstPoint == nil || absoluteDelta > (worstPoint?.absoluteDelta ?? 0) {
                worstPoint = SimulationGoldenVariableComparison.WorstPoint(
                    sweepValue: golden.sweepValues[point.referenceIndex],
                    goldenValue: goldenValue,
                    candidateValue: candidateValue,
                    absoluteDelta: absoluteDelta,
                    relativeDelta: relativeDelta
                )
            }
        }

        return SimulationGoldenVariableComparison(
            variableName: variableName,
            pointCount: points.count,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            worstPoint: worstPoint
        )
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

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
