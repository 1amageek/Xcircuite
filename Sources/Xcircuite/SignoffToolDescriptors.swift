import Foundation
import ToolQualification
import XcircuitePackage

public enum SignoffToolDescriptors {
    public static func pureSwiftDRC(level: ToolQualificationLevel = .smokeChecked) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "pure-swift-drc",
            displayName: "Pure Swift DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
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

    public static func pureSwiftLVS(level: ToolQualificationLevel = .smokeChecked) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "pure-swift-lvs",
            displayName: "Pure Swift LVS",
            kind: .lvs,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-lvs",
                    inputFormats: [.spice],
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

    public static func mockPEX(level: ToolQualificationLevel = .smokeChecked) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "mock-pex",
            displayName: "Mock PEX",
            kind: .pex,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-pex",
                    inputFormats: [.gdsii, .spice, .json],
                    outputFormats: [.spef, .json, .text],
                    limitations: [
                        "Generates deterministic synthetic parasitics for runtime contract validation.",
                    ]
                ),
            ],
            trustProfile: ToolTrustProfile(
                level: level,
                knownLimitations: [
                    "Not a physical signoff extractor.",
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func coreSpiceSimulation(level: ToolQualificationLevel = .smokeChecked) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "corespice",
            displayName: "CoreSpice Simulation",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-simulation",
                    inputFormats: [.spice],
                    outputFormats: [.csv, .json]
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
