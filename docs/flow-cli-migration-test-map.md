# Flow CLI Migration Test Map

Flow lifecycle services remain in `DesignFlowKernel`. The executable command surface and its integration tests are owned by `Xcircuite`, because `.xcircuite` persistence is a concrete workspace-runtime responsibility.

| Command | Kernel scenario retained | Xcircuite integration test destination | Status |
|---|---|---|---|
| `inspect-run` | Ledger summary, diagnostics, stage attempts, toolchain projection | `XcircuiteFlowLifecycleCLITests` | Baseline integration covered |
| `review-run` | Review bundle, actionable review items, artifact integrity | `XcircuiteFlowLifecycleCLITests` | Baseline integration covered |
| `build-stage-artifact-ladder` | Persisted ladder and suggested review command | `XcircuiteFlowLifecycleCLITests` | Baseline integration covered |
| `summarize-loop` | Agent-loop snapshot generation and persistence | `XcircuiteFlowLifecycleCLITests` | Baseline integration covered |
| `evaluate-run-guard` | Guard verdict generation and persistence | `XcircuiteAgentLoopCLITests` | Moved |
| `compare-artifacts` | Cross-artifact evaluation and persistence | `XcircuiteAgentLoopCLITests` | Moved |
| `build-decision-packet` | Packet creation and canonical artifact registration | `XcircuiteFlowLifecycleCLITests` | Baseline integration covered |
| `validate-decision-packet` | Accepted, blocked, and tampered evidence | `XcircuiteFlowLifecycleCLITests` | Baseline integrity integration covered |
| `build-release-envelope` | Accepted and blocked release gate | `XcircuiteFlowLifecycleCLITests` | Blocked release integration covered |
| `collect-release-evidence` | Dashboard and contract evidence collection | `XcircuiteFlowLifecycleCLITests` | Passing integration covered |
| `build-retention-index` | Index construction, persistence, artifact registration | `XcircuiteFlowLifecycleCLITests` | Passing integration covered |
| `validate-retention-index` | Digest, retention, and evidence-age validation | `XcircuiteFlowLifecycleCLITests` | Passing integration covered |
| `progress-run` | Snapshot, wait, JSONL follow, completion stop | `XcircuiteFlowLifecycleCLITests` | Cancellation snapshot integration covered |
| `approve-gate` | Approval, waiver reason, stale evidence rejection | `XcircuiteFlowLifecycleCLITests` | Approved evidence binding covered |
| `request-cancel` | Cancellation artifact and progress event | `XcircuiteFlowLifecycleCLITests` | Integration covered |

The migration is complete only when every row is implemented in `Xcircuite`, its former `DesignFlowKernel` CLI scenario has an equivalent integration test, and no `DesignFlowCLICommand` reference remains in kernel tests.
