#!/usr/bin/env python3
"""Regression tests for the hosted installed-tool matrix runner."""

from __future__ import annotations

import importlib.util
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
            self.assertIn("-DBUILD_GUI=OFF", openroad_options)
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


if __name__ == "__main__":
    unittest.main()
