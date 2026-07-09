import Foundation

public struct OpAmpSimulationDeckValidationReport: Sendable, Hashable, Codable {
    public struct DeckResult: Sendable, Hashable, Codable {
        public var deckID: String
        public var analysisKind: String?
        public var status: String
        public var parseStatus: String
        public var executionStatus: String?
        public var expectedMeasurementNames: [String]
        public var producedMeasurementNames: [String]
        public var directMetricIDs: [OpAmpMetricID]
        public var postProcessingMetricIDs: [OpAmpMetricID]
        public var executionContract: OpAmpSimulationDeckExecutionContract?
        public var diagnostic: OpAmpDesignDiagnostic?

        public init(
            deckID: String,
            analysisKind: String? = nil,
            status: String,
            parseStatus: String = "not-run",
            executionStatus: String? = nil,
            expectedMeasurementNames: [String] = [],
            producedMeasurementNames: [String] = [],
            directMetricIDs: [OpAmpMetricID] = [],
            postProcessingMetricIDs: [OpAmpMetricID] = [],
            executionContract: OpAmpSimulationDeckExecutionContract? = nil,
            diagnostic: OpAmpDesignDiagnostic? = nil
        ) {
            self.deckID = deckID
            self.analysisKind = analysisKind
            self.status = status
            self.parseStatus = parseStatus
            self.executionStatus = executionStatus
            self.expectedMeasurementNames = expectedMeasurementNames
            self.producedMeasurementNames = producedMeasurementNames
            self.directMetricIDs = directMetricIDs
            self.postProcessingMetricIDs = postProcessingMetricIDs
            self.executionContract = executionContract
            self.diagnostic = diagnostic
        }
    }

    public var schemaVersion: Int
    public var validationMode: OpAmpSimulationDeckValidationMode
    public var status: String
    public var deckResults: [DeckResult]

    public init(
        schemaVersion: Int = 2,
        validationMode: OpAmpSimulationDeckValidationMode = .parseOnly,
        status: String,
        deckResults: [DeckResult]
    ) {
        self.schemaVersion = schemaVersion
        self.validationMode = validationMode
        self.status = status
        self.deckResults = deckResults
    }
}
