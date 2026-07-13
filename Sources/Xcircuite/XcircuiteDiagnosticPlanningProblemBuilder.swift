import DRCEngine
import Foundation
import LVSEngine
import PEXEngine
import DesignFlowKernel

public struct XcircuiteDiagnosticPlanningProblemBuilder: Sendable {
    public init() {}

    public func makeDRCRepairProblem(
        runID: String,
        summary: DRCRunSummaryReport,
        summaryArtifactPath: String,
        layoutArtifactPath: String?,
        layoutNetlistPath: String? = nil,
        schematicNetlistPath: String? = nil,
        repairHints: DRCRepairHintReport? = nil,
        repairHintArtifactPath: String? = nil,
        actionDomainArtifactPath: String? = nil
    ) throws -> XcircuiteCircuitPlanningProblem {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let problemID = try identifier("\(runID)-drc-repair-problem")
        let summaryRef = XcircuitePlanningReference(
            refID: "drc-summary",
            kind: "drc-summary",
            path: summaryArtifactPath,
            artifactID: "drc-summary",
            metadata: [
                "activeViolationCount": .number(Double(summary.summary.activeViolationCount)),
                "waivedViolationCount": .number(Double(summary.summary.waivedViolationCount)),
                "topCell": .string(summary.summary.topCell),
            ]
        )
        let repairHintRef = repairHints.map { report in
            XcircuitePlanningReference(
                refID: "drc-repair-hints",
                kind: "drc-repair-hints",
                path: repairHintArtifactPath,
                artifactID: "drc-repair-hints",
                metadata: [
                    "status": .string(report.status),
                    "backendID": .string(report.backendID),
                    "topCell": .string(report.topCell),
                    "activeDiagnosticCount": .number(Double(report.activeDiagnosticCount)),
                    "hintCount": .number(Double(report.hintCount)),
                    "unsupportedDiagnosticIndexes": .array(
                        report.unsupportedDiagnosticIndexes.map { .number(Double($0)) }
                    ),
                ]
            )
        }
        let layoutRef = resolvableReference(
            refID: "layout-ref",
            kind: "layout",
            path: layoutArtifactPath
        )
        let layoutNetlistRef = resolvableReference(
            refID: "layout-netlist-ref",
            kind: "layout-netlist",
            path: layoutNetlistPath
        )
        let schematicNetlistRef = resolvableReference(
            refID: "schematic-netlist-ref",
            kind: "schematic-netlist",
            path: schematicNetlistPath
        )
        let actionDomainRef = XcircuitePlanningReference(
            refID: "action-domain-snapshot",
            kind: "action-domain-snapshot",
            path: actionDomainArtifactPath ?? actionDomainPath(runID: runID),
            artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID
        )
        let activeBuckets = summary.summary.violationBuckets.filter { $0.activeCount > 0 }
        let actionableHints = repairHints?.hints ?? []
        let objectives = !actionableHints.isEmpty
            ? try actionableHints.enumerated().map { index, hint in
                try drcObjective(
                    hint: hint,
                    index: index,
                    summaryRefID: summaryRef.refID,
                    repairHintRefID: repairHintRef?.refID
                )
            }
            : activeBuckets.isEmpty
            ? [cleanDRCObjective(summaryRefID: summaryRef.refID)]
            : try activeBuckets.enumerated().map { index, bucket in
                try drcObjective(bucket: bucket, index: index, summaryRefID: summaryRef.refID)
            }
        let candidateActions = !actionableHints.isEmpty
            ? try actionableHints.enumerated().map { index, hint in
                try drcCandidateAction(
                    hint: hint,
                    objectiveID: objectives[index].objectiveID,
                    index: index,
                    includesLVSRefs: layoutNetlistPath != nil && schematicNetlistPath != nil,
                    topCell: summary.summary.topCell
                )
            }
            : try activeBuckets.enumerated().flatMap { index, bucket in
            try drcCandidateActions(
                bucket: bucket,
                objectiveID: objectives[index].objectiveID,
                index: index,
                includesLVSRefs: layoutNetlistPath != nil && schematicNetlistPath != nil,
                topCell: summary.summary.topCell
            )
        }

        return XcircuiteCircuitPlanningProblem(
            problemID: problemID,
            runID: runID,
            sourceRefs: [summaryRef] + (repairHintRef.map { [$0] } ?? []),
            initialStateRefs: [layoutRef, layoutNetlistRef, schematicNetlistRef, actionDomainRef].compactMap { $0 },
            assumptions: generatedAssumptions(
                domain: "drc",
                summaryRefID: summaryRef.refID,
                actionDomainRefID: actionDomainRef.refID
            ),
            riskClassifications: drcRiskClassifications(
                objectives: objectives,
                candidateActions: candidateActions
            ),
            objectives: objectives,
            constraints: drcConstraints(
                summaryRefID: summaryRef.refID,
                repairHintRefID: repairHintRef?.refID
            ),
            actionDomainRefs: ["drc-signoff", "layout-edit", "lvs-signoff"],
            candidateActions: candidateActions,
            costModel: defaultCostModel(primaryDomain: "drc"),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "The repaired candidate must pass DRC with no active error diagnostics."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Physical DRC repairs must not introduce an LVS mismatch."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "All produced artifacts must verify by path, SHA-256, and byte count."
                ),
            ],
            resumeContract: defaultResumeContract()
        )
    }

    public func makeLVSRepairProblem(
        runID: String,
        summary: LVSRunSummaryReport,
        summaryArtifactPath: String,
        layoutArtifactPath: String?,
        layoutNetlistPath: String? = nil,
        schematicNetlistPath: String? = nil,
        repairHints: LVSRepairHintReport? = nil,
        repairHintArtifactPath: String? = nil,
        actionDomainArtifactPath: String? = nil
    ) throws -> XcircuiteCircuitPlanningProblem {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let problemID = try identifier("\(runID)-lvs-repair-problem")
        let summaryRef = XcircuitePlanningReference(
            refID: "lvs-summary",
            kind: "lvs-summary",
            path: summaryArtifactPath,
            artifactID: "lvs-summary",
            metadata: [
                "activeMismatchCount": .number(Double(summary.summary.activeMismatchCount)),
                "waivedMismatchCount": .number(Double(summary.summary.waivedMismatchCount)),
                "topCell": .string(summary.summary.topCell),
                "layoutInputKind": .string(summary.summary.layoutInputKind),
            ]
        )
        let repairHintRef = repairHints.map { report in
            XcircuitePlanningReference(
                refID: "lvs-repair-hints",
                kind: "lvs-repair-hints",
                path: repairHintArtifactPath,
                artifactID: "lvs-repair-hints",
                metadata: [
                    "status": .string(report.status),
                    "backendID": .string(report.backendID),
                    "topCell": .string(report.topCell),
                    "activeDiagnosticCount": .number(Double(report.activeDiagnosticCount)),
                    "hintCount": .number(Double(report.hintCount)),
                    "unsupportedDiagnosticIndexes": .array(
                        report.unsupportedDiagnosticIndexes.map { .number(Double($0)) }
                    ),
                ]
            )
        }
        let layoutRef = resolvableReference(
            refID: "layout-ref",
            kind: "layout",
            path: layoutArtifactPath
        )
        let layoutNetlistRef = resolvableReference(
            refID: "layout-netlist-ref",
            kind: "layout-netlist",
            path: layoutNetlistPath
        )
        let schematicRef = resolvableReference(
            refID: "schematic-netlist-ref",
            kind: "schematic-netlist",
            path: schematicNetlistPath
        )
        let actionDomainRef = XcircuitePlanningReference(
            refID: "action-domain-snapshot",
            kind: "action-domain-snapshot",
            path: actionDomainArtifactPath ?? actionDomainPath(runID: runID),
            artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID
        )
        let activeBuckets = summary.summary.mismatchBuckets.filter { $0.activeCount > 0 }
        let actionableHints = repairHints?.hints ?? []
        let objectives = !actionableHints.isEmpty
            ? try actionableHints.enumerated().map { index, hint in
                try lvsObjective(
                    hint: hint,
                    index: index,
                    summaryRefID: summaryRef.refID,
                    repairHintRefID: repairHintRef?.refID
                )
            }
            : activeBuckets.isEmpty
            ? [cleanLVSObjective(summaryRefID: summaryRef.refID)]
            : try activeBuckets.enumerated().map { index, bucket in
                try lvsObjective(bucket: bucket, index: index, summaryRefID: summaryRef.refID)
            }
        let candidateActions = !actionableHints.isEmpty
            ? try actionableHints.enumerated().map { index, hint in
                try lvsCandidateAction(
                    hint: hint,
                    objectiveID: objectives[index].objectiveID,
                    index: index,
                    includesLVSRefs: layoutNetlistPath != nil && schematicNetlistPath != nil,
                    topCell: summary.summary.topCell
                )
            }
            : try activeBuckets.enumerated().flatMap { index, bucket in
                try lvsCandidateActions(
                    bucket: bucket,
                    objectiveID: objectives[index].objectiveID,
                    index: index,
                    includesLVSRefs: layoutNetlistPath != nil && schematicNetlistPath != nil,
                    topCell: summary.summary.topCell
                )
            }

        return XcircuiteCircuitPlanningProblem(
            problemID: problemID,
            runID: runID,
            sourceRefs: [summaryRef] + (repairHintRef.map { [$0] } ?? []),
            initialStateRefs: [layoutRef, layoutNetlistRef, schematicRef, actionDomainRef].compactMap { $0 },
            assumptions: generatedAssumptions(
                domain: "lvs",
                summaryRefID: summaryRef.refID,
                actionDomainRefID: actionDomainRef.refID
            ),
            riskClassifications: lvsRiskClassifications(
                objectives: objectives,
                candidateActions: candidateActions
            ),
            objectives: objectives,
            constraints: lvsConstraints(
                summaryRefID: summaryRef.refID,
                repairHintRefID: repairHintRef?.refID
            ),
            actionDomainRefs: lvsActionDomainRefs(candidateActions: candidateActions),
            candidateActions: candidateActions,
            costModel: defaultCostModel(primaryDomain: "lvs"),
            verificationGates: lvsProblemVerificationGates(candidateActions: candidateActions),
            resumeContract: defaultResumeContract()
        )
    }

    public func makePEXRecoveryProblem(
        runID: String,
        summary: PEXRunSummaryReport,
        summaryArtifactPath: String,
        layoutArtifactPath: String?,
        sourceNetlistPath: String?,
        technologyArtifactPath: String? = nil,
        metricReportPath: String? = nil,
        metricReport: PostLayoutComparisonReport? = nil,
        actionDomainArtifactPath: String? = nil
    ) throws -> XcircuiteCircuitPlanningProblem {
        try XcircuiteIdentifierValidator().validate(runID, kind: .runID)
        let problemID = try identifier("\(runID)-pex-recovery-problem")
        let summaryRef = XcircuitePlanningReference(
            refID: "pex-summary",
            kind: "pex-summary",
            path: summaryArtifactPath,
            artifactID: "pex-summary",
            metadata: [
                "pexRunID": .string(summary.summary.runID),
                "status": .string(summary.summary.status),
                "backendID": .string(summary.summary.backendID),
                "cornerCount": .number(Double(summary.summary.corners.count)),
                "completenessStatus": .string(summary.completeness.status.rawValue),
                "completenessIssueCount": .number(Double(summary.completeness.issues.count)),
            ]
        )
        let layoutRef = resolvableReference(
            refID: "layout-ref",
            kind: "layout",
            path: layoutArtifactPath
        )
        let sourceNetlistRef = resolvableReference(
            refID: "source-netlist-ref",
            kind: "source-netlist",
            path: sourceNetlistPath
        )
        let technologyRef = resolvableReference(
            refID: "pex-technology-ref",
            kind: "pex-technology",
            path: technologyArtifactPath
        )
        let metricReportRef = XcircuitePlanningReference(
            refID: "post-layout-metric-report",
            kind: "metric-report",
            path: metricReportPath,
            metadata: postLayoutMetricReportMetadata(metricReport)
        )
        let actionDomainRef = XcircuitePlanningReference(
            refID: "action-domain-snapshot",
            kind: "action-domain-snapshot",
            path: actionDomainArtifactPath ?? actionDomainPath(runID: runID),
            artifactID: XcircuitePlanningArtifactStore.actionDomainArtifactID
        )
        let objectives = try pexObjectives(
            summary: summary,
            summaryRefID: summaryRef.refID,
            metricReport: metricReport,
            metricReportRefID: metricReportRef.refID
        )
        let sourceRefs = metricReportPath == nil ? [summaryRef] : [summaryRef, metricReportRef]
        let initialStateRefs = [layoutRef, sourceNetlistRef, technologyRef, actionDomainRef].compactMap { $0 }
        let pexGateHints = pexGateInputHints(summary: summary)
        let candidateActions = try objectives.enumerated().flatMap { index, objective in
            try pexCandidateActions(
                objective: objective,
                index: index,
                hasMetricReport: metricReportPath != nil,
                pexGateHints: pexGateHints
            )
        }

        return XcircuiteCircuitPlanningProblem(
            problemID: problemID,
            runID: runID,
            sourceRefs: sourceRefs,
            initialStateRefs: initialStateRefs,
            assumptions: generatedAssumptions(
                domain: "pex",
                summaryRefID: summaryRef.refID,
                actionDomainRefID: actionDomainRef.refID
            ),
            riskClassifications: pexRiskClassifications(
                objectives: objectives,
                candidateActions: candidateActions,
                hasMetricReport: metricReportPath != nil
            ),
            objectives: objectives,
            constraints: pexConstraints(
                summaryRefID: summaryRef.refID,
                metricReportRefID: metricReportRef.refID,
                hasMetricReport: metricReportPath != nil
            ),
            actionDomainRefs: ["pex-extraction", "simulation-analysis", "layout-edit", "drc-signoff", "lvs-signoff"],
            candidateActions: candidateActions,
            costModel: pexCostModel(),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary-gate",
                    required: true,
                    description: "The candidate must reduce or preserve declared PEX hotspot metrics."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: metricReportPath != nil,
                    description: "When a metric report is provided, post-layout simulation metrics must satisfy the requested bounds."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Layout-side PEX recovery edits must not introduce DRC violations."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Layout-side PEX recovery edits must preserve LVS equivalence."
                ),
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "All produced artifacts must verify by path, SHA-256, and byte count."
                ),
            ],
            resumeContract: defaultResumeContract()
        )
    }

    private func resolvableReference(
        refID: String,
        kind: String,
        path: String?,
        artifactID: String? = nil,
        metadata: [String: XcircuiteJSONValue] = [:]
    ) -> XcircuitePlanningReference? {
        guard path != nil || artifactID != nil else {
            return nil
        }
        return XcircuitePlanningReference(
            refID: refID,
            kind: kind,
            path: path,
            artifactID: artifactID,
            metadata: metadata
        )
    }
}
