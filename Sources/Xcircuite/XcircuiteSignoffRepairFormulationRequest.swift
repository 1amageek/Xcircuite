import Foundation

public struct XcircuiteSignoffRepairFormulationRequest: Sendable, Hashable {
    public var runID: String
    public var drcRepairHintPath: String?
    public var lvsRepairHintPath: String?
    public var formulationID: String?
    public var intentID: String?
    public var intent: String?
    public var problemID: String?

    public init(
        runID: String,
        drcRepairHintPath: String? = nil,
        lvsRepairHintPath: String? = nil,
        formulationID: String? = nil,
        intentID: String? = nil,
        intent: String? = nil,
        problemID: String? = nil
    ) {
        self.runID = runID
        self.drcRepairHintPath = drcRepairHintPath
        self.lvsRepairHintPath = lvsRepairHintPath
        self.formulationID = formulationID
        self.intentID = intentID
        self.intent = intent
        self.problemID = problemID
    }
}
