struct WaveformCSVAlignedPoint: Sendable, Hashable {
    var referenceIndex: Int
    var candidateLowerIndex: Int
    var candidateUpperIndex: Int
    var candidateFraction: Double

    init(
        referenceIndex: Int,
        candidateLowerIndex: Int,
        candidateUpperIndex: Int,
        candidateFraction: Double
    ) {
        self.referenceIndex = referenceIndex
        self.candidateLowerIndex = candidateLowerIndex
        self.candidateUpperIndex = candidateUpperIndex
        self.candidateFraction = candidateFraction
    }
}
