import Foundation

public enum XcircuiteGeneratedLayoutSignoffStageFamily: String, Codable, Sendable, Hashable, CaseIterable {
    case layout
    case drc
    case lvs
    case pex
    case simulation
    case postLayout = "post-layout"
    case other
}
