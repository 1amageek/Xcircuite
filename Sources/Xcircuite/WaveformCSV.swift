import Foundation

struct WaveformCSV: Sendable, Hashable {
    var sweepName: String
    var variableNames: [String]
    var sweepValues: [Double]
    var columns: [String: [Double]]

    var pointCount: Int {
        sweepValues.count
    }

    static func parse(_ csv: String, label: String) throws -> WaveformCSV {
        let records = try records(from: csv, label: label)
        guard let headerRecord = records.first else {
            throw WaveformCSVError.invalidCSV("\(label) waveform is empty.")
        }
        let header = headerRecord.map(normalizeName)
        guard header.count >= 2 else {
            throw WaveformCSVError.invalidCSV(
                "\(label) waveform must contain a sweep and at least one variable."
            )
        }

        let sweepName = header[0]
        guard !sweepName.isEmpty else {
            throw WaveformCSVError.invalidCSV("\(label) waveform sweep variable name is empty.")
        }
        let variableNames = Array(header.dropFirst())
        try validateVariableNames(variableNames, label: label)
        var sweepValues: [Double] = []
        var columns: [String: [Double]] = [:]
        for variableName in variableNames {
            guard columns[variableName] == nil else {
                throw WaveformCSVError.invalidCSV(
                    "\(label) waveform contains duplicate variable \(variableName)."
                )
            }
            columns[variableName] = []
        }

        for (rowOffset, values) in records.dropFirst().enumerated() {
            guard !values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            let lineNumber = rowOffset + 2
            guard values.count == header.count else {
                throw WaveformCSVError.invalidCSV(
                    "\(label) waveform row \(lineNumber) has \(values.count) columns; expected \(header.count)."
                )
            }
            guard let sweep = finiteDouble(values[0]) else {
                throw WaveformCSVError.invalidCSV(
                    "\(label) waveform row \(lineNumber) has an invalid sweep value."
                )
            }
            sweepValues.append(sweep)
            for (index, variableName) in variableNames.enumerated() {
                guard let value = finiteDouble(values[index + 1]) else {
                    throw WaveformCSVError.invalidCSV(
                        "\(label) waveform row \(lineNumber) has an invalid value for \(variableName)."
                    )
                }
                columns[variableName, default: []].append(value)
            }
        }

        guard !sweepValues.isEmpty else {
            throw WaveformCSVError.invalidCSV("\(label) waveform has no data rows.")
        }
        try validateSweepValues(sweepValues, label: label)
        try validateColumnLengths(columns, variableNames: variableNames, expected: sweepValues.count, label: label)
        return WaveformCSV(
            sweepName: sweepName,
            variableNames: variableNames,
            sweepValues: sweepValues,
            columns: columns
        )
    }

    func series(named variableName: String) -> [Double]? {
        columns[variableName]
    }

    func value(variableName: String, row: Int) -> Double? {
        guard let series = columns[variableName], series.indices.contains(row) else {
            return nil
        }
        return series[row]
    }

    func interpolatedValue(
        variableName: String,
        lowerRow: Int,
        upperRow: Int,
        fraction: Double
    ) -> Double? {
        guard let lower = value(variableName: variableName, row: lowerRow),
              let upper = value(variableName: variableName, row: upperRow) else {
            return nil
        }
        return lower + (upper - lower) * fraction
    }

    private static func records(from csv: String, label: String) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]
            if character == "\"" {
                let next = csv.index(after: index)
                if isQuoted && next < csv.endIndex && csv[next] == "\"" {
                    field.append("\"")
                    index = csv.index(after: next)
                    continue
                }
                isQuoted.toggle()
                index = next
                continue
            }
            if character == "," && !isQuoted {
                record.append(field)
                field.removeAll(keepingCapacity: true)
                index = csv.index(after: index)
                continue
            }
            if character.isNewline && !isQuoted {
                record.append(field)
                field.removeAll(keepingCapacity: true)
                if !record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    records.append(record)
                }
                record.removeAll(keepingCapacity: true)
                let next = csv.index(after: index)
                if character == "\r", next < csv.endIndex, csv[next] == "\n" {
                    index = csv.index(after: next)
                } else {
                    index = next
                }
                continue
            }
            field.append(character)
            index = csv.index(after: index)
        }

        guard !isQuoted else {
            throw WaveformCSVError.invalidCSV("\(label) waveform contains an unterminated quoted field.")
        }
        record.append(field)
        if !record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            records.append(record)
        }
        return records
    }

    private static func validateVariableNames(_ variableNames: [String], label: String) throws {
        var canonicalNames: Set<String> = []
        for variableName in variableNames {
            guard !variableName.isEmpty else {
                throw WaveformCSVError.invalidCSV("\(label) waveform contains an empty variable name.")
            }
            let canonicalName = canonicalName(variableName)
            guard canonicalNames.insert(canonicalName).inserted else {
                throw WaveformCSVError.invalidCSV(
                    "\(label) waveform contains duplicate variable \(variableName) after normalization."
                )
            }
        }
    }

    private static func validateSweepValues(_ sweepValues: [Double], label: String) throws {
        guard sweepValues.count >= 2 else { return }
        for index in 1..<sweepValues.count where sweepValues[index] < sweepValues[index - 1] {
            throw WaveformCSVError.invalidCSV(
                "\(label) waveform sweep values must be monotonic at row \(index + 2)."
            )
        }
    }

    private static func validateColumnLengths(
        _ columns: [String: [Double]],
        variableNames: [String],
        expected: Int,
        label: String
    ) throws {
        for variableName in variableNames {
            guard columns[variableName]?.count == expected else {
                throw WaveformCSVError.invalidCSV(
                    "\(label) waveform column \(variableName) does not match the sweep point count."
                )
            }
        }
    }

    private static func finiteDouble(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else {
            return nil
        }
        return value
    }

    private static func normalizeName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unitStart = trimmed.range(of: " [") else {
            return trimmed
        }
        return String(trimmed[..<unitStart.lowerBound])
    }

    private static func canonicalName(_ rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
