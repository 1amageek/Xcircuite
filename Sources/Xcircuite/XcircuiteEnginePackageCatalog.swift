import Foundation

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
                "pdk.qualify",
            ],
            inputArtifactRoles: [
                "pdk-manifest",
                "pdk-assets",
                "pdk-corpus-suite",
                "pdk-oracle-expectation",
                "pdk-corpus-report",
                "pdk-oracle-report",
            ],
            outputArtifactRoles: [
                "pdk-reference",
                "pdk-validation-report",
                "pdk-corpus-report",
                "pdk-standard-view-report",
                "pdk-oracle-report",
                "pdk-qualification-report",
            ]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "LogicDesign",
            products: ["LogicIR", "SystemVerilogFrontend", "PowerIntent"],
            stageIDs: ["logic.elaborate", "logic.power-intent"],
            inputArtifactRoles: ["rtl-source", "power-intent-source"],
            outputArtifactRoles: ["logic-design", "power-intent"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "LogicEngine",
            products: ["LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicQualification"],
            stageIDs: ["logic.lower", "logic.simulate", "logic.synthesize", "logic.equivalence", "logic.qualification"],
            inputArtifactRoles: ["rtl-snapshot", "logic-design", "timing-library", "timing-constraints", "logic-equivalence-request", "logic-qualification-report", "logic-process-qualification-evidence", "logic-release-approval"],
            outputArtifactRoles: [
                "execution-design",
                "logic-trace",
                "mapped-design",
                "logic-report",
                "logic-equivalence-evidence",
                "logic-synthesis-acceptance",
                "logic-equivalence-review",
                "logic-equivalence-audit"
            ]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "RTLVerificationEngine",
            products: ["RTLLint", "CDCAnalysis", "RDCAnalysis", "FormalEquivalence"],
            stageIDs: ["rtl.lint", "rtl.cdc", "rtl.rdc", "rtl.equivalence"],
            inputArtifactRoles: ["logic-design", "reference-design", "timing-constraints"],
            outputArtifactRoles: ["rtl-verification-report", "formal-counterexample"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "DFTEngine",
            products: ["ScanInsertion", "ATPGEngine", "BISTEngine"],
            stageIDs: ["dft.scan", "dft.atpg", "dft.bist"],
            inputArtifactRoles: ["mapped-design", "test-constraints", "pdk-reference"],
            outputArtifactRoles: ["test-design", "test-patterns", "fault-coverage-report"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "PhysicalDesignEngine",
            products: ["PhysicalDesignCore", "FloorplanEngine", "PlacementEngine", "CTSEngine", "RoutingEngine", "PhysicalECO", "PhysicalDFM", "PhysicalDesignEngine"],
            stageIDs: ["physical.floorplan", "physical.place", "physical.power", "physical.cts", "physical.global-route", "physical.detailed-route", "physical.route", "physical.eco", "physical.drc-repair", "physical.antenna", "physical.dfm", "physical.hotspot-repair", "physical.review"],
            inputArtifactRoles: ["mapped-design", "physical-snapshot", "physical-constraints", "pdk-reference", "verification-feedback", "physical-design-manifest"],
            outputArtifactRoles: ["physical-design", "physical-design-def", "physical-design-diff", "physical-report", "physical-design-review-packet"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "TimingEngine",
            products: ["TimingCore", "STAEngine", "SignalIntegrityEngine"],
            stageIDs: ["timing.sta", "timing.signal-integrity"],
            inputArtifactRoles: ["logic-design", "timing-library", "timing-constraints", "parasitics"],
            outputArtifactRoles: ["timing-report", "signal-integrity-report"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "ElectricalSignoffEngine",
            products: ["PowerIntegrityEngine", "ERCEngine", "ESDEngine", "LatchUpEngine", "AgingEngine", "ElectricalSignoffQualification"],
            stageIDs: ["electrical.power-integrity", "electrical.erc", "electrical.esd", "electrical.latch-up", "electrical.aging", "electrical-signoff.standard-layout-import", "electrical-signoff", "electrical-signoff.qualification", "electrical-signoff.repair-revision", "electrical-signoff.release-gate"],
            inputArtifactRoles: ["logic-design", "physical-design", "power-intent", "parasitics", "pdk-reference", "standard-layout", "layout-technology", "electrical-qualification-spec", "electrical-release-policy", "electrical-repair-plan"],
            outputArtifactRoles: ["electrical-standard-physical-snapshot", "electrical-signoff-report", "electrical-signoff-run-result", "electrical-qualification-report", "electrical-tool-evidence", "electrical-repair-plan", "electrical-repair-revision", "electrical-release-gate", "electrical-release-artifact-bundle"]
        ),
        XcircuiteEnginePackageDescriptor(
            packageID: "ReleaseEngine",
            products: ["QualificationEngine", "SignoffEngine", "TapeoutEngine"],
            stageIDs: ["release.qualification", "release.signoff", "release.tapeout"],
            inputArtifactRoles: [
                "qualification-suite",
                "qualification-report",
                "qualification-evidence",
                "signoff-evidence",
                "physical-design",
                "pdk-reference",
                "tool-qualification"
            ],
            outputArtifactRoles: ["release-qualification-result", "signoff-bundle", "tapeout-release"]
        ),
    ]
}
