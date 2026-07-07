import Foundation
import DRCEngine
import LayoutCore
import LayoutIO
import LVSEngine
import PEXEngine
import XcircuitePackage

extension XcircuiteCandidatePlanVerifier {
    func runSimulationMetricGate(
        required: Bool,
        sourceStepIDs: [String],
        spec: SimulationMetricExecutionSpec,
        netlistRef: XcircuitePlanningReference,
        manifest: XcircuiteRunManifest,
        verificationDirectory: URL,
        runID: String,
        projectRoot: URL
    ) async throws -> GateExecutionEvaluation {
        let netlistURL = try url(for: netlistRef, manifest: manifest, projectRoot: projectRoot)
        let source = try String(contentsOf: netlistURL, encoding: .utf8)
        let netlistCopyURL = verificationDirectory.appending(path: "input-\(netlistURL.lastPathComponent)")
        try packageStore.writeText(source, to: netlistCopyURL)
        let outcome = try await CoreSpiceSimulationEngine().run(
            netlistSource: source,
            fileName: netlistURL.lastPathComponent
        )
        let waveformURL = verificationDirectory.appending(path: "waveform.csv")
        try packageStore.writeText(outcome.waveformCSV, to: waveformURL)
        let measurementsURL = verificationDirectory.appending(path: "measurements.json")
        try packageStore.writeJSON(
            outcome.measurements,
            to: measurementsURL,
            forProjectAt: projectRoot
        )
        let summary = simulationMetricReport(
            outcome: outcome,
            expectations: spec.expectations
        )
        let summaryURL = verificationDirectory.appending(path: "simulation-summary.json")
        try packageStore.writeJSON(summary, to: summaryURL, forProjectAt: projectRoot)
        let artifacts = try simulationMetricArtifactRefs(
            netlistURL: netlistCopyURL,
            waveformURL: waveformURL,
            measurementsURL: measurementsURL,
            summaryURL: summaryURL,
            runID: runID,
            projectRoot: projectRoot
        )
        for artifact in artifacts {
            try packageStore.upsertRunArtifact(artifact, runID: runID, inProjectAt: projectRoot)
        }
        let diagnostics = simulationMetricDiagnostics(from: summary)
        return GateExecutionEvaluation(
            gateResult: XcircuitePlanVerificationGateResult(
                gateID: "simulation-metric-gate",
                required: required,
                status: summary.status,
                sourceStepIDs: sourceStepIDs,
                diagnostics: diagnostics
            ),
            artifactRefs: artifacts
        )
    }

    func evaluatePostLayoutMetricReportGate(
        required: Bool,
        sourceStepIDs: [String],
        metricReportRef: XcircuitePlanningReference,
        manifest: XcircuiteRunManifest,
        verificationDirectory: URL,
        runID: String,
        projectRoot: URL
    ) throws -> GateExecutionEvaluation {
        let reportURL = try url(for: metricReportRef, manifest: manifest, projectRoot: projectRoot)
        let postLayoutReport = try packageStore.readJSON(PostLayoutComparisonReport.self, from: reportURL)
        let summary = simulationMetricReport(
            postLayoutReport: postLayoutReport,
            sourceReportPath: metricReportRef.path
        )
        let summaryURL = verificationDirectory.appending(path: "simulation-summary.json")
        try packageStore.writeJSON(summary, to: summaryURL, forProjectAt: projectRoot)
        let artifacts = [
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: projectRoot,
                artifactID: "planning-simulation-summary",
                kind: .report,
                format: .json,
                producedByRunID: runID
            ),
        ]
        for artifact in artifacts {
            try packageStore.upsertRunArtifact(artifact, runID: runID, inProjectAt: projectRoot)
        }
        let diagnostics = simulationMetricDiagnostics(from: summary)
        return GateExecutionEvaluation(
            gateResult: XcircuitePlanVerificationGateResult(
                gateID: "simulation-metric-gate",
                required: required,
                status: summary.status,
                sourceStepIDs: sourceStepIDs,
                diagnostics: diagnostics
            ),
            artifactRefs: artifacts
        )
    }

    func simulationMetricArtifactRefs(
        netlistURL: URL,
        waveformURL: URL,
        measurementsURL: URL,
        summaryURL: URL,
        runID: String,
        projectRoot: URL
    ) throws -> [XcircuiteFileReference] {
        [
            try artifactBuilder.reference(
                for: netlistURL,
                projectRoot: projectRoot,
                artifactID: "planning-simulation-netlist",
                kind: .netlist,
                format: netlistFileFormat(from: netlistURL),
                producedByRunID: runID
            ),
            try artifactBuilder.reference(
                for: waveformURL,
                projectRoot: projectRoot,
                artifactID: "planning-simulation-waveform",
                kind: .waveform,
                format: .csv,
                producedByRunID: runID
            ),
            try artifactBuilder.reference(
                for: measurementsURL,
                projectRoot: projectRoot,
                artifactID: "planning-simulation-measurements",
                kind: .measurement,
                format: .json,
                producedByRunID: runID
            ),
            try artifactBuilder.reference(
                for: summaryURL,
                projectRoot: projectRoot,
                artifactID: "planning-simulation-summary",
                kind: .report,
                format: .json,
                producedByRunID: runID
            ),
        ]
    }

    func simulationMetricReport(
        outcome: SimulationStageOutcome,
        expectations: [SimulationMeasurementExpectation]
    ) -> XcircuiteSimulationMetricReport {
        let measured = Dictionary(
            outcome.measurements.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var diagnostics = [
            XcircuiteSimulationMetricReport.Diagnostic(
                severity: "info",
                code: "SIMULATION_ANALYSIS",
                message: "ran \(outcome.analysisLabel) with \(outcome.measurements.count) measurement(s)"
            ),
        ]
        var verdicts: [XcircuiteSimulationMetricReport.MeasurementVerdict] = []
        guard !expectations.isEmpty else {
            diagnostics.append(XcircuiteSimulationMetricReport.Diagnostic(
                severity: "error",
                code: "SIMULATION_EXPECTATIONS_EMPTY",
                message: "simulation metric gate requires at least one measurement expectation"
            ))
            return XcircuiteSimulationMetricReport(
                status: "failed",
                source: "corespice",
                analysisLabel: outcome.analysisLabel,
                expectations: expectations,
                measurements: outcome.measurements,
                verdicts: verdicts,
                diagnostics: diagnostics
            )
        }
        for expectation in expectations {
            guard let measurement = measured[expectation.name.lowercased()] else {
                verdicts.append(XcircuiteSimulationMetricReport.MeasurementVerdict(
                    name: expectation.name,
                    status: "missing",
                    value: nil,
                    target: expectation.target,
                    tolerance: expectation.tolerance
                ))
                diagnostics.append(XcircuiteSimulationMetricReport.Diagnostic(
                    severity: "error",
                    code: "SIMULATION_MEASUREMENT_MISSING",
                    message: "expected measurement '\(expectation.name)' was not produced"
                ))
                continue
            }
            let status = abs(measurement.value - expectation.target) <= expectation.tolerance
                ? "passed"
                : "failed"
            verdicts.append(XcircuiteSimulationMetricReport.MeasurementVerdict(
                name: expectation.name,
                status: status,
                value: measurement.value,
                target: expectation.target,
                tolerance: expectation.tolerance
            ))
            if status == "passed" {
                diagnostics.append(XcircuiteSimulationMetricReport.Diagnostic(
                    severity: "info",
                    code: "SIMULATION_MEASUREMENT_OK",
                    message: "'\(expectation.name)' = \(measurement.value) within \(expectation.target) ± \(expectation.tolerance)"
                ))
            } else {
                diagnostics.append(XcircuiteSimulationMetricReport.Diagnostic(
                    severity: "error",
                    code: "SIMULATION_MEASUREMENT_OUT_OF_TOLERANCE",
                    message: "'\(expectation.name)' = \(measurement.value), expected \(expectation.target) ± \(expectation.tolerance)"
                ))
            }
        }
        let status = verdicts.allSatisfy { $0.status == "passed" } ? "passed" : "failed"
        return XcircuiteSimulationMetricReport(
            status: status,
            source: "corespice",
            analysisLabel: outcome.analysisLabel,
            expectations: expectations,
            measurements: outcome.measurements,
            verdicts: verdicts,
            diagnostics: diagnostics
        )
    }

    func simulationMetricReport(
        postLayoutReport: PostLayoutComparisonReport,
        sourceReportPath: String?
    ) -> XcircuiteSimulationMetricReport {
        var diagnostics = postLayoutReport.diagnostics.map {
            XcircuiteSimulationMetricReport.Diagnostic(
                severity: "warning",
                code: "POST_LAYOUT_COMPARISON_DIAGNOSTIC",
                message: $0
            )
        }
        diagnostics.append(contentsOf: postLayoutReport.gateViolations.map {
            XcircuiteSimulationMetricReport.Diagnostic(
                severity: "error",
                code: "POST_LAYOUT_COMPARISON_GATE_VIOLATION",
                message: $0
            )
        })
        let status = postLayoutReport.gateStatus == "passed" && postLayoutReport.gateViolations.isEmpty
            ? "passed"
            : "failed"
        if status == "failed" && diagnostics.isEmpty {
            diagnostics.append(XcircuiteSimulationMetricReport.Diagnostic(
                severity: "error",
                code: "SIMULATION_METRIC_REPORT_FAILED",
                message: "Post-layout metric report finished with gate status \(postLayoutReport.gateStatus)."
            ))
        }
        return XcircuiteSimulationMetricReport(
            status: status,
            source: "post-layout-comparison",
            sourceReportPath: sourceReportPath,
            expectations: [],
            measurements: [],
            verdicts: [],
            diagnostics: diagnostics
        )
    }

    func simulationMetricDiagnostics(
        from summary: XcircuiteSimulationMetricReport
    ) -> [XcircuitePlanVerificationDiagnostic] {
        summary.diagnostics.map {
            XcircuitePlanVerificationDiagnostic(
                severity: $0.severity,
                code: $0.code,
                message: $0.message,
                gateID: "simulation-metric-gate"
            )
        }
    }

    func simulationMetricExecutionSpec(
        from plan: XcircuiteCandidatePlan,
        problem: XcircuiteCircuitPlanningProblem
    ) throws -> SimulationMetricExecutionSpec? {
        let hint = try simulationInputHint(from: plan)
        let references = problem.sourceRefs + problem.initialStateRefs
        let netlistRef = resolvableReference(planningReference(
            explicitID: hint.netlistRefID ?? hint.netlistRef,
            fallbackIDs: ["simulation-netlist-ref", "post-layout-netlist-ref", "source-netlist-ref", "schematic-netlist-ref"],
            fallbackKinds: ["simulation-netlist", "post-layout-netlist", "source-netlist", "schematic-netlist", "netlist"],
            references: references
        ))
        let metricReportRef = resolvableReference(planningReference(
            explicitID: hint.metricReportRefID ?? hint.metricReportRef,
            fallbackIDs: ["post-layout-metric-report", "metric-report"],
            fallbackKinds: ["post-layout-metric-report", "metric-report", "simulation-metric-report"],
            references: references
        ))
        let expectations = hint.measurementExpectations ?? hint.expectations ?? []
        if !expectations.isEmpty {
            guard let netlistRef else {
                return nil
            }
            return SimulationMetricExecutionSpec(
                netlistRef: netlistRef,
                metricReportRef: metricReportRef,
                expectations: expectations
            )
        }
        guard let metricReportRef else {
            return nil
        }
        return SimulationMetricExecutionSpec(
            netlistRef: netlistRef,
            metricReportRef: metricReportRef,
            expectations: expectations
        )
    }

    func simulationInputHint(from plan: XcircuiteCandidatePlan) throws -> CandidatePlanSimulationInputHint {
        var hint = CandidatePlanSimulationInputHint()
        for step in plan.steps.sorted(by: { $0.order < $1.order })
            where step.verificationGates.contains("simulation-metric-gate") {
            if let decoded: CandidatePlanSimulationInputHint = try decodedHint("simulationInputs", from: step) {
                hint.merge(decoded)
            }
            let measurementExpectations: [SimulationMeasurementExpectation]? =
                try decodedHint("measurementExpectations", from: step)
                    ?? decodedHint("simulationExpectations", from: step)
                    ?? decodedHint("expectations", from: step)
            hint.merge(CandidatePlanSimulationInputHint(
                netlistRef: stringHint("netlistRef", step: step)
                    ?? stringHint("sourceNetlistRef", step: step)
                    ?? stringHint("simulationNetlistRef", step: step),
                netlistRefID: stringHint("netlistRefID", step: step)
                    ?? stringHint("sourceNetlistRefID", step: step)
                    ?? stringHint("simulationNetlistRefID", step: step),
                metricReportRef: stringHint("metricReportRef", step: step)
                    ?? stringHint("postLayoutMetricReportRef", step: step),
                metricReportRefID: stringHint("metricReportRefID", step: step)
                    ?? stringHint("postLayoutMetricReportRefID", step: step),
                expectations: nil,
                measurementExpectations: measurementExpectations
            ))
        }
        return hint
    }
}
