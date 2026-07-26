#!/usr/bin/env python3
"""Regression tests for the hosted installed-tool matrix runner."""

from __future__ import annotations

import importlib.util
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

    def test_magic_headless_build_disables_incompatible_bundled_readline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "magic", "netgen", "opensta", "openroad", "ngspice")
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

    def test_opensta_build_receives_pinned_dependency_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            sources = {
                name: root / name
                for name in ("cudd", "magic", "netgen", "opensta", "openroad", "ngspice")
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


if __name__ == "__main__":
    unittest.main()
