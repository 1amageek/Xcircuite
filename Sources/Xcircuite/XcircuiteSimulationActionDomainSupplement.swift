struct XcircuiteSimulationActionDomainSupplement: Sendable {
    func applying(to domain: XcircuiteActionDomain) -> XcircuiteActionDomain {
        XcircuiteActionDomain(
            schemaVersion: domain.schemaVersion,
            domainID: domain.domainID,
            ownerPackages: stableUnique(domain.ownerPackages + ["Xcircuite"]),
            operations: replacingOperations(in: domain.operations, with: [
                metricImprovementObjectiveOperation(),
                comparePostLayoutOperation(),
                compareGoldenOperation(),
                assessGoldenCorpusOperation(),
            ])
        )
    }

    private func metricImprovementObjectiveOperation() -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: "simulation.metric-improvement-objective",
            maturity: "implemented",
            inputRefs: [
                "post-layout-metric-report",
                "source-netlist-ref",
                "optional-specification-ref",
                "optional-bounded-parameter-space",
                "optional-rejected-plan-history",
                "optional-metric-threshold-profile",
                "optional-cost-calibration",
                "optional-pareto-candidates",
            ],
            preconditions: [
                "metric-gap-detected",
                "source-netlist-readable",
                "editable-parameter-space-known",
            ],
            effects: [
                "metric-improvement-objective-created",
                "parameter-candidates-generated",
                "candidate-plan-produced",
                "numeric-repair-loop-audited",
            ],
            producedArtifacts: [
                "planning-problem",
                "parameter-candidates",
                "parameter-candidate-search-trace",
                "candidate-plan",
                "parameter-candidate-selection-trace",
                "numeric-repair-loop",
            ],
            verificationGates: [
                "schema-validation",
                "candidate-plan-verification",
                "simulation-metric-gate",
                "artifact-integrity",
                "human-review",
            ],
            reversible: true
        )
    }

    private func comparePostLayoutOperation() -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: "simulation.compare-post-layout",
            maturity: "implemented",
            inputRefs: [
                "pre-layout-waveform-ref",
                "post-layout-waveform-ref",
                "comparison-policy",
            ],
            preconditions: [
                "waveforms-readable",
                "shared-sweep-axis",
                "comparison-thresholds-resolved",
            ],
            effects: [
                "post-layout-comparison-produced",
                "metric-regressions-classified",
            ],
            producedArtifacts: ["post-layout-comparison"],
            verificationGates: ["simulation-metric-gate", "artifact-integrity"],
            reversible: true
        )
    }

    private func compareGoldenOperation() -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: "simulation.compare-golden",
            maturity: "implemented",
            inputRefs: [
                "golden-waveform-ref",
                "candidate-waveform-ref",
                "comparison-policy",
            ],
            preconditions: [
                "waveforms-readable",
                "golden-baseline-selected",
                "comparison-thresholds-resolved",
            ],
            effects: [
                "simulation-golden-comparison-produced",
                "waveform-regressions-classified",
            ],
            producedArtifacts: ["simulation-golden-comparison"],
            verificationGates: ["simulation-metric-gate", "artifact-integrity"],
            reversible: true
        )
    }

    private func assessGoldenCorpusOperation() -> XcircuiteActionDomainOperation {
        XcircuiteActionDomainOperation(
            operationID: "simulation.assess-golden-corpus",
            maturity: "implemented",
            inputRefs: [
                "simulation-golden-corpus-suite-ref",
                "spice-netlist-ref",
                "golden-waveform-ref",
            ],
            preconditions: [
                "corpus-suite-readable",
                "golden-baselines-readable",
                "simulation-backend-available",
            ],
            effects: [
                "simulation-golden-corpus-report-produced",
                "coverage-tags-aggregated",
                "case-artifacts-written",
            ],
            producedArtifacts: ["simulation-golden-corpus-report", "simulation-golden-comparison"],
            verificationGates: ["simulation-metric-gate", "artifact-integrity"],
            reversible: true
        )
    }

    private func replacingOperations(
        in operations: [XcircuiteActionDomainOperation],
        with replacements: [XcircuiteActionDomainOperation]
    ) -> [XcircuiteActionDomainOperation] {
        let replacementByID = Dictionary(uniqueKeysWithValues: replacements.map { ($0.operationID, $0) })
        var seen: Set<String> = []
        var result: [XcircuiteActionDomainOperation] = []
        for operation in operations where !seen.contains(operation.operationID) {
            seen.insert(operation.operationID)
            result.append(replacementByID[operation.operationID] ?? operation)
        }
        for operation in replacements where !seen.contains(operation.operationID) {
            seen.insert(operation.operationID)
            result.append(operation)
        }
        return result
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
