import DesignFlowKernel
import ToolQualification

public enum ToolQualificationToolDescriptors {
    public static func processEvidenceBuilder() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "tool-qualification",
            displayName: "Tool Qualification",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "build-process-qualification-evidence",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Evidence building validates retained artifacts but does not grant human or foundry approval."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
