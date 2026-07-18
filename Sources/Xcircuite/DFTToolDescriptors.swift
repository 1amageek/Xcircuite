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

    public static func oracleCorrelation() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "dft-oracle-correlation",
            displayName: "DFT Oracle Correlation",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "correlate-dft-oracle-corpus",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Correlation produces domain observations and does not grant tool or process qualification."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
