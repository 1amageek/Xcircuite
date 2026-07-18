public struct XcircuiteSymbolicPlannerFeatureMatrixProvider: Sendable {
    public init() {}

    public func currentMatrix() -> XcircuiteSymbolicPlannerFeatureMatrix {
        let features = [
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.pddl-export",
                category: "problem-encoding",
                capability: "Export planning/problem.json and ActionDomain snapshots into PDDL domain/problem artifacts with atom/action mappings.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPDDLExporter",
                    "xcircuite-flow export-symbolic-planner-problem",
                    "planning/symbolic-planner/pddl-export.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.weighted-action-cost",
                category: "problem-encoding",
                capability: "Export PDDL :action-costs, total-cost metric, and per-action cost mappings from explicit action hints or planning cost model terms.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPDDLExporter",
                    "XcircuiteSymbolicPlannerPDDLActionMapping.actionCost",
                    "planning/symbolic-planner/domain.pddl",
                    "planning/symbolic-planner/pddl-export.json",
                ],
                remainingWork: [
                    "Calibrate broader domain-specific cost terms from real repair-loop outcomes.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.external-solver-invocation",
                category: "solver-integration",
                capability: "Run an external PDDL-compatible solver with timeout, process cleanup, stdout/stderr capture, and solver-plan preservation.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunner",
                    "xcircuite-flow run-symbolic-planner-solver",
                    "planning/symbolic-planner/solver-run.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.expected-action-coverage",
                category: "validation",
                capability: "Compare expected candidate action IDs against actions observed from imported solver output.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverValidator",
                    "planning/symbolic-planner/solver-validation.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.plan-replay-validation",
                category: "validation",
                capability: "Replay imported PDDL solver plans over initial atoms, action preconditions, effects, goals, and action costs before accepting solver output.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteSymbolicPlannerPlanReplayValidator",
                    "planning/symbolic-planner/plan-replay-validation.json",
                    "planning/symbolic-planner/solver-validation.json",
                ],
                remainingWork: [
                    "Extend replay beyond the current additive STRIPS subset when negative effects or numeric fluents become part of exported domains.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.goal-coverage",
                category: "validation",
                capability: "Verify that imported solver plans cover explicit objective goal atoms through the normal candidate-plan verifier.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteCandidatePlanVerifier",
                    "planning/plan-verification.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.multi-case",
                category: "validation",
                capability: "Aggregate multiple prepared run cases into a domain assessment with pass rate and per-case artifact references.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverCorpusAssessor",
                    "assessments/symbolic-planner/<suite-id>/solver-corpus-assessment.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.suite-spec-provenance",
                category: "validation",
                capability: "Persist reproducible corpus suite input including solver, timeout, policy, required coverage tags, and case definitions.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverCorpusSuiteSpec",
                    "assessments/symbolic-planner/<suite-id>/solver-corpus-assessment-suite.json",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.required-coverage-gate",
                category: "validation",
                capability: "Fail a corpus when required coverage tags are not covered by validated cases.",
                maturity: "implemented",
                requiredForCorpusTrust: true,
                evidence: [
                    "missingRequiredCoverageTags",
                    "required-coverage-missing",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on width, spacing, enclosure, overlap-short, minimum-density, antenna, routing, notch, grid, and cut DRC repair-domain cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-repair-domain",
                ],
                remainingWork: [
                    "Add larger PDK-backed and process-family-specific repair suite cases.",
                    "Promote broader DRC diagnostic summaries into expected symbolic coverage tags.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-overlap-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on different-net overlap-short DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-overlap-repair-domain",
                ],
                remainingWork: [
                    "Add forbidden-overlap, same-net overlap, and routed detour variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-density-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on minimum-density DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-density-repair-domain",
                ],
                remainingWork: [
                    "Add maximum-density, density-window, and fill-blockage variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-antenna-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on antenna-ratio DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-antenna-repair-domain",
                ],
                remainingWork: [
                    "Add diode insertion, jumper insertion, multi-layer, and process-step variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-routing-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on DRC routing-detour repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-routing-repair-domain",
                ],
                remainingWork: [
                    "Add multi-net rip-up, preferred-direction, and congestion-aware routing variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-notch-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on notch DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-notch-repair-domain",
                ],
                remainingWork: [
                    "Add shape decomposition, jog cleanup, and layer-specific notch variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-grid-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on manufacturing-grid DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-grid-repair-domain",
                ],
                remainingWork: [
                    "Add multi-shape snap, via alignment, and hierarchy-preserving grid variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.drc-cut-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on cut-rule DRC repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverRunnerTests/assessSymbolicPlannerSolverCorpusCoversDRCRepairDomain",
                    "symbolic.drc-cut-repair-domain",
                ],
                remainingWork: [
                    "Add minimum-cut, cut-spacing, redundant-cut, and cut-array variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on port, model, parameter, device, terminal-equivalence, hierarchy, global-net, policy-mutation, black-box hierarchy, arrayed-device, and parasitic-device LVS mismatch repair-domain cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-repair-domain",
                ],
                remainingWork: [
                    "Add real Netgen policy, foundry-backed hierarchy, and external oracle suites.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-device-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS device mismatch repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-device-repair-domain",
                ],
                remainingWork: [
                    "Add diode, BJT, inductor, source-device, and arrayed-device variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-terminal-equivalence-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS terminal-equivalence repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-terminal-equivalence-repair-domain",
                ],
                remainingWork: [
                    "Add MOS source-drain, passive terminal, diode terminal, and policy-conflict variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-hierarchy-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS hierarchy binding repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-hierarchy-repair-domain",
                ],
                remainingWork: [
                    "Add black-box, flattening, subckt parameter, and repeated-instance hierarchy variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-global-net-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS global-net repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-global-net-repair-domain",
                ],
                remainingWork: [
                    "Add multi-rail, inherited supply, local override, and mixed-case naming variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-policy-mutation-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS matching policy mutation repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-policy-mutation-repair-domain",
                ],
                remainingWork: [
                    "Add competing policy mutation, policy provenance, and real Netgen oracle variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-black-box-hierarchy-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS black-box hierarchy repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-black-box-hierarchy-repair-domain",
                ],
                remainingWork: [
                    "Add nested black-box, mixed flattening, and real Netgen black-box policy variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-arrayed-device-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS arrayed-device repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-arrayed-device-repair-domain",
                ],
                remainingWork: [
                    "Add array expansion, multiplicity normalization, and parallel-device oracle variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.lvs-parasitic-device-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on LVS parasitic-device repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerLVSRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversLVSRepairDomain",
                    "symbolic.lvs-parasitic-device-repair-domain",
                ],
                remainingWork: [
                    "Add extracted parasitic resistor, capacitor, diode, and suppression-policy variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.pex-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on parasitic capacitance, coupling, post-layout metric degradation, multi-corner, RC-network, and post-layout simulation regression repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPEXRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversPEXRepairDomain",
                    "symbolic.pex-repair-domain",
                ],
                remainingWork: [
                    "Add real-extractor, foundry-backed RC topology, and multi-corner external extraction suites.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.pex-multi-corner-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on PEX multi-corner repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPEXRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversPEXRepairDomain",
                    "symbolic.pex-multi-corner-repair-domain",
                ],
                remainingWork: [
                    "Add real extractor and process-corner-specific parasitic threshold variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.pex-rc-network-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on PEX RC-network repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPEXRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversPEXRepairDomain",
                    "symbolic.pex-rc-network-repair-domain",
                ],
                remainingWork: [
                    "Add larger RC topology, coupling tree, and SPEF round-trip variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.pex-post-layout-simulation-repair-domain",
                category: "domain-corpus",
                capability: "Assess symbolic solver behavior on PEX-driven post-layout simulation regression repair cases.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPEXRepairDomainCorpusTests/assessSymbolicPlannerSolverCorpusCoversPEXRepairDomain",
                    "symbolic.pex-post-layout-simulation-repair-domain",
                ],
                remainingWork: [
                    "Add post-layout waveform, corner sweep, and metric-threshold regression variants.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.optimality-check",
                category: "solver-integration",
                capability: "Record and verify solver optimality or cost claims when the selected planner provides them.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverMetadataParser",
                    "XcircuiteSymbolicPlannerSolverValidator",
                    "planning/symbolic-planner/solver-validation.json",
                ],
                remainingWork: [
                    "Broaden parser patterns for additional installed planner families.",
                    "Add machine-checkable proof adapters for planner families that provide proof formats beyond textual certificates.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.independent-plan-cost",
                category: "validation",
                capability: "Evaluate imported solver plan length and PDDL action cost inside LSI and compare solver cost claims against that independent evaluation.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerPlanCostEvaluator",
                    "XcircuiteSymbolicPlannerSolverValidator",
                    "planning/symbolic-planner/solver-validation.json",
                ],
                remainingWork: [
                    "Calibrate domain-specific proof requirements for solver families that can emit machine-checkable certificates.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.solver-proof-validation",
                category: "solver-integration",
                capability: "Run an external proof checker against solver proof or certificate artifacts and persist typed proof-validation evidence in solver validation.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerProofValidation",
                    "xcircuite-flow validate-symbolic-planner-solver --require-proof-validation",
                    "planning/symbolic-planner/proof-validation.json",
                    "planning/symbolic-planner/solver-validation.json",
                ],
                remainingWork: [
                    "Add real planner-family proof checker fixtures beyond the generic external checker adapter.",
                    "Promote proof validation to required corpus trust for proof-bearing optimal planners after corpus coverage is broad enough.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.solver-native-certificate-parsing",
                category: "solver-integration",
                capability: "Parse planner-native JSON/text certificate claims, including Fast Downward, Metric-FF, OPTIC, and Madagascar text fixtures, persist structured certificate evidence, and compare certificate cost, length, optimality, proof, action, and goal-coverage claims against independent validation results.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerSolverCertificateParser",
                    "XcircuiteSymbolicPlannerSolverCertificateParseResult",
                    "XcircuiteSymbolicPlannerSolverRunnerTests/solverCertificateParserRecognizesPlannerFamilyTextFixtures",
                    "XcircuiteSymbolicPlannerSolverRunnerTests/runSymbolicPlannerSolverFamilyBatchPersistsPlannerFamilyCertificateFixtures",
                    "xcircuite-flow validate-symbolic-planner-solver --require-native-certificate",
                    "planning/symbolic-planner/solver-certificate.json",
                    "planning/symbolic-planner/solver-validation.json",
                ],
                remainingWork: [
                    "Connect Fast Downward, Metric-FF, Madagascar, and OPTIC fixtures to installed local solver binary validation lanes when those binaries are present.",
                    "Extend parser contracts for solver-specific certificate sections that go beyond the current JSON/text claim schema.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.repair-formulation-compiler",
                category: "problem-formulation",
                capability: "Compile Agent-provided structured repair formulations into auditable planning/repair-formulation.json and canonical planning/problem.json artifacts that can be validated and exported to PDDL.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteRepairPlanFormulation",
                    "XcircuiteRepairPlanFormulationCompiler",
                    "xcircuite-flow formulate-repair-planning-problem",
                    "planning/repair-formulation.json",
                    "planning/problem.json",
                    "XcircuiteRepairPlanFormulationCompilerTests/formulateRepairPlanningProblemCLICompilesAuditableProblemAndPDDLExport",
                ],
                remainingWork: [
                    "Add richer formulation policies for multi-objective analog optimization, layout-side repair alternatives, and human approval checkpoints.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.signoff-repair-formulation-bridge",
                category: "problem-formulation",
                capability: "Compile DRCEngine and LVSEngine repair hint reports into auditable planning/repair-formulation.json and canonical planning/problem.json artifacts before validation or PDDL export.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSignoffRepairFormulationBuilder",
                    "xcircuite-flow formulate-signoff-repair-planning-problem",
                    "planning/repair-formulation.json",
                    "planning/problem.json",
                    "XcircuiteSignoffRepairFormulationBuilderTests/signoffRepairHintsCLICompilesAuditableFormulationProblemAndPDDLExport",
                ],
                remainingWork: [
                    "Broaden signoff repair formulation inputs with PDK-backed DRC/LVS reports and executed candidate-produced layout artifacts.",
                ]
            ),
            XcircuiteSymbolicPlannerFeature(
                coverageTag: "symbolic.installed-solver-lane",
                category: "solver-integration",
                capability: "Discover installed local symbolic planner binaries, persist a solver-family lane artifact, record missing binary gaps, and generate a solver-family batch request containing only available candidates.",
                maturity: "implemented",
                requiredForCorpusTrust: false,
                evidence: [
                    "XcircuiteSymbolicPlannerInstalledSolverLaneResolver",
                    "xcircuite-flow discover-installed-symbolic-planner-solvers",
                    "planning/symbolic-planner/installed-solver-lane.json",
                    "XcircuiteSymbolicPlannerSolverRunnerTests/discoverInstalledSymbolicPlannerSolversCLIWritesLaneArtifactAndBatchSpec",
                ],
                remainingWork: [
                    "Retain CI runs with real installed planner binaries and prepared PDDL repair cases.",
                    "Add solver-specific argument policy variants for non-default search modes.",
                ]
            ),
        ]
        return XcircuiteSymbolicPlannerFeatureMatrix(
            matrixID: "symbolic-planner-feature-matrix-v1",
            requiredForCorpusTrustTags: features
                .filter(\.requiredForCorpusTrust)
                .map(\.coverageTag)
                .sorted(),
            implementedCoverageTags: features
                .filter { $0.maturity == "implemented" }
                .map(\.coverageTag)
                .sorted(),
            plannedCoverageTags: features
                .filter { $0.maturity != "implemented" }
                .map(\.coverageTag)
                .sorted(),
            features: features
        )
    }
}
