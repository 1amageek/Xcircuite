import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import XcircuitePackage

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
                    currentValue: .number(0),
                    requiredValue: .number(0),
                    description: "PEX summary contains no hotspots or diagnostics requiring a recovery plan.",
                    evidence: [
                        "symbolicGoalAtoms": .array([
                            .string("pex-summary-available"),
                            .string("artifact:pex-summary"),
                        ]),
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
            currentValue: .string(report.gateStatus),
            requiredValue: .string("passed"),
            description: "Recover post-layout simulation metrics until the comparison gate passes.",
            evidence: [
                "metricReportRefID": .string(metricReportRefID),
                "status": .string(report.status),
                "gateStatus": .string(report.gateStatus),
                "gateViolations": .array(report.gateViolations.map { .string($0) }),
                "maxAbsoluteDelta": .number(report.maxAbsoluteDelta),
                "maxRelativeDelta": .number(report.maxRelativeDelta),
                "comparedVariableCount": .number(Double(report.comparedVariables.count)),
                "missingPostLayoutVariables": .array(report.missingInPostLayout.map { .string($0) }),
                "addedPostLayoutVariables": .array(report.addedInPostLayout.map { .string($0) }),
                "symbolicGoalAtoms": .array([
                    .string("post-layout-metric-gate-passed"),
                    .string("artifact:simulation-metric-report"),
                ]),
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
            currentValue: .number(variable.maxRelativeDelta),
            requiredValue: nil,
            unit: "ratio",
            description: "Reduce post-layout waveform delta for variable \(variable.variableName).",
            evidence: [
                "metricReportRefID": .string(metricReportRefID),
                "variableName": .string(variable.variableName),
                "pointCount": .number(Double(variable.pointCount)),
                "maxAbsoluteDelta": .number(variable.maxAbsoluteDelta),
                "maxRelativeDelta": .number(variable.maxRelativeDelta),
                "symbolicGoalAtoms": .array([
                    .string("post-layout-variable-delta-reduced"),
                    .string("artifact:simulation-metric-report"),
                ]),
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
            currentValue: .string("missing"),
            requiredValue: .string("present"),
            description: "Restore required post-layout variable \(variable.variableName).",
            evidence: [
                "metricReportRefID": .string(metricReportRefID),
                "variableName": .string(variable.variableName),
                "present": .bool(variable.present),
                "symbolicGoalAtoms": .array([
                    .string("post-layout-variable-present"),
                    .string("artifact:simulation-metric-report"),
                ]),
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
        var evidence: [String: XcircuiteJSONValue] = [
            "metricReportRefID": .string(metricReportRefID),
            "variableName": .string(metric.variableName),
            "violations": .array(metric.violations.map { .string($0) }),
            "symbolicGoalAtoms": .array([
                .string("post-layout-oscillation-metric-recovered"),
                .string("artifact:simulation-metric-report"),
            ]),
        ]
        insertOptional(metric.frequencyRelativeDelta, key: "frequencyRelativeDelta", into: &evidence)
        if let postLayout = metric.postLayout {
            evidence["postLayoutAmplitude"] = .number(postLayout.amplitude)
            insertOptional(postLayout.frequency, key: "postLayoutFrequency", into: &evidence)
            insertOptional(postLayout.averagePeriod, key: "postLayoutAveragePeriod", into: &evidence)
            evidence["postLayoutTransitionCount"] = .number(Double(postLayout.transitionCount))
            insertOptional(postLayout.dutyCycle, key: "postLayoutDutyCycle", into: &evidence)
        }
        return XcircuitePlanningObjective(
            objectiveID: try identifier("post-layout-oscillation-\(metric.variableName)-\(index + 1)"),
            kind: "satisfy",
            domain: "simulation",
            priority: "error",
            sourceRefIDs: [metricReportRefID],
            target: "recover-post-layout-oscillation-metric",
            currentValue: .string("violating"),
            requiredValue: .string("passed"),
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
            currentValue: .number(totalCapF),
            requiredValue: nil,
            unit: "F",
            description: "Reduce parasitic hotspot on net \(net.name) in corner \(cornerID).",
            evidence: [
                "cornerID": .string(cornerID),
                "netName": .string(net.name),
                "groundCapF": .number(net.groundCapF),
                "couplingCapF": .number(net.couplingCapF),
                "totalCapF": .number(totalCapF),
                "resistanceOhm": .number(net.resistanceOhm),
                "nodeCount": .number(Double(net.nodeCount)),
                "symbolicGoalAtoms": .array([
                    .string("parasitic-hotspot-reduced"),
                    .string("artifact:pex-summary"),
                ]),
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
            currentValue: .string(diagnostic.code),
            requiredValue: .string("resolved"),
            description: "Resolve PEX summary diagnostic \(diagnostic.code) for corner \(corner.cornerID).",
            evidence: [
                "cornerID": .string(corner.cornerID),
                "severity": .string(diagnostic.severity),
                "code": .string(diagnostic.code),
                "message": .string(diagnostic.message),
                "symbolicGoalAtoms": .array([
                    .string("pex-summary-diagnostic-resolved"),
                    .string("artifact:pex-summary"),
                ]),
            ],
            suggestedActions: ["inspect_pex_artifacts", "rerun_pex_after_artifact_repair"]
        )
    }

    func pexCompletenessObjective(
        issue: PEXArtifactCompletenessIssue,
        index: Int,
        summaryRefID: String
    ) throws -> XcircuitePlanningObjective {
        var evidence: [String: XcircuiteJSONValue] = [
            "issueKind": .string(issue.kind.rawValue),
            "message": .string(issue.message),
            "symbolicGoalAtoms": .array([
                .string("pex-artifact-set-complete"),
                .string("artifact:pex-summary"),
            ]),
        ]
        insertOptional(issue.artifactID, key: "artifactID", into: &evidence)
        insertOptional(issue.cornerID?.value, key: "cornerID", into: &evidence)
        insertOptional(issue.path?.value, key: "path", into: &evidence)
        return XcircuitePlanningObjective(
            objectiveID: try identifier("pex-completeness-\(issue.kind.rawValue)-\(index + 1)"),
            kind: "satisfy",
            domain: "pex",
            priority: "error",
            sourceRefIDs: [summaryRefID],
            target: "complete-pex-artifact-set",
            currentValue: .string(issue.kind.rawValue),
            requiredValue: .string("complete"),
            description: "Repair incomplete PEX artifact evidence before metric recovery planning.",
            evidence: evidence,
            suggestedActions: ["repair_pex_artifact_manifest", "rerun_pex_summary"]
        )
    }

    func pexCandidateActions(
        objective: XcircuitePlanningObjective,
        index: Int,
        hasMetricReport: Bool,
        pexGateHints: [String: XcircuiteJSONValue]
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
        pexGateHints: [String: XcircuiteJSONValue]
    ) -> [String: XcircuiteJSONValue] {
        var hints = mergedHints(objective.evidence, pexGateHints)
        let goalAtoms = pexGoalAtoms(in: objective.evidence)
        if !goalAtoms.isEmpty {
            hints["symbolicEffects"] = .array(goalAtoms.map { .string($0) })
        }
        return hints
    }

    func pexGoalAtoms(in evidence: [String: XcircuiteJSONValue]) -> [String] {
        stableUniqueStrings(
            stringArrayValue(for: "symbolicGoalAtoms", in: evidence)
                + stringArrayValue(for: "goalAtoms", in: evidence)
                + stringArrayValue(for: "requiredEffects", in: evidence)
        )
    }

    func stringArrayValue(
        for key: String,
        in values: [String: XcircuiteJSONValue]
    ) -> [String] {
        guard case .array(let array)? = values[key] else {
            return []
        }
        return array.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
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

    func pexGateInputHints(summary: PEXRunSummaryReport) -> [String: XcircuiteJSONValue] {
        [
            "pexInputs": .object([
                "layoutRef": .string("layout-ref"),
                "sourceNetlistRef": .string("source-netlist-ref"),
                "technologyRef": .string("pex-technology-ref"),
                "backendID": .string(summary.summary.backendID),
                "corners": .array(summary.summary.corners.map { .string($0.cornerID) }),
            ]),
        ]
    }

    func postLayoutMetricReportMetadata(
        _ report: PostLayoutComparisonReport?
    ) -> [String: XcircuiteJSONValue] {
        guard let report else {
            return [:]
        }
        return [
            "status": .string(report.status),
            "gateStatus": .string(report.gateStatus),
            "gateViolationCount": .number(Double(report.gateViolations.count)),
            "comparedVariableCount": .number(Double(report.comparedVariables.count)),
            "maxAbsoluteDelta": .number(report.maxAbsoluteDelta),
            "maxRelativeDelta": .number(report.maxRelativeDelta),
        ]
    }

    func mergedHints(
        _ lhs: [String: XcircuiteJSONValue],
        _ rhs: [String: XcircuiteJSONValue]
    ) -> [String: XcircuiteJSONValue] {
        var merged = lhs
        for (key, value) in rhs {
            merged[key] = value
        }
        return merged
    }
}
