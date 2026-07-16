import Foundation
import CircuiteFoundation

public enum XcircuiteEnginePackageCatalog {
    public static let descriptors: [XcircuiteEnginePackageDescriptor] = [
        XcircuiteEnginePackageDescriptor(
            packageID: "PDKKit",
            products: ["PDKCore", "PDKDiscovery", "PDKValidation", "PDKStandardViews"],
            stageIDs: [
                "pdk.discover",
                "pdk.validate",
                "pdk.validate-corpus",
                "pdk.inspect-standard-view",
                "pdk.compare-oracle",
            ],
            inputArtifactRoles: roles([
                "pdk-manifest",
                "pdk-assets",
                "pdk-corpus-suite",
                "pdk-oracle-expectation",
                "pdk-corpus-report",
                "pdk-oracle-report",
            ]),
            outputArtifactRoles: roles([
                "pdk-reference",
                "pdk-validation-report",
                "pdk-corpus-report",
                "pdk-standard-view-report",
                "pdk-oracle-report",
            ])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "LogicDesign",
            products: ["LogicIR", "SystemVerilogFrontend", "PowerIntent"],
            stageIDs: ["logic.elaborate", "logic.power-intent"],
            inputArtifactRoles: roles(["rtl-source", "power-intent-source"]),
            outputArtifactRoles: roles(["logic-design", "power-intent"])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "LogicEngine",
            products: ["LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicEvidence"],
            stageIDs: ["logic.lower", "logic.simulate", "logic.synthesize", "logic.equivalence"],
            inputArtifactRoles: roles(["rtl-snapshot", "logic-design", "timing-library", "timing-constraints", "logic-equivalence-request"]),
            outputArtifactRoles: roles([
                "execution-design",
                "logic-trace",
                "mapped-design",
                "logic-report",
                "logic-equivalence-evidence",
                "logic-synthesis-acceptance",
                "logic-equivalence-review",
                "logic-equivalence-audit"
            ])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "RTLVerificationEngine",
            products: ["RTLLint", "CDCAnalysis", "RDCAnalysis", "FormalEquivalence"],
            stageIDs: ["rtl.lint", "rtl.cdc", "rtl.rdc", "rtl.equivalence"],
            inputArtifactRoles: roles(["logic-design", "reference-design", "timing-constraints"]),
            outputArtifactRoles: roles(["rtl-verification-report", "formal-counterexample"])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "DFTEngine",
            products: ["ScanInsertion", "ATPGEngine", "BISTEngine"],
            stageIDs: [
                "dft.scan",
                "dft.atpg",
                "dft.bist",
            ],
            inputArtifactRoles: roles([
                "mapped-design",
                "test-constraints",
                "pdk-reference",
                "dft-oracle-corpus",
                "dft-oracle-observations",
            ]),
            outputArtifactRoles: roles([
                "test-design",
                "test-patterns",
                "fault-coverage-report",
                "dft-corpus-observations",
                "dft-oracle-correlation",
            ])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "PhysicalDesignEngine",
            products: ["PhysicalDesignCore", "FloorplanEngine", "PlacementEngine", "CTSEngine", "RoutingEngine", "PhysicalECO", "PhysicalDFM", "PhysicalDesignEngine"],
            stageIDs: ["physical.floorplan", "physical.place", "physical.power", "physical.cts", "physical.global-route", "physical.detailed-route", "physical.route", "physical.eco", "physical.drc-repair", "physical.antenna", "physical.dfm", "physical.hotspot-repair", "physical.review"],
            inputArtifactRoles: roles(["mapped-design", "physical-snapshot", "physical-constraints", "pdk-reference", "verification-feedback", "physical-design-manifest"]),
            outputArtifactRoles: roles(["physical-design", "physical-design-def", "physical-design-diff", "physical-report", "physical-design-review-packet"])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "TimingEngine",
            products: ["TimingCore", "STAEngine", "SignalIntegrityEngine"],
            stageIDs: ["timing.sta", "timing.signal-integrity"],
            inputArtifactRoles: roles(["logic-design", "timing-library", "timing-constraints", "parasitics"]),
            outputArtifactRoles: roles(["timing-report", "signal-integrity-report"])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "ElectricalSignoffEngine",
            products: ["PowerIntegrityEngine", "ERCEngine", "ESDEngine", "LatchUpEngine", "AgingEngine", "ElectricalSignoffEvidence"],
            stageIDs: ["electrical.power-integrity", "electrical.erc", "electrical.esd", "electrical.latch-up", "electrical.aging", "electrical-signoff.standard-layout-import", "electrical-signoff", "electrical-signoff.corpus", "electrical-signoff.repair-revision"],
            inputArtifactRoles: roles(["logic-design", "physical-design", "power-intent", "parasitics", "pdk-reference", "standard-layout", "layout-technology", "electrical-corpus-spec", "electrical-oracle-observations", "electrical-repair-plan"]),
            outputArtifactRoles: roles(["electrical-standard-physical-snapshot", "electrical-signoff-report", "electrical-signoff-run-result", "electrical-corpus-report", "electrical-repair-plan", "electrical-repair-revision"])
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "ReleaseEngine",
            products: ["ReleaseEngine", "SignoffEngine", "TapeoutEngine"],
            stageIDs: ["release.authorization", "release.signoff", "release.tapeout"],
            inputArtifactRoles: roles([
                "signoff-evidence",
                "physical-design",
                "pdk-reference",
                "tool-trust-decision",
                "flow-approval-record"
            ]),
            outputArtifactRoles: roles(["release-authorization-decision", "signoff-bundle", "tapeout-release"])
        ),
    ]

    private static func roles(_ rawValues: [String]) -> [ArtifactRole] {
        rawValues.map { rawValue in
            guard let role = ArtifactRole(rawValue: rawValue) else {
                preconditionFailure("Invalid engine package artifact role: \(rawValue)")
            }
            return role
        }
    }
}
