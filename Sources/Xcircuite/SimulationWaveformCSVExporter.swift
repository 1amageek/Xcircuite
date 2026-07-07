import Foundation
import CoreSpiceWaveform

struct SimulationWaveformCSVExporter {
    enum ExportError: Error, LocalizedError, Equatable {
        case rowCountMismatch(expected: Int, actual: Int)
        case columnCountMismatch(point: Int, expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case .rowCountMismatch(let expected, let actual):
                return "Waveform CSV export expected \(expected) rows but received \(actual)."
            case .columnCountMismatch(let point, let expected, let actual):
                return "Waveform CSV export expected \(expected) columns at point \(point) but received \(actual)."
            }
        }
    }

    func csv(from waveform: WaveformData) throws -> String {
        var lines: [String] = []
        if waveform.isComplex {
            let header = ([waveform.sweepVariable.name] + waveform.variables.flatMap {
                ["\($0.name)_real", "\($0.name)_imag"]
            }).joined(separator: ",")
            lines.append(header)
            let rows = waveform.allComplexValues
            try validate(rowCount: rows.count, expected: waveform.sweepValues.count)
            for index in waveform.sweepValues.indices {
                let rowValues = rows[index]
                try validate(columnCount: rowValues.count, expected: waveform.variables.count, point: index)
                var row = [String(waveform.sweepValues[index])]
                for value in rowValues {
                    row.append(String(value.real))
                    row.append(String(value.imag))
                }
                lines.append(row.joined(separator: ","))
            }
        } else {
            let header = ([waveform.sweepVariable.name] + waveform.variables.map(\.name))
                .joined(separator: ",")
            lines.append(header)
            let rows = waveform.allRealValues
            try validate(rowCount: rows.count, expected: waveform.sweepValues.count)
            for index in waveform.sweepValues.indices {
                let rowValues = rows[index]
                try validate(columnCount: rowValues.count, expected: waveform.variables.count, point: index)
                var row = [String(waveform.sweepValues[index])]
                row.append(contentsOf: rowValues.map { String($0) })
                lines.append(row.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func csv(from parametric: ParametricWaveformData) throws -> String {
        var lines = ["variable,point,mean,stdev,min,max,p5,p95"]
        guard let firstRun = parametric.runs.first else {
            return lines.joined(separator: "\n") + "\n"
        }
        for variable in firstRun.waveform.variables {
            let statistics = try parametric.checkedStatistics(forVariable: variable.name)
            try validate(rowCount: statistics.mean.count, expected: firstRun.waveform.pointCount)
            for index in statistics.mean.indices {
                lines.append([
                    variable.name,
                    String(index),
                    String(statistics.mean[index]),
                    String(statistics.standardDeviation[index]),
                    String(statistics.minimum[index]),
                    String(statistics.maximum[index]),
                    String(statistics.percentile5[index]),
                    String(statistics.percentile95[index]),
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func validate(rowCount actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw ExportError.rowCountMismatch(expected: expected, actual: actual)
        }
    }

    private func validate(columnCount actual: Int, expected: Int, point: Int) throws {
        guard actual == expected else {
            throw ExportError.columnCountMismatch(point: point, expected: expected, actual: actual)
        }
    }
}
