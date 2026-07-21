import ToolQualification
import DesignFlowKernel

public enum LogicToolDescriptors {
    public static func elaboration() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-design.native",
            displayName: "Native SystemVerilog Elaboration",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-elaborate",
                    inputFormats: [.systemVerilog, .verilog],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func lowering() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-lowering",
            displayName: "Native Logic Lowering",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-lower",
                    inputFormats: [.json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func simulation() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-simulation",
            displayName: "Native Logic Simulation",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-simulate",
                    inputFormats: [.json],
                    outputFormats: [.json, .vcd]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func powerIntent() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-design.power-intent",
            displayName: "Native Power Intent Parsing",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-parse-power-intent",
                    inputFormats: [.upf, .cpf, .json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func synthesis() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-synthesis",
            displayName: "Native Logic Synthesis",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-synthesize",
                    inputFormats: [.json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func equivalence() -> ToolDescriptor {
        RTLToolDescriptors.native()
    }

    public static func evidenceValidation() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-evidence-validation",
            displayName: "Logic Evidence Validation",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-evidence-validate",
                    inputFormats: [.json],
                    outputFormats: [.json]
                ),
            ],
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
