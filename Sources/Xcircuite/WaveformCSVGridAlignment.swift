struct WaveformCSVGridAlignment: Sendable, Hashable {
    var points: [WaveformCSVAlignedPoint]
    var usesInterpolation: Bool
    var diagnostics: [String]

    init(
        points: [WaveformCSVAlignedPoint],
        usesInterpolation: Bool,
        diagnostics: [String]
    ) {
        self.points = points
        self.usesInterpolation = usesInterpolation
        self.diagnostics = diagnostics
    }
}
