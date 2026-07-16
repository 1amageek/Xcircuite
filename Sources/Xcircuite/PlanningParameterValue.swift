import Foundation
import PEXEngine

public enum PlanningParameterValue: Sendable, Hashable, Codable {
    case boolean(Bool)
    case scalar(Double)
    case text(String)
    case textList([String])
    case scalarList([Double])
    case parameterAssignments([XcircuiteParameterAssignment])
    case parameterBounds([XcircuiteParameterBound])
    case region(PlanningRegion)
    case lvsInputs(PlanningLVSInputs)
    case pexInputs(PlanningPEXInputs)
    case simulationInputs(PlanningSimulationInputs)
    case drcRules([PlanningDRCRule])
    case drcExportSpec(LayoutCommandDRCExportSpec)
    case drcViaDefinitions([LayoutCommandDRCViaDefinition])
    case pexOptions(PEXRunOptions)
    case pexEnvironmentOverrides([String: String])
    case equivalentPinGroups([[Int]])
    case standardLayoutExports([LayoutCommandStandardLayoutExportSpec])
}
