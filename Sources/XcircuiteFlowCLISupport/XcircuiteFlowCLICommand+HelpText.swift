import DesignFlowKernel
import Foundation
import Xcircuite
import XcircuitePackage

extension XcircuiteFlowCLICommand {
    public static var usageText: String {
        "Usage: xcircuite-flow inspect-platform-capabilities [--run-id <id>] [--generated-at <timestamp>] [--pretty] | xcircuite-flow run --project-root <path> --run-spec <path> --runtime-config <path> [--pretty] | xcircuite-flow resume-run --project-root <path> --run-id <id> --runtime-config <path> [--pretty] | xcircuite-flow attach-evidence --runtime-config <path> --stage-id <id> --evidence <path> [--out <path>] [--pretty] | xcircuite-flow generate-planning-problem --project-root <path> --run-id <id> --source <drc-summary|lvs-summary|pex-summary> [--pretty] | xcircuite-flow formulate-repair-planning-problem --project-root <path> --run-id <id> --formulation-path <path> [--pretty] | xcircuite-flow formulate-signoff-repair-planning-problem --project-root <path> --run-id <id> [--drc-repair-hints <path>] [--lvs-repair-hints <path>] [--pretty] | xcircuite-flow collect-generated-layout-signoff-corpus --project-root <path> --request <path> [--persist] [--pretty] | xcircuite-flow qualify-generated-layout-signoff-corpus --project-root <path> --report <path> [--policy <path>] [--persist] [--pretty] | xcircuite-flow attach-generated-layout-ready-oracle-evidence --project-root <path> --report <path> --retained-signoff-report <path> [--persist] [--pretty] | xcircuite-flow audit-generated-layout-signoff-corpus-coverage --project-root <path> --report <path> --policy <path> [--persist] [--pretty] | xcircuite-flow assess-generated-layout-signoff-promotion --project-root <path> --qualification <path> [--retained-signoff-report <path>] [--promotion-id <id>] [--persist] [--pretty] | xcircuite-flow collect-generated-layout-failure-ladder --project-root <path> --run-id <id> [--ladder-id <id>] [--persist] [--pretty] | xcircuite-flow audit-generated-layout-failure-ladder-coverage --project-root <path> --policy <path> --report <path> [--report <path> ...] [--persist] [--pretty] | xcircuite-flow audit-problem-translation --project-root <path> --run-id <id> [--pretty] | xcircuite-flow validate-planning-problem --project-root <path> --run-id <id> [--pretty] | xcircuite-flow generate-candidate-plan --project-root <path> --run-id <id> [--strategy <name>] [--calibration-policy <disabled|cp7-feedback>] [--cost-calibration-path <path>] [--pareto-candidates-path <path>] [--pretty] | xcircuite-flow run-symbolic-planner-family --project-root <path> --run-id <id> [--strategy <name> ...] [--calibration-policy <disabled|cp7-feedback>] [--pretty] | xcircuite-flow export-symbolic-planner-problem --project-root <path> --run-id <id> [--pretty] | xcircuite-flow run-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--arg <value> ...] [--pretty] | xcircuite-flow qualify-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--expected-action-id <id> ...] [--require-optimality] [--max-solver-cost <number>] [--require-native-certificate --certificate-path <path>] [--require-proof-validation --proof-path <path> --proof-checker-executable-path <path>] [--pretty] | xcircuite-flow discover-installed-symbolic-planner-solvers --project-root <path> --run-id <id> [--search-path <path> ...] [--batch-spec-output-path <path>] [--pretty] | xcircuite-flow run-symbolic-planner-solver-family --project-root <path> --spec <path> [--comparison-id <id>] [--no-promote] [--pretty] | xcircuite-flow compare-symbolic-planner-solver-family --project-root <path> --run-id <id> (--qualification-artifact-id <id> | --qualification-path <path>) [--comparison-id <id>] [--pretty] | xcircuite-flow promote-symbolic-planner-solver-family-selection --project-root <path> --run-id <id> [--comparison-id <id>] [--pretty] | xcircuite-flow qualify-symbolic-planner-solver-corpus --project-root <path> (--suite-spec <path> | --suite-id <id> --executable-path <path> --case <run-id:expected-action-ids> [--case <...>]) [--require-optimality] [--max-solver-cost <number>] [--require-proof-validation --proof-checker-executable-path <path> --case-proof <case-id:path>] [--pretty] | xcircuite-flow symbolic-planner-feature-matrix [--pretty] | xcircuite-flow import-symbolic-planner-plan --project-root <path> --run-id <id> --solver-plan-path <path> [--pretty] | xcircuite-flow generate-parameter-candidates --project-root <path> --run-id <id> [--strategy <name>] [--cost-calibration-path <path>] [--pareto-candidates-path <path>] [--pretty] | xcircuite-flow synthesize-parameter-candidate-plan --project-root <path> --run-id <id> [--rank <n>] [--candidate-id <id>] [--include-rejected-candidates] [--pretty] | xcircuite-flow approve-candidate-plan-risk --project-root <path> --run-id <id> --approval-id <id> --reviewer <name> [--reviewer-kind agent|human|cli|system] [--decision approved|rejected] [--pretty] | xcircuite-flow verify-candidate-plan --project-root <path> --run-id <id> [--mode <name>] [--pretty] | xcircuite-flow execute-candidate-plan --project-root <path> --run-id <id> [--pretty] | xcircuite-flow run-numeric-repair-loop --project-root <path> --run-id <id> [--max-iterations <count>] [--calibration-policy <disabled|cp7-feedback>] [--pretty] | xcircuite-flow generate-improvement-artifacts --project-root <path> --run-id <id> [--pretty] | xcircuite-flow qualify-verified-improvement-corpus --project-root <path> --suite-spec <path> [--persist] [--pretty] | xcircuite-flow run-selected-suggested-command --project-root <path> --run-id <id> [--command-id <id>] | xcircuite-flow summarize-loop --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty] | xcircuite-flow evaluate-run-guard --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty] | xcircuite-flow compare-artifacts --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty] | xcircuite-flow write-opamp-evaluation-profile --out <path> [--profile-id <id>] [--pretty] | xcircuite-flow write-opamp-spec --out <path> [--spec-id <id>] [--supply-v <number>] [--load-cap-f <number>] [--gain-db <number>] [--ugb-hz <number>] [--phase-margin-deg <number>] [--slew-rate-v-per-s <number>] [--pretty] | xcircuite-flow list-opamp-topologies --spec <path> [--pretty] | xcircuite-flow size-opamp --spec <path> [--technology <path>] [--topology <twoStageMiller|foldedCascode|telescopicCascode>] [--project-root <path> --run-id <id>] [--no-persist] [--pretty] | xcircuite-flow validate-opamp-simulation-decks --deck-set <path> [--mode <parseOnly|executeCoreSpice>|--execute] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty] | xcircuite-flow extract-opamp-waveform-metrics --analysis <ac-open-loop|tran-positive-step|tran-negative-step|noise-input-referred> --waveform <path> [--output-variable <name>] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty] | xcircuite-flow merge-opamp-metric-extractions --extraction <path> [--extraction <path> ...] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty] | xcircuite-flow evaluate-opamp --spec <path> (--cross-artifact-evaluation <path> | --sizing-result <path> | --simulation-metric-report <path> | --simulation-run-summary <path> | --simulation-measurements <path> | --opamp-metric-extraction <path>) [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty] | xcircuite-flow compare-opamp-post-layout --spec <path> --pre-report <path> --post-report <path> [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty] | xcircuite-flow inspect-toolchain-profile --runtime-config <path> [--project-root <path>] [--pretty] | xcircuite-flow inspect-technology-catalog (--catalog-path <path> | --runtime-config <path> | --pdk-root <path>) [--catalog-path <path> ...] [--pdk-root <path> ...] [--project-root <path>] [--pretty] | xcircuite-flow scaffold-run --run-id <id> --out-run-spec <path> --out-runtime-config <path> [--stage <kind>[,<kind>...]] [--pretty] | xcircuite-flow validate [--project-root <path>] [--run-spec <path>] [--runtime-config <path>] [--pretty]"
    }

    public static var helpText: String {
        """
        Usage:
          xcircuite-flow inspect-platform-capabilities [--run-id <id>] [--generated-at <timestamp>] [--pretty]
          xcircuite-flow compare-simulation-golden --golden-csv <path> --candidate-csv <path> [--max-absolute-delta <number>] [--max-relative-delta <number>] [--relative-delta-denominator-floor <number>] [--required-variable <name> ...] [--compare-variable <name> ...] [--no-interpolation] [--out <path>] [--pretty]
          xcircuite-flow qualify-simulation-golden-corpus --project-root <path> --suite <path> [--artifact-dir <path>] [--out <path>] [--pretty]
          xcircuite-flow run --project-root <path> --run-spec <path> --runtime-config <path> [--pretty]
          xcircuite-flow resume-run --project-root <path> --run-id <id> --runtime-config <path> [--pretty]
          xcircuite-flow attach-evidence --runtime-config <path> --stage-id <id> --evidence <path> [--out <path>] [--pretty]
          xcircuite-flow generate-planning-problem --project-root <path> --run-id <id> --source <drc-summary|lvs-summary|pex-summary> [--summary-artifact-id <id>] [--summary-path <path>] [--layout-artifact-id <id>] [--layout-path <path>] [--layout-netlist-path <path>] [--schematic-netlist-path <path>] [--source-netlist-path <path>] [--technology-artifact-id <id>] [--technology-path <path>] [--metric-report-path <path>] [--repair-hint-artifact-id <id>] [--repair-hint-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]
          xcircuite-flow formulate-repair-planning-problem --project-root <path> --run-id <id> --formulation-path <path> [--problem-id <id>] [--pretty]
          xcircuite-flow formulate-signoff-repair-planning-problem --project-root <path> --run-id <id> [--drc-repair-hints <path>] [--lvs-repair-hints <path>] [--formulation-id <id>] [--intent-id <id>] [--intent <text>] [--problem-id <id>] [--pretty]
          xcircuite-flow collect-generated-layout-signoff-corpus --project-root <path> --request <path> [--persist] [--pretty]
          xcircuite-flow qualify-generated-layout-signoff-corpus --project-root <path> --report <path> [--policy <path>] [--persist] [--pretty]
          xcircuite-flow attach-generated-layout-ready-oracle-evidence --project-root <path> --report <path> --retained-signoff-report <path> [--persist] [--pretty]
          xcircuite-flow audit-generated-layout-signoff-corpus-coverage --project-root <path> --report <path> --policy <path> [--persist] [--pretty]
          xcircuite-flow assess-generated-layout-signoff-promotion --project-root <path> --qualification <path> [--retained-signoff-report <path>] [--promotion-id <id>] [--persist] [--pretty]
          xcircuite-flow collect-generated-layout-failure-ladder --project-root <path> --run-id <id> [--ladder-id <id>] [--persist] [--pretty]
          xcircuite-flow audit-generated-layout-failure-ladder-coverage --project-root <path> --policy <path> --report <path> [--report <path> ...] [--persist] [--pretty]
          xcircuite-flow audit-problem-translation --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--pretty]
          xcircuite-flow validate-planning-problem --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]
          xcircuite-flow generate-candidate-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name>] [--calibration-policy <disabled|cp7-feedback>] [--pretty]
          xcircuite-flow run-symbolic-planner-family --project-root <path> --run-id <id> [--family-run-id <id>] [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name> ...] [--calibration-policy <disabled|cp7-feedback>] [--selection-policy <name>] [--pretty]
          xcircuite-flow export-symbolic-planner-problem --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]
          xcircuite-flow run-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--arg <value> ...] [--timeout-seconds <seconds>] [--domain-artifact-id <id>] [--domain-path <path>] [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--working-directory-path <path>] [--solver-plan-output-path <path>] [--no-import] [--pretty]
          xcircuite-flow qualify-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--tool-id <id>] [--arg <value> ...] [--timeout-seconds <seconds>] [--expected-action-id <id> ...] [--allow-missing-goal-coverage] [--require-optimality] [--max-solver-cost <number>] [--require-native-certificate] [--certificate-artifact-id <id>] [--certificate-path <path>] [--certificate-format <auto|generic-json|generic-text|fast-downward-text|metric-ff-text|optic-text|madagascar-text>] [--require-proof-validation] [--proof-artifact-id <id>] [--proof-path <path>] [--proof-checker-executable-path <path>] [--proof-checker-arg <value> ...] [--proof-checker-timeout-seconds <seconds>] [--proof-checker-working-directory-path <path>] [--policy-id <id>] [--domain-artifact-id <id>] [--domain-path <path>] [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--working-directory-path <path>] [--solver-plan-output-path <path>] [--pretty]
          xcircuite-flow discover-installed-symbolic-planner-solvers --project-root <path> --run-id <id> [--lane-id <id>] [--search-path <path> ...] [--selection-policy <id>] [--promote-selected-plan] [--allow-unqualified-promotion] [--skip-promotion-verification] [--batch-spec-output-path <path>] [--pretty]
          xcircuite-flow run-symbolic-planner-solver-family --project-root <path> --spec <path> [--comparison-id <id>] [--no-promote] [--allow-unqualified-promotion] [--skip-promotion-verification] [--pretty]
          xcircuite-flow compare-symbolic-planner-solver-family --project-root <path> --run-id <id> [--comparison-id <id>] [--qualification-artifact-id <id> ...] [--qualification-path <path> ...] [--selection-policy <id>] [--pretty]
          xcircuite-flow promote-symbolic-planner-solver-family-selection --project-root <path> --run-id <id> [--comparison-id <id>] [--comparison-artifact-id <id>] [--comparison-path <path>] [--candidate-index <n>] [--allow-unqualified] [--skip-verification] [--pretty]
          xcircuite-flow qualify-symbolic-planner-solver-corpus --project-root <path> --suite-spec <path> [--pretty]
          xcircuite-flow qualify-symbolic-planner-solver-corpus --project-root <path> --suite-id <id> --executable-path <path> [--tool-id <id>] [--arg <value> ...] [--timeout-seconds <seconds>] [--policy-id <id>] [--required-coverage-tag <tag> ...] [--case-coverage <case-id:tag[,tag]> ...] [--allow-missing-goal-coverage] [--require-optimality] [--max-solver-cost <number>] [--require-proof-validation] [--proof-checker-executable-path <path>] [--proof-checker-arg <value> ...] [--proof-checker-timeout-seconds <seconds>] [--proof-checker-working-directory-path <path>] [--case-proof <case-id:path> ...] --case <run-id:expected-action-ids> [--case <run-id:expected-action-ids> ...] [--pretty]
          xcircuite-flow symbolic-planner-feature-matrix [--pretty]
          xcircuite-flow import-symbolic-planner-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--solver-plan-artifact-id <id>] [--solver-plan-path <path>] [--pretty]
          xcircuite-flow generate-parameter-candidates --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--previous-parameter-candidates-artifact-id <id>] [--previous-parameter-candidates-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name>] [--max-candidates <count>] [--pretty]
          xcircuite-flow synthesize-parameter-candidate-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--parameter-candidates-artifact-id <id>] [--parameter-candidates-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--candidate-id <id>] [--rank <n>] [--strategy <name>] [--include-rejected-candidates] [--pretty]
          xcircuite-flow approve-candidate-plan-risk --project-root <path> --run-id <id> --approval-id <id> --reviewer <name> [--reviewer-kind agent|human|cli|system] [--decision approved|rejected] [--note <text>] [--pretty]
          xcircuite-flow verify-candidate-plan --project-root <path> --run-id <id> [--candidate-plan-artifact-id <id>] [--candidate-plan-path <path>] [--mode <name>] [--pretty]
          xcircuite-flow execute-candidate-plan --project-root <path> --run-id <id> [--candidate-plan-artifact-id <id>] [--candidate-plan-path <path>] [--actor <id>] [--pretty]
          xcircuite-flow run-numeric-repair-loop --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--initial-candidate-strategy <name>] [--feedback-candidate-strategy <name>] [--max-candidates <count>] [--max-iterations <count>] [--synthesis-strategy <name>] [--mode <name>] [--actor <id>] [--calibration-policy <disabled|cp7-feedback>] [--pretty]
          xcircuite-flow generate-improvement-artifacts --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--numeric-repair-loop-artifact-id <id>] [--numeric-repair-loop-path <path>] [--generated-at <timestamp>] [--pretty]
          xcircuite-flow qualify-verified-improvement-corpus --project-root <path> --suite-spec <path> [--persist] [--pretty]
          xcircuite-flow run-selected-suggested-command --project-root <path> --run-id <id> [--command-id <id>]
          xcircuite-flow summarize-loop --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]
          xcircuite-flow evaluate-run-guard --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]
          xcircuite-flow compare-artifacts --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]
          xcircuite-flow write-opamp-evaluation-profile --out <path> [--profile-id <id>] [--pretty]
          xcircuite-flow write-opamp-spec --out <path> [--spec-id <id>] [--supply-v <number>] [--load-cap-f <number>] [--gain-db <number>] [--ugb-hz <number>] [--phase-margin-deg <number>] [--slew-rate-v-per-s <number>] [--pretty]
          xcircuite-flow list-opamp-topologies --spec <path> [--pretty]
          xcircuite-flow size-opamp --spec <path> [--technology <path>] [--topology <twoStageMiller|foldedCascode|telescopicCascode>] [--project-root <path> --run-id <id>] [--no-persist] [--pretty]
          xcircuite-flow validate-opamp-simulation-decks --deck-set <path> [--mode <parseOnly|executeCoreSpice>|--execute] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]
          xcircuite-flow extract-opamp-waveform-metrics --analysis <ac-open-loop|tran-positive-step|tran-negative-step|noise-input-referred> --waveform <path> [--output-variable <name>] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]
          xcircuite-flow merge-opamp-metric-extractions --extraction <path> [--extraction <path> ...] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]
          xcircuite-flow evaluate-opamp --spec <path> (--cross-artifact-evaluation <path> | --sizing-result <path> | --simulation-metric-report <path> | --simulation-run-summary <path> | --simulation-measurements <path> | --opamp-metric-extraction <path>) [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]
          xcircuite-flow compare-opamp-post-layout --spec <path> --pre-report <path> --post-report <path> [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]
          xcircuite-flow inspect-toolchain-profile --runtime-config <path> [--project-root <path>] [--pretty]
          xcircuite-flow inspect-technology-catalog (--catalog-path <path> | --runtime-config <path> | --pdk-root <path>) [--catalog-path <path> ...] [--pdk-root <path> ...] [--project-root <path>] [--pretty]
          xcircuite-flow scaffold-run --run-id <id> --out-run-spec <run.json> --out-runtime-config <runtime.json> [--stage <kind>[,<kind>...]] [--pretty]
          xcircuite-flow validate [--project-root <path>] [--run-spec <path>] [--runtime-config <path>] [--pretty]
          xcircuite-flow --help
        """
    }

    public static var inspectPlatformCapabilitiesHelpText: String {
        """
        Usage:
          xcircuite-flow inspect-platform-capabilities [--run-id <id>] [--generated-at <timestamp>] [--pretty]

        Builds the canonical action-domain snapshot and returns milestone readiness for standalone signoff, Agent-operable design loops, human review, standard-format grounding, and post-layout improvement planning.
        """
    }

    public static var summarizeLoopHelpText: String {
        """
        Usage:
          xcircuite-flow summarize-loop --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]

        Builds loop/iterations.jsonl and loop/snapshot.json from the run ledger, action log, approvals, and artifact envelopes.
        """
    }

    public static var evaluateRunGuardHelpText: String {
        """
        Usage:
          xcircuite-flow evaluate-run-guard --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]

        Builds a loop snapshot, evaluates deterministic guard detectors, writes loop/guard-verdict.json, and emits a structured guard result for external Agent and human review.
        """
    }

    public static var compareArtifactsHelpText: String {
        """
        Usage:
          xcircuite-flow compare-artifacts --project-root <path> --run-id <id> [--profile <path>] [--no-persist] [--pretty]

        Builds reports/cross-artifact-evaluation.json from stage results, gates, design diff, artifact envelopes, and an optional XcircuiteEvaluationProfile. The external Agent owns the next edit decision.
        """
    }

    public static var writeOpAmpEvaluationProfileHelpText: String {
        """
        Usage:
          xcircuite-flow write-opamp-evaluation-profile --out <path> [--profile-id <id>] [--pretty]

        Writes an XcircuiteEvaluationProfile for op-amp design evaluation channels and required artifact roles. The profile is evaluation material, not a fixed design loop.
        """
    }

    public static var writeOpAmpSpecHelpText: String {
        """
        Usage:
          xcircuite-flow write-opamp-spec --out <path> [--spec-id <id>] [--supply-v <number>] [--load-cap-f <number>] [--gain-db <number>] [--ugb-hz <number>] [--phase-margin-deg <number>] [--slew-rate-v-per-s <number>] [--pretty]

        Writes a first-class OpAmpSpec JSON file with gain, bandwidth, stability, slew, CMRR, PSRR, noise, offset, power, swing, and common-mode requirements.
        """
    }

    public static var listOpAmpTopologiesHelpText: String {
        """
        Usage:
          xcircuite-flow list-opamp-topologies --spec <path> [--pretty]

        Ranks two-stage Miller, folded cascode, and telescopic cascode topology candidates against an OpAmpSpec and returns structured capability diagnostics.
        """
    }

    public static var sizeOpAmpHelpText: String {
        """
        Usage:
          xcircuite-flow size-opamp --spec <path> [--technology <path>] [--topology <twoStageMiller|foldedCascode|telescopicCascode>] [--project-root <path> --run-id <id>] [--no-persist] [--pretty]

        Generates an initial gm/Id sizing result, SPICE netlist, estimated metrics, and analog layout constraint plan. By default the command persists opamp artifacts under .xcircuite/runs/<run-id>/opamp/.
        """
    }

    public static var validateOpAmpSimulationDecksHelpText: String {
        """
        Usage:
          xcircuite-flow validate-opamp-simulation-decks --deck-set <path> [--mode <parseOnly|executeCoreSpice>|--execute] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]

        Parses an OpAmpSimulationDeckSet and, in executeCoreSpice mode, runs every deck through CoreSpiceSimulationEngine while checking required direct measurements and waveform-post-processing contracts.
        """
    }

    public static var extractOpAmpWaveformMetricsHelpText: String {
        """
        Usage:
          xcircuite-flow extract-opamp-waveform-metrics --analysis <ac-open-loop|tran-positive-step|tran-negative-step|noise-input-referred> --waveform <path> [--output-variable <name>] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]

        Extracts op-amp metrics from CoreSpice waveform CSV artifacts. AC waveforms produce gain, unity-gain frequency, and phase-margin material when available; transient waveforms produce slew and settling metrics; noise waveforms produce input-referred-noise metrics.
        """
    }

    public static var mergeOpAmpMetricExtractionsHelpText: String {
        """
        Usage:
          xcircuite-flow merge-opamp-metric-extractions --extraction <path> [--extraction <path> ...] [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]

        Merges multiple op-amp metric extraction artifacts into one evaluation-ready artifact. Duplicate metrics are resolved by input order and conflicting values are retained as structured diagnostics.
        """
    }

    public static var evaluateOpAmpHelpText: String {
        """
        Usage:
          xcircuite-flow evaluate-opamp --spec <path> (--cross-artifact-evaluation <path> | --sizing-result <path> | --simulation-metric-report <path> | --simulation-run-summary <path> | --simulation-measurements <path> | --opamp-metric-extraction <path>) [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]

        Evaluates op-amp metrics against an OpAmpSpec and emits pass/fail/missing results with failure classifications and suggested next actions for an external Agent or developer. Simulation metric reports, simulation run summaries, measurements.json artifacts, op-amp waveform metric extraction artifacts, and merged op-amp metric extraction artifacts are mapped into first-class op-amp metrics before evaluation.
        """
    }

    public static var compareOpAmpPostLayoutHelpText: String {
        """
        Usage:
          xcircuite-flow compare-opamp-post-layout --spec <path> --pre-report <path> --post-report <path> [--out <path>] [--project-root <path> --run-id <id> --persist] [--pretty]

        Compares pre-layout and post-layout op-amp evaluation reports and classifies PEX-driven regressions such as gain loss, stability loss, slew degradation, noise growth, and offset drift.
        """
    }

    public static var compareSimulationGoldenHelpText: String {
        """
        Usage:
          xcircuite-flow compare-simulation-golden --golden-csv <path> --candidate-csv <path> [--max-absolute-delta <number>] [--max-relative-delta <number>] [--relative-delta-denominator-floor <number>] [--required-variable <name> ...] [--compare-variable <name> ...] [--no-interpolation] [--out <path>] [--pretty]

        Compares a candidate simulation waveform CSV against a golden waveform CSV and emits a structured report with variable-level deltas, worst points, gate violations, and required-variable coverage. With --out, the report is also written to the given path.
        """
    }

    public static var qualifySimulationGoldenCorpusHelpText: String {
        """
        Usage:
          xcircuite-flow qualify-simulation-golden-corpus --project-root <path> --suite <path> [--artifact-dir <path>] [--out <path>] [--pretty]

        Runs each SPICE netlist in a simulation golden corpus suite, compares the produced waveform against the checked-in golden waveform, writes per-case candidate waveform and comparison artifacts, and emits a corpus report with pass/fail counts and coverage tags.
        """
    }

    public static var resumeRunHelpText: String {
        """
        Usage:
          xcircuite-flow resume-run --project-root <path> --run-id <id> --runtime-config <path> [--pretty]

        Loads an XcircuiteFlowRuntimeSpec JSON file and resumes the stored run plan.
        """
    }

    public static var runHelpText: String {
        """
        Usage:
          xcircuite-flow run --project-root <path> --run-spec <path> --runtime-config <path> [--pretty]

        Loads an XcircuiteFlowRunSpec and XcircuiteFlowRuntimeSpec, then executes the flow.
        """
    }

    public static var attachEvidenceHelpText: String {
        """
        Usage:
          xcircuite-flow attach-evidence --runtime-config <path> --stage-id <id> --evidence <path> [--out <path>] [--pretty]

        Loads a runtime config and a ToolEvidence-compatible export, then attaches
        the evidence to the selected stage executor. Without --out, the updated
        runtime config is written to stdout.
        """
    }

    public static var scaffoldRunHelpText: String {
        """
        Usage:
          xcircuite-flow scaffold-run --run-id <id> --out-run-spec <run.json> --out-runtime-config <runtime.json> [--stage <kind>[,<kind>...]] [--pretty]

        Writes a minimal valid XcircuiteFlowRunSpec + XcircuiteFlowRuntimeSpec pair
        with sequential stage IDs (001-…), the contract-correct requiredTool block
        per stage kind (the mock PEX stage stays at minimumLevel "unknown" with no
        qualified-evidence requirement), placeholder input paths, and corpus
        evidence whose checkedAt is stamped with the current time. Stage kinds:
        coreSpiceSimulation, mockPEX, postLayoutComparison (default: all three, in
        that order). Both files are decoded back through the real spec types and
        pass coverage validation before anything is written. Edit the placeholder
        paths, then run xcircuite-flow validate.
        """
    }

    public static var validateHelpText: String {
        """
        Usage:
          xcircuite-flow validate [--project-root <path>] [--run-spec <path>] [--runtime-config <path>] [--pretty]

        Validates a run spec, runtime config, or both. When both are provided,
        the command also verifies that every run stage has a runtime executor.
        Add --project-root to resolve runtime technology catalogs and required files.
        """
    }

    public static var inspectToolchainProfileHelpText: String {
        """
        Usage:
          xcircuite-flow inspect-toolchain-profile --runtime-config <path> [--project-root <path>] [--pretty]

        Loads a runtime config and returns a structured toolchain profile readiness report. Unlike validate, this command returns failed readiness as JSON so Agent and CI callers can inspect missing PDK/catalog files without parsing thrown errors.
        """
    }

    public static var inspectTechnologyCatalogHelpText: String {
        """
        Usage:
          xcircuite-flow inspect-technology-catalog (--catalog-path <path> | --runtime-config <path> | --pdk-root <path>) [--catalog-path <path> ...] [--pdk-root <path> ...] [--project-root <path>] [--pretty]

        Loads one or more technology catalogs and returns entry-level required-file inventory. When --runtime-config is provided, the command also inspects toolchainProfile.technologyCatalogPath when present. When --pdk-root is provided, bounded catalog discovery runs under that root and relative required files can resolve from the PDK root when they are not present next to the catalog.
        """
    }

    public static var generatePlanningProblemHelpText: String {
        """
        Usage:
          xcircuite-flow generate-planning-problem --project-root <path> --run-id <id> --source <drc-summary|lvs-summary|pex-summary> [--summary-artifact-id <id>] [--summary-path <path>] [--layout-artifact-id <id>] [--layout-path <path>] [--layout-netlist-path <path>] [--schematic-netlist-path <path>] [--source-netlist-path <path>] [--technology-artifact-id <id>] [--technology-path <path>] [--metric-report-path <path>] [--repair-hint-artifact-id <id>] [--repair-hint-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]

        Loads a run summary artifact and writes planning/problem.json for planner and review consumption.
        """
    }

    public static var formulateRepairPlanningProblemHelpText: String {
        """
        Usage:
          xcircuite-flow formulate-repair-planning-problem --project-root <path> --run-id <id> --formulation-path <path> [--problem-id <id>] [--pretty]

        Loads a structured repair plan formulation, writes planning/repair-formulation.json for audit, and compiles it into planning/problem.json for planner and review consumption.
        """
    }

    public static var formulateSignoffRepairPlanningProblemHelpText: String {
        """
        Usage:
          xcircuite-flow formulate-signoff-repair-planning-problem --project-root <path> --run-id <id> [--drc-repair-hints <path>] [--lvs-repair-hints <path>] [--formulation-id <id>] [--intent-id <id>] [--intent <text>] [--problem-id <id>] [--pretty]

        Loads DRC and LVS engine-owned repair hint reports from registered run artifacts, verifies their SHA-256 and byte counts, writes planning/repair-formulation.json for audit, and compiles it into planning/problem.json for planner and review consumption.
        """
    }

    public static var collectGeneratedLayoutSignoffCorpusHelpText: String {
        """
        Usage:
          xcircuite-flow collect-generated-layout-signoff-corpus --project-root <path> --request <path> [--persist] [--pretty]

        Loads a generated-layout signoff corpus request, collects run-ledger and review-bundle artifact refs for layout, DRC, LVS, PEX, simulation, and post-layout stages, and returns a corpus report with expected verdicts, coverage tags, oracle readiness, and SHA-256 / byte-count artifact refs. With --persist, the suite spec and report are written under .xcircuite/qualification/generated-layout-signoff/<suite-id>/.
        """
    }

    public static var qualifyGeneratedLayoutSignoffCorpusHelpText: String {
        """
        Usage:
          xcircuite-flow qualify-generated-layout-signoff-corpus --project-root <path> --report <path> [--policy <path>] [--persist] [--pretty]

        Loads a generated-layout signoff corpus report and applies a qualification policy for case count, coverage, required stage families, oracle readiness, artifact hashes, byte counts, and integrity status. With --persist, the policy and qualification result are written under .xcircuite/qualification/generated-layout-signoff/<suite-id>/.
        """
    }

    public static var attachGeneratedLayoutReadyOracleEvidenceHelpText: String {
        """
        Usage:
          xcircuite-flow attach-generated-layout-ready-oracle-evidence --project-root <path> --report <path> --retained-signoff-report <path> [--persist] [--pretty]

        Loads a generated-layout signoff corpus report plus a retained signoff report, then attaches DRC/LVS/PEX ready-oracle evidence refs from passing retained external-oracle lanes. With --persist, the evidence-backed corpus report is written under .xcircuite/qualification/generated-layout-signoff/<suite-id>/corpus-report-ready-oracle-evidence.json.
        """
    }

    public static var auditGeneratedLayoutSignoffCorpusCoverageHelpText: String {
        """
        Usage:
          xcircuite-flow audit-generated-layout-signoff-corpus-coverage --project-root <path> --report <path> --policy <path> [--persist] [--pretty]

        Loads a generated-layout signoff corpus report and an explicit coverage audit policy, then returns missing coverage tags, source artifact formats, signoff artifacts, stage families, and ready-oracle evidence requirements. With --persist, the policy and audit are written under .xcircuite/qualification/generated-layout-signoff/<suite-id>/.
        """
    }

    public static var assessGeneratedLayoutSignoffPromotionHelpText: String {
        """
        Usage:
          xcircuite-flow assess-generated-layout-signoff-promotion --project-root <path> --qualification <path> [--retained-signoff-report <path>] [--promotion-id <id>] [--persist] [--pretty]

        Loads a generated-layout corpus qualification result and an optional retained signoff report, then emits a promotion assessment that separates local generated-layout corpus qualification, case-level oracle readiness, retained DRC/LVS/PEX external-oracle infrastructure readiness, production blockers, and suggested next actions. With --persist, the assessment is written under .xcircuite/qualification/generated-layout-signoff/<suite-id>/promotion-assessment.json.
        """
    }

    public static var collectGeneratedLayoutFailureLadderHelpText: String {
        """
        Usage:
          xcircuite-flow collect-generated-layout-failure-ladder --project-root <path> --run-id <id> [--ladder-id <id>] [--persist] [--pretty]

        Loads a generated-layout signoff run, finds the first failed, blocked, incomplete, or integrity-failed ladder node, and returns typed diagnostics, source artifact refs, affected downstream stages, retry evidence, and suggested candidate actions for Agent and human review. With --persist, the report is written under .xcircuite/runs/<run-id>/reports/generated-layout-failure-ladder-<ladder-id>.json and registered with <ladder-id> as its artifact ID.
        """
    }

    public static var auditGeneratedLayoutFailureLadderCoverageHelpText: String {
        """
        Usage:
          xcircuite-flow audit-generated-layout-failure-ladder-coverage --project-root <path> --policy <path> --report <path> [--report <path> ...] [--persist] [--pretty]

        Loads one or more generated-layout failure ladder reports plus an explicit coverage audit policy, then returns missing first-failing families, suggested actions, evidence artifacts, and diagnostic-code coverage. With --persist, the policy and audit are written under .xcircuite/qualification/generated-layout-failure-ladder/<audit-id>/.
        """
    }

    public static var validatePlanningProblemHelpText: String {
        """
        Usage:
          xcircuite-flow validate-planning-problem --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]

        Loads planning/problem.json and planning/action-domain-snapshot.json, validates the translated planning problem before plan generation, and writes planning/problem-validation.json.
        """
    }

    public static var auditProblemTranslationHelpText: String {
        """
        Usage:
          xcircuite-flow audit-problem-translation --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--pretty]

        Loads planning/problem.json, resolves the run action-domain snapshot, audits source diagnostic and human-intent clause coverage across objectives, constraints, goal atoms, candidate actions, verification gates, and candidate-produced goal effects, then writes planning/problem-translation-audit.json.
        """
    }

    public static var generateCandidatePlanHelpText: String {
        """
        Usage:
          xcircuite-flow generate-candidate-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name>] [--calibration-policy <disabled|cp7-feedback>] [--pretty]

        Loads planning/problem.json plus optional rejected-plan and CP7 calibration artifacts, then writes planning/candidate-plan.json and planning/symbolic-planner-trace.json for planner, executor, and review consumption. With --calibration-policy cp7-feedback, CP7 artifacts in the request or run manifest select a calibrated symbolic strategy and are recorded in the policy trace.
        """
    }

    public static var runSymbolicPlannerFamilyHelpText: String {
        """
        Usage:
          xcircuite-flow run-symbolic-planner-family --project-root <path> --run-id <id> [--family-run-id <id>] [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name> ...] [--calibration-policy <disabled|cp7-feedback>] [--selection-policy prefer-ready-then-goal-coverage-then-score] [--pretty]

        Runs multiple symbolic candidate-plan strategies over the same planning problem and evidence, writes per-strategy candidate plan and trace artifacts under planning/symbolic-planner/family/<family-run-id>/, writes a family-run summary artifact, and promotes the selected candidate to planning/candidate-plan.json plus planning/symbolic-planner-trace.json.
        """
    }

    public static var exportSymbolicPlannerProblemHelpText: String {
        """
        Usage:
          xcircuite-flow export-symbolic-planner-problem --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--action-domain-artifact-id <id>] [--action-domain-path <path>] [--pretty]

        Loads planning/problem.json and planning/action-domain-snapshot.json, then writes PDDL-compatible symbolic planner domain/problem files plus a mapping artifact for external solver integration.
        """
    }

    public static var runSymbolicPlannerSolverHelpText: String {
        """
        Usage:
          xcircuite-flow run-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--arg <value> ...] [--timeout-seconds <seconds>] [--domain-artifact-id <id>] [--domain-path <path>] [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--working-directory-path <path>] [--solver-plan-output-path <path>] [--no-import] [--pretty]

        Runs an external PDDL-compatible symbolic planner with timeout and process-tree cleanup, writes solver stdout/stderr/run-report artifacts, preserves the solver plan, and imports it into planning/candidate-plan.json unless --no-import is set.
        Supported argument placeholders: {domain}, {problem}, {solverPlan}.
        """
    }

    public static var qualifySymbolicPlannerSolverHelpText: String {
        """
        Usage:
          xcircuite-flow qualify-symbolic-planner-solver --project-root <path> --run-id <id> --executable-path <path> [--tool-id <id>] [--arg <value> ...] [--timeout-seconds <seconds>] [--expected-action-id <id> ...] [--allow-missing-goal-coverage] [--require-optimality] [--max-solver-cost <number>] [--require-native-certificate] [--certificate-artifact-id <id>] [--certificate-path <path>] [--certificate-format <auto|generic-json|generic-text|fast-downward-text|metric-ff-text|optic-text|madagascar-text>] [--require-proof-validation] [--proof-artifact-id <id>] [--proof-path <path>] [--proof-checker-executable-path <path>] [--proof-checker-arg <value> ...] [--proof-checker-timeout-seconds <seconds>] [--proof-checker-working-directory-path <path>] [--policy-id <id>] [--domain-artifact-id <id>] [--domain-path <path>] [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--working-directory-path <path>] [--solver-plan-output-path <path>] [--pretty]

        Runs an external symbolic planner on the run's PDDL artifacts, imports the solver plan, verifies goal coverage, optionally parses a native solver certificate from an explicit certificate artifact/path or the solver stdout artifact, validates a solver proof artifact with an external checker, writes planning/symbolic-planner/solver-certificate.json plus solver-qualification.json, and returns a ToolHealthCheckResult-compatible qualification result.
        """
    }

    public static var discoverInstalledSymbolicPlannerSolversHelpText: String {
        """
        Usage:
          xcircuite-flow discover-installed-symbolic-planner-solvers --project-root <path> --run-id <id> [--lane-id <id>] [--search-path <path> ...] [--selection-policy <id>] [--promote-selected-plan] [--allow-unqualified-promotion] [--skip-promotion-verification] [--batch-spec-output-path <path>] [--pretty]

        Discovers installed symbolic planner binaries for known solver families, writes planning/symbolic-planner/installed-solver-lane.json, and returns a batch request containing only available candidates so Agent/CI can run solver-family qualification when binaries are present.
        """
    }

    public static var runSymbolicPlannerSolverFamilyHelpText: String {
        """
        Usage:
          xcircuite-flow run-symbolic-planner-solver-family --project-root <path> --spec <path> [--comparison-id <id>] [--no-promote] [--allow-unqualified-promotion] [--skip-promotion-verification] [--pretty]

        Loads a solver-family batch spec, qualifies each external symbolic planner, snapshots candidate certificates under planning/symbolic-planner/solver-family/<comparison-id>/candidates/<candidate-id>/, compares the resulting certificates, optionally promotes the selected plan, writes solver-family-batch.json, and returns all comparison/promotion artifacts.
        """
    }

    public static var compareSymbolicPlannerSolverFamilyHelpText: String {
        """
        Usage:
          xcircuite-flow compare-symbolic-planner-solver-family --project-root <path> --run-id <id> [--comparison-id <id>] [--qualification-artifact-id <id> ...] [--qualification-path <path> ...] [--selection-policy <id>] [--pretty]

        Compares existing symbolic planner solver qualification certificates, scores correctness and trust evidence, writes planning/symbolic-planner/solver-family/<comparison-id>/solver-family-comparison.json, and returns the selected certificate with score components.
        """
    }

    public static var promoteSymbolicPlannerSolverFamilySelectionHelpText: String {
        """
        Usage:
          xcircuite-flow promote-symbolic-planner-solver-family-selection --project-root <path> --run-id <id> [--comparison-id <id>] [--comparison-artifact-id <id>] [--comparison-path <path>] [--candidate-index <n>] [--allow-unqualified] [--skip-verification] [--pretty]

        Promotes the selected solver-family qualification certificate into canonical planning/candidate-plan.json, optionally re-promotes replay evidence, verifies the promoted candidate plan, writes planning/symbolic-planner/solver-family/<comparison-id>/solver-family-promotion.json, and returns the promotion artifact.
        """
    }

    public static var qualifySymbolicPlannerSolverCorpusHelpText: String {
        """
        Usage:
          xcircuite-flow qualify-symbolic-planner-solver-corpus --project-root <path> --suite-spec <path> [--pretty]
          xcircuite-flow qualify-symbolic-planner-solver-corpus --project-root <path> --suite-id <id> --executable-path <path> [--tool-id <id>] [--arg <value> ...] [--timeout-seconds <seconds>] [--policy-id <id>] [--required-coverage-tag <tag> ...] [--case-coverage <case-id:tag[,tag]> ...] [--allow-missing-goal-coverage] [--require-optimality] [--max-solver-cost <number>] [--require-proof-validation] [--proof-checker-executable-path <path>] [--proof-checker-arg <value> ...] [--proof-checker-timeout-seconds <seconds>] [--proof-checker-working-directory-path <path>] [--case-proof <case-id:path> ...] --case <run-id:expected-action-ids> [--case <run-id:expected-action-ids> ...] [--pretty]

        Runs symbolic planner qualification across multiple prepared run cases, writes per-run solver qualification artifacts, writes .xcircuite/qualification/symbolic-planner/<suite-id>/solver-qualification-corpus-suite.json and solver-qualification-corpus.json, checks required coverage tags against qualified cases, and returns aggregate ToolHealthCheckResult-compatible corpus evidence.
        """
    }

    public static var symbolicPlannerFeatureMatrixHelpText: String {
        """
        Usage:
          xcircuite-flow symbolic-planner-feature-matrix [--pretty]

        Emits the symbolic planner feature matrix with implemented and planned coverage tags, required corpus trust tags, current evidence, and remaining work.
        """
    }

    public static var importSymbolicPlannerPlanHelpText: String {
        """
        Usage:
          xcircuite-flow import-symbolic-planner-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--pddl-export-artifact-id <id>] [--pddl-export-path <path>] [--solver-plan-artifact-id <id>] [--solver-plan-path <path>] [--pretty]

        Loads a PDDL-compatible solver plan and planning/symbolic-planner/pddl-export.json, maps PDDL action names back to typed candidate actions, writes planning/symbolic-planner/solver-plan.txt, and writes planning/candidate-plan.json for normal verification.
        """
    }

    public static var generateParameterCandidatesHelpText: String {
        """
        Usage:
          xcircuite-flow generate-parameter-candidates --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--previous-parameter-candidates-artifact-id <id>] [--previous-parameter-candidates-path <path>] [--metric-threshold-profile-artifact-id <id>] [--metric-threshold-profile-path <path>] [--cost-calibration-artifact-id <id>] [--cost-calibration-path <path>] [--pareto-candidates-artifact-id <id>] [--pareto-candidates-path <path>] [--strategy <name>] [--max-candidates <count>] [--pretty]

        Loads planning/problem.json and writes planning/parameter-candidates.jsonl plus planning/parameter-candidate-search-trace.json with bounded numeric candidates, search provenance, adaptive-bounded-refinement ordering, feedback-aware-bounded-refinement learning from rejected plan history, and calibrated-feedback-aware-bounded-refinement ranking from CP7 threshold/cost/Pareto artifacts when available.
        """
    }

    public static var synthesizeParameterCandidatePlanHelpText: String {
        """
        Usage:
          xcircuite-flow synthesize-parameter-candidate-plan --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--parameter-candidates-artifact-id <id>] [--parameter-candidates-path <path>] [--rejected-plans-artifact-id <id>] [--rejected-plans-path <path>] [--candidate-id <id>] [--rank <n>] [--strategy <name>] [--include-rejected-candidates] [--pretty]

        Loads planning/problem.json and planning/parameter-candidates.jsonl, selects a bounded parameter candidate, applies costModel feedback weighting terms, avoids rejected candidates recorded in planning/rejected-plans.jsonl unless explicitly included, and writes planning/candidate-plan.json plus planning/parameter-candidate-selection-trace.json.
        """
    }

    public static var verifyCandidatePlanHelpText: String {
        """
        Usage:
          xcircuite-flow verify-candidate-plan --project-root <path> --run-id <id> [--candidate-plan-artifact-id <id>] [--candidate-plan-path <path>] [--mode <name>] [--pretty]

        Loads planning/candidate-plan.json and writes planning/plan-verification.json with symbolic state, gate results, riskReviews, diagnostics, next actions, and an actions.jsonl record. Approval-required risks synthesize an approval-gate before acceptance. With --mode post-execution, reads planning/plan-execution.json and runs native DRC, native LVS, PEX summary, and simulation metric gates when their inputs are present.
        """
    }

    public static var approveCandidatePlanRiskHelpText: String {
        """
        Usage:
          xcircuite-flow approve-candidate-plan-risk --project-root <path> --run-id <id> --approval-id <id> --reviewer <name> [--reviewer-kind agent|human|cli|system] [--decision approved|rejected] [--note <text>] [--pretty]

        Writes .xcircuite/runs/<run-id>/approvals/<approval-id>.json using the shared XcircuiteApprovalRecord schema. The next verify-candidate-plan or execute-candidate-plan call reads the approval and updates riskReviews or pre-execution mutation policy.
        """
    }

    public static var executeCandidatePlanHelpText: String {
        """
        Usage:
          xcircuite-flow execute-candidate-plan --project-root <path> --run-id <id> [--candidate-plan-artifact-id <id>] [--candidate-plan-path <path>] [--actor <id>] [--pretty]

        Loads planning/candidate-plan.json, blocks approval-required risks before design mutation, executes supported design-mutating steps, and writes planning/plan-execution.json, design-diff.json, produced artifacts, and an actions.jsonl record.
        """
    }

    public static var runNumericRepairLoopHelpText: String {
        """
        Usage:
          xcircuite-flow run-numeric-repair-loop --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--initial-candidate-strategy <name>] [--feedback-candidate-strategy <name>] [--max-candidates <count>] [--max-iterations <count>] [--synthesis-strategy <name>] [--mode <name>] [--actor <id>] [--calibration-policy <disabled|cp7-feedback>] [--pretty]

        Runs bounded numeric candidate generation, parameter-candidate plan synthesis, execution, and post-execution verification until a candidate is accepted, no eligible candidate remains, or max iterations is reached. With --calibration-policy cp7-feedback, each retry materializes CP7 threshold, cost calibration, Pareto, and improvement-loop artifacts from prior iterations before selecting the next candidate strategy. Writes planning/numeric-repair-loop.json and per-iteration snapshots under planning/numeric-repair-loop/iterations/.
        """
    }

    public static var generateImprovementArtifactsHelpText: String {
        """
        Usage:
          xcircuite-flow generate-improvement-artifacts --project-root <path> --run-id <id> [--problem-artifact-id <id>] [--problem-path <path>] [--numeric-repair-loop-artifact-id <id>] [--numeric-repair-loop-path <path>] [--generated-at <timestamp>] [--pretty]

        Loads planning/numeric-repair-loop.json and the planning problem when available, then writes CP7 metric threshold, cost calibration, Pareto candidate, and improvement-loop artifacts into the run manifest.
        """
    }

    public static var qualifyVerifiedImprovementCorpusHelpText: String {
        """
        Usage:
          xcircuite-flow qualify-verified-improvement-corpus --project-root <path> --suite-spec <path> [--persist] [--pretty]

        Loads a verified improvement corpus suite, checks DRC/LVS/PEX/numeric loop outcomes against expected status, accepted/rejected results, diagnostics, failed gates, design diffs, and plan verification artifacts. With --persist, writes corpus-suite.json and corpus-report.json under .xcircuite/qualification/verified-improvement/<suite-id>/.
        """
    }

    public static var runSelectedSuggestedCommandHelpText: String {
        """
        Usage:
          xcircuite-flow run-selected-suggested-command --project-root <path> --run-id <id> [--command-id <id>]

        Loads the latest ready review.selectSuggestedCommand action from actions.jsonl, verifies that it targets this project/run and an allowlisted xcircuite-flow planning command, then dispatches it through the typed CLI handler.
        """
    }
}
