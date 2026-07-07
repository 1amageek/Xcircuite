struct WaveformCSVGridAligner: Sendable {
    func align(
        reference: WaveformCSV,
        candidate: WaveformCSV,
        sweepTolerance: Double
    ) -> WaveformCSVGridAlignment {
        guard isMonotonic(reference.sweepValues), isMonotonic(candidate.sweepValues) else {
            return WaveformCSVGridAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Sweep values must be monotonic."]
            )
        }

        if reference.sweepValues.count == candidate.sweepValues.count {
            let equal = zip(reference.sweepValues, candidate.sweepValues).allSatisfy {
                abs($0.0 - $0.1) <= sweepTolerance
            }
            if equal {
                let points = reference.sweepValues.indices.map {
                    WaveformCSVAlignedPoint(
                        referenceIndex: $0,
                        candidateLowerIndex: $0,
                        candidateUpperIndex: $0,
                        candidateFraction: 0
                    )
                }
                return WaveformCSVGridAlignment(points: points, usesInterpolation: false, diagnostics: [])
            }
        }

        guard let firstCandidate = candidate.sweepValues.first,
              let lastCandidate = candidate.sweepValues.last else {
            return WaveformCSVGridAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Candidate sweep is empty."]
            )
        }
        guard candidate.sweepValues.count >= 2, firstCandidate < lastCandidate else {
            return WaveformCSVGridAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Candidate sweep has insufficient increasing points for grid alignment."]
            )
        }

        var points: [WaveformCSVAlignedPoint] = []
        var candidateIndex = 0
        var skippedBeforeCandidateRange = 0
        var skippedAfterCandidateRange = 0
        for (referenceIndex, referenceSweep) in reference.sweepValues.enumerated() {
            if referenceSweep < firstCandidate - sweepTolerance {
                skippedBeforeCandidateRange += 1
                continue
            }
            if referenceSweep > lastCandidate + sweepTolerance {
                skippedAfterCandidateRange += 1
                continue
            }
            while candidateIndex + 1 < candidate.sweepValues.count
                && candidate.sweepValues[candidateIndex + 1] < referenceSweep {
                candidateIndex += 1
            }
            let upperIndex = min(candidateIndex + 1, candidate.sweepValues.count - 1)
            let lowerSweep = candidate.sweepValues[candidateIndex]
            let upperSweep = candidate.sweepValues[upperIndex]
            let fraction = upperSweep == lowerSweep
                ? 0
                : (referenceSweep - lowerSweep) / (upperSweep - lowerSweep)
            points.append(
                WaveformCSVAlignedPoint(
                    referenceIndex: referenceIndex,
                    candidateLowerIndex: candidateIndex,
                    candidateUpperIndex: upperIndex,
                    candidateFraction: max(0, min(1, fraction))
                )
            )
        }

        var diagnostics: [String] = points.isEmpty ? ["No overlapping sweep range."] : []
        let skippedPointCount = skippedBeforeCandidateRange + skippedAfterCandidateRange
        if skippedPointCount > 0 {
            diagnostics.append(
                "Candidate sweep does not cover \(skippedPointCount) reference point(s) outside its range: before=\(skippedBeforeCandidateRange), after=\(skippedAfterCandidateRange)."
            )
        }

        return WaveformCSVGridAlignment(
            points: points,
            usesInterpolation: true,
            diagnostics: diagnostics
        )
    }

    private func isMonotonic(_ values: [Double]) -> Bool {
        guard values.count >= 2 else { return true }
        for index in 1..<values.count where values[index] < values[index - 1] {
            return false
        }
        return true
    }
}
