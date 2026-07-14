import Foundation
import LayoutAutoGen
import LayoutCore
import LayoutIO
import LayoutTech
import PEXEngine
import Testing
import Xcircuite
import XcircuiteFlowCLISupport
import DesignFlowKernel


struct ProducedLayoutCorpusCase: Sendable, Hashable {
    var id: String
    var artifactID: String
    var fileName: String
    var layoutFileFormat: LayoutFileFormat
    var xcircuiteFileFormat: XcircuiteFileFormat
    var pexLayoutFormat: String
}

struct ProducedDeviceCorpusCase: Sendable, Hashable {
    var id: String
    var deviceKindID: String
    var modelName: String
    var instanceName: String
    var parameters: [String: Double]
    var netByPin: [String: String]

    var schematicNetlist: String {
        """
        .subckt top d g s b
        \(instanceName) d g s b \(modelName) W=2u L=0.18u
        .ends
        """
    }
}

enum ProducedCircuitLayoutKind: Sendable, Hashable {
    case mosDevice(ProducedDeviceCorpusCase)
    case cmosInverter
    case hierarchicalCMOSInverter
    case arrayedParallelNMOS
    case horizontalArrayedParallelNMOS
}

enum ProducedArrayedNMOSOrientation: Sendable, Hashable {
    case verticalRows
    case horizontalColumns
}

struct ProducedCircuitCorpusCase: Sendable, Hashable {
    var id: String
    var schematicNetlist: String
    var layoutKind: ProducedCircuitLayoutKind
}


extension XcircuiteCandidatePlanVerifierTests {
    enum ProducedLayoutFixtureError: Error {
        case missingPin(String)
        case missingBoundingBox
    }

    func prepareRun(
        root: URL,
        runID: String,
        problem: XcircuiteCircuitPlanningProblem
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            problem,
            runID: runID,
            projectRoot: root
        )
    }

    func candidatePlanRef(runID: String) -> XcircuiteFileReference {
        XcircuiteFileReference(
            artifactID: XcircuitePlanningArtifactStore.candidatePlanArtifactID,
            path: ".xcircuite/runs/\(runID)/planning/candidate-plan.json",
            kind: .other,
            format: .json,
            sha256: "abc",
            byteCount: 12,
            producedByRunID: runID
        )
    }

    func makeSingleStepPlan(
        runID: String,
        domainID: String,
        operationID: String,
        maturity: String
    ) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-candidate-plan-1",
            problemID: "\(runID)-problem",
            runID: runID,
            strategy: "symbolic-planner-contract-test",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "\(runID)-candidate-plan-1-step-1",
                    order: 1,
                    actionID: "candidate-action-1",
                    domainID: domainID,
                    operationID: operationID,
                    maturity: maturity,
                    readiness: "ready",
                    sourceObjectiveIDs: ["objective-1"],
                    requiredInputRefs: [],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity"],
                    reason: "Verify symbolic planner action-domain contract.",
                    parameterHints: [:],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "artifact-integrity",
                    required: true,
                    description: "Candidate plan and action-domain artifacts must be auditable."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func makeDRCPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-1-drc-repair-problem",
            runID: "run-1",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "drc-summary",
                    kind: "drc-summary",
                    path: ".xcircuite/runs/run-1/stages/007-drc/raw/drc-summary.json",
                    artifactID: "drc-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout",
                    path: ".xcircuite/runs/run-1/stages/006-layout/raw/layout.gds"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "drc-m1-width-1",
                    kind: "satisfy",
                    domain: "drc",
                    priority: "error",
                    sourceRefIDs: ["drc-summary"],
                    target: "no-active-violations-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair M1 width violation."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "drc-must-pass",
                    kind: "verification",
                    severity: "error",
                    description: "The candidate must pass DRC.",
                    sourceRefIDs: ["drc-summary"]
                ),
            ],
            actionDomainRefs: ["drc-signoff", "layout-edit", "lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "layout-add-rect-1",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    reason: "Apply a concrete layout edit family.",
                    sourceObjectiveIDs: ["drc-m1-width-1"],
                    requiredInputRefs: ["layout-ref"],
                    verificationGates: ["artifact-integrity", "native-drc", "native-lvs"],
                    parameterHints: ["ruleID": .string("M1.width")]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate must pass DRC."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeExecutableDRCPlan(
        runID: String,
        width: Double,
        requiredWidth: Double
    ) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-native-drc-plan",
            problemID: "\(runID)-native-drc-problem",
            runID: runID,
            strategy: "post-execution-native-drc",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.add-rect",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["drc-objective"],
                    requiredInputRefs: [],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-drc"],
                    reason: "Create a DRC-verifiable layout candidate.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000301"),
                        "shapeID": .string("10000000-0000-0000-0000-000000000303"),
                        "cellName": .string("top"),
                        "layer": .string("M1"),
                        "originX": .number(0),
                        "originY": .number(0),
                        "width": .number(width),
                        "height": .number(1),
                        "drcRules": .array([
                            .object([
                                "id": .string("M1.width"),
                                "kind": .string("minimumWidth"),
                                "layer": .string("M1"),
                                "value": .number(requiredWidth),
                            ]),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-drc",
                    required: true,
                    description: "Candidate layout must pass native DRC."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func prepareExecutableLVSRun(
        root: URL,
        runID: String,
        layoutNetlist: String,
        schematicNetlist: String
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText(layoutNetlist, path: "circuits/layout.spice", root: root)
        try writeText(schematicNetlist, path: "circuits/schematic.spice", root: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makeExecutableLVSProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeExecutableLVSPlan(runID: runID),
            runID: runID,
            projectRoot: root
        )
    }

    func prepareProducedStandardLayoutLVSRun(
        root: URL,
        runID: String,
        layoutCase: ProducedLayoutCorpusCase,
        circuitCase: ProducedCircuitCorpusCase
    ) throws {
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText(
            circuitCase.schematicNetlist,
            path: "circuits/standard-layout-schematic.spice",
            root: root
        )
        try writeJSON(LayoutTechDatabase.sampleProcess(), path: "tech/layout-tech.json", root: root)
        let problem = makeProducedStandardLayoutLVSProblem(runID: runID)
        let plan = makeProducedStandardLayoutLVSPlan(runID: runID, layoutCase: layoutCase)
        try artifactStore.persistPlanningProblem(problem, runID: runID, projectRoot: root)
        let candidatePlanRef = try artifactStore.persistCandidatePlan(plan, runID: runID, projectRoot: root)
        let layoutRef = try writeProducedLayoutArtifact(
            root: root,
            runID: runID,
            planID: plan.planID,
            stepID: "step-1",
            layoutCase: layoutCase,
            circuitCase: circuitCase
        )
        try store.upsertRunArtifact(layoutRef, runID: runID, inProjectAt: root)
        try artifactStore.persistPlanExecution(
            try XcircuiteCandidatePlanExecution(
                runID: runID,
                problemID: problem.problemID,
                planID: plan.planID,
                status: "executed",
                candidatePlanRef: candidatePlanRef,
                stepResults: [
                    XcircuiteCandidatePlanExecutionStepResult(
                        stepID: "step-1",
                        order: 1,
                        actionID: "layout-action-1",
                        domainID: "layout-edit",
                        operationID: "layout.create-cell",
                        status: "executed",
                        artifactRefs: [layoutRef]
                    ),
                ],
                artifactRefs: [layoutRef],
                diagnostics: [],
                nextActions: []
            ),
            runID: runID,
            projectRoot: root
        )
    }

    func prepareProducedStandardLayoutPEXRun(
        root: URL,
        runID: String,
        layoutCase: ProducedLayoutCorpusCase
    ) throws {
        let store = XcircuitePackageStore()
        let artifactStore = XcircuitePlanningArtifactStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText(
            """
            .subckt top in out vdd vss
            M1 out in vdd vdd pmos W=1u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends top
            """,
            path: "circuits/source.spice",
            root: root
        )
        try writeJSON(makeTestPEXTechnology(), path: "tech/pex-technology.json", root: root)
        let problem = makeProducedStandardLayoutPEXProblem(runID: runID)
        let plan = makeProducedStandardLayoutPEXPlan(runID: runID, layoutCase: layoutCase)
        try artifactStore.persistPlanningProblem(problem, runID: runID, projectRoot: root)
        let candidatePlanRef = try artifactStore.persistCandidatePlan(plan, runID: runID, projectRoot: root)
        let layoutRef = try writeProducedLayoutArtifact(
            root: root,
            runID: runID,
            planID: plan.planID,
            stepID: "step-1",
            layoutCase: layoutCase,
            circuitCase: producedSingleNMOSCircuitCase()
        )
        try store.upsertRunArtifact(layoutRef, runID: runID, inProjectAt: root)
        try artifactStore.persistPlanExecution(
            try XcircuiteCandidatePlanExecution(
                runID: runID,
                problemID: problem.problemID,
                planID: plan.planID,
                status: "executed",
                candidatePlanRef: candidatePlanRef,
                stepResults: [
                    XcircuiteCandidatePlanExecutionStepResult(
                        stepID: "step-1",
                        order: 1,
                        actionID: "layout-action-1",
                        domainID: "layout-edit",
                        operationID: "layout.create-cell",
                        status: "executed",
                        artifactRefs: [layoutRef]
                    ),
                ],
                artifactRefs: [layoutRef],
                diagnostics: [],
                nextActions: []
            ),
            runID: runID,
            projectRoot: root
        )
    }

    func makeExecutableLVSProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-native-lvs-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-netlist-ref",
                    kind: "layout-netlist",
                    path: "circuits/layout.spice"
                ),
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/schematic.spice"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-equivalence",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "layout-and-schematic-equivalent",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Verify the candidate against LVS."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["lvs-signoff", "layout-edit"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate must pass native LVS."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeExecutableLVSPlan(runID: String) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-native-lvs-plan",
            problemID: "\(runID)-native-lvs-problem",
            runID: runID,
            strategy: "post-execution-native-lvs",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["lvs-equivalence"],
                    requiredInputRefs: ["layout-netlist-ref", "schematic-netlist-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-lvs"],
                    reason: "Run a concrete post-execution LVS gate.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000601"),
                        "cellName": .string("lvs_gate_marker"),
                        "lvsInputs": .object([
                            "layoutNetlistRef": .string("layout-netlist-ref"),
                            "schematicNetlistRef": .string("schematic-netlist-ref"),
                            "topCell": .string("inv"),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Candidate netlists must match."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func makeProducedStandardLayoutLVSProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-native-lvs-produced-layout-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/standard-layout-schematic.spice"
                ),
                XcircuitePlanningReference(
                    refID: "layout-technology-ref",
                    kind: "layout-technology",
                    path: "tech/layout-tech.json"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-produced-layout-equivalence",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "post-edit-layout-and-schematic-equivalent",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Verify the produced standard layout artifact against LVS."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["lvs-signoff", "layout-edit"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Produced standard layout must pass native LVS."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeProducedStandardLayoutLVSPlan(
        runID: String,
        layoutCase: ProducedLayoutCorpusCase
    ) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-native-lvs-produced-layout-plan",
            problemID: "\(runID)-native-lvs-produced-layout-problem",
            runID: runID,
            strategy: "post-execution-produced-standard-layout-native-lvs",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["lvs-produced-layout-equivalence"],
                    requiredInputRefs: ["schematic-netlist-ref", "layout-technology-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "native-lvs"],
                    reason: "Run native LVS from a produced standard layout artifact.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000611"),
                        "cellName": .string("produced_lvs_gate_marker"),
                        "lvsInputs": .object([
                            "layoutGDSRefID": .string(layoutCase.artifactID),
                            "schematicNetlistRef": .string("schematic-netlist-ref"),
                            "technologyRef": .string("layout-technology-ref"),
                            "topCell": .string("TOP"),
                            "backendID": .string("native-gds"),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "native-lvs",
                    required: true,
                    description: "Produced standard layout must match the schematic."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func prepareExecutableSimulationRun(
        root: URL,
        runID: String,
        target: Double
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText(
            """
            * rc lowpass step
            V1 1 0 1
            R1 1 2 1k
            C1 2 0 1n
            .tran 0.1u 5u
            .measure tran vfinal FIND V(2) AT=5u
            .end
            """,
            path: "circuits/rc.cir",
            root: root
        )
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makeExecutableSimulationProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeExecutableSimulationPlan(runID: runID, target: target),
            runID: runID,
            projectRoot: root
        )
    }

    func makeExecutableSimulationProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-simulation-metric-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/rc.cir"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "simulation-vfinal",
                    kind: "satisfy",
                    domain: "simulation",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "measurement-within-tolerance",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Verify the candidate against a simulation measurement."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["simulation-analysis", "layout-edit"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Candidate simulation metrics must satisfy expectations."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeExecutableSimulationPlan(runID: String, target: Double) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-simulation-metric-plan",
            problemID: "\(runID)-simulation-metric-problem",
            runID: runID,
            strategy: "post-execution-simulation-metric",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["simulation-vfinal"],
                    requiredInputRefs: ["source-netlist-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "simulation-metric-gate"],
                    reason: "Run a concrete post-execution simulation metric gate.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000801"),
                        "cellName": .string("simulation_gate_marker"),
                        "simulationInputs": .object([
                            "netlistRef": .string("source-netlist-ref"),
                            "expectations": .array([
                                .object([
                                    "name": .string("vfinal"),
                                    "target": .number(target),
                                    "tolerance": .number(0.01),
                                ]),
                            ]),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "simulation-metric-gate",
                    required: true,
                    description: "Candidate simulation metrics must satisfy expectations."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func prepareExecutablePEXRun(
        root: URL,
        runID: String
    ) throws {
        let store = XcircuitePackageStore()
        try store.createPackage(at: root)
        try store.createRunDirectory(for: runID, inProjectAt: root)
        try writeText("GDS placeholder for deterministic mock PEX input", path: "layout/top.gds", root: root)
        try writeText(
            """
            .subckt top in out vdd vss
            M1 out in vdd vdd pmos W=1u L=0.15u
            M2 out in vss vss nmos W=1u L=0.15u
            .ends top
            """,
            path: "circuits/source.spice",
            root: root
        )
        try writeJSON(makeTestPEXTechnology(), path: "tech/pex-technology.json", root: root)
        try XcircuitePlanningArtifactStore().persistPlanningProblem(
            makeExecutablePEXProblem(runID: runID),
            runID: runID,
            projectRoot: root
        )
        try XcircuitePlanningArtifactStore().persistCandidatePlan(
            makeExecutablePEXPlan(runID: runID),
            runID: runID,
            projectRoot: root
        )
    }

    func makeExecutablePEXProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-pex-summary-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "layout-ref",
                    kind: "layout-gds",
                    path: "layout/top.gds"
                ),
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/source.spice"
                ),
                XcircuitePlanningReference(
                    refID: "pex-technology-ref",
                    kind: "pex-technology",
                    path: "tech/pex-technology.json"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "pex-summary-complete",
                    kind: "satisfy",
                    domain: "pex",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "complete-pex-summary",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Verify the candidate against PEX summary completeness."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["pex-extraction", "layout-edit"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary-gate",
                    required: true,
                    description: "Candidate must produce a complete PEX summary."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeExecutablePEXPlan(runID: String) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-pex-summary-plan",
            problemID: "\(runID)-pex-summary-problem",
            runID: runID,
            strategy: "post-execution-pex-summary",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["pex-summary-complete"],
                    requiredInputRefs: ["layout-ref", "source-netlist-ref", "pex-technology-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "pex-summary-gate"],
                    reason: "Run a concrete post-execution PEX summary gate.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000701"),
                        "cellName": .string("pex_gate_marker"),
                        "pexInputs": .object([
                            "layoutRef": .string("layout-ref"),
                            "sourceNetlistRef": .string("source-netlist-ref"),
                            "technologyRef": .string("pex-technology-ref"),
                            "topCell": .string("top"),
                            "backendID": .string("mock"),
                            "allowMockBackend": .bool(true),
                            "layoutFormat": .string("gds"),
                            "sourceNetlistFormat": .string("spice"),
                            "corners": .array([.string("tt")]),
                            "topNets": .number(5),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary-gate",
                    required: true,
                    description: "Candidate must produce a complete PEX summary."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func updatePEXInputs(
        in plan: inout XcircuiteCandidatePlan,
        update: (inout [String: XcircuiteJSONValue]) -> Void
    ) throws {
        let pexInputsValue = try #require(plan.steps.first?.parameterHints["pexInputs"])
        guard case .object(var pexInputs) = pexInputsValue else {
            Issue.record("Expected pexInputs to be an object.")
            return
        }
        update(&pexInputs)
        plan.steps[0].parameterHints["pexInputs"] = .object(pexInputs)
    }

    func makeProducedStandardLayoutPEXProblem(runID: String) -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "\(runID)-pex-produced-layout-problem",
            runID: runID,
            sourceRefs: [],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "source-netlist-ref",
                    kind: "source-netlist",
                    path: "circuits/source.spice"
                ),
                XcircuitePlanningReference(
                    refID: "pex-technology-ref",
                    kind: "pex-technology",
                    path: "tech/pex-technology.json"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "pex-produced-layout-summary-complete",
                    kind: "satisfy",
                    domain: "pex",
                    priority: "error",
                    sourceRefIDs: [],
                    target: "complete-post-edit-pex-summary",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Verify the produced standard layout artifact through PEX."
                ),
            ],
            constraints: [],
            actionDomainRefs: ["pex-extraction", "layout-edit"],
            candidateActions: [],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary-gate",
                    required: true,
                    description: "Produced standard layout must produce a complete PEX summary."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["candidate-rejected"]
            )
        )
    }

    func makeProducedStandardLayoutPEXPlan(
        runID: String,
        layoutCase: ProducedLayoutCorpusCase
    ) -> XcircuiteCandidatePlan {
        XcircuiteCandidatePlan(
            planID: "\(runID)-pex-produced-layout-plan",
            problemID: "\(runID)-pex-produced-layout-problem",
            runID: runID,
            strategy: "post-execution-produced-standard-layout-pex-summary",
            executionReadiness: "ready",
            sourceProblemRef: XcircuitePlanningReference(
                refID: "planning-problem",
                kind: "planning-problem",
                path: ".xcircuite/runs/\(runID)/planning/problem.json",
                artifactID: XcircuitePlanningArtifactStore.problemArtifactID
            ),
            steps: [
                XcircuiteCandidatePlanStep(
                    stepID: "step-1",
                    order: 1,
                    actionID: "layout-action-1",
                    domainID: "layout-edit",
                    operationID: "layout.create-cell",
                    maturity: "implemented",
                    readiness: "ready",
                    sourceObjectiveIDs: ["pex-produced-layout-summary-complete"],
                    requiredInputRefs: ["source-netlist-ref", "pex-technology-ref"],
                    missingInputRefs: [],
                    verificationGates: ["artifact-integrity", "pex-summary-gate"],
                    reason: "Run PEX from a produced standard layout artifact.",
                    parameterHints: [
                        "cellID": .string("10000000-0000-0000-0000-000000000711"),
                        "cellName": .string("produced_pex_gate_marker"),
                        "pexInputs": .object([
                            "layoutRefID": .string(layoutCase.artifactID),
                            "sourceNetlistRef": .string("source-netlist-ref"),
                            "technologyRef": .string("pex-technology-ref"),
                            "topCell": .string("top"),
                            "backendID": .string("mock"),
                            "allowMockBackend": .bool(true),
                            "layoutFormat": .string(layoutCase.pexLayoutFormat),
                            "sourceNetlistFormat": .string("spice"),
                            "corners": .array([.string("tt")]),
                            "topNets": .number(5),
                        ]),
                    ],
                    blockers: []
                ),
            ],
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "pex-summary-gate",
                    required: true,
                    description: "Produced standard layout must produce a complete PEX summary."
                ),
            ],
            constraints: [],
            unresolvedObjectives: [],
            blockers: []
        )
    }

    func makeTestPEXTechnology() -> TechnologyIR {
        TechnologyIR(
            processName: "test_process",
            stack: [
                TechnologyLayer(
                    name: "M1",
                    order: 0,
                    thickness: 0.1,
                    material: "copper",
                    resistivity: 1.7e-8
                ),
            ],
            logicalToPhysicalLayerMap: [:],
            vias: [],
            defaultExtractionRules: .default,
            backendHints: [:]
        )
    }

    func makeLVSPlanningProblem() -> XcircuiteCircuitPlanningProblem {
        XcircuiteCircuitPlanningProblem(
            problemID: "run-2-lvs-repair-problem",
            runID: "run-2",
            sourceRefs: [
                XcircuitePlanningReference(
                    refID: "lvs-summary",
                    kind: "lvs-summary",
                    path: ".xcircuite/runs/run-2/stages/008-lvs/raw/lvs-summary.json",
                    artifactID: "lvs-summary"
                ),
            ],
            initialStateRefs: [
                XcircuitePlanningReference(
                    refID: "schematic-netlist-ref",
                    kind: "schematic-netlist",
                    path: "circuits/top.spice"
                ),
            ],
            objectives: [
                XcircuitePlanningObjective(
                    objectiveID: "lvs-model-policy-1",
                    kind: "satisfy",
                    domain: "lvs",
                    priority: "error",
                    sourceRefIDs: ["lvs-summary"],
                    target: "layout-and-schematic-equivalent-for-bucket",
                    currentValue: .number(1),
                    requiredValue: .number(0),
                    description: "Repair model policy mismatch."
                ),
            ],
            constraints: [
                XcircuitePlanningConstraint(
                    constraintID: "policy-repair-approval",
                    kind: "human-approval",
                    severity: "warning",
                    description: "Policy repair requires approval.",
                    sourceRefIDs: ["lvs-summary"]
                ),
            ],
            actionDomainRefs: ["lvs-signoff"],
            candidateActions: [
                XcircuitePlanningCandidateAction(
                    actionID: "lvs-policy-1",
                    domainID: "lvs-signoff",
                    operationID: "lvs.policy-repair",
                    maturity: "implemented",
                    reason: "Resolve model equivalence through an auditable policy update.",
                    sourceObjectiveIDs: ["lvs-model-policy-1"],
                    requiredInputRefs: ["lvs-summary", "schematic-netlist-ref"],
                    verificationGates: ["approval-gate", "native-lvs"]
                ),
            ],
            costModel: XcircuitePlanningCostModel(strategy: "minimize-risk-then-churn", terms: []),
            verificationGates: [
                XcircuitePlanningVerificationGate(
                    gateID: "approval-gate",
                    required: true,
                    description: "Policy repair requires approval."
                ),
            ],
            resumeContract: XcircuitePlanningResumeContract(
                mode: "run-ledger",
                requiredArtifacts: ["planning/problem.json"],
                blockedStates: ["approval-required"]
            )
        )
    }

}
