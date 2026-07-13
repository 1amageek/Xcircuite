import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func generatedAssumptions(
        domain: String,
        summaryRefID: String,
        actionDomainRefID: String
    ) -> [XcircuitePlanningAssumption] {
        return [
            XcircuitePlanningAssumption(
                assumptionID: "\(domain)-summary-current",
                source: "xcircuite.generate-planning-problem",
                statement: "The diagnostic summary describes the current design state for the generated planning problem.",
                status: "resolved",
                confidence: 1,
                sourceRefIDs: [summaryRefID],
                requiredBeforeExecution: true,
                evidence: [
                    "reviewSurface": .string("planning/problem-validation.json"),
                    "verificationGate": .string("artifact-integrity"),
                ]
            ),
            XcircuitePlanningAssumption(
                assumptionID: "\(domain)-action-domain-current",
                source: "xcircuite.generate-planning-problem",
                statement: "The action-domain snapshot is the planner-visible capability surface for this run.",
                status: "resolved",
                confidence: 1,
                sourceRefIDs: [actionDomainRefID],
                requiredBeforeExecution: true,
                evidence: [
                    "reviewSurface": .string("planning/action-domain-snapshot.json"),
                ]
            ),
        ]
    }

    func drcRiskClassifications(
        objectives: [XcircuitePlanningObjective],
        candidateActions: [XcircuitePlanningCandidateAction]
    ) -> [XcircuitePlanningRiskClassification] {
        guard !candidateActions.isEmpty else {
            return []
        }
        return [
            XcircuitePlanningRiskClassification(
                riskID: "drc-layout-edit-regression-risk",
                category: "layout-regression",
                severity: "medium",
                scope: "candidate-plan",
                description: "DRC repair edits can change geometry and must preserve LVS equivalence and artifact integrity.",
                affectedObjectiveIDs: objectives.map(\.objectiveID),
                affectedActionIDs: candidateActions.map(\.actionID),
                mitigationActions: ["native-drc", "native-lvs", "artifact-integrity"],
                evidence: [
                    "sourceOperation": .string("xcircuite.generate-planning-problem"),
                    "candidateOperationIDs": .array(candidateActions.map { .string($0.operationID) }),
                ]
            ),
        ]
    }

    func lvsRiskClassifications(
        objectives: [XcircuitePlanningObjective],
        candidateActions: [XcircuitePlanningCandidateAction]
    ) -> [XcircuitePlanningRiskClassification] {
        var risks: [XcircuitePlanningRiskClassification] = []
        let layoutActions = candidateActions.filter { $0.domainID == "layout-edit" }
        if !layoutActions.isEmpty {
            risks.append(
                XcircuitePlanningRiskClassification(
                    riskID: "lvs-layout-edit-regression-risk",
                    category: "layout-regression",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "Layout-side LVS repairs can affect DRC and must preserve artifact integrity.",
                    affectedObjectiveIDs: objectives.map(\.objectiveID),
                    affectedActionIDs: layoutActions.map(\.actionID),
                    mitigationActions: ["native-lvs", "native-drc", "artifact-integrity"],
                    evidence: [
                        "sourceOperation": .string("xcircuite.generate-planning-problem"),
                        "candidateOperationIDs": .array(layoutActions.map { .string($0.operationID) }),
                    ]
                )
            )
        }
        let policyActions = candidateActions.filter { $0.operationID == "lvs.policy-repair" }
        if !policyActions.isEmpty {
            risks.append(
                XcircuitePlanningRiskClassification(
                    riskID: "lvs-policy-mutation-risk",
                    category: "policy-mutation",
                    severity: "high",
                    scope: "candidate-plan",
                    description: "LVS policy mutations can change equivalence semantics and require human approval.",
                    affectedObjectiveIDs: objectives.map(\.objectiveID),
                    affectedActionIDs: policyActions.map(\.actionID),
                    requiredApprovals: ["policy-repair-approval"],
                    mitigationActions: ["approval-gate", "native-lvs", "artifact-integrity"],
                    evidence: [
                        "sourceOperation": .string("xcircuite.generate-planning-problem"),
                        "candidateOperationIDs": .array(policyActions.map { .string($0.operationID) }),
                    ]
                )
            )
        }
        let netlistEditActions = candidateActions.filter { $0.operationID == "simulation.set-netlist-parameters" }
        if !netlistEditActions.isEmpty {
            risks.append(
                XcircuitePlanningRiskClassification(
                    riskID: "lvs-netlist-parameter-edit-risk",
                    category: "netlist-mutation",
                    severity: "medium",
                    scope: "candidate-plan",
                    description: "LVS parameter repairs mutate a layout-side netlist and must be verified against the schematic.",
                    affectedObjectiveIDs: objectives.map(\.objectiveID),
                    affectedActionIDs: netlistEditActions.map(\.actionID),
                    mitigationActions: ["native-lvs", "artifact-integrity"],
                    evidence: [
                        "sourceOperation": .string("xcircuite.generate-planning-problem"),
                        "candidateOperationIDs": .array(netlistEditActions.map { .string($0.operationID) }),
                    ]
                )
            )
        }
        return risks
    }

    func lvsActionDomainRefs(candidateActions: [XcircuitePlanningCandidateAction]) -> [String] {
        var refs = ["lvs-signoff", "layout-edit", "drc-signoff"]
        if candidateActions.contains(where: { $0.domainID == "simulation-analysis" }) {
            refs.append("simulation-analysis")
        }
        return refs
    }

    func pexRiskClassifications(
        objectives: [XcircuitePlanningObjective],
        candidateActions: [XcircuitePlanningCandidateAction],
        hasMetricReport: Bool
    ) -> [XcircuitePlanningRiskClassification] {
        guard !candidateActions.isEmpty else {
            return []
        }
        var mitigationActions = ["pex-summary-gate", "native-drc", "native-lvs", "artifact-integrity"]
        if hasMetricReport {
            mitigationActions.append("simulation-metric-gate")
        }
        return [
            XcircuitePlanningRiskClassification(
                riskID: "pex-recovery-tradeoff-risk",
                category: "post-layout-metric-regression",
                severity: "medium",
                scope: "candidate-plan",
                description: "PEX recovery plans can trade parasitic reduction against simulation metrics and signoff cleanliness.",
                affectedObjectiveIDs: objectives.map(\.objectiveID),
                affectedActionIDs: candidateActions.map(\.actionID),
                mitigationActions: mitigationActions,
                evidence: [
                    "sourceOperation": .string("xcircuite.generate-planning-problem"),
                    "hasMetricReport": .bool(hasMetricReport),
                    "candidateOperationIDs": .array(candidateActions.map { .string($0.operationID) }),
                ]
            ),
        ]
    }

    func drcConstraints(
        summaryRefID: String,
        repairHintRefID: String? = nil
    ) -> [XcircuitePlanningConstraint] {
        let sourceRefIDs = traceableDiagnosticSourceRefIDs(
            summaryRefID: summaryRefID,
            repairHintRefID: repairHintRefID
        )
        return [
            XcircuitePlanningConstraint(
                constraintID: "drc-must-pass",
                kind: "verification",
                severity: "error",
                description: "The resulting design must pass DRC with no active error diagnostics.",
                sourceRefIDs: sourceRefIDs
            ),
            XcircuitePlanningConstraint(
                constraintID: "preserve-lvs",
                kind: "regression",
                severity: "error",
                description: "Layout edits proposed for DRC repair must preserve LVS equivalence.",
                sourceRefIDs: sourceRefIDs
            ),
        ]
    }

    func lvsConstraints(
        summaryRefID: String,
        repairHintRefID: String? = nil
    ) -> [XcircuitePlanningConstraint] {
        let sourceRefIDs = traceableDiagnosticSourceRefIDs(
            summaryRefID: summaryRefID,
            repairHintRefID: repairHintRefID
        )
        return [
            XcircuitePlanningConstraint(
                constraintID: "lvs-must-pass",
                kind: "verification",
                severity: "error",
                description: "The resulting design must pass LVS with no active mismatch diagnostics.",
                sourceRefIDs: sourceRefIDs
            ),
            XcircuitePlanningConstraint(
                constraintID: "preserve-drc",
                kind: "regression",
                severity: "error",
                description: "Layout-side LVS repairs must preserve DRC cleanliness.",
                sourceRefIDs: sourceRefIDs
            ),
            XcircuitePlanningConstraint(
                constraintID: "policy-repair-approval",
                kind: "human-approval",
                severity: "warning",
                description: "Model or terminal-equivalence policy repairs require an approval gate.",
                sourceRefIDs: sourceRefIDs
            ),
        ]
    }

    func traceableDiagnosticSourceRefIDs(
        summaryRefID: String,
        repairHintRefID: String?
    ) -> [String] {
        var sourceRefIDs = [summaryRefID]
        if let repairHintRefID {
            sourceRefIDs.append(repairHintRefID)
        }
        return sourceRefIDs
    }

    func lvsProblemVerificationGates(
        candidateActions: [XcircuitePlanningCandidateAction]
    ) -> [XcircuitePlanningVerificationGate] {
        let candidateGateIDs = Set(candidateActions.flatMap(\.verificationGates))
        var gates = [
            XcircuitePlanningVerificationGate(
                gateID: "native-lvs",
                required: true,
                description: "The repaired candidate must pass LVS with no active mismatch diagnostics."
            ),
        ]
        if candidateGateIDs.contains("native-drc") {
            gates.append(
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Layout-side LVS repairs must not introduce DRC violations."
                )
            )
        }
        gates.append(
            XcircuitePlanningVerificationGate(
                gateID: "artifact-integrity",
                required: true,
                description: "All produced artifacts must verify by path, SHA-256, and byte count."
            )
        )
        if candidateGateIDs.contains("approval-gate") {
            gates.append(
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Policy repairs require human approval before they are applied."
                )
            )
        }
        return gates
    }

    func pexConstraints(
        summaryRefID: String,
        metricReportRefID: String,
        hasMetricReport: Bool
    ) -> [XcircuitePlanningConstraint] {
        var constraints = [
            XcircuitePlanningConstraint(
                constraintID: "pex-artifacts-complete",
                kind: "verification",
                severity: "error",
                description: "The resulting candidate must keep PEX artifacts complete and auditable.",
                sourceRefIDs: [summaryRefID]
            ),
            XcircuitePlanningConstraint(
                constraintID: "preserve-drc",
                kind: "regression",
                severity: "error",
                description: "Layout-side PEX recovery edits must preserve DRC cleanliness.",
                sourceRefIDs: [summaryRefID]
            ),
            XcircuitePlanningConstraint(
                constraintID: "preserve-lvs",
                kind: "regression",
                severity: "error",
                description: "Layout-side PEX recovery edits must preserve LVS equivalence.",
                sourceRefIDs: [summaryRefID]
            ),
        ]
        if hasMetricReport {
            constraints.append(
                XcircuitePlanningConstraint(
                    constraintID: "post-layout-metric-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "Metric recovery candidates must satisfy the supplied post-layout metric report.",
                    sourceRefIDs: [metricReportRefID]
                )
            )
        }
        return constraints
    }

    func defaultCostModel(primaryDomain: String) -> XcircuitePlanningCostModel {
        XcircuitePlanningCostModel(
            strategy: "minimize-risk-then-churn",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "\(primaryDomain)-active-error-count",
                    weight: 10,
                    direction: "minimize",
                    description: "Minimize active signoff errors for the primary failing domain."
                ),
                XcircuitePlanningCostTerm(
                    termID: "layout-churn",
                    weight: 3,
                    direction: "minimize",
                    description: "Prefer smaller physical edits when multiple candidates satisfy the gates."
                ),
                XcircuitePlanningCostTerm(
                    termID: "approval-cost",
                    weight: 2,
                    direction: "minimize",
                    description: "Prefer candidates that avoid unnecessary policy or waiver approvals."
                ),
            ]
        )
    }

    func pexCostModel() -> XcircuitePlanningCostModel {
        XcircuitePlanningCostModel(
            strategy: "minimize-parasitic-hotspot-then-risk",
            terms: [
                XcircuitePlanningCostTerm(
                    termID: "top-net-total-capacitance",
                    weight: 8,
                    direction: "minimize",
                    description: "Prefer candidates that reduce total capacitance on hotspot nets."
                ),
                XcircuitePlanningCostTerm(
                    termID: "top-net-resistance",
                    weight: 5,
                    direction: "minimize",
                    description: "Prefer candidates that reduce extracted resistance on hotspot nets."
                ),
                XcircuitePlanningCostTerm(
                    termID: "layout-churn",
                    weight: 3,
                    direction: "minimize",
                    description: "Prefer smaller physical edits when multiple candidates satisfy the gates."
                ),
                XcircuitePlanningCostTerm(
                    termID: "simulation-regression-risk",
                    weight: 6,
                    direction: "minimize",
                    description: "Prefer candidates that keep post-layout simulation metrics within bounds."
                ),
            ]
        )
    }

    func defaultResumeContract() -> XcircuitePlanningResumeContract {
        XcircuitePlanningResumeContract(
            mode: "run-ledger",
            requiredArtifacts: [
                "planning/action-domain-snapshot.json",
                "planning/problem.json",
            ],
            blockedStates: [
                "missing-source-artifact",
                "candidate-rejected",
                "approval-required",
            ]
        )
    }
}
