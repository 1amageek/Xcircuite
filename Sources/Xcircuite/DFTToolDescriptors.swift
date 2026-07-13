import Foundation
import ToolQualification
import XcircuitePackage

public enum DFTToolDescriptors {
    public static func engine(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
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
                level: level,
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

    public static func qualification(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
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
                level: level,
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
}
