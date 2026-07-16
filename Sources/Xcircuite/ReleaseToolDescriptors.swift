import Foundation
import ToolQualification
import DesignFlowKernel

public enum ReleaseToolDescriptors {
    public static func authorization(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        descriptor(
            toolID: "native-release-authorization",
            displayName: "Release authorization",
            operationID: "release-authorize",
            level: level
        )
    }

    public static func signoff(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        descriptor(
            toolID: "native-release-signoff",
            displayName: "Release signoff",
            operationID: "release-signoff",
            level: level
        )
    }

    public static func tapeout(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        descriptor(
            toolID: "native-release-tapeout",
            displayName: "Release tapeout",
            operationID: "release-tapeout",
            level: level
        )
    }

    private static func descriptor(
        toolID: String,
        displayName: String,
        operationID: String,
        level: ToolQualificationLevel
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
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
