import Foundation
import ToolQualification
import DesignFlowKernel

public enum SignoffToolDescriptors {
    public static func pexToolID(backendID: String) -> String {
        "pex-\(backendID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public static func nativeDRC() -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func nativeLVS() -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func pexBackend(
        backendID: String
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: normalizedBackendID,
                platform: "macOS"
            )
        )
    }

    public static func coreSpiceSimulation() -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func postLayoutComparison() -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func layoutCommand() -> ToolDescriptor {
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
            trustProfile: ToolTrustProfile(level: .unknown),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func nativeElectricalStandardLayoutImport() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-electrical-standard-layout-import",
            displayName: "Native Electrical Standard Layout Import",
            kind: .maskIO,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "import-standard-layout",
                    inputFormats: [.def, .gdsii, .oasis, .lef, .json],
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

    public static func nativeElectricalSignoff() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-electrical-signoff",
            displayName: "Native Electrical Signoff",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-electrical-signoff",
                    inputFormats: [.json, .spef, .def, .gdsii, .oasis],
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

    public static func nativeElectricalCorpus() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-electrical-signoff-corpus",
            displayName: "Native Electrical Signoff Corpus",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "observe-electrical-signoff-corpus",
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

    public static func nativeElectricalRepairRevision() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "native-electrical-signoff-repair-revision",
            displayName: "Native Electrical Signoff Repair Revision",
            kind: .layout,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "apply-electrical-repair-revision",
                    inputFormats: [.json],
                    outputFormats: [.json, .def]
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
