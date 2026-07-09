import CoreSpiceIO
import Foundation

public struct OpAmpSimulationDeckValidator: Sendable {
    public init() {}

    public func validate(
        _ deckSet: OpAmpSimulationDeckSet,
        mode: OpAmpSimulationDeckValidationMode = .parseOnly
    ) async -> OpAmpSimulationDeckValidationReport {
        var results: [OpAmpSimulationDeckValidationReport.DeckResult] = []
        for deck in deckSet.decks {
            do {
                _ = try await SPICEIO.parse(deck.netlist, fileName: "\(deck.deckID).cir").get()
                if mode == .executeCoreSpice {
                    results.append(await execute(deck))
                } else {
                    results.append(.init(
                        deckID: deck.deckID,
                        analysisKind: deck.analysisKind,
                        status: "passed",
                        parseStatus: "passed",
                        expectedMeasurementNames: deck.measurementNames,
                        directMetricIDs: deck.directMetricIDs,
                        postProcessingMetricIDs: deck.postProcessingMetricIDs,
                        executionContract: deck.executionContract
                    ))
                }
            } catch {
                results.append(.init(
                    deckID: deck.deckID,
                    analysisKind: deck.analysisKind,
                    status: "failed",
                    parseStatus: "failed",
                    expectedMeasurementNames: deck.measurementNames,
                    directMetricIDs: deck.directMetricIDs,
                    postProcessingMetricIDs: deck.postProcessingMetricIDs,
                    executionContract: deck.executionContract,
                    diagnostic: .init(
                        severity: .error,
                        code: "opamp.simulation-deck.parse-failed",
                        message: "Simulation deck \(deck.deckID) failed SPICE parsing: \(error.localizedDescription)",
                        suggestedActions: ["inspect-simulation-deck", "regenerate-opamp-simulation-decks"]
                    )
                ))
            }
        }
        return OpAmpSimulationDeckValidationReport(
            validationMode: mode,
            status: results.allSatisfy { $0.status == "passed" } ? "passed" : "failed",
            deckResults: results
        )
    }

    private func execute(
        _ deck: OpAmpSimulationDeckSet.Deck
    ) async -> OpAmpSimulationDeckValidationReport.DeckResult {
        guard deck.executionContract.coreSpiceEngineRunnable else {
            return .init(
                deckID: deck.deckID,
                analysisKind: deck.analysisKind,
                status: "blocked",
                parseStatus: "passed",
                executionStatus: "blocked",
                expectedMeasurementNames: deck.measurementNames,
                directMetricIDs: deck.directMetricIDs,
                postProcessingMetricIDs: deck.postProcessingMetricIDs,
                executionContract: deck.executionContract,
                diagnostic: .init(
                    severity: .warning,
                    code: "opamp.simulation-deck.execution-not-supported",
                    message: "Simulation deck \(deck.deckID) is not marked runnable by CoreSpiceSimulationEngine.",
                    suggestedActions: ["inspect-simulation-deck-execution-contract"]
                )
            )
        }

        do {
            let outcome = try await CoreSpiceSimulationEngine().run(
                netlistSource: deck.netlist,
                fileName: "\(deck.deckID).cir"
            )
            let producedMeasurementNames = outcome.measurements.map(\.name)
            let missing = missingMeasurements(
                expected: deck.measurementNames,
                produced: producedMeasurementNames
            )
            guard missing.isEmpty || !deck.executionContract.directMeasurementsRequired else {
                return .init(
                    deckID: deck.deckID,
                    analysisKind: deck.analysisKind,
                    status: "failed",
                    parseStatus: "passed",
                    executionStatus: "failed",
                    expectedMeasurementNames: deck.measurementNames,
                    producedMeasurementNames: producedMeasurementNames,
                    directMetricIDs: deck.directMetricIDs,
                    postProcessingMetricIDs: deck.postProcessingMetricIDs,
                    executionContract: deck.executionContract,
                    diagnostic: .init(
                        severity: .error,
                        code: "opamp.simulation-deck.measurements-missing",
                        message: "Simulation deck \(deck.deckID) executed but missed required measurement(s): \(missing.joined(separator: ", ")).",
                        suggestedActions: ["inspect-measurement-names", "regenerate-opamp-simulation-decks"]
                    )
                )
            }
            return .init(
                deckID: deck.deckID,
                analysisKind: outcome.analysisLabel,
                status: "passed",
                parseStatus: "passed",
                executionStatus: "passed",
                expectedMeasurementNames: deck.measurementNames,
                producedMeasurementNames: producedMeasurementNames,
                directMetricIDs: deck.directMetricIDs,
                postProcessingMetricIDs: deck.postProcessingMetricIDs,
                executionContract: deck.executionContract
            )
        } catch {
            return .init(
                deckID: deck.deckID,
                analysisKind: deck.analysisKind,
                status: "failed",
                parseStatus: "passed",
                executionStatus: "failed",
                expectedMeasurementNames: deck.measurementNames,
                directMetricIDs: deck.directMetricIDs,
                postProcessingMetricIDs: deck.postProcessingMetricIDs,
                executionContract: deck.executionContract,
                diagnostic: .init(
                    severity: .error,
                    code: "opamp.simulation-deck.execution-failed",
                    message: "Simulation deck \(deck.deckID) failed CoreSpice execution: \(error.localizedDescription)",
                    suggestedActions: ["run-deck-with-corespice", "inspect-simulation-deck", "regenerate-opamp-simulation-decks"]
                )
            )
        }
    }

    private func missingMeasurements(expected: [String], produced: [String]) -> [String] {
        let producedSet = Set(produced.map(normalizedMeasurementName))
        return expected.filter { !producedSet.contains(normalizedMeasurementName($0)) }
    }

    private func normalizedMeasurementName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
