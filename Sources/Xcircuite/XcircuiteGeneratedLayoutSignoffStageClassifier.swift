import DesignFlowKernel
import Foundation

public struct XcircuiteGeneratedLayoutSignoffStageClassifier: Sendable {
    public init() {}

    public func family(for stage: FlowStageResult) -> XcircuiteGeneratedLayoutSignoffStageFamily {
        let gateIDs = Set(stage.gates.map(\.gateID))
        if gateIDs.contains("layout-command") {
            return .layout
        }
        if gateIDs.contains("drc") {
            return .drc
        }
        if gateIDs.contains("lvs") {
            return .lvs
        }
        if gateIDs.contains("pex") {
            return .pex
        }
        if gateIDs.contains("simulation") {
            return .simulation
        }
        if gateIDs.contains("post-layout-comparison") || gateIDs.contains("comparison") {
            return .postLayout
        }
        return .other
    }
}
