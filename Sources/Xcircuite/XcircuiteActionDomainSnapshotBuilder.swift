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
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
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
}
