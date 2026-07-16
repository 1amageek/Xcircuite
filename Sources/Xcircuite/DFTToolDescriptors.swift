import Foundation
import ToolQualification
import DesignFlowKernel

public enum DFTToolDescriptors {
    public static func engine() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "dft-engine",
            displayName: "DFT Engine",
            kind: .planning,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-dft",
                    inputFormats: [.json],
                    outputFormats: [.json, .stil, .wgl]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Native DFT backends are smoke-checked and do not claim process qualification."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func qualification() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "dft-qualification",
            displayName: "DFT Qualification",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "qualify-dft",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Process qualification requires retained oracle artifacts and explicit approval evidence."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func release() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "dft-release-gate",
            displayName: "DFT Release Gate",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "release-dft",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Release requires independently validated process qualification evidence, process-qualified DFT provenance, downstream signoff artifacts and explicit review approval."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
