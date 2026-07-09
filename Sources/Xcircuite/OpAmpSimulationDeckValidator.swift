import CoreSpiceIO
import Foundation

public struct OpAmpSimulationDeckValidator: Sendable {
    public init() {}

    public func validate(_ deckSet: OpAmpSimulationDeckSet) async -> OpAmpSimulationDeckValidationReport {
        var results: [OpAmpSimulationDeckValidationReport.DeckResult] = []
        for deck in deckSet.decks {
            do {
                _ = try await SPICEIO.parse(deck.netlist, fileName: "\(deck.deckID).cir").get()
                results.append(.init(deckID: deck.deckID, status: "passed"))
            } catch {
                results.append(.init(
                    deckID: deck.deckID,
                    status: "failed",
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
            status: results.allSatisfy { $0.status == "passed" } ? "passed" : "failed",
            deckResults: results
        )
    }
}
