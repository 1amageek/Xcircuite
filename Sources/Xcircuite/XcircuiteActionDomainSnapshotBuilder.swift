import CoreSpice
import DRCEngine
import Foundation
import LayoutCommands
import LVSEngine
import PEXEngine
import DesignFlowKernel

public struct XcircuiteActionDomainSnapshotBuilder: Sendable {
    public init() {}

    public func snapshot(
        runID: String,
        generatedAt: String
    ) throws -> XcircuitePlanningActionDomainSnapshot {
        try FlowIdentifierValidator().validate(runID, kind: .runID)
        let simulationDomain = try XcircuiteSimulationActionDomainSupplement().applying(
            to: canonicalDomain(CoreSpiceActionDomainExporter().snapshot())
        )
        let pexDomain = try XcircuitePEXActionDomainSupplement().applying(
            to: canonicalDomain(PEXActionDomainExporter().snapshot())
        )
        let domains = try [
            canonicalDomain(LayoutActionDomainExporter().snapshot()),
            canonicalDomain(DRCActionDomainExporter().snapshot()),
            canonicalDomain(LVSActionDomainExporter().snapshot()),
            pexDomain,
            simulationDomain,
            logicDesignDomain(),
            logicExecutionDomain(),
            rtlVerificationDomain(),
            dftDomain(),
            physicalDesignDomain(),
            timingDomain(),
            electricalSignoffDomain(),
            releaseDomain(),
        ].sorted { $0.domainID < $1.domainID }

        return XcircuitePlanningActionDomainSnapshot(
            runID: runID,
            generatedAt: generatedAt,
            domains: domains
        )
    }

    private func canonicalDomain<T: Encodable>(_ domain: T) throws -> XcircuiteActionDomain {
        let encoder = JSONEncoder()
        let data = try encoder.encode(domain)
        return try JSONDecoder().decode(XcircuiteActionDomain.self, from: data)
    }

    private func logicDesignDomain() -> XcircuiteActionDomain {
        domain(
            id: "logic-design",
            owner: "LogicDesign",
            operations: [
                operation("logic.elaborate", artifacts: ["logic-design", "logic-elaboration-result"]),
            ]
        )
    }

    private func logicExecutionDomain() -> XcircuiteActionDomain {
        domain(
            id: "logic-execution",
            owner: "LogicEngine",
            operations: [
                operation("logic.lower", artifacts: ["logic-execution-design", "logic-lowering-result"]),
                operation("logic.synthesize", artifacts: ["mapped-design", "logic-synthesis-result"]),
                operation("logic.simulate", artifacts: ["logic-waveform", "logic-simulation-report"]),
                operation("logic.equivalence", artifacts: ["logic-equivalence-evidence"]),
            ]
        )
    }

    private func rtlVerificationDomain() -> XcircuiteActionDomain {
        domain(
            id: "rtl-verification",
            owner: "RTLVerificationEngine",
            operations: [
                operation("rtl.lint", artifacts: ["rtl-lint-report"]),
                operation("rtl.cdc", artifacts: ["rtl-cdc-report"]),
                operation("rtl.rdc", artifacts: ["rtl-rdc-report"]),
                operation("rtl.equivalence", artifacts: ["rtl-equivalence-report"]),
            ]
        )
    }

    private func dftDomain() -> XcircuiteActionDomain {
        domain(
            id: "dft",
            owner: "DFTEngine",
            operations: [
                operation("dft.scan", artifacts: ["test-design", "scan-report"]),
                operation("dft.atpg", artifacts: ["test-patterns", "fault-coverage-report"]),
                operation("dft.bist", artifacts: ["bist-report"]),
            ]
        )
    }

    private func physicalDesignDomain() -> XcircuiteActionDomain {
        domain(
            id: "physical-design",
            owner: "PhysicalDesignEngine",
            operations: [
                operation("physical.floorplan", artifacts: ["physical-design", "physical-report"]),
                operation("physical.place", artifacts: ["physical-design", "placement-report"]),
                operation("physical.power", artifacts: ["physical-design", "power-plan-report"]),
                operation("physical.cts", artifacts: ["physical-design", "cts-report"]),
                operation("physical.global-route", artifacts: ["physical-design", "global-route-report"]),
                operation("physical.detailed-route", artifacts: ["physical-design", "detailed-route-report"]),
                operation("physical.eco", artifacts: ["physical-design-diff", "physical-report"]),
                operation("physical.antenna", artifacts: ["antenna-report"]),
                operation("physical.dfm", artifacts: ["density-fill-report"]),
            ]
        )
    }

    private func timingDomain() -> XcircuiteActionDomain {
        domain(
            id: "timing-signoff",
            owner: "TimingEngine",
            operations: [
                operation("timing.sta", artifacts: ["timing-sta-result"]),
                operation("timing.signal-integrity", artifacts: ["timing-signal-integrity-result"]),
            ]
        )
    }

    private func electricalSignoffDomain() -> XcircuiteActionDomain {
        domain(
            id: "electrical-signoff",
            owner: "ElectricalSignoffEngine",
            operations: [
                operation("electrical.standard-layout-import", artifacts: ["electrical-standard-physical-snapshot"]),
                operation("electrical.signoff", artifacts: ["electrical-signoff-report"]),
                operation("electrical.corpus", artifacts: ["electrical-corpus-report"]),
            ]
        )
    }

    private func releaseDomain() -> XcircuiteActionDomain {
        domain(
            id: "release",
            owner: "ReleaseEngine",
            operations: [
                operation("release.authorization", artifacts: ["release-authorization-decision"]),
                operation("release.signoff", artifacts: ["signoff-bundle"]),
                operation("release.tapeout", artifacts: ["tapeout-release"]),
            ]
        )
    }

    private func domain(
        id: String,
        owner: String,
        operations: [XcircuiteActionDomainOperation]
    ) -> XcircuiteActionDomain {
        XcircuiteActionDomain(domainID: id, ownerPackages: [owner], operations: operations)
    }

    private func operation(
        _ id: String,
        artifacts: [String]
    ) -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: id,
            maturity: .implemented,
            inputRefs: ["artifact-reference", "execution-provenance"],
            preconditions: ["input-artifact-integrity", "tool-qualification"],
            effects: ["persist-stage-result"],
            producedArtifacts: artifacts,
            verificationGates: ["artifact-integrity", "execution-provenance", id],
            reversible: false
        )
    }
}
