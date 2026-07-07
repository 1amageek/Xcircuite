import Foundation

public struct XcircuiteRepairPlanFormulationCompilationRequest: Sendable, Hashable {
    public var runID: String
    public var formulation: XcircuiteRepairPlanFormulation?
    public var formulationPath: String?
    public var problemID: String?

    public init(
        runID: String,
        formulation: XcircuiteRepairPlanFormulation? = nil,
        formulationPath: String? = nil,
        problemID: String? = nil
    ) {
        self.runID = runID
        self.formulation = formulation
        self.formulationPath = formulationPath
        self.problemID = problemID
    }
}
