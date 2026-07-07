import Foundation
import DesignFlowKernel

public struct SimulationRunSummaryReport: Sendable, Hashable, Codable {
    public struct Summary: Sendable, Hashable, Codable {
        public var status: String
        public var analysis: String
        public var measurementCount: Int
        public var waveformVariableCount: Int
        public var expectationCount: Int
        public var failedExpectationCount: Int

        public init(
            status: String,
            analysis: String,
            measurementCount: Int,
            waveformVariableCount: Int,
            expectationCount: Int,
            failedExpectationCount: Int
        ) {
            self.status = status
            self.analysis = analysis
            self.measurementCount = measurementCount
            self.waveformVariableCount = waveformVariableCount
            self.expectationCount = expectationCount
            self.failedExpectationCount = failedExpectationCount
        }
    }

    public struct ExpectationResult: Sendable, Hashable, Codable {
        public var name: String
        public var target: Double
        public var tolerance: Double
        public var measuredValue: Double?
        public var status: String
        public var residual: Double?

        public init(
            name: String,
            target: Double,
            tolerance: Double,
            measuredValue: Double?,
            status: String,
            residual: Double?
        ) {
            self.name = name
            self.target = target
            self.tolerance = tolerance
            self.measuredValue = measuredValue
            self.status = status
            self.residual = residual
        }
    }

    public struct Diagnostic: Sendable, Hashable, Codable {
        public var severity: String
        public var code: String
        public var message: String

        public init(severity: String, code: String, message: String) {
            self.severity = severity
            self.code = code
            self.message = message
        }
    }

    public var schemaVersion: Int
    public var stageID: String
    public var toolID: String
    public var summary: Summary
    public var measurements: [SimulationMeasurementValue]
    public var waveformVariables: [String]
    public var expectations: [ExpectationResult]
    public var diagnostics: [Diagnostic]

    public init(
        schemaVersion: Int = 1,
        stageID: String,
        toolID: String,
        summary: Summary,
        measurements: [SimulationMeasurementValue],
        waveformVariables: [String],
        expectations: [ExpectationResult],
        diagnostics: [Diagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.stageID = stageID
        self.toolID = toolID
        self.summary = summary
        self.measurements = measurements
        self.waveformVariables = waveformVariables
        self.expectations = expectations
        self.diagnostics = diagnostics
    }

    public static func make(
        stageID: String,
        toolID: String,
        outcome: SimulationStageOutcome,
        expectationResults: [ExpectationResult],
        gateStatus: FlowGateStatus,
        diagnostics: [FlowDiagnostic]
    ) -> SimulationRunSummaryReport {
        let waveformVariables = waveformVariableNames(from: outcome.waveformCSV)
        return SimulationRunSummaryReport(
            stageID: stageID,
            toolID: toolID,
            summary: Summary(
                status: gateStatus.rawValue,
                analysis: outcome.analysisLabel,
                measurementCount: outcome.measurements.count,
                waveformVariableCount: waveformVariables.count,
                expectationCount: expectationResults.count,
                failedExpectationCount: expectationResults.filter { $0.status != "passed" }.count
            ),
            measurements: outcome.measurements,
            waveformVariables: waveformVariables,
            expectations: expectationResults,
            diagnostics: diagnostics.map {
                Diagnostic(
                    severity: $0.severity.rawValue,
                    code: $0.code,
                    message: $0.message
                )
            }
        )
    }

    private static func waveformVariableNames(from csv: String) -> [String] {
        guard let header = csv.split(separator: "\n", omittingEmptySubsequences: false).first else {
            return []
        }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard columns.count > 1 else {
            return []
        }
        return Array(columns.dropFirst())
    }
}
