import Foundation
import ToolQualification
import XcircuitePackage

public enum SignoffToolDescriptors {
    public static func pexToolID(backendID: String) -> String {
        "pex-\(backendID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public static func nativeDRC(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-drc",
            displayName: "Native DRC",
            kind: .drc,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-drc",
                    inputFormats: [.json, .gdsii, .oasis, .raw],
                    outputFormats: [.json, .text]
                ),
            ],
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func nativeLVS(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-lvs",
            displayName: "Native LVS",
            kind: .lvs,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-lvs",
                    inputFormats: [.spice, .gdsii, .oasis, .raw],
                    outputFormats: [.json, .text]
                ),
            ],
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func mockPEX(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "mock-pex",
            displayName: "Mock PEX",
            kind: .pex,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-pex",
                    inputFormats: [.gdsii, .oasis, .spice, .json],
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

    public static func pexBackend(
        backendID: String,
        level: ToolQualificationLevel = .unknown
    ) -> ToolDescriptor {
        let normalizedBackendID = backendID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolDescriptor(
            toolID: pexToolID(backendID: normalizedBackendID),
            displayName: "PEX Backend \(normalizedBackendID)",
            kind: .pex,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-pex",
                    inputFormats: [.gdsii, .oasis, .spice, .json],
                    outputFormats: [.spef, .json, .text]
                ),
            ],
            trustProfile: ToolTrustProfile(level: level),
            environment: ToolEnvironment(
                executablePath: normalizedBackendID,
                platform: "macOS"
            )
        )
    }

    public static func coreSpiceSimulation(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
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
                ToolCapability(
                    operationID: "compare-waveforms",
                    inputFormats: [.csv],
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

    public static func postLayoutComparison(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "post-layout-comparison",
            displayName: "Post-layout Waveform Comparison",
            kind: .simulation,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "compare-waveforms",
                    inputFormats: [.csv],
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

    public static func layoutCommand(level: ToolQualificationLevel = .unknown) -> ToolDescriptor {
        ToolDescriptor(
            toolID: "layout-command",
            displayName: "Layout Command Runner",
            kind: .layout,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "edit-layout",
                    inputFormats: [.json],
                    outputFormats: [.json, .gdsii, .oasis, .raw]
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
