# Engine Package Integration

Electrical signoff integration uses the following canonical path:

```text
LEF + DEF/GDSII/OASIS + SPEF/ParasiticIR
              ↓
standard-layout import / verified source loading
              ↓
ElectricalSignoffRunResult (all corners and axes)
              ↓
qualification + independent-oracle evidence
              ↓
release gate + ElectricalSignoffReleaseArtifactBundle
              ↓
human review / approval / resume
```

The release bundle is persisted under `.xcircuite/runs/<run-id>/electrical-signoff/release-artifact-bundle.json` and every referenced file must carry a verified SHA-256 digest and byte count. GDSII/OASIS geometry without explicit routed electrical connectivity remains blocked.

## Role of Xcircuite

Xcircuite is the central composition layer for semiconductor design execution. Domain packages own algorithms, typed requests, typed payloads and domain artifacts. Xcircuite owns stage construction, artifact resolution, tool qualification policy, persistence, repair-loop coordination, approval and resume.

```text
Domain package protocol
        ↓
XcircuiteEngineStageAdapting
        ↓
DesignFlowKernel.FlowStageExecutor
        ↓
.xcircuite run ledger and review artifacts
```

## Dependency rule

- Xcircuite depends on every domain package.
- Domain packages depend on Xcircuite workspace contracts where needed.
- Domain packages never depend on Xcircuite or circuit-studio.
- circuit-studio depends on Xcircuite and presents the retained artifacts.

## Adapter responsibilities

Each adapter must resolve and verify inputs, evaluate ToolQualification requirements, invoke one injected domain protocol, persist returned artifacts, map diagnostics into FlowStageResult and bind the result to design, PDK and tool digests.

The PDK standard-view and rule-deck adapters additionally expose an explicit
external-process path. `PDKExternalInspectionProcessConfiguration` is carried
in the agent-facing runtime spec, `TimedPDKExternalInspectionProcessRunner`
uses `SignoffToolSupport` for timeout and cancellation-aware execution, and the
provider persists request/result/stdout/stderr/execution artifacts under the
run stage before `PDKKit` validates the returned envelope. This boundary is
process execution and evidence retention, not tool qualification: the
`ToolQualification` descriptor and any independent process evidence remain a
separate trust gate.

## Stage registration

XcircuiteEnginePackageCatalog is the canonical scaffold catalog for package, product, stage and artifact-role ownership. Implementation agents must update the catalog and integration tests when adding or changing a stage.

RTLVerificationEngine is registered as `rtl.lint`, `rtl.cdc`, `rtl.rdc` and `rtl.equivalence`. `RTLVerificationFlowStageExecutor` resolves digest-bearing RTL, reference and optional SDC inputs, carries frontend/policy/proof-view/assumption state into the request, invokes the native or injected protocol, persists the envelope and a separate qualification artifact under the run stage, and maps blocked/failed/completed status to the flow gate. ToolQualification selection remains a separate gate from execution status.

ElectricalSignoffEngine is registered for standard-layout import, electrical
analysis, corpus observation, and repair-revision stages.
`ElectricalStandardLayoutImportFlowStageExecutor` converts verified standard
inputs into a canonical physical snapshot. `ElectricalSignoffFlowStageExecutor`
persists the canonical run result and Foundation evidence. Corpus execution
persists raw measurements and independent-oracle observations for
ToolQualification. `ElectricalSignoffRepairRevisionFlowStageExecutor` applies a
provenance-checked repair candidate to a new revision. DesignFlowKernel owns
approval and resume; ReleaseEngine owns release authorization.

PhysicalDesignEngine also exposes `PhysicalDesignReviewFlowStageExecutor` as
the Xcircuite human-review boundary. It persists the native immutable review
packet under the run stage, lets `DesignFlowKernel` record the approval, and
re-validates the packet manifest and referenced artifact digests before the same
run resumes through `PhysicalDesignReviewGate`. This retained boundary proves
review/approval/resume integrity; it remains separate from DRC/LVS/PEX, timing,
external-oracle correlation, and process qualification.

## Completion rule

A package implementation is not platform-complete until Xcircuite can execute it headlessly, persist its artifacts, expose structured failure reasons, resume after approval or repair, and include the result in the appropriate signoff profile.

The latest complete Xcircuite regression passed 557 test cases in 59 suites.
This is package-integration evidence for these adapters, not foundry or process
qualification. The regression used an isolated SwiftPM scratch path and a
bounded parallel runner; a serial rerun remains a developer reproducibility
option when shared-worktree processes are active.
