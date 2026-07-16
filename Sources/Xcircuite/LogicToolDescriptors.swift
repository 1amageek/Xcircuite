import ToolQualification
import DesignFlowKernel

public enum LogicToolDescriptors {
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
        ToolDescriptor(
            toolID: "native-rtl-verification",
            displayName: "Native RTL-to-Mapped Equivalence",
            kind: .rtlVerification,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-equivalence",
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

    public static func qualification() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "logic-qualification",
            displayName: "Logic Qualification Promotion Gate",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "logic-qualify",
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
