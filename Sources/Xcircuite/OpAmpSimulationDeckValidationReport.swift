import Foundation

public struct OpAmpSimulationDeckValidationReport: Sendable, Hashable, Codable {
    public struct DeckResult: Sendable, Hashable, Codable {
        public var deckID: String
        public var status: String
        public var diagnostic: OpAmpDesignDiagnostic?

        public init(
            deckID: String,
            status: String,
            diagnostic: OpAmpDesignDiagnostic? = nil
        ) {
            self.deckID = deckID
            self.status = status
            self.diagnostic = diagnostic
        }
    }

    public var schemaVersion: Int
    public var status: String
    public var deckResults: [DeckResult]

    public init(
        schemaVersion: Int = 1,
        status: String,
        deckResults: [DeckResult]
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.deckResults = deckResults
    }
}
