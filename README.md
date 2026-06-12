# Xcircuite

`.xcircuite` project runtime: the adapter layer between `DesignFlowKernel` and the
engine packages. It turns engine results into `FlowStageResult`s, gates, and
artifact references — and implements **no** verdict logic, parsers, or external
tool invocation itself (those stay in `CoreSpice` / `DRCEngine` / `LVSEngine` /
`PEXEngine`).

## Stage executors

| Type | Responsibility |
|---|---|
| `DRCFlowStageExecutor` | Runs DRC through `DRCEngine`, converts the result to stage result / gates / artifacts |
| `LVSFlowStageExecutor` | Runs LVS through `LVSEngine`, same conversion |
| `PEXFlowStageExecutor` | Runs PEX through `PEXEngine`, indexes extraction artifacts as `XcircuiteFileReference`s |
| `SimulationFlowStageExecutor` | Runs SPICE simulation, persists waveform/measurement artifacts, gates on measurement expectations |

## Engine seams

| Protocol | Implementation |
|---|---|
| `DRCExecuting` / `LVSExecuting` / `PEXExecuting` | Engine swapped in from the adapter side |
| `SimulationExecuting` | `CoreSpiceSimulationEngine` — runs CoreSpice in-process, executes the netlist's own `.op` / `.tran`, evaluates `.measure` results. Unsupported analyses (`.ac` / `.dc`) throw typed errors; nothing is silently skipped |

The simulation gate compares declared `SimulationMeasurementExpectation`s
(name / target / tolerance) against the netlist's `.measure` results; a missing
expected measurement is a failure (`SIMULATION_MEASUREMENT_MISSING`), not a pass.

## Support types

| Type | Responsibility |
|---|---|
| `SignoffToolDescriptors` | Qualification descriptors for the pure Swift DRC/LVS backends, CoreSpice simulation, and PEX backends |
| `StageArtifactReferenceBuilder` | Builds `XcircuiteFileReference`s for stage outputs (path, kind, format, digest) |
| `XcircuiteRuntimeError` | Typed runtime failures |

## Build & test

```bash
swift build
swift test
```
