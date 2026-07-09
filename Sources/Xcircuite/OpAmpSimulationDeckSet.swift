import Foundation

public struct OpAmpSimulationDeckSet: Sendable, Hashable, Codable {
    public struct Deck: Sendable, Hashable, Codable {
        public var deckID: String
        public var analysisKind: String
        public var title: String
        public var netlist: String
        public var directMetricIDs: [OpAmpMetricID]
        public var postProcessingMetricIDs: [OpAmpMetricID]
        public var measurementNames: [String]
        public var notes: [String]

        public init(
            deckID: String,
            analysisKind: String,
            title: String,
            netlist: String,
            directMetricIDs: [OpAmpMetricID] = [],
            postProcessingMetricIDs: [OpAmpMetricID] = [],
            measurementNames: [String] = [],
            notes: [String] = []
        ) {
            self.deckID = deckID
            self.analysisKind = analysisKind
            self.title = title
            self.netlist = netlist
            self.directMetricIDs = directMetricIDs
            self.postProcessingMetricIDs = postProcessingMetricIDs
            self.measurementNames = measurementNames
            self.notes = notes
        }
    }

    public var schemaVersion: Int
    public var specID: String
    public var topologyKind: OpAmpTopologyKind
    public var decks: [Deck]
    public var diagnostics: [OpAmpDesignDiagnostic]

    public init(
        schemaVersion: Int = 1,
        specID: String,
        topologyKind: OpAmpTopologyKind,
        decks: [Deck],
        diagnostics: [OpAmpDesignDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.specID = specID
        self.topologyKind = topologyKind
        self.decks = decks
        self.diagnostics = diagnostics
    }
}
