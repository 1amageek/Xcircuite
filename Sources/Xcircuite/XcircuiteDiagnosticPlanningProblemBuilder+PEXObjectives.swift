import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

extension XcircuiteDiagnosticPlanningProblemBuilder {
    func pexObjectives(
        summary: PEXRunSummaryReport,
        summaryRefID: String,
        metricReport: PostLayoutComparisonReport?,
        metricReportRefID: String
    ) throws -> [XcircuitePlanningObjective] {
        var objectives: [XcircuitePlanningObjective] = []
        for issue in summary.completeness.issues {
            objectives.append(try pexCompletenessObjective(
                issue: issue,
                index: objectives.count,
                summaryRefID: summaryRefID
            ))
        }
        for corner in summary.summary.corners {
            for diagnostic in corner.diagnostics where diagnostic.severity == "error" || diagnostic.severity == "warning" {
                objectives.append(try pexDiagnosticObjective(
                    corner: corner,
                    diagnostic: diagnostic,
                    index: objectives.count,
                    summaryRefID: summaryRefID
                ))
            }
            for net in corner.topNets {
                objectives.append(try pexHotspotObjective(
                    cornerID: corner.cornerID,
                    net: net,
                    index: objectives.count,
                    summaryRefID: summaryRefID
                ))
            }
        }
        if let metricReport {
            objectives.append(contentsOf: try postLayoutMetricObjectives(
                report: metricReport,
                startingIndex: objectives.count,
                metricReportRefID: metricReportRefID
            ))
        }
        if objectives.isEmpty {
            objectives.append(
                XcircuitePlanningObjective(
                    objectiveID: "pex.summary-available",
                    kind: "satisfy",
                    domain: "pex",
                    priority: "info",
                    sourceRefIDs: [summaryRefID],
                    target: "pex-summary-available",
                    currentValue: .scalar(0),
                    requiredValue: .scalar(0),
                    description: "PEX summary contains no hotspots or diagnostics requiring a recovery plan.",
                    evidence: [
                        "symbolicGoalAtoms": .textList(["pex-summary-available", "artifact:pex-summary"]),
                    ]
                )
            )
        }
        return objectives
    }

    func postLayoutMetricObjectives(
        report: PostLayoutComparisonReport,
        startingIndex: Int,
        metricReportRefID: String
    ) throws -> [XcircuitePlanningObjective] {
        var objectives: [XcircuitePlanningObjective] = []
        if report.gateStatus != "passed" || !report.gateViolations.isEmpty {
            objectives.append(try postLayoutMetricGateObjective(
                report: report,
                index: startingIndex + objectives.count,
                metricReportRefID: metricReportRefID
            ))
        }
        for variable in report.comparedVariables where variable.maxAbsoluteDelta > 0 || variable.maxRelativeDelta > 0 {
            objectives.append(try postLayoutVariableDeltaObjective(
                variable: variable,
                index: startingIndex + objectives.count,
                metricReportRefID: metricReportRefID
            ))
        }
        for variable in report.requiredPostVariables where !variable.present {
            objectives.append(try postLayoutRequiredVariableObjective(
                variable: variable,
                index: startingIndex + objectives.count,
                metricReportRefID: metricReportRefID
            ))
        }
        for metric in report.oscillationMetrics where !metric.violations.isEmpty {
            objectives.append(try postLayoutOscillationObjective(
                metric: metric,
                index: startingIndex + objectives.count,
                metricReportRefID: metricReportRefID
            ))
        }
        return objectives
    }

    func postLayoutMetricGateObjective(
        report: PostLayoutComparisonReport,
        index: Int,
        metricReportRefID: String
    ) throws -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: try identifier("post-layout-metric-gate-\(index + 1)"),
            kind: "satisfy",
            domain: "simulation",
            priority: "error",
            sourceRefIDs: [metricReportRefID],
            target: "post-layout-metric-gate-passed",
            currentValue: .text(report.gateStatus),
            requiredValue: .text("passed"),
            description: "Recover post-layout simulation metrics until the comparison gate passes.",
            evidence: [
                "metricReportRefID": .text(metricReportRefID),
                "status": .text(report.status),
                "gateStatus": .text(report.gateStatus),
                "gateViolations": .textList(report.gateViolations),
                "maxAbsoluteDelta": .scalar(report.maxAbsoluteDelta),
                "maxRelativeDelta": .scalar(report.maxRelativeDelta),
                "comparedVariableCount": .scalar(Double(report.comparedVariables.count)),
                "missingPostLayoutVariables": .textList(report.missingInPostLayout),
                "addedPostLayoutVariables": .textList(report.addedInPostLayout),
                "symbolicGoalAtoms": .textList(["post-layout-metric-gate-passed", "artifact:simulation-metric-report"]),
            ],
            suggestedActions: [
                "inspect_post_layout_metric_violations",
                "adjust_layout_or_parameters",
                "rerun_post_layout_simulation_metric_gate",
            ]
        )
    }

    func postLayoutVariableDeltaObjective(
        variable: PostLayoutVariableComparison,
        index: Int,
        metricReportRefID: String
    ) throws -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: try identifier("post-layout-variable-\(variable.variableName)-delta-\(index + 1)"),
            kind: "minimize",
            domain: "simulation",
            priority: "warning",
            sourceRefIDs: [metricReportRefID],
            target: "reduce-post-layout-waveform-delta",
            currentValue: .scalar(variable.maxRelativeDelta),
            requiredValue: nil,
            unit: "ratio",
            description: "Reduce post-layout waveform delta for variable \(variable.variableName).",
            evidence: [
                "metricReportRefID": .text(metricReportRefID),
                "variableName": .text(variable.variableName),
                "pointCount": .scalar(Double(variable.pointCount)),
                "maxAbsoluteDelta": .scalar(variable.maxAbsoluteDelta),
                "maxRelativeDelta": .scalar(variable.maxRelativeDelta),
                "symbolicGoalAtoms": .textList(["post-layout-variable-delta-reduced", "artifact:simulation-metric-report"]),
            ],
            suggestedActions: [
                "identify_post_layout_waveform_delta_source",
                "adjust_layout_or_parameters",
                "rerun_post_layout_comparison",
            ]
        )
    }

    func postLayoutRequiredVariableObjective(
        variable: PostLayoutRequiredVariableResult,
        index: Int,
        metricReportRefID: String
    ) throws -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: try identifier("post-layout-required-variable-\(variable.variableName)-\(index + 1)"),
            kind: "satisfy",
            domain: "simulation",
            priority: "error",
            sourceRefIDs: [metricReportRefID],
            target: "restore-required-post-layout-variable",
            currentValue: .text("missing"),
            requiredValue: .text("present"),
            description: "Restore required post-layout variable \(variable.variableName).",
            evidence: [
                "metricReportRefID": .text(metricReportRefID),
                "variableName": .text(variable.variableName),
                "present": .boolean(variable.present),
                "symbolicGoalAtoms": .textList(["post-layout-variable-present", "artifact:simulation-metric-report"]),
            ],
            suggestedActions: [
                "inspect_post_layout_output_variables",
                "repair_post_layout_simulation_setup",
                "rerun_post_layout_comparison",
            ]
        )
    }

    func postLayoutOscillationObjective(
        metric: PostLayoutOscillationMetricComparison,
        index: Int,
        metricReportRefID: String
    ) throws -> XcircuitePlanningObjective {
        var evidence: [String: PlanningParameterValue] = [
            "metricReportRefID": .text(metricReportRefID),
            "variableName": .text(metric.variableName),
            "violations": .textList(metric.violations),
            "symbolicGoalAtoms": .textList(["post-layout-oscillation-metric-recovered", "artifact:simulation-metric-report"]),
        ]
        insertOptional(metric.frequencyRelativeDelta, key: "frequencyRelativeDelta", into: &evidence)
        if let postLayout = metric.postLayout {
            evidence["postLayoutAmplitude"] = .scalar(postLayout.amplitude)
            insertOptional(postLayout.frequency, key: "postLayoutFrequency", into: &evidence)
            insertOptional(postLayout.averagePeriod, key: "postLayoutAveragePeriod", into: &evidence)
            evidence["postLayoutTransitionCount"] = .scalar(Double(postLayout.transitionCount))
            insertOptional(postLayout.dutyCycle, key: "postLayoutDutyCycle", into: &evidence)
        }
        return XcircuitePlanningObjective(
            objectiveID: try identifier("post-layout-oscillation-\(metric.variableName)-\(index + 1)"),
            kind: "satisfy",
            domain: "simulation",
            priority: "error",
            sourceRefIDs: [metricReportRefID],
            target: "recover-post-layout-oscillation-metric",
            currentValue: .text("violating"),
            requiredValue: .text("passed"),
            description: "Recover post-layout oscillation metric for variable \(metric.variableName).",
            evidence: evidence,
            suggestedActions: [
                "inspect_post_layout_oscillation_metric",
                "adjust_layout_or_parameters",
                "rerun_post_layout_comparison",
            ]
        )
    }

    func pexHotspotObjective(
        cornerID: String,
        net: PEXNetParasiticSummary,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        let totalCapF = net.groundCapF + net.couplingCapF
        return XcircuitePlanningObjective(
            objectiveID: try identifier("pex-\(cornerID)-\(net.name)-hotspot-\(index + 1)"),
            kind: "minimize",
            domain: "pex",
            priority: "warning",
            sourceRefIDs: [summaryRefID],
            target: "reduce-parasitic-hotspot",
            currentValue: .scalar(totalCapF),
            requiredValue: nil,
            unit: "F",
            description: "Reduce parasitic hotspot on net \(net.name) in corner \(cornerID).",
            evidence: [
                "cornerID": .text(cornerID),
                "netName": .text(net.name),
                "groundCapF": .scalar(net.groundCapF),
                "couplingCapF": .scalar(net.couplingCapF),
                "totalCapF": .scalar(totalCapF),
                "resistanceOhm": .scalar(net.resistanceOhm),
                "nodeCount": .scalar(Double(net.nodeCount)),
                "symbolicGoalAtoms": .textList(["parasitic-hotspot-reduced", "artifact:pex-summary"]),
            ],
            suggestedActions: [
                "identify_layout_geometry_for_hotspot_net",
                "evaluate_route_spacing_or_width_change",
                "rerun_pex_and_post_layout_simulation",
            ]
        )
    }

    func pexDiagnosticObjective(
        corner: PEXCornerParasiticSummary,
        diagnostic: PEXRunSummaryDiagnostic,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        XcircuitePlanningObjective(
            objectiveID: try identifier("pex-\(corner.cornerID)-diagnostic-\(diagnostic.code)-\(index + 1)"),
            kind: "satisfy",
            domain: "pex",
            priority: diagnostic.severity,
            sourceRefIDs: [summaryRefID],
            target: "resolve-pex-summary-diagnostic",
            currentValue: .text(diagnostic.code),
            requiredValue: .text("resolved"),
            description: "Resolve PEX summary diagnostic \(diagnostic.code) for corner \(corner.cornerID).",
            evidence: [
                "cornerID": .text(corner.cornerID),
                "severity": .text(diagnostic.severity),
                "code": .text(diagnostic.code),
                "message": .text(diagnostic.message),
                "symbolicGoalAtoms": .textList(["pex-summary-diagnostic-resolved", "artifact:pex-summary"]),
            ],
            suggestedActions: ["inspect_pex_artifacts", "rerun_pex_after_artifact_repair"]
        )
    }

    func pexCompletenessObjective(
        issue: PEXArtifactCompletenessIssue,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        var evidence: [String: PlanningParameterValue] = [
            "issueKind": .text(issue.kind.rawValue),
            "message": .text(issue.message),
            "symbolicGoalAtoms": .textList(["pex-artifact-set-complete", "artifact:pex-summary"]),
        ]
        insertOptional(issue.artifactID, key: "artifactID", into: &evidence)
        insertOptional(issue.cornerID?.value, key: "cornerID", into: &evidence)
        insertOptional(issue.location?.value, key: "path", into: &evidence)
        return XcircuitePlanningObjective(
            objectiveID: try identifier("pex-completeness-\(issue.kind.rawValue)-\(index + 1)"),
            kind: "satisfy",
            domain: "pex",
            priority: "error",
            sourceRefIDs: [summaryRefID],
            target: "complete-pex-artifact-set",
            currentValue: .text(issue.kind.rawValue),
            requiredValue: .text("complete"),
            description: "Repair incomplete PEX artifact evidence before metric recovery planning.",
            evidence: evidence,
            suggestedActions: ["repair_pex_artifact_manifest", "rerun_pex_summary"]
        )
    }

    func pexCandidateActions(
        objective: XcircuitePlanningObjective,
        index: Int,
        hasMetricReport: Bool,
        pexGateHints: [String: PlanningParameterValue]
    ) throws -> [XcircuitePlanningCandidateAction] {
        let requiredInputs = hasMetricReport
            ? ["pex-summary", "post-layout-metric-report", "source-netlist-ref", "layout-ref", "pex-technology-ref"]
            : ["pex-summary", "source-netlist-ref", "layout-ref", "pex-technology-ref"]
        let parameterHints = pexActionParameterHints(
            objective: objective,
            pexGateHints: pexGateHints
        )
        var actions: [XcircuitePlanningCandidateAction] = [
            XcircuitePlanningCandidateAction(
                actionID: try identifier("pex-metric-recovery-\(index + 1)"),
                domainID: "pex-extraction",
                operationID: "pex.metric-recovery-objective",
                maturity: "implemented",
                reason: "Convert the PEX summary evidence into a bounded post-layout recovery objective.",
                sourceObjectiveIDs: [objective.objectiveID],
                requiredInputRefs: requiredInputs,
                verificationGates: ["schema-validation", "pex-summary-gate", "simulation-metric-gate"],
                parameterHints: parameterHints
            ),
            XcircuitePlanningCandidateAction(
                actionID: try identifier("layout-pex-replay-\(index + 1)"),
                domainID: "layout-edit",
                operationID: "layout-command-replay",
                maturity: "implemented",
                reason: "Allow the planner to emit replayable layout edits after resolving hotspot geometry.",
                sourceObjectiveIDs: [objective.objectiveID],
                requiredInputRefs: ["layout-ref", "source-netlist-ref", "pex-technology-ref"],
                verificationGates: ["artifact-integrity", "native-drc", "native-lvs", "pex-summary-gate"],
                parameterHints: parameterHints
            ),
        ]
        if hasMetricReport {
            actions.append(
                XcircuitePlanningCandidateAction(
                    actionID: try identifier("simulation-metric-improvement-\(index + 1)"),
                    domainID: "simulation-analysis",
                    operationID: "simulation.metric-improvement-objective",
                    maturity: "implemented",
                    reason: "Tie PEX recovery candidates to post-layout simulation metric acceptance.",
                    sourceObjectiveIDs: [objective.objectiveID],
                    requiredInputRefs: ["post-layout-metric-report", "source-netlist-ref"],
                    verificationGates: ["schema-validation", "simulation-metric-gate"],
                    parameterHints: parameterHints
                )
            )
        }
        return actions
    }

    func pexActionParameterHints(
        objective: XcircuitePlanningObjective,
        pexGateHints: [String: PlanningParameterValue]
    ) -> [String: PlanningParameterValue] {
        var hints = mergedHints(objective.evidence, pexGateHints)
        let goalAtoms = pexGoalAtoms(in: objective.evidence)
        if !goalAtoms.isEmpty {
            hints["symbolicEffects"] = .textList(goalAtoms)
        }
        return hints
    }

    func pexGoalAtoms(in evidence: [String: PlanningParameterValue]) -> [String] {
        stableUniqueStrings(
            stringArrayValue(for: "symbolicGoalAtoms", in: evidence)
                + stringArrayValue(for: "goalAtoms", in: evidence)
                + stringArrayValue(for: "requiredEffects", in: evidence)
        )
    }

    func stringArrayValue(
        for key: String,
        in values: [String: PlanningParameterValue]
    ) -> [String] {
        guard case .textList(let array)? = values[key] else {
            return []
        }
        return array
    }

    func stableUniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    func pexGateInputHints(summary: PEXRunSummaryReport) -> [String: PlanningParameterValue] {
        [
            "pexInputs": .pexInputs(
                PlanningPEXInputs(
                    layoutReferenceID: "layout-ref",
                    sourceNetlistReferenceID: "source-netlist-ref",
                    technologyReferenceID: "pex-technology-ref",
                    backendID: summary.summary.backendID,
                    cornerIDs: summary.summary.corners.map(\.cornerID)
                )
            ),
        ]
    }

    func postLayoutMetricReportMetadata(
        _ report: PostLayoutComparisonReport?
    ) -> [String: PlanningParameterValue] {
        guard let report else {
            return [:]
        }
        return [
            "status": .text(report.status),
            "gateStatus": .text(report.gateStatus),
            "gateViolationCount": .scalar(Double(report.gateViolations.count)),
            "comparedVariableCount": .scalar(Double(report.comparedVariables.count)),
            "maxAbsoluteDelta": .scalar(report.maxAbsoluteDelta),
            "maxRelativeDelta": .scalar(report.maxRelativeDelta),
        ]
    }

    func mergedHints(
        _ lhs: [String: PlanningParameterValue],
        _ rhs: [String: PlanningParameterValue]
    ) -> [String: PlanningParameterValue] {
        var merged = lhs
        for (key, value) in rhs {
            merged[key] = value
        }
        return merged
    }
}
