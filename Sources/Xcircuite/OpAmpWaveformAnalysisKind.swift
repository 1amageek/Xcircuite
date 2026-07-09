import Foundation

public enum OpAmpWaveformAnalysisKind: String, Sendable, Hashable, Codable, CaseIterable {
    case acOpenLoop = "ac-open-loop"
    case transientPositiveStep = "tran-positive-step"
    case transientNegativeStep = "tran-negative-step"
    case noiseInputReferred = "noise-input-referred"
}
