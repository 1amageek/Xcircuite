#!/usr/bin/env python3
"""Regression tests for the hosted installed-tool matrix runner."""

from __future__ import annotations

import importlib.util
import math
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


RUNNER_PATH = Path(__file__).parents[1] / "hosted_installed_tool_matrix.py"
MODULE_SPEC = importlib.util.spec_from_file_location(
    "hosted_installed_tool_matrix",
    RUNNER_PATH,
)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"Unable to load matrix runner at {RUNNER_PATH}")
MATRIX = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(MATRIX)


class HostedInstalledToolMatrixBuildTests(unittest.TestCase):
    def test_checked_in_lock_pins_source_built_dependencies(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )

        MATRIX.validate_lock(lock)

        cudd = lock["buildDependencies"]["cudd"]
        self.assertRegex(cudd["revision"], r"^[0-9a-f]{40}$")
        self.assertEqual(
            set(cudd["artifacts"]),
            {
                "installed/include/cudd.h",
                "installed/lib/libcudd.a",
            },
        )
        fmt = lock["buildDependencies"]["fmt"]
        self.assertRegex(fmt["revision"], r"^[0-9a-f]{40}$")
        self.assertEqual(
            fmt["revision"],
            "1be298e1bd68957e4cd352e1f676f00e07dcfb57",
        )
        self.assertEqual(
            set(fmt["artifacts"]),
            {
                "installed/include/fmt/format.h",
                "installed/lib/libfmt.a",
            },
        )
        self.assertEqual(
            lock["tools"]["yosys"]["revision"],
            "b85cad634782fafac275e5f540c056bfacb2b5d2",
        )
        self.assertEqual(
            lock["tools"]["iverilog"]["revision"],
            "dfeee909ed9f20b4870dd93423156c0170c0e1ff",
        )
        self.assertEqual(
            lock["tools"]["verilator"]["revision"],
            "848d926ebd4addacacd294dc84e35d9d4ae8078c",
        )
        self.assertEqual(
            lock["tools"]["yosys"]["companions"][0]["name"],
            "yosys-abc",
        )
        self.assertEqual(
            lock["tools"]["iverilog"]["companions"][0]["name"],
            "vvp",
        )
        self.assertEqual(
            set(lock["lanes"]["logic"]["oracles"]),
            {"yosys-synthesis-equivalence", "iverilog-simulation"},
        )
        self.assertEqual(
            set(lock["lanes"]["rtl-verification"]["oracles"]),
            {"verilator-lint", "yosys-synthesis-equivalence"},
        )
        self.assertEqual(
            set(lock["lanes"]["dft"]["oracles"]),
            {
                "openroad-dft",
                "yosys-dft-equivalence",
                "iverilog-dft-replay",
            },
        )
        self.assertEqual(
            lock["lanes"]["dft"]["revision"],
            "5acd86d91b0827fceb02cab0931bcad546202dae",
        )
        self.assertEqual(
            MATRIX.process_verilog_definitions(
                {"process": lock["process"]}
            ),
            ["FUNCTIONAL=1", "UNIT_DELAY="],
        )

    def test_workflow_executes_every_locked_lane(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        workflow = (
            RUNNER_PATH.parents[2]
            / ".github"
            / "workflows"
            / "hosted-installed-tool-matrix.yml"
        ).read_text(encoding="utf-8")

        for lane_name in lock["lanes"]:
            self.assertIn(f"          - {lane_name}\n", workflow)

    def test_checked_in_corpus_materializes_exact_bytes(self) -> None:
        lock_path = (
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock = MATRIX.load_json(lock_path)

        with tempfile.TemporaryDirectory() as temporary_directory:
            destination = Path(temporary_directory)
            MATRIX.materialize_corpus(lock_path, lock, destination)

            manifest = MATRIX.load_json(destination / "corpus-manifest.json")
            for artifact in manifest["artifacts"]:
                identity = MATRIX.file_digest(destination / artifact["path"])
                self.assertEqual(identity["sha256"], artifact["sha256"])
                self.assertEqual(identity["byteCount"], artifact["byteCount"])

    def test_checked_in_dft_corpus_materializes_exact_bytes(self) -> None:
        lock_path = (
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock = MATRIX.load_json(lock_path)

        with tempfile.TemporaryDirectory() as temporary_directory:
            destination = Path(temporary_directory)
            MATRIX.materialize_corpus(
                lock_path,
                lock,
                destination,
                "dftCorpus",
            )

            manifest = MATRIX.load_json(destination / "corpus-manifest.json")
            self.assertEqual(
                manifest["profileID"],
                "sky130A-open-reference-dft-v1",
            )
            for artifact in manifest["artifacts"]:
                identity = MATRIX.file_digest(destination / artifact["path"])
                self.assertEqual(identity["sha256"], artifact["sha256"])
                self.assertEqual(identity["byteCount"], artifact["byteCount"])

    def test_dft_evidence_requires_openroad_netlist_lineage(self) -> None:
        lock_path = (
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock = MATRIX.load_json(lock_path)

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            corpus = root / "corpus"
            MATRIX.materialize_corpus(
                lock_path,
                lock,
                corpus,
                "dftCorpus",
            )
            identity = MATRIX.dft_probe_input_identity(corpus)
            files = root / "files"
            files.mkdir()

            def fixture(name: str, contents: str) -> Path:
                path = files / name
                path.write_text(contents, encoding="utf-8")
                return path

            technology_lef = fixture("technology.lef", "VERSION 5.8 ;\n")
            library_lef = fixture("library.lef", "MACRO scan_cell\nEND scan_cell\n")
            timing_library = fixture("timing.lib", "library(test) {}\n")
            cell_models = fixture("cells.v", "module scan_cell; endmodule\n")
            primitives = fixture("primitives.v", "module primitive; endmodule\n")
            transformed = fixture(
                "transformed.v",
                "module hosted_dft_probe; endmodule\n",
            )
            scan_def = fixture(
                "transformed.def",
                "SCANCHAINS 1 ;\nEND SCANCHAINS\n",
            )
            execution_log = fixture(
                "openroad.log",
                "HOSTED_OPENROAD_DFT_COMPLETE\n",
            )
            openroad_driver = fixture("openroad.tcl", "execute_dft_plan\n")
            yosys_driver = fixture("equivalence.ys", "equiv_status -assert\n")
            wrapper = fixture("wrapper.v", "module gate; endmodule\n")
            pattern = fixture("patterns.stil", "STIL 1.0;\n")
            implementation = fixture("implementation.json", "{}\n")
            universe = fixture("universe.json", "{}\n")
            compiler_descriptor = fixture("iverilog.json", "{}\n")
            simulator_descriptor = fixture("vvp.json", "{}\n")
            replay_result = fixture("replay.json", "{}\n")
            source = corpus / "source.v"

            evidence = {
                "designInputIdentity": identity,
                "process": {
                    "assets": [
                        MATRIX.artifact_input("technologyLEF", technology_lef),
                        MATRIX.artifact_input("libraryLEF", library_lef),
                        MATRIX.artifact_input(
                            "standardCellVerilog",
                            cell_models,
                        ),
                        MATRIX.artifact_input(
                            "standardCellVerilogPrimitives",
                            primitives,
                        ),
                    ],
                    "corners": [{
                        "assets": [
                            MATRIX.artifact_input(
                                "timingLibrary",
                                timing_library,
                            ),
                        ],
                    }],
                },
                "oracleInvocations": [
                    {
                        "oracle": "openroad-dft",
                        "consumedInputs": [
                            MATRIX.artifact_input("driver", openroad_driver),
                            MATRIX.artifact_input("sourceNetlist", source),
                            MATRIX.artifact_input(
                                "technologyLEF",
                                technology_lef,
                            ),
                            MATRIX.artifact_input("libraryLEF", library_lef),
                            MATRIX.artifact_input(
                                "timingLibrary",
                                timing_library,
                            ),
                        ],
                        "outputArtifacts": [
                            MATRIX.artifact_input(
                                "transformedNetlist",
                                transformed,
                            ),
                            MATRIX.artifact_input("scanDEF", scan_def),
                            MATRIX.artifact_input(
                                "executionEvidence",
                                execution_log,
                            ),
                        ],
                    },
                    {
                        "oracle": "yosys-dft-equivalence",
                        "consumedInputs": [
                            MATRIX.artifact_input("driver", yosys_driver),
                            MATRIX.artifact_input(
                                "functionalWrapper",
                                wrapper,
                            ),
                            MATRIX.artifact_input("sourceNetlist", source),
                            MATRIX.artifact_input(
                                "transformedNetlist",
                                transformed,
                            ),
                            MATRIX.artifact_input(
                                "standardCellVerilog",
                                cell_models,
                            ),
                            MATRIX.artifact_input(
                                "standardCellVerilogPrimitives",
                                primitives,
                            ),
                        ],
                    },
                    {
                        "oracle": "iverilog-dft-replay",
                        "consumedInputs": [
                            MATRIX.artifact_input("patternArtifact", pattern),
                            MATRIX.artifact_input(
                                "scanNetlistArtifact",
                                transformed,
                            ),
                            MATRIX.artifact_input(
                                "scanImplementationArtifact",
                                implementation,
                            ),
                            MATRIX.artifact_input(
                                "faultUniverseArtifact",
                                universe,
                            ),
                            MATRIX.artifact_input(
                                "standardCellVerilog",
                                cell_models,
                            ),
                            MATRIX.artifact_input(
                                "standardCellVerilogPrimitives",
                                primitives,
                            ),
                            MATRIX.artifact_input(
                                "compilerDescriptor",
                                compiler_descriptor,
                            ),
                            MATRIX.artifact_input(
                                "simulatorDescriptor",
                                simulator_descriptor,
                            ),
                        ],
                        "outputArtifact": MATRIX.artifact_input(
                            "replayResult",
                            replay_result,
                        ),
                        "pipelineInputs": [
                            MATRIX.artifact_input("sourceNetlist", source),
                            MATRIX.artifact_input(
                                "transformedNetlist",
                                transformed,
                            ),
                            MATRIX.artifact_input("scanDEF", scan_def),
                            MATRIX.artifact_input(
                                "scanCellLibrary",
                                corpus / "cell-library.json",
                            ),
                            MATRIX.artifact_input(
                                "executionEvidence",
                                execution_log,
                            ),
                            MATRIX.artifact_input(
                                "scanConstraints",
                                corpus / "constraints.sdc",
                            ),
                            MATRIX.artifact_input(
                                "pdkIdentity",
                                corpus / "pdk-identity.json",
                            ),
                            MATRIX.artifact_input(
                                "timingLibrary",
                                timing_library,
                            ),
                        ],
                        "correlation": {
                            "faultCount": 2,
                            "detectedFaultCount": 2,
                            "status": "matched",
                        },
                    },
                ],
            }

            MATRIX.validate_dft_consumed_input_contract(
                lock["lanes"]["dft"],
                evidence,
            )

            detached = fixture(
                "detached.v",
                "module hosted_dft_probe; wire changed; endmodule\n",
            )
            evidence["oracleInvocations"][2]["consumedInputs"][1] = (
                MATRIX.artifact_input("scanNetlistArtifact", detached)
            )
            with self.assertRaises(MATRIX.MatrixFailure) as failure:
                MATRIX.validate_dft_consumed_input_contract(
                    lock["lanes"]["dft"],
                    evidence,
                )

            self.assertEqual(
                failure.exception.code,
                "dft_transformed_netlist_lineage_mismatch",
            )

            evidence["oracleInvocations"][2]["consumedInputs"][1] = (
                MATRIX.artifact_input("scanNetlistArtifact", transformed)
            )
            evidence["oracleInvocations"][2]["pipelineInputs"][3] = (
                MATRIX.artifact_input("scanCellLibrary", implementation)
            )
            with self.assertRaises(MATRIX.MatrixFailure) as failure:
                MATRIX.validate_dft_consumed_input_contract(
                    lock["lanes"]["dft"],
                    evidence,
                )

            self.assertEqual(
                failure.exception.code,
                "dft_pipeline_input_lineage_mismatch",
            )

    def test_runner_environment_rejects_architecture_drift(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )

        with (
            patch.object(MATRIX.platform, "machine", return_value="x86_64"),
            patch.dict(
                os.environ,
                {"DEVELOPER_DIR": lock["runnerEnvironment"]["developerDirectory"]},
            ),
        ):
            with self.assertRaises(MATRIX.MatrixFailure) as failure:
                MATRIX.validate_runner_environment(lock)

        self.assertEqual(failure.exception.code, "runner_architecture_mismatch")

    def test_profile_identity_resolves_the_host_revision(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        with patch.dict(os.environ, {"GITHUB_SHA": "a" * 40}):
            first = MATRIX.profile_identity_sha256(lock)
            repeated = MATRIX.profile_identity_sha256(lock)
        with patch.dict(os.environ, {"GITHUB_SHA": "b" * 40}):
            different_revision = MATRIX.profile_identity_sha256(lock)

        self.assertEqual(first, repeated)
        self.assertNotEqual(first, different_revision)

    def test_realization_identity_ignores_volatile_invocation_timestamps(self) -> None:
        manifest = {
            "schemaVersion": 1,
            "kind": "hosted-installed-toolchain",
            "profileIdentitySHA256": "a" * 64,
            "runner": {"lockImage": "macos-26"},
            "process": {"root": "/volatile/root", "name": "sky130A"},
            "buildDependencies": {},
            "tools": {
                "tool": {
                    "sourceRevision": "b" * 40,
                    "executableSHA256": "c" * 64,
                    "versionInvocation": {"startedAt": "first"},
                    "companions": [
                        {
                            "name": "runtime",
                            "executableSHA256": "d" * 64,
                            "versionInvocation": {"startedAt": "first"},
                        }
                    ],
                }
            },
        }
        changed = {
            **manifest,
            "process": {**manifest["process"], "root": "/other/root"},
            "tools": {
                "tool": {
                    **manifest["tools"]["tool"],
                    "versionInvocation": {"startedAt": "second"},
                    "companions": [
                        {
                            **manifest["tools"]["tool"]["companions"][0],
                            "versionInvocation": {"startedAt": "second"},
                        }
                    ],
                }
            },
        }

        self.assertEqual(
            MATRIX.realization_identity_sha256(manifest),
            MATRIX.realization_identity_sha256(changed),
        )

    def test_magic_headless_build_disables_incompatible_bundled_readline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "fmt", "magic", "netgen", "opensta", "openroad", "ngspice")
            }
            for source in sources.values():
                source.mkdir()
            dependency_installer = sources["openroad"] / "etc" / "DependencyInstaller.sh"
            dependency_installer.parent.mkdir()
            dependency_installer.write_text("#!/bin/sh\n", encoding="utf-8")
            (sources["ngspice"] / "autogen.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            with (
                patch.object(MATRIX, "run_command"),
                patch.object(MATRIX, "build_autotools_tool") as autotools_build,
                patch.object(MATRIX, "build_cmake_tool"),
            ):
                MATRIX.build_tools(
                    sources,
                    root / "installed",
                    root / "logs",
                    timeout=30,
                )

            magic_build = next(
                call
                for call in autotools_build.call_args_list
                if call.args[0] == "magic"
            )
            options = magic_build.args[3]
            self.assertIn("--without-x", options)
            self.assertIn("--disable-readline", options)

    def test_netgen_build_preincludes_its_declared_verilog_api(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "fmt", "magic", "netgen", "opensta", "openroad", "ngspice")
            }
            for source in sources.values():
                source.mkdir()
            dependency_installer = sources["openroad"] / "etc" / "DependencyInstaller.sh"
            dependency_installer.parent.mkdir()
            dependency_installer.write_text("#!/bin/sh\n", encoding="utf-8")
            (sources["ngspice"] / "autogen.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            with (
                patch.object(MATRIX, "run_command"),
                patch.object(MATRIX, "build_autotools_tool") as autotools_build,
                patch.object(MATRIX, "build_cmake_tool"),
            ):
                MATRIX.build_tools(
                    sources,
                    root / "installed",
                    root / "logs",
                    timeout=30,
                )

            netgen_build = next(
                call
                for call in autotools_build.call_args_list
                if call.args[0] == "netgen"
            )
            self.assertIn(
                f"CFLAGS=-include {sources['netgen'] / 'base' / 'tech.h'}",
                netgen_build.args[3],
            )

    def test_opensta_build_receives_pinned_dependency_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "fmt", "magic", "netgen", "opensta", "openroad", "ngspice")
            }
            for source in sources.values():
                source.mkdir()
            dependency_installer = sources["openroad"] / "etc" / "DependencyInstaller.sh"
            dependency_installer.parent.mkdir()
            dependency_installer.write_text("#!/bin/sh\n", encoding="utf-8")
            (sources["ngspice"] / "autogen.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            with (
                patch.object(MATRIX, "run_command"),
                patch.object(MATRIX, "build_autotools_tool"),
                patch.object(MATRIX, "build_cmake_tool") as cmake_build,
            ):
                MATRIX.build_tools(
                    sources,
                    root / "installed",
                    root / "logs",
                    timeout=30,
                )

            opensta_build = next(
                call
                for call in cmake_build.call_args_list
                if call.args[0] == "opensta"
            )
            options = opensta_build.args[3]
            environment = opensta_build.args[4]
            self.assertLess(
                environment["PATH"].index("/opt/homebrew/opt/flex/bin"),
                environment["PATH"].index("/usr/bin"),
            )
            self.assertIn(
                f"-DCUDD_LIB={root / 'installed' / 'lib' / 'libcudd.a'}",
                options,
            )
            self.assertIn(
                f"-DCUDD_HEADER={root / 'installed' / 'include' / 'cudd.h'}",
                options,
            )
            self.assertIn(
                "-DFLEX_INCLUDE_DIR=/opt/homebrew/opt/flex/include",
                options,
            )
            openroad_build = next(
                call
                for call in cmake_build.call_args_list
                if call.args[0] == "openroad"
            )
            openroad_options = openroad_build.args[3]
            openroad_environment = openroad_build.args[4]
            self.assertIn("-DBUILD_GUI=OFF", openroad_options)
            self.assertIn("-DBUILD_PYTHON=OFF", openroad_options)
            self.assertIn(
                "-DCMAKE_DISABLE_FIND_PACKAGE_Qt5=TRUE",
                openroad_options,
            )
            self.assertIn(
                "-DTCL_LIBRARY=/opt/homebrew/opt/tcl-tk@8/lib/libtcl8.6.dylib",
                openroad_options,
            )
            self.assertIn(
                "-DTCL_HEADER=/opt/homebrew/opt/tcl-tk@8/include/tcl-tk/tcl.h",
                openroad_options,
            )
            self.assertIn(
                f"-DCUDD_LIB={root / 'installed' / 'lib' / 'libcudd.a'}",
                openroad_options,
            )
            self.assertIn(
                f"-DCUDD_HEADER={root / 'installed' / 'include' / 'cudd.h'}",
                openroad_options,
            )
            self.assertIn(
                "-DFLEX_INCLUDE_DIR=/opt/homebrew/opt/flex/include",
                openroad_options,
            )
            self.assertIn(
                "/opt/homebrew/opt/zstd",
                openroad_environment["CMAKE_PREFIX_PATH"],
            )
            self.assertIn(
                "/opt/homebrew/opt/icu4c",
                openroad_environment["CMAKE_PREFIX_PATH"],
            )
            self.assertIn(
                "-L/opt/homebrew/opt/zstd/lib",
                openroad_environment["LDFLAGS"],
            )
            self.assertIn(
                "-L/opt/homebrew/opt/icu4c/lib",
                openroad_environment["LDFLAGS"],
            )
            self.assertIn(
                f"-Dfmt_DIR={root / 'installed' / 'lib' / 'cmake' / 'fmt'}",
                openroad_options,
            )
            self.assertIn(
                "-DCMAKE_CXX_FLAGS=-DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED -DFMT_DEPRECATED_HEAVY_CORE",
                openroad_options,
            )
            fmt_build = next(
                call
                for call in cmake_build.call_args_list
                if call.args[0] == "fmt"
            )
            self.assertIn("-DBUILD_SHARED_LIBS=OFF", fmt_build.args[3])
            self.assertIn("-DFMT_TEST=OFF", fmt_build.args[3])

    def test_acquisition_does_not_use_an_unpinned_cudd_formula(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            with patch.object(MATRIX, "run_command") as command:
                MATRIX.install_build_dependencies(
                    Path(temporary_directory),
                    timeout=30,
                )

            formulas = command.call_args.args[0]
            self.assertEqual(formulas[:2], ["brew", "install"])
            self.assertNotIn("cudd", formulas[2:])
            self.assertIn("zstd", formulas[2:])
            self.assertIn("icu4c", formulas[2:])

    def test_cudd_regenerates_its_versioned_autotools_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "fmt", "magic", "netgen", "opensta", "openroad", "ngspice")
            }
            for source in sources.values():
                source.mkdir()
            dependency_installer = sources["openroad"] / "etc" / "DependencyInstaller.sh"
            dependency_installer.parent.mkdir()
            dependency_installer.write_text("#!/bin/sh\n", encoding="utf-8")
            (sources["ngspice"] / "autogen.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            with (
                patch.object(MATRIX, "run_command"),
                patch.object(MATRIX, "build_autotools_tool") as autotools_build,
                patch.object(MATRIX, "build_cmake_tool"),
            ):
                MATRIX.build_tools(
                    sources,
                    root / "installed",
                    root / "logs",
                    timeout=30,
                )

            cudd_build = next(
                call
                for call in autotools_build.call_args_list
                if call.args[0] == "cudd"
            )
            self.assertTrue(cudd_build.kwargs["regenerate_build_system"])

    def test_autotools_regeneration_runs_before_configure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source"
            source.mkdir()

            with patch.object(MATRIX, "run_command") as command:
                MATRIX.build_autotools_tool(
                    "fixture",
                    source,
                    root / "installed",
                    [],
                    {},
                    root / "logs",
                    timeout=30,
                    run_autogen=False,
                    regenerate_build_system=True,
                )

            commands = [call.args[0] for call in command.call_args_list]
            self.assertEqual(commands[0], ["autoreconf", "-fi"])
            self.assertEqual(
                commands[1],
                ["./configure", f"--prefix={root / 'installed'}"],
            )

    def test_tool_companion_paths_are_unique_and_contained(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock["tools"]["ngspice"]["companions"] = [
            {
                "name": "runtime",
                "executable": "installed/bin/ngspice-runtime",
                "versionArguments": ["--version"],
            }
        ]

        MATRIX.validate_lock(lock)

        lock["tools"]["ngspice"]["companions"].append(
            {
                "name": "duplicate-path",
                "executable": "installed/bin/ngspice-runtime",
                "versionArguments": ["--version"],
            }
        )
        with self.assertRaises(MATRIX.MatrixFailure) as failure:
            MATRIX.validate_lock(lock)
        self.assertEqual(failure.exception.code, "duplicate_tool_executable")

    def test_process_corner_rejects_non_finite_temperature(self) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock["process"]["corners"][0]["temperatureCelsius"] = math.nan

        with self.assertRaises(MATRIX.MatrixFailure) as failure:
            MATRIX.validate_lock(lock)

        self.assertEqual(failure.exception.code, "invalid_lock_field")

    def test_process_verilog_definitions_reject_unsafe_or_duplicate_names(
        self,
    ) -> None:
        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock["process"]["verilogDefines"].append(
            {"name": "FUNCTIONAL", "value": "1"}
        )

        with self.assertRaises(MATRIX.MatrixFailure) as duplicate_failure:
            MATRIX.validate_lock(lock)
        self.assertEqual(
            duplicate_failure.exception.code,
            "invalid_lock_field",
        )

        lock = MATRIX.load_json(
            RUNNER_PATH.parents[2]
            / "ci-artifacts"
            / "contracts"
            / "hosted-installed-tool-lock.json"
        )
        lock["process"]["verilogDefines"][1]["value"] = "#1"
        with self.assertRaises(MATRIX.MatrixFailure) as unsafe_failure:
            MATRIX.validate_lock(lock)
        self.assertEqual(
            unsafe_failure.exception.code,
            "invalid_lock_field",
        )

    def test_source_built_logic_tools_use_locked_install_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            install_root = root / "installed"
            logs = root / "logs"
            sources = {
                name: root / name
                for name in ("yosys", "iverilog", "verilator")
            }
            for source in sources.values():
                source.mkdir()

            with (
                patch.object(MATRIX, "run_command") as command,
                patch.object(MATRIX, "build_autotools_tool") as autotools_build,
            ):
                MATRIX.build_yosys(
                    sources["yosys"],
                    install_root,
                    {},
                    logs,
                    timeout=30,
                )
                MATRIX.build_iverilog(
                    sources["iverilog"],
                    install_root,
                    {},
                    logs,
                    timeout=30,
                )
                MATRIX.build_verilator(
                    sources["verilator"],
                    install_root,
                    {},
                    logs,
                    timeout=30,
                )

            commands = [call.args[0] for call in command.call_args_list]
            self.assertIn(["make", "config-clang"], commands)
            self.assertIn(
                ["make", "-j2", f"PREFIX={install_root}"],
                commands,
            )
            self.assertIn(
                ["make", "install", f"PREFIX={install_root}"],
                commands,
            )
            self.assertIn(["sh", "autoconf.sh"], commands)
            self.assertIn(["autoconf"], commands)
            self.assertEqual(
                [call.args[0] for call in autotools_build.call_args_list],
                ["iverilog", "verilator"],
            )


if __name__ == "__main__":
    unittest.main()
