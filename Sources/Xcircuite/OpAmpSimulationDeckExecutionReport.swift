import Foundation

public struct OpAmpSimulationDeckExecutionReport: Sendable, Hashable, Codable {
    public struct DeckResult: Sendable, Hashable, Codable {
        public var deckID: String
        public var analysisKind: String
        public var status: String
        public var executionStatus: String
        public var measurementCount: Int
        public var waveformVariableCount: Int
        public var directMetricIDs: [OpAmpMetricID]
        public var postProcessingMetricIDs: [OpAmpMetricID]
        public var directMetricExtraction: OpAmpSimulationMetricExtraction?
        public var waveformMetricExtraction: OpAmpSimulationMetricExtraction?
        public var diagnostics: [OpAmpDesignDiagnostic]

        public init(
            deckID: String,
            analysisKind: String,
            status: String,
            executionStatus: String,
            measurementCount: Int = 0,
            waveformVariableCount: Int = 0,
            directMetricIDs: [OpAmpMetricID] = [],
            postProcessingMetricIDs: [OpAmpMetricID] = [],
            directMetricExtraction: OpAmpSimulationMetricExtraction? = nil,
            waveformMetricExtraction: OpAmpSimulationMetricExtraction? = nil,
            diagnostics: [OpAmpDesignDiagnostic] = []
        ) {
            self.deckID = deckID
            self.analysisKind = analysisKind
            self.status = status
            self.executionStatus = executionStatus
            self.measurementCount = measurementCount
            self.waveformVariableCount = waveformVariableCount
            self.directMetricIDs = directMetricIDs
            self.postProcessingMetricIDs = postProcessingMetricIDs
            self.directMetricExtraction = directMetricExtraction
            self.waveformMetricExtraction = waveformMetricExtraction
            self.diagnostics = diagnostics
        }
    }

    public var schemaVersion: Int
    public var specID: String
    public var topologyKind: OpAmpTopologyKind
    public var status: String
    public var deckResults: [DeckResult]
    public var mergedMetricExtraction: OpAmpSimulationMetricExtraction?
    public var diagnostics: [OpAmpDesignDiagnostic]

    public init(
        schemaVersion: Int = 1,
        specID: String,
        topologyKind: OpAmpTopologyKind,
        status: String,
        deckResults: [DeckResult],
        mergedMetricExtraction: OpAmpSimulationMetricExtraction? = nil,
        diagnostics: [OpAmpDesignDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.specID = specID
        self.topologyKind = topologyKind
        self.status = status
        self.deckResults = deckResults
        self.mergedMetricExtraction = mergedMetricExtraction
        self.diagnostics = diagnostics
    }
}
