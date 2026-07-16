import RTLVerificationCore
import ToolQualification

public extension XcircuiteFlowStageExecutorSpec {
    struct RTLVerification: Sendable, Hashable, Codable {
        public var stageID: String
        public var analysis: RTLVerificationAnalysis
        public var rtlInput: XcircuiteFlowInputReference
        public var additionalRTLInputs: [XcircuiteFlowInputReference]
        public var referenceInput: XcircuiteFlowInputReference?
        public var additionalReferenceInputs: [XcircuiteFlowInputReference]
        public var constraintsInput: XcircuiteFlowInputReference?
        public var evidenceInput: XcircuiteFlowInputReference?
        public var topModuleName: String
        public var policy: RTLVerificationPolicy
        public var frontend: RTLVerificationFrontendOptions
        public var proofView: RTLVerificationProofView
        public var assumptions: [RTLVerificationAssumption]
        public var tool: XcircuiteFlowToolSpec
        public var oracleTool: RTLVerificationOracleToolSpec?

        public init(
            stageID: String? = nil,
            analysis: RTLVerificationAnalysis,
            rtlInput: XcircuiteFlowInputReference,
            additionalRTLInputs: [XcircuiteFlowInputReference] = [],
            referenceInput: XcircuiteFlowInputReference? = nil,
            additionalReferenceInputs: [XcircuiteFlowInputReference] = [],
            constraintsInput: XcircuiteFlowInputReference? = nil,
            evidenceInput: XcircuiteFlowInputReference? = nil,
            topModuleName: String,
            policy: RTLVerificationPolicy = RTLVerificationPolicy(),
            frontend: RTLVerificationFrontendOptions = RTLVerificationFrontendOptions(),
            proofView: RTLVerificationProofView = .rtlToRtlStructural,
            assumptions: [RTLVerificationAssumption] = [],
            tool: XcircuiteFlowToolSpec = XcircuiteFlowToolSpec(),
            oracleTool: RTLVerificationOracleToolSpec? = nil
        ) {
            self.stageID = stageID ?? analysis.stageID
            self.analysis = analysis
            self.rtlInput = rtlInput
            self.additionalRTLInputs = additionalRTLInputs
            self.referenceInput = referenceInput
            self.additionalReferenceInputs = additionalReferenceInputs
            self.constraintsInput = constraintsInput
            self.evidenceInput = evidenceInput
            self.topModuleName = topModuleName
            self.policy = policy
            self.frontend = frontend
            self.proofView = proofView
            self.assumptions = assumptions
            self.tool = tool
            self.oracleTool = oracleTool
        }
    }
}
