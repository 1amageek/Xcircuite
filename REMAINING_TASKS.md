# Xcircuite Remaining Tasks

Updated: 2026-07-26

Xcircuite has broad headless runtime, ledger, stage-executor, planning,
qualification-handoff, review, resume, and release composition. Remaining work
is concentrated in current evidence and real-tool breadth rather than adding an
`AgentHarness` facade.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| XCI-4 | P2 | Xcircuite planning | Broaden symbolic-planner cost, replay, proof, installed-solver, DRC/LVS/PEX, and repair-formulation corpora. | The `XcircuiteSymbolicPlannerFeatureMatrixProvider.remainingWork` entries are closed by retained real solver/process cases, independent validation, calibrated costs, proof checking where available, and expanded process-family repair coverage. |

## Responsibility boundary

Xcircuite owns composition, concrete `.xcircuite` persistence, action/plan
artifacts, review/resume plumbing, and policy integration. Domain algorithms
and verdict semantics stay in their engine packages; tool trust stays in
ToolQualification; human interaction stays in circuit-studio.

XCI-2 and XCI-3 require an installed production tool matrix, exact PDK views,
independent oracle evidence, and release authorization. These inputs are not
bundled in this repository and must not be replaced with native or synthetic
success.

| Former ID | Owner | Required evidence |
|---|---|---|
| XCI-2 | Hosted installed-tool workflow | Exact tool/PDK acquisition evidence and passing production lanes for logic, RTL verification, DFT, DRC, LVS, PEX, physical design, timing, electrical signoff, Xcircuite composition, and ReleaseEngine authorization under one pinned toolchain. |
| XCI-3 | Production process workflow | Real PDK-backed repair-loop fixtures in which DRC/LVS/PEX/timing/electrical diagnostics drive auditable mutations, gate re-runs, rejected feedback, approval/resume, and independent production trust. |

## Completed P1

| ID | Completion evidence |
|---|---|
| XCI-1 | `ci-artifacts/platform-capability/current-platform-capability-readiness.json` was produced by the in-process test runner from 15 bounded Xcode test lanes. All 15 retained execution records, transcripts, digests, provenance records and non-serializable runner receipts validated. Agent-operable, standard-format and post-layout milestones passed; the other milestones identify only the external `production-qualified-release-flow` requirement. |

## Evidence reviewed

- `README.md`
- `ENGINE_PACKAGE_INTEGRATION.md`
- `docs/flow-runtime-schema.md`
- `docs/hosted-installed-tool-matrix.md`
- `Sources/Xcircuite/XcircuitePlatformCapabilityReadinessAssessor.swift`
- `Sources/Xcircuite/XcircuiteSymbolicPlannerFeatureMatrixProvider.swift`
- Hosted installed-tool GitHub workflow
- Ledger, stage executor, planning, approval, resume, and release paths
- `Sources` incomplete-implementation marker scan
