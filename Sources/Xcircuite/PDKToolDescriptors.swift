import Foundation
import ToolQualification
import DesignFlowKernel
import CircuiteFoundation

public enum PDKToolDescriptors {
    public static func discovery() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-discovery",
            displayName: "PDK discovery",
            operationID: "pdk-discover",
            inputFormats: [.json, .text]
        )
    }

    public static func validation() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-validation",
            displayName: "PDK validation",
            operationID: "pdk-validate",
            inputFormats: [.json, .text]
        )
    }

    public static func corpus() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-corpus-validation",
            displayName: "PDK retained corpus validation",
            operationID: "pdk-validate-corpus",
            inputFormats: [.json, .text]
        )
    }

    public static func standardView() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-standard-view-inspection",
            displayName: "PDK standard-view inspection",
            operationID: "pdk-inspect-standard-view",
            inputFormats: [.json, .lef, .gdsii, .oasis, .spice, .liberty]
        )
    }

    public static func ruleDeck() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-rule-deck-inspection",
            displayName: "PDK rule-deck inspection",
            operationID: "pdk-inspect-rule-deck",
            inputFormats: [.json, .text]
        )
    }

    public static func oracle() -> ToolDescriptor {
        descriptor(
            toolID: "pdk-oracle-comparison",
            displayName: "PDK immutable oracle comparison",
            operationID: "pdk-compare-oracle",
            inputFormats: [.json, .lef, .gdsii, .oasis, .spice, .liberty]
        )
    }

    private static func descriptor(
        toolID: String,
        displayName: String,
        operationID: String,
        inputFormats: [ArtifactFormat]
    ) -> ToolDescriptor {
        ToolDescriptor(
            toolID: toolID,
            displayName: displayName,
            kind: .reporting,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: operationID,
                    inputFormats: inputFormats,
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
