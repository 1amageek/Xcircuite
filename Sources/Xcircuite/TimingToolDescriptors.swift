import DesignFlowKernel
import ToolQualification

public enum TimingToolDescriptors {
    public static func staticTimingAnalysis() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-sta",
            displayName: "Native Static Timing Analysis",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "timing-sta",
                    inputFormats: [.json, .liberty, .sdc, .spef],
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

    public static func signalIntegrity() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-signal-integrity",
            displayName: "Native Signal Integrity Analysis",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "timing-signal-integrity",
                    inputFormats: [.json, .sdc, .spef],
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
