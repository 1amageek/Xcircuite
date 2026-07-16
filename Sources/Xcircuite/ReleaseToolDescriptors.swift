import Foundation
import ToolQualification
import DesignFlowKernel

public enum ReleaseToolDescriptors {
    public static func authorization() -> ToolDescriptor {
        descriptor(
            toolID: "native-release-authorization",
            displayName: "Release authorization",
            operationID: "release-authorize"
        )
    }

    public static func signoff() -> ToolDescriptor {
        descriptor(
            toolID: "native-release-signoff",
            displayName: "Release signoff",
            operationID: "release-signoff"
        )
    }

    public static func tapeout() -> ToolDescriptor {
        descriptor(
            toolID: "native-release-tapeout",
            displayName: "Release tapeout",
            operationID: "release-tapeout"
        )
    }

    private static func descriptor(
        toolID: String,
        displayName: String,
        operationID: String
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: toolID,
            displayName: displayName,
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: operationID,
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
