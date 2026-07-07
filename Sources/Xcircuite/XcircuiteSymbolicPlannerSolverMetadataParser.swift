import Foundation

public struct XcircuiteSymbolicPlannerSolverMetadataParser: Sendable {
    public init() {}

    public func parse(
        standardOutput: String,
        standardError: String,
        solverPlanText: String?
    ) -> XcircuiteSymbolicPlannerSolverMetadata? {
        var metadata = XcircuiteSymbolicPlannerSolverMetadata()
        inspect(standardOutput, metadata: &metadata)
        inspect(standardError, metadata: &metadata)
        if let solverPlanText {
            inspect(solverPlanText, metadata: &metadata)
        }
        return metadata.evidenceLines.isEmpty ? nil : metadata
    }

    private func inspect(
        _ text: String,
        metadata: inout XcircuiteSymbolicPlannerSolverMetadata
    ) {
        for rawLine in text.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            var didCapture = false

            if let cost = parseCost(line) {
                metadata.planCost = cost.value
                metadata.planCostUnit = cost.unit
                didCapture = true
            }
            if let planLength = parsePlanLength(line) {
                metadata.planLength = planLength
                didCapture = true
            }
            if let makespan = parseMakespan(line) {
                metadata.makespan = makespan
                didCapture = true
            }
            if let optimalityStatus = parseOptimalityStatus(line) {
                metadata.optimalityStatus = optimalityStatus
                didCapture = true
            }

            if didCapture, !metadata.evidenceLines.contains(line) {
                metadata.evidenceLines.append(line)
            }
        }
    }

    private func parseCost(_ line: String) -> (value: Double, unit: String?)? {
        guard line.range(of: "cost", options: [.caseInsensitive]) != nil,
              let suffix = suffix(after: "cost", in: line),
              let value = firstDouble(in: suffix) else {
            return nil
        }
        return (value, parenthesizedUnit(in: suffix))
    }

    private func parsePlanLength(_ line: String) -> Int? {
        guard let suffix = suffix(after: "plan length", in: line),
              let value = firstDouble(in: suffix) else {
            return nil
        }
        return Int(value)
    }

    private func parseMakespan(_ line: String) -> Double? {
        guard let suffix = suffix(after: "makespan", in: line) else {
            return nil
        }
        return firstDouble(in: suffix)
    }

    private func parseOptimalityStatus(_ line: String) -> String? {
        let lowercased = line.lowercased()
        if lowercased.contains("not optimal")
            || lowercased.contains("suboptimal")
            || lowercased.contains("not proven optimal")
            || lowercased.contains("not proved optimal")
            || lowercased.contains("optimality not proven") {
            return "not-optimal"
        }
        if lowercased.contains("satisficing") {
            return "satisficing"
        }
        if lowercased.contains("optimal") {
            return "optimal"
        }
        return nil
    }

    private func suffix(after marker: String, in line: String) -> String? {
        guard let markerRange = line.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }
        let rawSuffix = line[markerRange.upperBound...]
        if let delimiter = rawSuffix.firstIndex(where: { $0 == "=" || $0 == ":" }) {
            return String(rawSuffix[rawSuffix.index(after: delimiter)...])
        }
        return String(rawSuffix)
    }

    private func firstDouble(in text: String) -> Double? {
        var candidate = ""
        var hasDigit = false
        var started = false
        var previousWasExponent = false

        for scalar in text.unicodeScalars {
            if !started {
                if isDigit(scalar) || scalar == "-" || scalar == "+" || scalar == "." {
                    started = true
                    candidate.append(String(scalar))
                    hasDigit = hasDigit || isDigit(scalar)
                    previousWasExponent = false
                }
                continue
            }

            if isDigit(scalar) || scalar == "." {
                candidate.append(String(scalar))
                hasDigit = hasDigit || isDigit(scalar)
                previousWasExponent = false
            } else if scalar == "e" || scalar == "E" {
                candidate.append(String(scalar))
                previousWasExponent = true
            } else if (scalar == "-" || scalar == "+") && previousWasExponent {
                candidate.append(String(scalar))
                previousWasExponent = false
            } else {
                break
            }
        }

        guard hasDigit else { return nil }
        return Double(candidate)
    }

    private func parenthesizedUnit(in text: String) -> String? {
        guard let open = text.firstIndex(of: "("),
              let close = text[open...].firstIndex(of: ")"),
              open < close else {
            return nil
        }
        let start = text.index(after: open)
        let value = text[start..<close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar >= "0" && scalar <= "9"
    }
}
