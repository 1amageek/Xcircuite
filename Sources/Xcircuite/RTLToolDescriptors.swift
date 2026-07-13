import ToolQualification
import XcircuitePackage

public enum RTLToolDescriptors {
    public static func native(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
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
                )
            ],
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
