import Foundation

public struct OpAmpSimulationDeckRunner: Sendable {
    private let engine: any SimulationExecuting

    public init(engine: any SimulationExecuting = CoreSpiceSimulationEngine()) {
        self.engine = engine
    }

    public func run(
        _ deckSet: OpAmpSimulationDeckSet,
        outputVariable: String = "V(vout)"
    ) async -> OpAmpSimulationDeckRunResult {
        var deckResults: [OpAmpSimulationDeckExecutionReport.DeckResult] = []
        var waveforms: [OpAmpSimulationDeckRunResult.DeckWaveform] = []
        var extractions: [OpAmpSimulationMetricExtraction] = []

        for deck in deckSet.decks {
            guard deck.executionContract.coreSpiceEngineRunnable else {
                deckResults.append(blockedResult(for: deck))
                continue
            }

            do {
                let outcome = try await engine.run(
                    netlistSource: deck.netlist,
                    fileName: "\(deck.deckID).cir"
                )
                waveforms.append(.init(
                    deckID: deck.deckID,
                    analysisKind: outcome.analysisLabel,
                    waveformCSV: outcome.waveformCSV
                ))
                let result = deckResult(
                    deck: deck,
                    outcome: outcome,
                    outputVariable: outputVariable,
                    extractions: &extractions
                )
                deckResults.append(result)
            } catch {
                deckResults.append(.init(
                    deckID: deck.deckID,
                    analysisKind: deck.analysisKind,
                    status: "failed",
                    executionStatus: "failed",
                    directMetricIDs: deck.directMetricIDs,
                    postProcessingMetricIDs: deck.postProcessingMetricIDs,
                    diagnostics: [
                        .init(
                            severity: .error,
                            code: "opamp.simulation-deck-run.execution-failed",
                            message: "Simulation deck \(deck.deckID) failed CoreSpice execution: \(error.localizedDescription)",
                            suggestedActions: ["inspect-simulation-deck", "run-deck-with-corespice"]
                        ),
                    ]
                ))
            }
        }

        let mergedExtraction: OpAmpSimulationMetricExtraction?
        var diagnostics = deckSet.diagnostics
        if extractions.isEmpty {
            mergedExtraction = nil
            diagnostics.append(.init(
                severity: .warning,
                code: "opamp.simulation-deck-run.no-metrics",
                message: "No op-amp metrics were extracted from the simulation deck set.",
                suggestedActions: ["inspect-simulation-deck-results", "add-direct-measurements-or-waveform-post-processing"]
            ))
        } else {
            do {
                mergedExtraction = try OpAmpSimulationMetricExtractionMerger().merge(
                    extractions,
                    sourceKind: "xcircuite-opamp-simulation-deck-run"
                )
            } catch {
                mergedExtraction = nil
                diagnostics.append(.init(
                    severity: .error,
                    code: "opamp.simulation-deck-run.metric-merge-failed",
                    message: "Simulation deck metric extraction merge failed: \(error.localizedDescription)",
                    suggestedActions: ["inspect-simulation-metric-extractions"]
                ))
            }
        }

        let report = OpAmpSimulationDeckExecutionReport(
            specID: deckSet.specID,
            topologyKind: deckSet.topologyKind,
            status: reportStatus(deckResults: deckResults, diagnostics: diagnostics),
            deckResults: deckResults,
            mergedMetricExtraction: mergedExtraction,
            diagnostics: diagnostics
        )
        return OpAmpSimulationDeckRunResult(report: report, waveforms: waveforms)
    }

    private func deckResult(
        deck: OpAmpSimulationDeckSet.Deck,
        outcome: SimulationStageOutcome,
        outputVariable: String,
        extractions: inout [OpAmpSimulationMetricExtraction]
    ) -> OpAmpSimulationDeckExecutionReport.DeckResult {
        var diagnostics: [OpAmpDesignDiagnostic] = []
        let directExtraction = directMetricExtraction(deck: deck, outcome: outcome)
        if let directExtraction {
            diagnostics.append(contentsOf: directExtraction.diagnostics)
            extractions.append(directExtraction)
            diagnostics.append(contentsOf: missingMetricDiagnostics(
                required: deck.directMetricIDs,
                observed: directExtraction.observedMetrics,
                code: "opamp.simulation-deck-run.direct-metrics-missing",
                suggestedActions: ["inspect-direct-measurements", "regenerate-opamp-simulation-decks"]
            ))
        }

        let waveformExtraction = waveformMetricExtraction(
            deck: deck,
            outcome: outcome,
            outputVariable: outputVariable,
            diagnostics: &diagnostics
        )
        if let waveformExtraction {
            extractions.append(waveformExtraction)
            diagnostics.append(contentsOf: missingMetricDiagnostics(
                required: deck.postProcessingMetricIDs,
                observed: waveformExtraction.observedMetrics,
                code: "opamp.simulation-deck-run.waveform-metrics-missing",
                suggestedActions: ["inspect-waveform-post-processing", "adjust-output-variable"]
            ))
        }

        let status = diagnostics.contains { $0.severity == .error } ? "failed" : "passed"
        return .init(
            deckID: deck.deckID,
            analysisKind: outcome.analysisLabel,
            status: status,
            executionStatus: "passed",
            measurementCount: outcome.measurements.count,
            waveformVariableCount: waveformVariableCount(outcome.waveformCSV),
            directMetricIDs: deck.directMetricIDs,
            postProcessingMetricIDs: deck.postProcessingMetricIDs,
            directMetricExtraction: directExtraction,
            waveformMetricExtraction: waveformExtraction,
            diagnostics: diagnostics
        )
    }

    private func directMetricExtraction(
        deck: OpAmpSimulationDeckSet.Deck,
        outcome: SimulationStageOutcome
    ) -> OpAmpSimulationMetricExtraction? {
        guard !deck.directMetricIDs.isEmpty else {
            return nil
        }
        return OpAmpSimulationMetricExtractor().extract(
            measurements: outcome.measurements,
            sourceKind: "xcircuite-opamp-simulation-direct-measurements",
            sourceStatus: "passed",
            sourceAnalysisLabel: deck.deckID
        )
    }

    private func waveformMetricExtraction(
        deck: OpAmpSimulationDeckSet.Deck,
        outcome: SimulationStageOutcome,
        outputVariable: String,
        diagnostics: inout [OpAmpDesignDiagnostic]
    ) -> OpAmpSimulationMetricExtraction? {
        guard !deck.postProcessingMetricIDs.isEmpty || deck.executionContract.waveformPostProcessingRequired else {
            return nil
        }
        guard let analysisKind = waveformAnalysisKind(for: deck) else {
            diagnostics.append(.init(
                severity: .error,
                code: "opamp.simulation-deck-run.unsupported-waveform-analysis",
                message: "Simulation deck \(deck.deckID) does not map to a supported op-amp waveform metric analysis.",
                suggestedActions: ["inspect-simulation-deck-analysis-kind"]
            ))
            return nil
        }

        do {
            let extraction = try OpAmpWaveformMetricExtractor().extract(
                analysisKind: analysisKind,
                waveformCSV: outcome.waveformCSV,
                outputVariable: outputVariable,
                sourceKind: "xcircuite-opamp-simulation-waveform"
            )
            diagnostics.append(contentsOf: extraction.diagnostics)
            return extraction
        } catch {
            diagnostics.append(.init(
                severity: .error,
                code: "opamp.simulation-deck-run.waveform-metric-extraction-failed",
                message: "Simulation deck \(deck.deckID) waveform metric extraction failed: \(error.localizedDescription)",
                relatedMetricIDs: deck.postProcessingMetricIDs,
                suggestedActions: ["inspect-waveform-csv", "adjust-output-variable"]
            ))
            return nil
        }
    }

    private func missingMetricDiagnostics(
        required: [OpAmpMetricID],
        observed: [OpAmpEstimatedMetric],
        code: String,
        suggestedActions: [String]
    ) -> [OpAmpDesignDiagnostic] {
        let observedIDs = Set(observed.map(\.metricID))
        let missing = required.filter { !observedIDs.contains($0) }
        guard !missing.isEmpty else {
            return []
        }
        return [
            .init(
                severity: .error,
                code: code,
                message: "Simulation deck run missed required op-amp metric(s): \(missing.map(\.rawValue).joined(separator: ", ")).",
                relatedMetricIDs: missing,
                suggestedActions: suggestedActions
            ),
        ]
    }

    private func waveformAnalysisKind(for deck: OpAmpSimulationDeckSet.Deck) -> OpAmpWaveformAnalysisKind? {
        if let kind = OpAmpWaveformAnalysisKind(rawValue: deck.deckID) {
            return kind
        }
        return OpAmpWaveformAnalysisKind(rawValue: deck.analysisKind)
    }

    private func blockedResult(
        for deck: OpAmpSimulationDeckSet.Deck
    ) -> OpAmpSimulationDeckExecutionReport.DeckResult {
        .init(
            deckID: deck.deckID,
            analysisKind: deck.analysisKind,
            status: "blocked",
            executionStatus: "blocked",
            directMetricIDs: deck.directMetricIDs,
            postProcessingMetricIDs: deck.postProcessingMetricIDs,
            diagnostics: [
                .init(
                    severity: .warning,
                    code: "opamp.simulation-deck-run.execution-not-supported",
                    message: "Simulation deck \(deck.deckID) is not marked runnable by CoreSpiceSimulationEngine.",
                    suggestedActions: ["inspect-simulation-deck-execution-contract"]
                ),
            ]
        )
    }

    private func reportStatus(
        deckResults: [OpAmpSimulationDeckExecutionReport.DeckResult],
        diagnostics: [OpAmpDesignDiagnostic]
    ) -> String {
        if deckResults.contains(where: { $0.status == "failed" }) ||
            diagnostics.contains(where: { $0.severity == .error }) {
            return "failed"
        }
        if deckResults.contains(where: { $0.status == "blocked" }) {
            return "blocked"
        }
        if diagnostics.contains(where: { $0.severity == .warning }) {
            return "warning"
        }
        return "passed"
    }

    private func waveformVariableCount(_ csv: String) -> Int {
        guard let header = csv.split(separator: "\n", omittingEmptySubsequences: false).first else {
            return 0
        }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false)
        return max(columns.count - 1, 0)
    }
}
