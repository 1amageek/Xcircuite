import DRCEngine
import Foundation
import LVSEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import XcircuitePackage

@Suite("Xcircuite diagnostic planning problem builder")
struct XcircuiteDiagnosticPlanningProblemBuilderTests {
    @Test func drcSummaryBecomesPlanningProblemAndRunArtifact() throws {
        let root = try makeTemporaryRoot("drc-planning")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        let summary = DRCRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: DRCRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native DRC",
                topCell: "TOP",
                layoutFormat: "gds",
                passed: false,
                completed: true,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeViolationCount: 1,
                waivedViolationCount: 0,
                violationBuckets: [
                    DRCViolationBucketSummary(
                        ruleID: "M1.width",
                        kind: "minimumWidth",
                        layer: "M1",
                        activeCount: 1,
                        waivedCount: 0,
                        maxMeasured: 0.12,
                        required: 0.14,
                        relatedShapeIDs: ["shape-1"],
                        relatedNetIDs: ["net-vdd"],
                        suggestedFixes: ["increase_width"]
                    ),
                ],
                unusedWaiverIDs: []
            )
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-1",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-1/stages/006-layout/raw/layout.gds"
        )
        let reference = try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: "run-1",
            projectRoot: root
        )

        #expect(problem.problemID == "run-1-drc-repair-problem")
        #expect(problem.actionDomainRefs == ["drc-signoff", "layout-edit", "lvs-signoff"])
        #expect(problem.assumptions.map(\.assumptionID) == [
            "drc-summary-current",
            "drc-action-domain-current",
        ])
        #expect(problem.riskClassifications.contains {
            $0.riskID == "drc-layout-edit-regression-risk"
                && $0.severity == "medium"
                && $0.affectedActionIDs == problem.candidateActions.map(\.actionID)
        })
        #expect(problem.objectives.map(\.target) == ["no-active-violations-for-bucket"])
        #expect(problem.objectives.first?.evidence["ruleID"] == .string("M1.width"))
        #expect(problem.objectives.first?.evidence["problemSourceOperation"] == .string("xcircuite.generate-planning-problem"))
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("drc.run-native"))
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("shape-size-updated"),
            .string("artifact:layout-document"),
        ]))
        #expect(!problem.candidateActions.contains {
            $0.domainID == "drc-signoff"
                && $0.operationID == "drc.diagnostic-to-repair-objective"
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "layout-edit"
                && $0.operationID == "layout.resize-shape"
                && $0.maturity == "implemented"
                && $0.parameterHints["shapeID"] == .string("shape-1")
                && $0.parameterHints["deltaMaxX"] == .number(0.020000000000000018)
        })
        #expect(reference.artifactID == XcircuitePlanningArtifactStore.problemArtifactID)
        #expect(reference.path == ".xcircuite/runs/run-1/planning/problem.json")
        #expect(reference.sha256?.isEmpty == false)
        #expect(reference.byteCount != nil)

        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: root.appending(path: ".xcircuite/runs/run-1/manifest.json")
        )
        #expect(manifest.artifacts.contains {
            $0.artifactID == XcircuitePlanningArtifactStore.problemArtifactID
                && $0.path == reference.path
        })
        let loaded = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: reference.path)
        )
        #expect(loaded == problem)
        try expectValidPlanningProblem(problem, problemPath: reference.path)
    }

    @Test func drcRepairHintsBecomeEngineOwnedPlanningCandidates() throws {
        let summary = makeDRCSummary()
        let hints = makeDRCRepairHints()

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-drc-hints/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-drc-hints/stages/006-layout/raw/layout.gds",
            layoutNetlistPath: "circuits/layout.spice",
            schematicNetlistPath: "circuits/schematic.spice",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-drc-hints/stages/007-drc/raw/drc-repair-hints.json"
        )

        #expect(problem.sourceRefs.contains {
            $0.refID == "drc-repair-hints"
                && $0.kind == "drc-repair-hints"
                && $0.path == ".xcircuite/runs/run-drc-hints/stages/007-drc/raw/drc-repair-hints.json"
        })
        #expect(problem.objectives.first?.sourceRefIDs == ["drc-summary", "drc-repair-hints"])
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("drc.export-repair-hints"))
        #expect(problem.objectives.first?.evidence["sourceRepairHintID"] == .string("drc-repair-0-M1-width"))
        #expect(problem.objectives.first?.evidence["repairHintConfidence"] == .string("high"))
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("shape-size-updated"),
            .string("artifact:layout-document"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.operationID == "layout.resize-shape")
        #expect(action.reason == "M1.width maps to layout.resize-shape.")
        #expect(action.parameterHints["sourceRepairHintID"] == .string("drc-repair-0-M1-width"))
        #expect(action.parameterHints["repairHintConfidence"] == .string("high"))
        #expect(action.parameterHints["shapeID"] == .string("shape-1"))
        #expect(action.parameterHints["deltaMaxX"] == .number(0.02))
        #expect(action.parameterHints["lvsInputs"] != nil)
        #expect(action.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-drc-hints/planning/problem.json")
    }

    @Test func drcRepairProblemDoesNotInventUnresolvableLayoutReference() throws {
        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-missing-layout",
            summary: makeDRCSummary(),
            summaryArtifactPath: ".xcircuite/runs/run-drc-missing-layout/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: nil
        )

        #expect(problem.initialStateRefs.contains { $0.refID == "layout-ref" } == false)
        let action = try #require(problem.candidateActions.first)
        #expect(action.requiredInputRefs.contains("layout-ref"))

        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: problem.runID,
            generatedAt: "2026-06-21T00:00:00Z"
        )
        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: ".xcircuite/runs/run-drc-missing-layout/planning/problem.json",
            actionDomainSnapshot: snapshot
        )

        #expect(validation.status == "invalid")
        #expect(validation.diagnostics.contains {
            $0.severity == "error"
                && $0.code == "candidate-action-required-ref-missing"
                && $0.refID == "layout-ref"
                && $0.actionID == action.actionID
        })
    }

    @Test func drcViaRepairHintPreservesRelatedViaIDsInPlanningCandidates() throws {
        let summary = makeDRCSummary()
        let hints = DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-via1-minimum-cut",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.add-via",
                    confidence: "medium",
                    ruleID: "via1.minimumCut",
                    kind: "minimumCut",
                    layer: "via1",
                    targetShapeIDs: ["lower", "upper", "cut-a"],
                    relatedViaIDs: ["cut-a"],
                    relatedNetIDs: ["sig"],
                    region: DRCRegion(x: 0, y: 0, width: 2, height: 2),
                    measured: 1,
                    required: 2,
                    numericParameters: [
                        "positionX": 1,
                        "positionY": 1,
                        "existingCutCount": 1,
                        "requiredCutCount": 2,
                        "missingCutCount": 1,
                    ],
                    stringParameters: [
                        "viaDefinitionID": "VIA1",
                        "cutLayer": "via1",
                        "existingCutIDs": "cut-a",
                    ],
                    verificationGates: ["native-drc", "artifact-integrity", "native-lvs"],
                    rationale: "via1.minimumCut maps to layout.add-via."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-via-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-drc-via-hints/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-drc-via-hints/stages/006-layout/raw/layout.gds",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-drc-via-hints/stages/007-drc/raw/drc-repair-hints.json"
        )

        let objective = try #require(problem.objectives.first)
        #expect(objective.evidence["relatedViaIDs"] == .array([.string("cut-a")]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.operationID == "layout.add-via")
        #expect(action.parameterHints["relatedViaIDs"] == .array([.string("cut-a")]))
        #expect(action.parameterHints["positionX"] == .number(1))
        #expect(action.parameterHints["viaDefinitionID"] == .string("VIA1"))
        #expect(action.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-drc-via-hints/planning/problem.json")
    }

    @Test func drcEnclosedAreaRepairHintBecomesFillRectCandidate() throws {
        let summary = makeDRCSummary()
        let hints = DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-met1-enclosed-area",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.add-rect",
                    confidence: "medium",
                    ruleID: "met1.enclosedArea",
                    kind: "minimumEnclosedArea",
                    layer: "met1",
                    targetShapeIDs: ["left", "right", "bottom", "top"],
                    relatedNetIDs: [],
                    region: DRCRegion(x: 1, y: 1, width: 0.2, height: 0.2),
                    measured: 0.04,
                    required: 0.1,
                    numericParameters: [
                        "originX": 1,
                        "originY": 1,
                        "width": 0.2,
                        "height": 0.2,
                        "enclosedArea": 0.04,
                        "requiredEnclosedArea": 0.1,
                    ],
                    stringParameters: [
                        "layer": "met1",
                        "fillPurpose": "minimumEnclosedArea",
                    ],
                    verificationGates: ["native-drc", "artifact-integrity", "native-lvs"],
                    rationale: "met1.enclosedArea maps to layout.add-rect."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-enclosed-area-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-drc-enclosed-area-hints/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-drc-enclosed-area-hints/stages/006-layout/raw/layout.gds",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-drc-enclosed-area-hints/stages/007-drc/raw/drc-repair-hints.json"
        )

        let objective = try #require(problem.objectives.first)
        #expect(objective.evidence["repairHintOperationID"] == .string("layout.add-rect"))
        #expect(objective.evidence["symbolicGoalAtoms"] == .array([
            .string("rect-shape-created"),
            .string("artifact:layout-document"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.operationID == "layout.add-rect")
        #expect(action.parameterHints["fillPurpose"] == .string("minimumEnclosedArea"))
        #expect(action.parameterHints["originX"] == .number(1))
        #expect(action.parameterHints["originY"] == .number(1))
        #expect(action.parameterHints["width"] == .number(0.2))
        #expect(action.parameterHints["height"] == .number(0.2))
        #expect(action.parameterHints["enclosedArea"] == .number(0.04))
        #expect(action.parameterHints["requiredEnclosedArea"] == .number(0.1))
        #expect(action.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])
        try expectValidPlanningProblem(
            problem,
            problemPath: ".xcircuite/runs/run-drc-enclosed-area-hints/planning/problem.json"
        )
    }

    @Test func drcMinimumDensityRepairHintBecomesFillRectCandidate() throws {
        let summary = makeDRCSummary()
        let fillSide = sqrt(0.1375)
        let fillOrigin = (1.0 - fillSide) / 2.0
        let hints = DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-met1-minimum-density",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.add-rect",
                    confidence: "medium",
                    ruleID: "met1.minimumDensity",
                    kind: "minimumDensity",
                    layer: "met1",
                    targetShapeIDs: ["sparse"],
                    relatedNetIDs: [],
                    region: DRCRegion(x: 0, y: 0, width: 1, height: 1),
                    measured: 0.0625,
                    required: 0.2,
                    numericParameters: [
                        "originX": fillOrigin,
                        "originY": fillOrigin,
                        "width": fillSide,
                        "height": fillSide,
                        "densityWindowX": 0,
                        "densityWindowY": 0,
                        "densityWindowWidth": 1,
                        "densityWindowHeight": 1,
                        "densityWindowArea": 1,
                        "measuredDensity": 0.0625,
                        "requiredDensity": 0.2,
                        "targetFillArea": 0.1375,
                    ],
                    stringParameters: [
                        "layer": "met1",
                        "fillPurpose": "minimumDensity",
                    ],
                    verificationGates: ["native-drc", "artifact-integrity", "native-lvs"],
                    rationale: "met1.minimumDensity maps to layout.add-rect."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-min-density-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-drc-min-density-hints/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-drc-min-density-hints/stages/006-layout/raw/layout.gds",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-drc-min-density-hints/stages/007-drc/raw/drc-repair-hints.json"
        )

        let objective = try #require(problem.objectives.first)
        #expect(objective.evidence["repairHintOperationID"] == .string("layout.add-rect"))
        #expect(objective.evidence["symbolicGoalAtoms"] == .array([
            .string("rect-shape-created"),
            .string("artifact:layout-document"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.operationID == "layout.add-rect")
        #expect(action.parameterHints["fillPurpose"] == .string("minimumDensity"))
        #expect(action.parameterHints["originX"] == .number(fillOrigin))
        #expect(action.parameterHints["originY"] == .number(fillOrigin))
        #expect(action.parameterHints["width"] == .number(fillSide))
        #expect(action.parameterHints["height"] == .number(fillSide))
        #expect(action.parameterHints["densityWindowArea"] == .number(1))
        #expect(action.parameterHints["measuredDensity"] == .number(0.0625))
        #expect(action.parameterHints["requiredDensity"] == .number(0.2))
        #expect(action.parameterHints["targetFillArea"] == .number(0.1375))
        #expect(action.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])
        try expectValidPlanningProblem(
            problem,
            problemPath: ".xcircuite/runs/run-drc-min-density-hints/planning/problem.json"
        )
    }

    @Test func drcOverlapRepairHintCarriesExecutableTranslationVector() throws {
        let summary = makeDRCSummary()
        let hints = DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-met1-different-net-overlap",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.translate-shape",
                    confidence: "medium",
                    ruleID: "met1.differentNetOverlap",
                    kind: "differentNetOverlap",
                    layer: "met1",
                    targetShapeIDs: ["short-left", "short-right"],
                    relatedNetIDs: ["a", "b"],
                    region: DRCRegion(x: 0.8, y: 0.2, width: 0.2, height: 0.6),
                    measured: 0.12,
                    required: 0,
                    numericParameters: [
                        "minimumSeparationDelta": 0,
                        "deltaX": -0.2,
                        "deltaY": 0,
                        "translationDistance": 0.2,
                        "overlapWidth": 0.2,
                        "overlapHeight": 0.6,
                        "overlapArea": 0.12,
                    ],
                    stringParameters: [
                        "shapeID": "short-left",
                        "anchorShapeID": "short-right",
                        "translationAxis": "horizontal",
                        "translationReason": "overlapSeparation",
                    ],
                    verificationGates: ["native-drc", "artifact-integrity", "native-lvs"],
                    rationale: "met1.differentNetOverlap maps to layout.translate-shape."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-drc-overlap-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-drc-overlap-hints/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-drc-overlap-hints/stages/006-layout/raw/layout.gds",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-drc-overlap-hints/stages/007-drc/raw/drc-repair-hints.json"
        )

        let objective = try #require(problem.objectives.first)
        #expect(objective.evidence["repairHintOperationID"] == .string("layout.translate-shape"))
        #expect(objective.evidence["symbolicGoalAtoms"] == .array([
            .string("shape-position-updated"),
            .string("artifact:layout-document"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.operationID == "layout.translate-shape")
        #expect(action.parameterHints["shapeID"] == .string("short-left"))
        #expect(action.parameterHints["anchorShapeID"] == .string("short-right"))
        #expect(action.parameterHints["translationAxis"] == .string("horizontal"))
        #expect(action.parameterHints["translationReason"] == .string("overlapSeparation"))
        #expect(action.parameterHints["deltaX"] == .number(-0.2))
        #expect(action.parameterHints["deltaY"] == .number(0))
        #expect(action.parameterHints["translationDistance"] == .number(0.2))
        #expect(action.parameterHints["overlapArea"] == .number(0.12))
        #expect(action.verificationGates == ["native-drc", "artifact-integrity", "native-lvs"])
        try expectValidPlanningProblem(
            problem,
            problemPath: ".xcircuite/runs/run-drc-overlap-hints/planning/problem.json"
        )
    }

    @Test func lvsSummaryCreatesPolicyRepairCandidate() throws {
        let summary = LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "TOP",
                layoutInputKind: "layout-gds",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "model-mismatch",
                        category: "model-equivalence",
                        componentSignature: "M1",
                        parameterName: nil,
                        layoutModel: "nfet_01v8",
                        schematicModel: "nfet",
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: 1,
                        schematicCount: 1,
                        layoutPorts: ["D", "G", "S"],
                        schematicPorts: ["D", "G", "S"],
                        suggestedFixes: ["review_model_equivalence_policy"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeLVSRepairProblem(
            runID: "run-2",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-2/stages/008-lvs/raw/lvs-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-2/stages/006-layout/raw/layout.gds",
            schematicNetlistPath: "circuits/top.spice"
        )

        #expect(problem.problemID == "run-2-lvs-repair-problem")
        #expect(problem.actionDomainRefs == ["lvs-signoff", "layout-edit", "drc-signoff"])
        #expect(problem.assumptions.map(\.assumptionID) == [
            "lvs-summary-current",
            "lvs-action-domain-current",
        ])
        #expect(problem.riskClassifications.contains {
            $0.riskID == "lvs-policy-mutation-risk"
                && $0.severity == "high"
                && $0.requiredApprovals == ["policy-repair-approval"]
                && $0.affectedActionIDs == ["lvs-policy-1"]
        })
        #expect(problem.objectives.map(\.target) == ["layout-and-schematic-equivalent-for-bucket"])
        #expect(problem.objectives.first?.evidence["category"] == .string("model-equivalence"))
        #expect(problem.objectives.first?.evidence["problemSourceOperation"] == .string("xcircuite.generate-planning-problem"))
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("lvs.run-native"))
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("model-or-terminal-equivalence-policy-updated"),
            .string("artifact:policy-artifact"),
        ]))
        #expect(!problem.candidateActions.contains {
            $0.domainID == "lvs-signoff"
                && $0.operationID == "lvs.diagnostic-to-repair-objective"
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "lvs-signoff"
                && $0.operationID == "lvs.policy-repair"
                && $0.verificationGates.contains("approval-gate")
        })
        #expect(problem.constraints.contains {
            $0.constraintID == "policy-repair-approval"
                && $0.kind == "human-approval"
        })
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-2/planning/problem.json")
    }

    @Test func lvsRepairHintsBecomeEngineOwnedPlanningCandidates() throws {
        let summary = makeLVSPortSummary()
        let hints = makeLVSPortRepairHints()

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeLVSRepairProblem(
            runID: "run-lvs-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-lvs-hints/stages/008-lvs/raw/lvs-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-lvs-hints/stages/006-layout/raw/layout.gds",
            schematicNetlistPath: "circuits/top.spice",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-lvs-hints/stages/008-lvs/raw/lvs-repair-hints.json"
        )

        #expect(problem.sourceRefs.contains {
            $0.refID == "lvs-repair-hints"
                && $0.kind == "lvs-repair-hints"
                && $0.path == ".xcircuite/runs/run-lvs-hints/stages/008-lvs/raw/lvs-repair-hints.json"
        })
        #expect(problem.objectives.first?.sourceRefIDs == ["lvs-summary", "lvs-repair-hints"])
        #expect(problem.objectives.first?.target == "layout-and-schematic-equivalent-for-repair-hint")
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("lvs.export-repair-hints"))
        #expect(problem.objectives.first?.evidence["sourceRepairHintID"] == .string("lvs-repair-0-LVS_PORT_MISMATCH"))
        #expect(problem.objectives.first?.evidence["repairHintConfidence"] == .string("high"))
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("label-created"),
            .string("artifact:layout-document"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.domainID == "layout-edit")
        #expect(action.operationID == "layout.add-label")
        #expect(action.maturity == "implemented")
        #expect(action.reason.contains("LVS_PORT_MISMATCH maps to layout.add-label"))
        #expect(action.parameterHints["sourceRepairHintID"] == .string("lvs-repair-0-LVS_PORT_MISMATCH"))
        #expect(action.parameterHints["repairHintConfidence"] == .string("high"))
        #expect(action.parameterHints["portName"] == .string("VDD"))
        #expect(action.parameterHints["labelText"] == .string("VDD"))
        #expect(action.parameterHints["netName"] == .string("VDD"))
        #expect(action.verificationGates.contains("native-lvs"))
        #expect(action.verificationGates.contains("native-drc"))
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-lvs-hints/planning/problem.json")
    }

    @Test func lvsParameterRepairHintBecomesNetlistParameterEditCandidate() throws {
        let summary = makeLVSPortSummary()
        let hints = makeLVSParameterRepairHints()

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeLVSRepairProblem(
            runID: "run-lvs-parameter-hints",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-lvs-parameter-hints/stages/008-lvs/raw/lvs-summary.json",
            layoutArtifactPath: nil,
            layoutNetlistPath: "circuits/layout.spice",
            schematicNetlistPath: "circuits/top.spice",
            repairHints: hints,
            repairHintArtifactPath: ".xcircuite/runs/run-lvs-parameter-hints/stages/008-lvs/raw/lvs-repair-hints.json"
        )

        #expect(problem.actionDomainRefs.contains("simulation-analysis"))
        #expect(problem.objectives.first?.evidence["repairHintOperationID"] == .string("simulation.set-netlist-parameters"))
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("edited-spice-netlist-produced"),
            .string("parameter-edit-report-produced"),
        ]))

        let action = try #require(problem.candidateActions.first)
        #expect(action.domainID == "simulation-analysis")
        #expect(action.operationID == "simulation.set-netlist-parameters")
        #expect(action.requiredInputRefs == ["layout-netlist-ref", "schematic-netlist-ref"])
        #expect(action.verificationGates == ["artifact-integrity", "native-lvs"])
        #expect(action.parameterHints["assignmentName"] == .string("M1.w"))
        #expect(action.parameterHints["assignmentValue"] == .number(2e-6))
        #expect(action.parameterHints["lvsEditedNetlistRole"] == .string("layout"))
        #expect(action.parameterHints["assignments"] == .array([
            .object([
                "name": .string("M1.w"),
                "value": .number(2e-6),
            ]),
        ]))
        #expect(action.parameterHints["lvsInputs"] == .object([
            "layoutNetlistRef": .string("layout-netlist-ref"),
            "schematicNetlistRef": .string("schematic-netlist-ref"),
            "topCell": .string("TOP"),
        ]))
        #expect(problem.riskClassifications.contains {
            $0.riskID == "lvs-netlist-parameter-edit-risk"
                && $0.affectedActionIDs == [action.actionID]
        })
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-lvs-parameter-hints/planning/problem.json")
    }

    @Test func lvsPortMismatchCreatesConcreteLayoutCandidates() throws {
        let summary = makeLVSPortSummary()

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeLVSRepairProblem(
            runID: "run-lvs-port",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-lvs-port/stages/008-lvs/raw/lvs-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-lvs-port/stages/006-layout/raw/layout.gds",
            schematicNetlistPath: "circuits/top.spice"
        )

        #expect(problem.candidateActions.contains {
            $0.domainID == "layout-edit"
                && $0.operationID == "layout.add-label"
                && $0.maturity == "implemented"
                && $0.verificationGates.contains("native-lvs")
        })
        #expect(problem.candidateActions.contains {
            $0.domainID == "layout-edit"
                && $0.operationID == "layout.add-net"
                && $0.maturity == "implemented"
        })
        #expect(!problem.candidateActions.contains {
            $0.domainID == "lvs-signoff"
                && $0.operationID == "lvs.diagnostic-to-repair-objective"
        })
        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("label-created"),
            .string("artifact:layout-document"),
        ]))
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-lvs-port/planning/problem.json")
    }

    @Test func drcMaximumDensityCreatesDeleteShapeCandidate() throws {
        let summary = DRCRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: DRCRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native DRC",
                topCell: "TOP",
                layoutFormat: "gds",
                passed: false,
                completed: true,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeViolationCount: 1,
                waivedViolationCount: 0,
                violationBuckets: [
                    DRCViolationBucketSummary(
                        ruleID: "M1.maximumDensity",
                        kind: "maximumDensity",
                        layer: "M1",
                        activeCount: 1,
                        waivedCount: 0,
                        maxMeasured: 0.92,
                        required: 0.80,
                        relatedShapeIDs: ["fill-shape-1"],
                        relatedNetIDs: [],
                        suggestedFixes: ["remove_excess_fill"]
                    ),
                ],
                unusedWaiverIDs: []
            )
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-density",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-density/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-density/stages/006-layout/raw/layout.gds"
        )

        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("shape-deleted"),
            .string("artifact:layout-document"),
        ]))
        let action = try #require(problem.candidateActions.first)
        #expect(action.domainID == "layout-edit")
        #expect(action.operationID == "layout.delete-shape")
        #expect(action.maturity == "implemented")
        #expect(action.parameterHints["shapeID"] == .string("fill-shape-1"))
        #expect(action.verificationGates.contains("native-drc"))
        #expect(action.verificationGates.contains("native-lvs"))
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-density/planning/problem.json")
    }

    @Test func drcNotchCreatesFillRectCandidate() throws {
        let summary = DRCRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: DRCRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native DRC",
                topCell: "TOP",
                layoutFormat: "gds",
                passed: false,
                completed: true,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeViolationCount: 1,
                waivedViolationCount: 0,
                violationBuckets: [
                    DRCViolationBucketSummary(
                        ruleID: "M1.notch",
                        kind: "minimumNotch",
                        layer: "M1",
                        activeCount: 1,
                        waivedCount: 0,
                        maxMeasured: 0.03,
                        required: 0.08,
                        representativeRegion: DRCRegion(x: 1.0, y: 0.0, width: 0.2, height: 2.0),
                        relatedShapeIDs: ["10000000-0000-0000-0000-000000000101"],
                        relatedNetIDs: ["net-out"],
                        suggestedFixes: ["fill notch region"]
                    ),
                ],
                unusedWaiverIDs: []
            )
        )

        let problem = try XcircuiteDiagnosticPlanningProblemBuilder().makeDRCRepairProblem(
            runID: "run-notch",
            summary: summary,
            summaryArtifactPath: ".xcircuite/runs/run-notch/stages/007-drc/raw/drc-summary.json",
            layoutArtifactPath: ".xcircuite/runs/run-notch/stages/006-layout/raw/layout.gds"
        )

        #expect(problem.objectives.first?.evidence["symbolicGoalAtoms"] == .array([
            .string("rect-shape-created"),
            .string("artifact:layout-document"),
        ]))
        let action = try #require(problem.candidateActions.first)
        #expect(action.domainID == "layout-edit")
        #expect(action.operationID == "layout.add-rect")
        #expect(action.maturity == "implemented")
        #expect(action.parameterHints["shapeID"] == nil)
        #expect(action.parameterHints["originX"] == .number(1.0))
        #expect(action.parameterHints["originY"] == .number(0.0))
        #expect(action.parameterHints["width"] == .number(0.2))
        #expect(action.parameterHints["height"] == .number(2.0))
        #expect(action.verificationGates.contains("native-drc"))
        #expect(action.verificationGates.contains("native-lvs"))
        try expectValidPlanningProblem(problem, problemPath: ".xcircuite/runs/run-notch/planning/problem.json")
    }

    @Test func planningProblemPersistenceRejectsRunMismatch() throws {
        let root = try makeTemporaryRoot("run-mismatch")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-expected", inProjectAt: root)
        let problem = XcircuiteCircuitPlanningProblem(
            problemID: "problem-1",
            runID: "run-actual",
            sourceRefs: [],
            initialStateRefs: [],
            objectives: [],
            constraints: [],
            actionDomainRefs: [],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "none", terms: []),
            verificationGates: [],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: [],
                blockedStates: []
            )
        )

        #expect(throws: XcircuitePlanningArtifactError.runMismatch(
            expected: "run-expected",
            actual: "run-actual"
        )) {
            try XcircuitePlanningArtifactStore().persistPlanningProblem(
                problem,
                runID: "run-expected",
                projectRoot: root
            )
        }
    }

    @Test func generatePlanningProblemCLIReadsDRCSummaryFromRunManifest() async throws {
        let root = try makeTemporaryRoot("drc-planning-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-1", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json"
        let layoutPath = ".xcircuite/runs/run-1/stages/006-layout/raw/layout.gds"
        try registerJSONArtifact(
            makeDRCSummary(),
            artifactID: "drc-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-1"
        )
        let repairHintPath = ".xcircuite/runs/run-1/stages/007-drc/raw/drc-repair-hints.json"
        try registerJSONArtifact(
            makeDRCRepairHints(),
            artifactID: "drc-repair-hints",
            path: repairHintPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-1"
        )
        try registerDataArtifact(
            Data("GDS payload\n".utf8),
            artifactID: "layout-gds",
            path: layoutPath,
            kind: .layout,
            format: .gdsii,
            root: root,
            runID: "run-1"
        )

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-1",
                "--source",
                "drc-summary",
                "--layout-artifact-id",
                "layout-gds",
                "--repair-hint-artifact-id",
                "drc-repair-hints",
                "--layout-netlist-path",
                "circuits/layout.spice",
                "--schematic-netlist-path",
                "circuits/schematic.spice",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuitePlanningProblemGenerationResult.self, from: data)

        #expect(result.status == "generated")
        #expect(result.runID == "run-1")
        #expect(result.source == .drcSummary)
        #expect(result.problemID == "run-1-drc-repair-problem")
        #expect(result.summaryPath == summaryPath)
        #expect(result.layoutPath == layoutPath)
        #expect(result.repairHintPath == repairHintPath)
        #expect(result.layoutNetlistPath == "circuits/layout.spice")
        #expect(result.schematicNetlistPath == "circuits/schematic.spice")
        #expect(result.problemArtifact.artifactID == XcircuitePlanningArtifactStore.problemArtifactID)
        #expect(result.problemArtifact.byteCount != nil)

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: result.problemArtifact.path)
        )
        #expect(problem.sourceRefs.first?.path == summaryPath)
        #expect(problem.sourceRefs.contains {
            $0.refID == "drc-repair-hints" && $0.path == repairHintPath
        })
        #expect(problem.initialStateRefs.contains { $0.refID == "layout-ref" && $0.path == layoutPath })
        #expect(problem.initialStateRefs.contains {
            $0.refID == "layout-netlist-ref" && $0.path == "circuits/layout.spice"
        })
        #expect(problem.initialStateRefs.contains {
            $0.refID == "schematic-netlist-ref" && $0.path == "circuits/schematic.spice"
        })
        #expect(problem.objectives.map(\.target) == ["no-active-violation-for-repair-hint"])
        #expect(problem.objectives.first?.evidence["sourceRepairHintID"] == .string("drc-repair-0-M1-width"))
        #expect(problem.candidateActions.map(\.operationID) == ["layout.resize-shape"])
        #expect(problem.candidateActions.first?.parameterHints["sourceRepairHintID"] == .string("drc-repair-0-M1-width"))
        #expect(problem.candidateActions.first?.parameterHints["lvsInputs"] == .object([
            "layoutNetlistRef": .string("layout-netlist-ref"),
            "schematicNetlistRef": .string("schematic-netlist-ref"),
            "topCell": .string("TOP"),
        ]))
    }

    @Test func generatePlanningProblemRejectsStaleManifestArtifact() throws {
        let root = try makeTemporaryRoot("drc-planning-stale-artifact")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-stale", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-stale/stages/007-drc/raw/drc-summary.json"
        try registerJSONArtifact(
            makeDRCSummary(),
            artifactID: "drc-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-stale"
        )
        try store.writeText(#"{"stale":true}"#, to: root.appending(path: summaryPath))

        do {
            _ = try XcircuitePlanningProblemGenerator().generateRepairProblem(
                request: XcircuitePlanningProblemGenerationRequest(
                    runID: "run-stale",
                    source: .drcSummary
                ),
                projectRoot: root
            )
            Issue.record("Expected planning problem generation to reject the stale summary artifact.")
        } catch let error as XcircuitePlanningProblemGenerationError {
            guard case .artifactIntegrityFailed(let artifactID, let path, let status, _) = error else {
                Issue.record("Unexpected planning problem generation error: \(error)")
                return
            }
            #expect(artifactID == "drc-summary")
            #expect(path == summaryPath)
            #expect(status == .byteCountMismatch || status == .sha256Mismatch)
        }
    }

    @Test func generatePlanningProblemRejectsDuplicateManifestArtifactID() throws {
        let root = try makeTemporaryRoot("drc-planning-duplicate-artifact")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-duplicate", inProjectAt: root)
        let summaryPath = ".xcircuite/runs/run-duplicate/stages/007-drc/raw/drc-summary.json"
        try registerJSONArtifact(
            makeDRCSummary(),
            artifactID: "drc-summary",
            path: summaryPath,
            kind: .report,
            format: .json,
            root: root,
            runID: "run-duplicate"
        )

        let duplicatePath = ".xcircuite/runs/run-duplicate/stages/007-drc/raw/drc-summary-copy.json"
        let duplicateURL = root.appending(path: duplicatePath)
        try FileManager.default.createDirectory(
            at: duplicateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(makeDRCSummary(), to: duplicateURL, forProjectAt: root)
        let duplicateReference = try store.fileReference(
            forProjectRelativePath: duplicatePath,
            artifactID: "drc-summary",
            kind: .report,
            format: .json,
            inProjectAt: root,
            producedByRunID: "run-duplicate"
        )
        let manifestURL = try XcircuitePackage(projectRoot: root)
            .runDirectoryURL(for: "run-duplicate")
            .appending(path: "manifest.json")
        var manifest = try store.readJSON(XcircuiteRunManifest.self, from: manifestURL)
        manifest.artifacts.append(duplicateReference)
        try store.writeJSON(manifest, to: manifestURL, forProjectAt: root)

        #expect(throws: XcircuitePlanningProblemGenerationError.duplicateArtifactReference(
            runID: "run-duplicate",
            artifactID: "drc-summary",
            count: 2
        )) {
            _ = try XcircuitePlanningProblemGenerator().generateRepairProblem(
                request: XcircuitePlanningProblemGenerationRequest(
                    runID: "run-duplicate",
                    source: .drcSummary
                ),
                projectRoot: root
            )
        }
    }

    @Test func generatePlanningProblemCLIReadsLVSSummaryFromExplicitPath() async throws {
        let root = try makeTemporaryRoot("lvs-planning-cli")
        defer { removeTemporaryRoot(root) }
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: "run-2", inProjectAt: root)
        let summaryPath = "summaries/lvs-summary.json"
        let summaryURL = root.appending(path: summaryPath)
        let repairHintPath = "summaries/lvs-repair-hints.json"
        let repairHintURL = root.appending(path: repairHintPath)
        try FileManager.default.createDirectory(
            at: summaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(makeLVSSummary(), to: summaryURL, forProjectAt: root)
        try store.writeJSON(makeLVSPolicyRepairHints(), to: repairHintURL, forProjectAt: root)

        let json = try await XcircuiteFlowCLICommand.run(
            arguments: [
                "generate-planning-problem",
                "--project-root",
                root.path(percentEncoded: false),
                "--run-id",
                "run-2",
                "--source",
                "lvs-summary",
                "--summary-path",
                summaryPath,
                "--repair-hint-path",
                repairHintPath,
                "--schematic-netlist-path",
                "circuits/top.spice",
                "--pretty",
            ]
        )
        let data = try #require(json.data(using: .utf8))
        let result = try JSONDecoder().decode(XcircuitePlanningProblemGenerationResult.self, from: data)

        #expect(result.status == "generated")
        #expect(result.source == .lvsSummary)
        #expect(result.problemID == "run-2-lvs-repair-problem")
        #expect(result.summaryPath == summaryPath)
        #expect(result.repairHintPath == repairHintPath)
        #expect(result.schematicNetlistPath == "circuits/top.spice")

        let problem = try store.readJSON(
            XcircuiteCircuitPlanningProblem.self,
            from: root.appending(path: result.problemArtifact.path)
        )
        #expect(problem.sourceRefs.first?.path == summaryPath)
        #expect(problem.initialStateRefs.contains {
            $0.refID == "schematic-netlist-ref" && $0.path == "circuits/top.spice"
        })
        #expect(problem.sourceRefs.contains {
            $0.refID == "lvs-repair-hints" && $0.path == repairHintPath
        })
        #expect(problem.objectives.first?.evidence["sourceEngineOperation"] == .string("lvs.export-repair-hints"))
        #expect(problem.objectives.first?.evidence["sourceRepairHintID"] == .string("lvs-repair-0-LVS_MODEL_MISMATCH"))
        #expect(problem.candidateActions.contains {
            $0.operationID == "lvs.policy-repair"
                && $0.parameterHints["sourceRepairHintID"] == .string("lvs-repair-0-LVS_MODEL_MISMATCH")
        })
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "XcircuiteDiagnosticPlanningProblemBuilderTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        let path = root.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func makeDRCSummary() -> DRCRunSummaryReport {
        DRCRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: DRCRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native DRC",
                topCell: "TOP",
                layoutFormat: "gds",
                passed: false,
                completed: true,
                diagnosticSummary: DRCDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeViolationCount: 1,
                waivedViolationCount: 0,
                violationBuckets: [
                    DRCViolationBucketSummary(
                        ruleID: "M1.width",
                        kind: "minimumWidth",
                        layer: "M1",
                        activeCount: 1,
                        waivedCount: 0,
                        maxMeasured: 0.12,
                        required: 0.14,
                        relatedShapeIDs: ["shape-1"],
                        relatedNetIDs: ["net-vdd"],
                        suggestedFixes: ["increase_width"]
                    ),
                ],
                unusedWaiverIDs: []
            )
        )
    }

    private func makeDRCRepairHints() -> DRCRepairHintReport {
        DRCRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                DRCRepairHint(
                    hintID: "drc-repair-0-M1-width",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.resize-shape",
                    confidence: "high",
                    ruleID: "M1.width",
                    kind: "minimumWidth",
                    layer: "M1",
                    targetShapeIDs: ["shape-1"],
                    relatedNetIDs: ["net-vdd"],
                    region: nil,
                    measured: 0.12,
                    required: 0.14,
                    numericParameters: [
                        "deltaMinX": 0,
                        "deltaMinY": 0,
                        "deltaMaxX": 0.02,
                        "deltaMaxY": 0,
                    ],
                    stringParameters: [
                        "shapeID": "shape-1",
                        "ruleID": "M1.width",
                        "kind": "minimumWidth",
                        "layer": "M1",
                    ],
                    verificationGates: ["native-drc", "artifact-integrity"],
                    rationale: "M1.width maps to layout.resize-shape."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeLVSSummary() -> LVSRunSummaryReport {
        LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "TOP",
                layoutInputKind: "layout-gds",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "model-mismatch",
                        category: "model-equivalence",
                        componentSignature: "M1",
                        parameterName: nil,
                        layoutModel: "nfet_01v8",
                        schematicModel: "nfet",
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: 1,
                        schematicCount: 1,
                        layoutPorts: ["D", "G", "S"],
                        schematicPorts: ["D", "G", "S"],
                        suggestedFixes: ["review_model_equivalence_policy"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
    }

    private func makeLVSPortSummary() -> LVSRunSummaryReport {
        LVSRunSummaryReport(
            reportURL: nil,
            manifestURL: nil,
            summary: LVSRunSummary(
                status: "failed",
                backendID: "native",
                toolName: "Native LVS",
                topCell: "TOP",
                layoutInputKind: "layout-gds",
                passed: false,
                completed: true,
                diagnosticSummary: LVSDiagnosticSummary(infoCount: 0, warningCount: 0, errorCount: 1),
                activeMismatchCount: 1,
                waivedMismatchCount: 0,
                mismatchBuckets: [
                    LVSMismatchBucketSummary(
                        ruleID: "LVS_PORT_MISMATCH",
                        category: "portMismatch",
                        componentSignature: nil,
                        parameterName: nil,
                        layoutModel: nil,
                        schematicModel: nil,
                        activeCount: 1,
                        waivedCount: 0,
                        layoutCount: nil,
                        schematicCount: nil,
                        layoutPorts: ["A", "Y"],
                        schematicPorts: ["A", "Y", "VDD"],
                        suggestedFixes: ["add_missing_layout_label"]
                    ),
                ],
                extractedLayoutNetlistURL: nil,
                unusedWaiverIDs: []
            )
        )
    }

    private func makeLVSPortRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-LVS_PORT_MISMATCH",
                    sourceDiagnosticIndex: 0,
                    operationID: "layout.add-label",
                    confidence: "high",
                    ruleID: "LVS_PORT_MISMATCH",
                    category: "portMismatch",
                    componentSignature: nil,
                    parameterName: nil,
                    layoutModel: nil,
                    schematicModel: nil,
                    layoutValue: nil,
                    schematicValue: nil,
                    layoutPorts: ["A", "Y"],
                    schematicPorts: ["A", "Y", "VDD"],
                    layoutCount: nil,
                    schematicCount: nil,
                    stringParameters: [
                        "portName": "VDD",
                        "labelText": "VDD",
                        "netName": "VDD",
                    ],
                    verificationGates: ["native-lvs", "native-drc", "artifact-integrity"],
                    rationale: "LVS_PORT_MISMATCH maps to layout.add-label because the diagnostic exposes a missing schematic port."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeLVSParameterRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-LVS_PARAMETER_MISMATCH",
                    sourceDiagnosticIndex: 0,
                    operationID: "simulation.set-netlist-parameters",
                    confidence: "high",
                    ruleID: "LVS_PARAMETER_MISMATCH",
                    category: "parameterMismatch",
                    componentSignature: "mos|pmos|out,in,vdd,vdd||pmos",
                    parameterName: "w",
                    layoutModel: "pmos",
                    schematicModel: "pmos",
                    layoutValue: "1u",
                    schematicValue: "2u",
                    layoutPorts: [],
                    schematicPorts: [],
                    layoutCount: nil,
                    schematicCount: nil,
                    stringParameters: [
                        "assignmentName": "M1.w",
                        "layoutComponentName": "M1",
                        "schematicComponentName": "M1",
                        "lvsEditedNetlistRole": "layout",
                        "sourceValue": "1u",
                        "targetValue": "2u",
                    ],
                    verificationGates: ["artifact-integrity", "native-lvs"],
                    rationale: "LVS_PARAMETER_MISMATCH maps to simulation.set-netlist-parameters because the diagnostic exposes parameter M1.w and schematic target value 2u.",
                    numericParameters: ["assignmentValue": 2e-6]
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func makeLVSPolicyRepairHints() -> LVSRepairHintReport {
        LVSRepairHintReport(
            status: "ready",
            reportURL: nil,
            backendID: "native",
            topCell: "TOP",
            activeDiagnosticCount: 1,
            hintCount: 1,
            hints: [
                LVSRepairHint(
                    hintID: "lvs-repair-0-LVS_MODEL_MISMATCH",
                    sourceDiagnosticIndex: 0,
                    operationID: "lvs.policy-repair",
                    confidence: "medium",
                    ruleID: "LVS_MODEL_MISMATCH",
                    category: "modelMismatch",
                    componentSignature: "M1",
                    parameterName: nil,
                    layoutModel: "nfet_01v8",
                    schematicModel: "nfet",
                    layoutValue: nil,
                    schematicValue: nil,
                    layoutPorts: ["D", "G", "S"],
                    schematicPorts: ["D", "G", "S"],
                    layoutCount: 1,
                    schematicCount: 1,
                    stringParameters: [
                        "layoutModel": "nfet_01v8",
                        "schematicModel": "nfet",
                    ],
                    verificationGates: ["approval-gate", "native-lvs", "artifact-integrity"],
                    rationale: "LVS_MODEL_MISMATCH maps to lvs.policy-repair because model equivalence may need an approved policy update."
                ),
            ],
            unsupportedDiagnosticIndexes: []
        )
    }

    private func expectValidPlanningProblem(
        _ problem: XcircuiteCircuitPlanningProblem,
        problemPath: String
    ) throws {
        let snapshot = try XcircuiteActionDomainSnapshotBuilder().snapshot(
            runID: problem.runID,
            generatedAt: "2026-06-21T00:00:00Z"
        )
        let validation = XcircuitePlanningProblemValidator().makeValidation(
            problem: problem,
            problemPath: problemPath,
            actionDomainSnapshot: snapshot
        )
        #expect(validation.status == "valid")
        #expect(validation.diagnostics == [])
    }

    private func registerJSONArtifact<T: Encodable>(
        _ value: T,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try store.writeJSON(value, to: url, forProjectAt: root)
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }

    private func registerDataArtifact(
        _ data: Data,
        artifactID: String,
        path: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        let reference = try store.fileReference(
            forProjectRelativePath: path,
            artifactID: artifactID,
            kind: kind,
            format: format,
            inProjectAt: root,
            producedByRunID: runID
        )
        try store.upsertRunArtifact(reference, runID: runID, inProjectAt: root)
    }
}
