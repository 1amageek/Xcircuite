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
| [30202503357](https://github.com/1amageek/Xcircuite/actions/runs/30202503357) | `5dd888a6785015dfd6a6f3476d84eaeab3cefd7b` | Dependency selection and API compatibility | Slang required fmt 12.1 or newer, rejected the pinned 11.2 CMake package, and selected an unpinned Homebrew fmt 12.2 whose lightweight `core.h` no longer declares `fmt::format`. | `844c6ea81b38ceee3897b7d4af8d49b1d878fb3f` |
| [30203381430](https://github.com/1amageek/Xcircuite/actions/runs/30203381430) | `bc1564959f79ee27f4d4ea7839b7647656339c09` | Undeclared binding surface | OpenROAD built the unused Python/SWIG bindings, whose hosted Python 3.14 link introduced an undeclared `zstd` dependency and failed at 77%. | `2d64d9589beab581c56c5f858396083caa846a75` |
| [30205109019](https://github.com/1amageek/Xcircuite/actions/runs/30205109019) | `88067bc63ceecf667cac4622f5ceed49eec107f3` | Dependency discovery | With Python disabled, OpenROAD reached 85%, but the OpenDB Tcl `odbtcl` target still linked `zstd` without a declared keg or CMake prefix. | `c39a9d436b2c48311981a9db6900f674f1d698eb` |
| [30208241165](https://github.com/1amageek/Xcircuite/actions/runs/30208241165) | `dadd24a885fee72209861ba9773b3bb8d1c790d6` | Linker search contract | The `zstd` keg was installed and discoverable by CMake, but Boost exported a raw `-lzstd` dependency and the OpenDB Tcl executable had no `-L/opt/homebrew/opt/zstd/lib` linker search path. | `e761e489f15603a6ffe13a2e94770d66e25d46ab` |
| [30210071256](https://github.com/1amageek/Xcircuite/actions/runs/30210071256) | `e4198ef0057c8ab09346433c0b20db591cc296cc` | Linker search contract | The explicit zstd search path allowed OpenROAD to reach the same OpenDB Tcl link at 85%, where Boost then exposed a second raw `-licudata` dependency without the keg-only ICU search path. | `51f400cfe2879d621a7550ed3cbf1db73c24d82f` |

## Invariants confirmed

- Every acquisition failure uploaded a typed blocked record and raw build log.
- No package lane ran after an unqualified acquisition.
- The publication job treated all missing lane evidence as blocked.
- Magic, Netgen, CUDD, fmt, and OpenSTA now advance through installation;
  OpenROAD reaches 85%. The declared headless realization excludes unused GUI,
  Python, and upstream-test surfaces, while its consumed Tcl surface retains
  explicit zstd and ICU build dependencies and linker search paths.
- CUDD is source-built from a full revision and its installed bytes are part of
  the realization identity.
- The checked-in corpus and profile identity are independent from volatile
  timestamps and temporary paths.

## Active continuation

The next dispatched run must prove that the headless OpenROAD executable
completes with the explicit zstd and ICU kegs and linker search paths. The
reviewed package graph is also aligned to one remotely resolvable revision set.
If acquisition succeeds, all package lanes must execute from that single
archive. The added DFT lane then must retain real OpenROAD scan insertion,
Yosys equivalence, DFTEngine ATPG/STIL artifacts, and Icarus fault correlation
before M0 can close.
