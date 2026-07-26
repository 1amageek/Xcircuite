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
| [30198691272](https://github.com/1amageek/Xcircuite/actions/runs/30198691272) | `9b6d2a15dbaa2a7237d3496206e2e87c6fa86bd5` | Dependency discovery | OpenROAD's embedded OpenSTA scope did not inherit qualified Tcl, Flex, and CUDD paths. | `d60f4214acf7d0466088d66e73330ed73bf86fe0` |
| [30198936671](https://github.com/1amageek/Xcircuite/actions/runs/30198936671) | `d60f4214acf7d0466088d66e73330ed73bf86fe0` | Build-system generation | CUDD's generated Autotools files retained an obsolete `aclocal-1.14` dependency and were rebuilt based on clone-time timestamp ordering. | `90decdb1b8b2323055924c2ddbdb854b511e4e0f` |
| [30199139111](https://github.com/1amageek/Xcircuite/actions/runs/30199139111) | `db5382f5d924ea34345f3804713f8e55ac95dd86` | Dependency version drift | OpenROAD's pinned slang revision discovered hosted fmt 12.2, whose `fmt/core.h` no longer exposed the API expected by that source. | `f44efb40b74f5084d73010a84c78992c72851a34` |
| [30199805781](https://github.com/1amageek/Xcircuite/actions/runs/30199805781) | `6fc16f0231e7afa73464c2b2bf266218e184ee02` | Tool build compatibility | Netgen omitted its existing `VerilogTop` declaration under C99-or-later compilation, while Homebrew Boost.Stacktrace required explicit Darwin `_Unwind_Backtrace` capability for OpenROAD. | `942d2828d16aa16e4014c94aebfc0e8ea64ea31f` |
| [30200668102](https://github.com/1amageek/Xcircuite/actions/runs/30200668102) | `ebc19a812340731d61ed81dd3aa29846886f79b8` | Dependency API compatibility | Netgen completed installation and OpenROAD reached 70%, but the pinned fmt 12.1 compatibility header no longer re-exported `fmt::format` required by OpenROAD's pinned slang source. | `b99a5807e21e2cbbbf844516f4301b3b2b560b03` |

## Invariants confirmed

- Every acquisition failure uploaded a typed blocked record and raw build log.
- No package lane ran after an unqualified acquisition.
- The publication job treated all missing lane evidence as blocked.
- Magic, Netgen, CUDD, fmt, and OpenSTA now advance through installation;
  OpenROAD reached 70% source compilation on the Xcode 26 runner.
- CUDD is source-built from a full revision and its installed bytes are part of
  the realization identity.
- The checked-in corpus and profile identity are independent from volatile
  timestamps and temporary paths.

## Active continuation

The next dispatched run must prove fmt 11.2 compatibility with pinned slang and
complete the remaining OpenROAD build before the package lanes can execute and
M0 can close.
