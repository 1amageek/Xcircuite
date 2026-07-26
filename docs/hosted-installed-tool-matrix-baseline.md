# Hosted Installed-Tool Matrix Baseline

Updated: 2026-07-26

## Purpose

This record preserves the first execution-derived acquisition failure
inventory for `sky130A-open-reference-v1`. Each failure was retained by the
fail-closed publication gate and fixed at the layer that owned the broken
contract.

## Failure inventory

| Run | Host revision | Classification | Retained root cause | Corrective commit |
|---|---|---|---|---|
| [30197582213](https://github.com/1amageek/Xcircuite/actions/runs/30197582213) | `86fee28535a70c3e363dad488ca3d8f5824e984d` | Tool build | Headless Magic selected bundled readline 4.3, which does not compile with the runner's Clang. | `5c000abd5af1fb2acca1209932b3363fcebef931` |
| [30197819312](https://github.com/1amageek/Xcircuite/actions/runs/30197819312) | `5c000abd5af1fb2acca1209932b3363fcebef931` | Dependency discovery | OpenSTA had no CUDD library and no valid Flex include root. | `153c3153130e67d41b675e67c65de4b424d0dc1b` |
| [30198051840](https://github.com/1amageek/Xcircuite/actions/runs/30198051840) | `153c3153130e67d41b675e67c65de4b424d0dc1b` | Acquisition | The hosted Homebrew inventory had no trusted `cudd` formula. | `e987e561b438318e5c36fc5589709b1be49ce17c` |
| [30198213181](https://github.com/1amageek/Xcircuite/actions/runs/30198213181) | `e987e561b438318e5c36fc5589709b1be49ce17c` | Tool build | OpenSTA used the system Flex generator with a different Homebrew `FlexLexer.h`. | `585632a94fb27aff01c3a4d05f1e5d079cd4f5e3` |
| [30198431982](https://github.com/1amageek/Xcircuite/actions/runs/30198431982) | `585632a94fb27aff01c3a4d05f1e5d079cd4f5e3` | Tool configuration | Headless OpenROAD configuration still discovered a broken Qt5 GUI installation. | `9b6d2a15dbaa2a7237d3496206e2e87c6fa86bd5` |

## Invariants confirmed

- Every acquisition failure uploaded a typed blocked record and raw build log.
- No package lane ran after an unqualified acquisition.
- The publication job treated all missing lane evidence as blocked.
- Magic, Netgen, CUDD, and OpenSTA now advance through installation before the
  OpenROAD configuration boundary.
- CUDD is source-built from a full revision and its installed bytes are part of
  the realization identity.
- The checked-in corpus and profile identity are independent from volatile
  timestamps and temporary paths.

## Active continuation

Run
[30198691272](https://github.com/1amageek/Xcircuite/actions/runs/30198691272)
contains the headless OpenROAD configuration, exact Xcode host binding, stable
profile identity, and stable realization identity. Its result must be appended
here before M0 closes.
