import Foundation
import ToolQualification
import DesignFlowKernel

public enum PhysicalDesignToolDescriptors {
    public static func review() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "physical-design-review",
            displayName: "Physical Design Review Gate",
            kind: .planning,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "review-physical-design",
                    inputFormats: [.json],
                    outputFormats: [.json]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "The gate validates immutable local artifacts and approval identity; it does not replace DRC, LVS, PEX or timing signoff."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }

    public static func engine() -> ToolDescriptor {
        ToolDescriptor(
            toolID: "physical-design",
            displayName: "Physical Design Engine",
            kind: .planning,
            version: "1.0.0",
            capabilities: [
                ToolCapability(
                    operationID: "run-physical-design",
                    inputFormats: [.json],
                    outputFormats: [.json, .def]
                )
            ],
            trustProfile: ToolTrustProfile(
                level: .unknown,
                knownLimitations: [
                    "Native execution is deterministic over the canonical PhysicalDesignSnapshot JSON model.",
                    "DRC, LVS, PEX and timing remain independent verification oracles.",
                    "GDSII and OASIS stream-out require a qualified external adapter."
                ]
            ),
            environment: ToolEnvironment(
                executablePath: "in-process",
                platform: "macOS"
            )
        )
    }
}
