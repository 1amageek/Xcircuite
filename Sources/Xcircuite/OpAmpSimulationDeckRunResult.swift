import Foundation

public struct OpAmpSimulationDeckRunResult: Sendable, Hashable {
    public struct DeckWaveform: Sendable, Hashable {
        public var deckID: String
        public var analysisKind: String
        public var waveformCSV: String

        public init(deckID: String, analysisKind: String, waveformCSV: String) {
            self.deckID = deckID
            self.analysisKind = analysisKind
            self.waveformCSV = waveformCSV
        }
    }

    public var report: OpAmpSimulationDeckExecutionReport
    public var waveforms: [DeckWaveform]

    public init(
        report: OpAmpSimulationDeckExecutionReport,
        waveforms: [DeckWaveform]
    ) {
        self.report = report
        self.waveforms = waveforms
    }
}
