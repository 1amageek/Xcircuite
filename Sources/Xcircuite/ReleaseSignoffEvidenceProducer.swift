import Foundation

public enum ReleaseSignoffEvidenceProducer: String, Sendable, Hashable, Codable {
    case logicSimulation
    case logicSynthesisEquivalence
    case rtlVerification
    case dft
    case powerIntent
    case staticTiming
    case signalIntegrity
    case designRuleCheck
    case layoutVersusSchematic
    case parasiticExtraction
    case physicalDesign
    case electricalSignoff
}
