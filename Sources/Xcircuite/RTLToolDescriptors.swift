import ToolQualification
import DesignFlowKernel
import RTLVerificationCore

public enum RTLToolDescriptors {
    public static func native() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-rtl-verification",
            displayName: "Native RTL Verification",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "rtl.lint",
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
                ToolCapability(
                    operationID: "rtl.cdc",
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
                ToolCapability(
                    operationID: "rtl.rdc",
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
                ToolCapability(
                    operationID: "rtl.equivalence.rtlToRtlStructural",
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
                ToolCapability(
                    operationID: "rtl.equivalence.rtlToMappedExecutionStructural",
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
                ToolCapability(
                    operationID: "logic-equivalence",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func oracle(
        toolID: String,
        executablePath: String,
        version: String,
        analysis: RTLVerificationAnalysis,
        proofView: RTLVerificationProofView
    ) -> ToolDescriptor {
        let operationID = analysis == .formalEquivalence
            ? "\(analysis.stageID).\(proofView.rawValue)"
            : analysis.stageID
        return ToolDescriptor(
            toolID: toolID,
            displayName: "External RTL Verification Oracle",
            kind: .rtlVerification,
            version: version,
            capabilities: [
                ToolCapability(
                    operationID: operationID,
                    inputFormats: [.systemVerilog, .verilog, .json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: executablePath,
                platform: "macOS"
            )
        )
    }
}
