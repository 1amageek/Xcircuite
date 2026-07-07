struct XcircuitePEXActionDomainSupplement: Sendable {
    func applying(to domain: XcircuiteActionDomain) -> XcircuiteActionDomain {
        XcircuiteActionDomain(
            schemaVersion: domain.schemaVersion,
            domainID: domain.domainID,
            ownerPackages: stableUnique(domain.ownerPackages + ["Xcircuite"]),
            operations: domain.operations.map { operation in
                operation.operationID == "pex.metric-recovery-objective"
                    ? implementedMetricRecoveryOperation(from: operation)
                    : operation
            }
        )
    }

    private func implementedMetricRecoveryOperation(
        from operation: XcircuiteActionDomainOperation
    ) -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: operation.operationID,
            maturity: "implemented",
            inputRefs: stableUnique(operation.inputRefs + [
                "pex-technology-ref",
                "action-domain-snapshot",
            ]),
            preconditions: stableUnique(operation.preconditions + [
                "pex-summary-readable",
                "post-layout-metric-report-readable",
                "planning-artifact-store-writable",
            ]),
            effects: stableUnique(operation.effects + [
                "pex-recovery-planning-problem-produced",
                "post-layout-metric-objectives-produced",
                "candidate-actions-bounded-by-signoff-gates",
            ]),
            producedArtifacts: stableUnique(operation.producedArtifacts + ["planning-problem"]),
            verificationGates: stableUnique(operation.verificationGates + [
                "artifact-integrity",
                "native-drc",
                "native-lvs",
            ]),
            reversible: operation.reversible
        )
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
