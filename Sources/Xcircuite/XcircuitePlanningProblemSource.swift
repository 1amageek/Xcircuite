import Foundation

public enum XcircuitePlanningProblemSource: String, Codable, Sendable, Hashable {
    case drcSummary = "drc-summary"
    case lvsSummary = "lvs-summary"
    case pexSummary = "pex-summary"
}
