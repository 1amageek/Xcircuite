#!/usr/bin/env python3
"""Build, verify, and retain evidence for the hosted installed-tool matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence


SCHEMA_VERSION = 1
FULL_REVISION = re.compile(r"^[0-9a-f]{40}$")


class MatrixFailure(Exception):
    """A typed failure that must block publication readiness."""

    def __init__(self, code: str, reason: str, suggested_action: str) -> None:
        super().__init__(reason)
        self.code = code
        self.reason = reason
        self.suggested_action = suggested_action

    def diagnostic(self) -> dict[str, str]:
        return {
            "severity": "error",
            "code": self.code,
            "reason": self.reason,
            "suggestedAction": self.suggested_action,
        }


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MatrixFailure(
            "lock_unreadable",
            f"Unable to read JSON at {path}: {error}",
            "Restore a valid checked-in matrix lock file and retry.",
        ) from error
    if not isinstance(value, dict):
        raise MatrixFailure(
            "invalid_json_root",
            f"Expected an object at {path}.",
            "Replace the JSON root with an object that follows the checked-in schema.",
        )
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def file_digest(path: Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    byte_count = 0
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                byte_count += len(chunk)
                digest.update(chunk)
    except OSError as error:
        raise MatrixFailure(
            "artifact_unreadable",
            f"Unable to hash {path}: {error}",
            "Restore the artifact and rerun acquisition.",
        ) from error
    return {"sha256": digest.hexdigest(), "byteCount": byte_count}


def contained_path(root: Path, relative_path: str, context: str) -> Path:
    relative = Path(relative_path)
    resolved_root = root.resolve()
    resolved = (resolved_root / relative).resolve()
    if relative.is_absolute() or (resolved != resolved_root and resolved_root not in resolved.parents):
        raise MatrixFailure(
            "path_containment_failure",
            f"{context} escapes the declared root: {relative_path}.",
            "Use a normalized relative path contained by the artifact root.",
        )
    return resolved


def require_string(mapping: dict[str, Any], key: str, context: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise MatrixFailure(
            "invalid_lock_field",
            f"{context}.{key} must be a non-empty string.",
            "Correct the checked-in lock file.",
        )
    return value


def require_integer(mapping: dict[str, Any], key: str, context: str) -> int:
    value = mapping.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise MatrixFailure(
            "invalid_lock_field",
            f"{context}.{key} must be a positive integer.",
            "Correct the checked-in lock file.",
        )
    return value


def validate_lock(lock: dict[str, Any]) -> None:
    if lock.get("schemaVersion") != SCHEMA_VERSION:
        raise MatrixFailure(
            "unsupported_lock_schema",
            f"Expected lock schema {SCHEMA_VERSION}.",
            "Migrate the lock and this runner together.",
        )
    tools = lock.get("tools")
    lanes = lock.get("lanes")
    process = lock.get("process")
    timeouts = lock.get("timeouts")
    if not isinstance(tools, dict) or not tools:
        raise MatrixFailure("invalid_lock", "tools must be non-empty.", "Declare pinned tools.")
    if not isinstance(lanes, dict) or not lanes:
        raise MatrixFailure("invalid_lock", "lanes must be non-empty.", "Declare package lanes.")
    if not isinstance(process, dict):
        raise MatrixFailure("invalid_lock", "process must be an object.", "Declare a pinned process.")
    if not isinstance(timeouts, dict):
        raise MatrixFailure("invalid_lock", "timeouts must be an object.", "Declare bounded timeouts.")
    require_string(lock, "runner", "lock")
    acquisition_client = process.get("acquisitionClient")
    if not isinstance(acquisition_client, dict):
        raise MatrixFailure("invalid_lock", "process.acquisitionClient must be an object.", "Pin the PDK client.")
    require_string(acquisition_client, "name", "process.acquisitionClient")
    require_string(acquisition_client, "version", "process.acquisitionClient")
    for tool_name, tool in tools.items():
        if not isinstance(tool, dict):
            raise MatrixFailure("invalid_lock", f"Tool {tool_name} must be an object.", "Correct the lock.")
        revision = require_string(tool, "revision", f"tools.{tool_name}")
        if FULL_REVISION.fullmatch(revision) is None:
            raise MatrixFailure(
                "unpinned_tool_revision",
                f"Tool {tool_name} does not use a full Git revision.",
                "Pin the tool to a full 40-character commit revision.",
            )
        require_string(tool, "repository", f"tools.{tool_name}")
        executable_path = require_string(tool, "executable", f"tools.{tool_name}")
        contained_path(Path("/hosted-toolchain"), executable_path, f"tools.{tool_name}.executable")
        arguments = tool.get("versionArguments")
        if not isinstance(arguments, list) or not all(isinstance(item, str) for item in arguments):
            raise MatrixFailure(
                "invalid_lock_field",
                f"tools.{tool_name}.versionArguments must be a string array.",
                "Correct the checked-in lock file.",
            )
        alias = tool.get("aliasOf")
        if alias is not None and (not isinstance(alias, str) or alias not in tools or alias == tool_name):
            raise MatrixFailure(
                "invalid_tool_alias",
                f"tools.{tool_name}.aliasOf does not name another locked tool.",
                "Correct the checked-in lock file.",
            )
        if isinstance(alias, str):
            aliased_tool = tools[alias]
            if not isinstance(aliased_tool, dict) or any(
                tool.get(field) != aliased_tool.get(field)
                for field in ("repository", "revision", "executable")
            ):
                raise MatrixFailure(
                    "tool_alias_identity_mismatch",
                    f"tools.{tool_name} does not share source and executable identity with {alias}.",
                    "Keep capability aliases bound to one installed executable identity.",
                )
    process_revision = require_string(process, "revision", "process")
    if FULL_REVISION.fullmatch(process_revision) is None:
        raise MatrixFailure(
            "unpinned_process_revision",
            "The process revision is not a full Git revision.",
            "Pin the PDK to a full open_pdks revision.",
        )
    assets = process.get("assets")
    if not isinstance(assets, list) or not assets:
        raise MatrixFailure("invalid_lock", "process.assets must be non-empty.", "Declare required PDK assets.")
    for index, asset in enumerate(assets):
        if not isinstance(asset, dict):
            raise MatrixFailure(
                "invalid_lock_field",
                f"process.assets[{index}] must be an object.",
                "Correct the checked-in lock file.",
            )
        require_string(asset, "role", f"process.assets[{index}]")
        asset_path = require_string(asset, "path", f"process.assets[{index}]")
        contained_path(Path("/hosted-pdk"), asset_path, f"process.assets[{index}].path")
    corners = process.get("corners")
    if not isinstance(corners, list) or len(corners) < 3:
        raise MatrixFailure(
            "insufficient_process_corners",
            "process.corners must contain at least typical, slow, and fast corners.",
            "Lock real TT, SS, and FF process assets.",
        )
    corner_ids: set[str] = set()
    classifications: set[str] = set()
    for corner_index, corner in enumerate(corners):
        if not isinstance(corner, dict):
            raise MatrixFailure("invalid_lock_field", f"process.corners[{corner_index}] must be an object.", "Correct the lock.")
        corner_id = require_string(corner, "id", f"process.corners[{corner_index}]")
        classification = require_string(corner, "classification", f"process.corners[{corner_index}]")
        require_string(corner, "ngspiceSection", f"process.corners[{corner_index}]")
        supply_voltage = corner.get("supplyVoltage")
        if not isinstance(supply_voltage, (int, float)) or isinstance(supply_voltage, bool) or supply_voltage <= 0:
            raise MatrixFailure("invalid_lock_field", f"Corner {corner_id} needs a positive supplyVoltage.", "Correct the lock.")
        if corner_id in corner_ids:
            raise MatrixFailure("duplicate_process_corner", f"Duplicate corner {corner_id}.", "Use unique corner IDs.")
        corner_ids.add(corner_id)
        classifications.add(classification)
        corner_assets = corner.get("assets")
        if not isinstance(corner_assets, list):
            raise MatrixFailure("invalid_lock_field", f"Corner {corner_id} needs assets.", "Lock timing and extraction assets.")
        roles: set[str] = set()
        for asset_index, asset in enumerate(corner_assets):
            if not isinstance(asset, dict):
                raise MatrixFailure("invalid_lock_field", f"Corner {corner_id} asset {asset_index} is invalid.", "Correct the lock.")
            role = require_string(asset, "role", f"process.corners.{corner_id}.assets[{asset_index}]")
            asset_path = require_string(asset, "path", f"process.corners.{corner_id}.assets[{asset_index}]")
            contained_path(Path("/hosted-pdk"), asset_path, f"process.corners.{corner_id}.{role}")
            roles.add(role)
        if roles != {"timingLibrary", "openRCXRules", "ngspiceModelLibrary"}:
            raise MatrixFailure(
                "incomplete_corner_assets",
                f"Corner {corner_id} must lock timingLibrary, openRCXRules, and ngspiceModelLibrary.",
                "Declare all real corner assets.",
            )
    if not {"typical", "slow", "fast"}.issubset(classifications):
        raise MatrixFailure(
            "incomplete_corner_classification",
            "The lock does not cover typical, slow, and fast classifications.",
            "Lock TT, SS, and FF corners.",
        )
    for lane_name, lane in lanes.items():
        if not isinstance(lane, dict):
            raise MatrixFailure("invalid_lock", f"Lane {lane_name} must be an object.", "Correct the lock.")
        revision = require_string(lane, "revision", f"lanes.{lane_name}")
        if revision != "$GITHUB_SHA" and FULL_REVISION.fullmatch(revision) is None:
            raise MatrixFailure(
                "unpinned_package_revision",
                f"Lane {lane_name} does not use a full Git revision.",
                "Pin the package or use $GITHUB_SHA only for the host repository.",
            )
        require_string(lane, "repository", f"lanes.{lane_name}")
        require_string(lane, "scheme", f"lanes.{lane_name}")
        tests = lane.get("tests")
        oracles = lane.get("oracles")
        if not isinstance(tests, list) or not tests or not all(isinstance(item, str) and item for item in tests):
            raise MatrixFailure("invalid_lock", f"Lane {lane_name} needs tests.", "Declare test filters.")
        if not isinstance(oracles, list) or not oracles or not all(isinstance(item, str) and item for item in oracles):
            raise MatrixFailure("invalid_lock", f"Lane {lane_name} needs real oracles.", "Declare real tools.")
    required_corner_oracles = {
        "pex": "openrcx",
        "timing": "opensta",
        "electrical-signoff": "ngspice-dc",
    }
    for lane_name, oracle in required_corner_oracles.items():
        if oracle not in lanes[lane_name]["oracles"]:
            raise MatrixFailure(
                "corner_oracle_missing",
                f"Lane {lane_name} must execute {oracle} at every corner.",
                "Restore the required real corner oracle.",
            )
    xcircuite_tests = lanes["xcircuite"]["tests"]
    for suite in ("EndToEndDesignFlowTests", "ReleaseFlowStageExecutorTests", "ReleaseSignoffRawEvidenceValidatorTests"):
        if not any(suite in test_filter for test_filter in xcircuite_tests):
            raise MatrixFailure(
                "release_handoff_filter_missing",
                f"The Xcircuite lane is missing {suite}.",
                "Restore same-design flow and release-handoff coverage.",
            )
    for timeout_name in (
        "acquisitionSeconds",
        "oracleSeconds",
        "dependencyResolutionSeconds",
        "buildForTestingSeconds",
        "testWithoutBuildingSeconds",
    ):
        require_integer(timeouts, timeout_name, "timeouts")


def run_command(
    command: Sequence[str],
    *,
    cwd: Path,
    timeout: int,
    log_path: Path,
    environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started_at = utc_now()
    merged_environment = os.environ.copy()
    if environment is not None:
        merged_environment.update(environment)
    try:
        completed = subprocess.run(
            list(command),
            cwd=cwd,
            env=merged_environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        output = completed.stdout
        exit_code: int | None = completed.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        output_value = error.stdout or ""
        output = output_value.decode("utf-8", errors="replace") if isinstance(output_value, bytes) else output_value
        exit_code = None
        timed_out = True
    log_path.write_text(output, encoding="utf-8")
    record = {
        "command": list(command),
        "workingDirectory": str(cwd),
        "startedAt": started_at,
        "finishedAt": utc_now(),
        "timeoutSeconds": timeout,
        "timedOut": timed_out,
        "exitCode": exit_code,
        "log": str(log_path),
    }
    if timed_out:
        raise MatrixFailure(
            "process_timed_out",
            f"Command timed out after {timeout} seconds; see {log_path}.",
            "Inspect the retained log and remove the hang before retrying.",
        )
    if exit_code != 0:
        raise MatrixFailure(
            "process_failed",
            f"Command exited with {exit_code}; see {log_path}.",
            "Inspect the retained log and correct the tool or package failure.",
        )
    return record


def clone_revision(repository: str, revision: str, destination: Path, timeout: int, log: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    commands = [
        ["git", "init", "--quiet"],
        ["git", "remote", "add", "origin", repository],
        ["git", "fetch", "--depth", "1", "origin", revision],
        ["git", "checkout", "--quiet", "--detach", "FETCH_HEAD"],
        ["git", "submodule", "update", "--init", "--recursive", "--depth", "1"],
    ]
    for index, command in enumerate(commands):
        run_command(command, cwd=destination, timeout=timeout, log_path=log.with_name(f"{log.stem}-{index}.log"))
    resolved = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=destination,
        capture_output=True,
        text=True,
        check=False,
    )
    if resolved.returncode != 0 or resolved.stdout.strip() != revision:
        raise MatrixFailure(
            "revision_mismatch",
            f"Expected {revision} from {repository}, got {resolved.stdout.strip() or 'unresolved'}.",
            "Verify the locked revision and repository identity.",
        )


def acquire_tool_sources(lock: dict[str, Any], root: Path, log_root: Path, timeout: int) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    tools = lock["tools"]
    for tool_name, tool in tools.items():
        if tool.get("aliasOf") is not None:
            continue
        source = root / "sources" / tool_name
        clone_revision(tool["repository"], tool["revision"], source, timeout, log_root / f"clone-{tool_name}.log")
        sources[tool_name] = source
    for tool_name, tool in tools.items():
        alias = tool.get("aliasOf")
        if alias is not None:
            sources[tool_name] = sources[alias]
    return sources


def install_build_dependencies(log_root: Path, timeout: int) -> None:
    formulas = [
        "autoconf",
        "automake",
        "bison",
        "boost",
        "cairo",
        "cmake",
        "eigen",
        "flex",
        "gnu-sed",
        "libomp",
        "libtool",
        "libx11",
        "pkg-config",
        "readline",
        "swig",
        "tcl-tk",
        "zlib",
    ]
    run_command(
        ["brew", "install", *formulas],
        cwd=Path.cwd(),
        timeout=timeout,
        log_path=log_root / "brew-install.log",
    )


def build_tools(sources: dict[str, Path], install_root: Path, log_root: Path, timeout: int) -> None:
    install_root.mkdir(parents=True, exist_ok=True)
    openroad_dependency_script = sources["openroad"] / "etc" / "DependencyInstaller.sh"
    if not openroad_dependency_script.is_file():
        raise MatrixFailure(
            "openroad_dependency_installer_missing",
            f"Missing {openroad_dependency_script} at the pinned revision.",
            "Update the acquisition implementation and lock together.",
        )
    run_command(
        [str(openroad_dependency_script), "-base"],
        cwd=sources["openroad"],
        timeout=timeout,
        log_path=log_root / "openroad-dependencies.log",
    )
    build_environment = {
        "PATH": f"/opt/homebrew/opt/bison/bin:/usr/local/opt/bison/bin:{os.environ.get('PATH', '')}",
        "PKG_CONFIG_PATH": ":".join(
            [
                "/opt/homebrew/opt/tcl-tk/lib/pkgconfig",
                "/usr/local/opt/tcl-tk/lib/pkgconfig",
                os.environ.get("PKG_CONFIG_PATH", ""),
            ]
        ),
        "CMAKE_PREFIX_PATH": ":".join(
            [
                "/opt/homebrew/opt/or-tools",
                "/usr/local/opt/or-tools",
                "/opt/homebrew/opt/tcl-tk@8",
                "/usr/local/opt/tcl-tk@8",
                os.environ.get("CMAKE_PREFIX_PATH", ""),
            ]
        ),
    }
    build_autotools_tool(
        "magic",
        sources["magic"],
        install_root,
        ["--without-x"],
        build_environment,
        log_root,
        timeout,
    )
    build_autotools_tool(
        "netgen",
        sources["netgen"],
        install_root,
        ["--without-x"],
        build_environment,
        log_root,
        timeout,
    )
    build_cmake_tool(
        "opensta",
        sources["opensta"],
        install_root,
        ["-DBUILD_SHARED_LIBS=OFF"],
        build_environment,
        log_root,
        timeout,
    )
    build_cmake_tool(
        "openroad",
        sources["openroad"],
        install_root,
        ["-DENABLE_TESTS=OFF"],
        build_environment,
        log_root,
        timeout,
    )
    ngspice = sources["ngspice"]
    run_command(
        ["./autogen.sh"],
        cwd=ngspice,
        timeout=timeout,
        log_path=log_root / "ngspice-autogen.log",
        environment=build_environment,
    )
    build_autotools_tool(
        "ngspice",
        ngspice,
        install_root,
        ["--without-x", "--enable-xspice", "--disable-debug"],
        build_environment,
        log_root,
        timeout,
        run_autogen=False,
    )


def build_autotools_tool(
    name: str,
    source: Path,
    install_root: Path,
    options: list[str],
    environment: dict[str, str],
    log_root: Path,
    timeout: int,
    *,
    run_autogen: bool = True,
) -> None:
    if run_autogen and not (source / "configure").is_file():
        bootstrap = "./autogen.sh" if (source / "autogen.sh").is_file() else "autoreconf"
        command = [bootstrap] if bootstrap.startswith("./") else [bootstrap, "-fi"]
        run_command(
            command,
            cwd=source,
            timeout=timeout,
            log_path=log_root / f"{name}-autogen.log",
            environment=environment,
        )
    run_command(
        ["./configure", f"--prefix={install_root}", *options],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-configure.log",
        environment=environment,
    )
    run_command(
        ["make", "-j2"],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-build.log",
        environment=environment,
    )
    run_command(
        ["make", "install"],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-install.log",
        environment=environment,
    )


def build_cmake_tool(
    name: str,
    source: Path,
    install_root: Path,
    options: list[str],
    environment: dict[str, str],
    log_root: Path,
    timeout: int,
) -> None:
    build = source / "build-hosted"
    run_command(
        [
            "cmake",
            "-S",
            str(source),
            "-B",
            str(build),
            "-DCMAKE_BUILD_TYPE=Release",
            f"-DCMAKE_INSTALL_PREFIX={install_root}",
            *options,
        ],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-configure.log",
        environment=environment,
    )
    run_command(
        ["cmake", "--build", str(build), "--parallel", "2"],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-build.log",
        environment=environment,
    )
    run_command(
        ["cmake", "--install", str(build)],
        cwd=source,
        timeout=timeout,
        log_path=log_root / f"{name}-install.log",
        environment=environment,
    )


def acquire_pdk(lock: dict[str, Any], root: Path, log_root: Path, timeout: int) -> Path:
    process = lock["process"]
    client = process["acquisitionClient"]
    virtual_environment = root / "volare-venv"
    run_command(
        [sys.executable, "-m", "venv", str(virtual_environment)],
        cwd=root,
        timeout=timeout,
        log_path=log_root / "volare-venv.log",
    )
    python = virtual_environment / "bin" / "python3"
    run_command(
        [str(python), "-m", "pip", "install", f"volare=={client['version']}"],
        cwd=root,
        timeout=timeout,
        log_path=log_root / "volare-install.log",
    )
    volare = virtual_environment / "bin" / "volare"
    if not volare.is_file() or not os.access(volare, os.X_OK):
        raise MatrixFailure(
            "volare_executable_missing",
            f"Pinned Volare did not install an executable at {volare}.",
            "Inspect the retained pip installation log.",
        )
    volare_home = root / "pdk" / "volare"
    run_command(
        [
            str(volare),
            "enable",
            "--pdk",
            "sky130",
            process["revision"],
        ],
        cwd=root,
        timeout=timeout,
        log_path=log_root / "volare-enable.log",
        environment={"VOLARE_HOME": str(volare_home)},
    )
    candidates = sorted(volare_home.glob(f"sky130/versions/{process['revision']}/sky130A"))
    if len(candidates) != 1:
        raise MatrixFailure(
            "pdk_root_unresolved",
            f"Expected exactly one sky130A root for {process['revision']}, found {len(candidates)}.",
            "Inspect the Volare log and pinned PDK layout.",
        )
    return candidates[0]


def collect_toolchain_manifest(lock: dict[str, Any], root: Path, pdk_root: Path, log_root: Path) -> dict[str, Any]:
    tools: dict[str, Any] = {}
    version_timeout = min(120, lock["timeouts"]["oracleSeconds"])
    for tool_name, specification in lock["tools"].items():
        executable = root / specification["executable"]
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise MatrixFailure(
                "tool_executable_missing",
                f"The installed {tool_name} executable is missing or not executable at {executable}.",
                "Inspect the retained build and install logs.",
            )
        version_log = log_root / f"{tool_name}-version.log"
        invocation = run_command(
            [str(executable), *specification["versionArguments"]],
            cwd=root,
            timeout=version_timeout,
            log_path=version_log,
        )
        identity = file_digest(executable)
        version_output = version_log.read_text(encoding="utf-8").strip()
        if not version_output:
            raise MatrixFailure(
                "tool_version_unverified",
                f"Tool {tool_name} returned no version identity.",
                "Correct the version invocation before qualifying this tool.",
            )
        tools[tool_name] = {
            "repository": specification["repository"],
            "sourceRevision": specification["revision"],
            "executable": specification["executable"],
            "executableSHA256": identity["sha256"],
            "executableByteCount": identity["byteCount"],
            "versionInvocation": invocation,
            "versionOutput": version_output,
        }
        if specification.get("aliasOf") is not None:
            tools[tool_name]["aliasOf"] = specification["aliasOf"]
    assets: list[dict[str, Any]] = []
    pdk_container = pdk_root.parent
    for specification in lock["process"]["assets"]:
        path = pdk_container / specification["path"]
        if not path.is_file():
            raise MatrixFailure(
                "pdk_asset_missing",
                f"Required PDK asset {specification['role']} is missing at {path}.",
                "Correct the pinned asset path or the PDK acquisition.",
            )
        identity = file_digest(path)
        assets.append(
            {
                "role": specification["role"],
                "path": str(path.relative_to(root)),
                "sha256": identity["sha256"],
                "byteCount": identity["byteCount"],
            }
        )
    corners: list[dict[str, Any]] = []
    for corner in lock["process"]["corners"]:
        corner_assets: list[dict[str, Any]] = []
        for specification in corner["assets"]:
            path = pdk_container / specification["path"]
            if not path.is_file():
                raise MatrixFailure(
                    "corner_asset_missing",
                    f"Required {corner['id']} asset {specification['role']} is missing at {path}.",
                    "Correct the pinned corner asset path or PDK acquisition.",
                )
            identity = file_digest(path)
            corner_assets.append(
                {
                    "role": specification["role"],
                    "path": str(path.relative_to(root)),
                    "sha256": identity["sha256"],
                    "byteCount": identity["byteCount"],
                }
            )
        corners.append(
            {
                "id": corner["id"],
                "classification": corner["classification"],
                "ngspiceSection": corner["ngspiceSection"],
                "supplyVoltage": corner["supplyVoltage"],
                "assets": corner_assets,
            }
        )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "hosted-installed-toolchain",
        "status": "passed",
        "generatedAt": utc_now(),
        "runner": {
            "lockImage": lock["runner"],
            "platform": platform.platform(),
            "architecture": platform.machine(),
        },
        "process": {
            "name": lock["process"]["name"],
            "revision": lock["process"]["revision"],
            "root": str(pdk_root.relative_to(root)),
            "assets": assets,
            "corners": corners,
        },
        "tools": tools,
        "diagnostics": [],
    }


def create_toolchain_archive(root: Path, archive: Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w:gz", dereference=False) as handle:
        for name in ("installed", "pdk", "toolchain-manifest.json"):
            path = root / name
            if path.exists():
                handle.add(path, arcname=name, recursive=True)


def acquire(args: argparse.Namespace) -> int:
    lock_path = Path(args.lock).resolve()
    root = Path(args.toolchain_root).resolve()
    evidence = Path(args.evidence).resolve()
    archive = Path(args.archive).resolve()
    log_root = evidence.parent / "acquisition-logs"
    lock: dict[str, Any] | None = None
    root.mkdir(parents=True, exist_ok=True)
    try:
        lock = load_json(lock_path)
        validate_lock(lock)
        timeout = lock["timeouts"]["acquisitionSeconds"]
        install_build_dependencies(log_root, timeout)
        sources = acquire_tool_sources(lock, root, log_root, timeout)
        build_tools(sources, root / "installed", log_root, timeout)
        pdk_root = acquire_pdk(lock, root, log_root, timeout)
        manifest = collect_toolchain_manifest(lock, root, pdk_root, log_root)
        write_json(root / "toolchain-manifest.json", manifest)
        write_json(evidence, manifest)
        shutil.rmtree(root / "sources")
        shutil.rmtree(root / "volare-venv")
        create_toolchain_archive(root, archive)
        return 0
    except (MatrixFailure, OSError, tarfile.TarError) as error:
        failure = error if isinstance(error, MatrixFailure) else MatrixFailure(
            "acquisition_io_failure",
            str(error),
            "Inspect the retained acquisition workspace and retry after correcting the I/O failure.",
        )
        blocked = {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "hosted-installed-toolchain",
            "status": "blocked",
            "generatedAt": utc_now(),
            "runner": {"lockImage": lock.get("runner") if lock is not None else None},
            "process": lock.get("process") if lock is not None else None,
            "tools": {},
            "diagnostics": [failure.diagnostic()],
        }
        write_json(evidence, blocked)
        return 1


def extract_archive(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:gz") as handle:
        root = destination.resolve()
        for member in handle.getmembers():
            resolved = (destination / member.name).resolve()
            if resolved != root and root not in resolved.parents:
                raise MatrixFailure(
                    "archive_path_escape",
                    f"Toolchain archive member escapes the destination: {member.name}.",
                    "Regenerate the toolchain artifact from the checked-in acquisition script.",
                )
        handle.extractall(destination, filter="data")


def verify_toolchain(lock: dict[str, Any], root: Path) -> tuple[dict[str, Any], str]:
    manifest_path = root / "toolchain-manifest.json"
    manifest = load_json(manifest_path)
    if manifest.get("status") != "passed":
        raise MatrixFailure(
            "toolchain_not_qualified",
            "The downloaded toolchain manifest is not passed.",
            "Repair acquisition before running package lanes.",
        )
    process = manifest.get("process")
    if not isinstance(process, dict):
        raise MatrixFailure("toolchain_manifest_invalid", "Missing process identity.", "Regenerate the artifact.")
    for key in ("name", "revision"):
        if process.get(key) != lock["process"].get(key):
            raise MatrixFailure(
                "process_identity_mismatch",
                f"Toolchain process {key} does not match the lock.",
                "Discard the artifact and rerun acquisition from this revision.",
            )
    tools = manifest.get("tools")
    if not isinstance(tools, dict) or set(tools) != set(lock["tools"]):
        raise MatrixFailure("tool_identity_mismatch", "Tool set does not match the lock.", "Regenerate the artifact.")
    for tool_name, locked in lock["tools"].items():
        recorded = tools.get(tool_name)
        if not isinstance(recorded, dict) or recorded.get("sourceRevision") != locked["revision"]:
            raise MatrixFailure(
                "tool_revision_mismatch",
                f"Tool {tool_name} does not match its locked revision.",
                "Discard the artifact and rerun acquisition.",
            )
        executable = contained_path(root, locked["executable"], f"tools.{tool_name}.executable")
        identity = file_digest(executable)
        if identity["sha256"] != recorded.get("executableSHA256") or identity["byteCount"] != recorded.get("executableByteCount"):
            raise MatrixFailure(
                "tool_digest_mismatch",
                f"Tool {tool_name} failed executable integrity verification.",
                "Discard the artifact and rerun acquisition.",
            )
    recorded_assets = process.get("assets")
    if not isinstance(recorded_assets, list):
        raise MatrixFailure("toolchain_manifest_invalid", "Missing process assets.", "Regenerate the artifact.")
    process_root_relative = require_string(process, "root", "toolchain.process")
    expected_asset_prefix = Path(process_root_relative).parent
    expected_common_paths = {
        item["role"]: contained_path(root, str(expected_asset_prefix / item["path"]), f"locked process asset {item['role']}")
        for item in lock["process"]["assets"]
    }
    if {asset.get("role") for asset in recorded_assets if isinstance(asset, dict)} != set(expected_common_paths):
        raise MatrixFailure("pdk_asset_set_mismatch", "Process asset roles do not match the lock.", "Regenerate the artifact.")
    for asset in recorded_assets:
        if not isinstance(asset, dict) or not isinstance(asset.get("path"), str):
            raise MatrixFailure("toolchain_manifest_invalid", "Invalid process asset.", "Regenerate the artifact.")
        asset_path = contained_path(root, asset["path"], f"process.assets.{asset.get('role', 'unknown')}")
        if expected_common_paths.get(asset.get("role")) != asset_path:
            raise MatrixFailure(
                "pdk_asset_path_mismatch",
                f"PDK asset {asset.get('role', 'unknown')} does not match the locked path.",
                "Discard the artifact and rerun acquisition.",
            )
        identity = file_digest(asset_path)
        if identity["sha256"] != asset.get("sha256") or identity["byteCount"] != asset.get("byteCount"):
            raise MatrixFailure(
                "pdk_asset_digest_mismatch",
                f"PDK asset {asset.get('role', 'unknown')} failed integrity verification.",
                "Discard the artifact and rerun acquisition.",
            )
    recorded_corners = process.get("corners")
    if not isinstance(recorded_corners, list):
        raise MatrixFailure("toolchain_manifest_invalid", "Missing process corners.", "Regenerate the artifact.")
    if [item.get("id") for item in recorded_corners if isinstance(item, dict)] != [item["id"] for item in lock["process"]["corners"]]:
        raise MatrixFailure("corner_identity_mismatch", "Process corners do not match the lock.", "Regenerate the artifact.")
    for corner, locked_corner in zip(recorded_corners, lock["process"]["corners"], strict=True):
        if any(
            corner.get(field) != locked_corner.get(field)
            for field in ("id", "classification", "ngspiceSection", "supplyVoltage")
        ):
            raise MatrixFailure(
                "corner_metadata_mismatch",
                f"Corner metadata for {locked_corner['id']} does not match the lock.",
                "Discard the artifact and rerun acquisition.",
            )
        if {asset.get("role") for asset in corner.get("assets", []) if isinstance(asset, dict)} != {
            "timingLibrary",
            "openRCXRules",
            "ngspiceModelLibrary",
        }:
            raise MatrixFailure(
                "corner_asset_set_mismatch",
                f"Corner asset roles for {locked_corner['id']} are incomplete.",
                "Discard the artifact and rerun acquisition.",
            )
        expected_corner_paths = {
            item["role"]: contained_path(root, str(expected_asset_prefix / item["path"]), f"locked corner asset {locked_corner['id']}/{item['role']}")
            for item in locked_corner["assets"]
        }
        for asset in corner.get("assets", []):
            asset_path = contained_path(root, asset["path"], f"process.corners.{corner.get('id')}.{asset.get('role')}")
            if expected_corner_paths.get(asset.get("role")) != asset_path:
                raise MatrixFailure(
                    "corner_asset_path_mismatch",
                    f"Corner asset {corner.get('id')}/{asset.get('role')} does not match the locked path.",
                    "Discard the artifact and rerun acquisition.",
                )
            identity = file_digest(asset_path)
            if identity["sha256"] != asset.get("sha256") or identity["byteCount"] != asset.get("byteCount"):
                raise MatrixFailure(
                    "corner_asset_digest_mismatch",
                    f"Corner asset {corner.get('id')}/{asset.get('role')} failed integrity verification.",
                    "Discard the artifact and rerun acquisition.",
                )
    return manifest, file_digest(manifest_path)["sha256"]


def manifest_asset(manifest: dict[str, Any], root: Path, role: str) -> Path:
    process = manifest["process"]
    for asset in process["assets"]:
        if asset.get("role") == role:
            return contained_path(root, asset["path"], f"process.assets.{role}")
    raise MatrixFailure(
        "pdk_asset_role_missing",
        f"Toolchain manifest has no {role} asset.",
        "Regenerate the artifact from the complete lock.",
    )


def manifest_corner(manifest: dict[str, Any], corner_id: str) -> dict[str, Any]:
    for corner in manifest["process"]["corners"]:
        if corner.get("id") == corner_id:
            return corner
    raise MatrixFailure(
        "process_corner_missing",
        f"Toolchain manifest has no {corner_id} corner.",
        "Regenerate the artifact from the complete corner lock.",
    )


def manifest_corner_asset(manifest: dict[str, Any], root: Path, corner_id: str, role: str) -> Path:
    corner = manifest_corner(manifest, corner_id)
    for asset in corner["assets"]:
        if asset.get("role") == role:
            return contained_path(root, asset["path"], f"process.corners.{corner_id}.{role}")
    raise MatrixFailure(
        "corner_asset_role_missing",
        f"Corner {corner_id} has no {role} asset.",
        "Regenerate the artifact from the complete corner lock.",
    )


def tool_path(lock: dict[str, Any], root: Path, name: str) -> Path:
    return contained_path(root, lock["tools"][name]["executable"], f"tools.{name}.executable")


def package_environment(lock: dict[str, Any], manifest: dict[str, Any], root: Path) -> dict[str, str]:
    pdk_root = contained_path(root, manifest["process"]["root"], "process.root")
    return {
        "PATH": f"{root / 'installed' / 'bin'}:{os.environ.get('PATH', '')}",
        "PDK": "sky130A",
        "PDK_ROOT": str(pdk_root.parent),
        "SKY130A": str(pdk_root),
        "MAGIC_BIN": str(tool_path(lock, root, "magic")),
        "MAGIC_RCFILE": str(manifest_asset(manifest, root, "magicStartup")),
        "NETGEN_BIN": str(tool_path(lock, root, "netgen")),
        "NETGEN_SETUP": str(manifest_asset(manifest, root, "netgenSetup")),
        "OPENROAD_BIN": str(tool_path(lock, root, "openroad")),
        "OPENRCX_BIN": str(tool_path(lock, root, "openroad")),
        "OPENSTA_BIN": str(tool_path(lock, root, "opensta")),
        "NGSPICE_BIN": str(tool_path(lock, root, "ngspice")),
    }


def prepare_package(
    lane_name: str,
    lane: dict[str, Any],
    host_checkout: Path,
    work_root: Path,
    timeout: int,
    log_root: Path,
) -> tuple[Path, str]:
    revision = lane["revision"]
    if revision == "$GITHUB_SHA":
        github_sha = os.environ.get("GITHUB_SHA", "")
        if FULL_REVISION.fullmatch(github_sha) is None:
            raise MatrixFailure(
                "github_sha_missing",
                "The host lane requires a full GITHUB_SHA.",
                "Run the lane from a GitHub checkout with a non-shallow commit identity.",
            )
        resolved = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=host_checkout,
            capture_output=True,
            text=True,
            check=False,
        )
        if resolved.returncode != 0 or resolved.stdout.strip() != github_sha:
            raise MatrixFailure(
                "host_checkout_mismatch",
                "The host checkout does not match GITHUB_SHA.",
                "Use actions/checkout for the triggering commit before running the lane.",
            )
        return host_checkout, github_sha
    destination = work_root / lane_name
    clone_revision(lane["repository"], revision, destination, timeout, log_root / "package-clone.log")
    return destination, revision


def write_probe_inputs(probe_root: Path) -> None:
    probe_root.mkdir(parents=True, exist_ok=True)
    write_json(
        probe_root / "design-contract.json",
        {
            "schemaVersion": 1,
            "designID": "sky130-hd-buffer-1",
            "logicalTop": "hosted_probe",
            "physicalTop": "sky130_fd_sc_hd__buf_1",
            "standardCell": "sky130_fd_sc_hd__buf_1",
            "pinMapping": {"a": "A", "y": "X"},
        },
    )
    (probe_root / "design.v").write_text(
        "module hosted_probe(input a, output y);\n"
        "  sky130_fd_sc_hd__buf_1 buffer_instance(.A(a), .X(y));\n"
        "endmodule\n",
        encoding="utf-8",
    )
    (probe_root / "electrical-template.cir").write_text(
        "Hosted electrical oracle\n"
        ".lib {{MODEL_LIBRARY}} {{MODEL_SECTION}}\n"
        ".include {{STANDARD_CELL_SPICE}}\n"
        "VDD vdd 0 {{SUPPLY_VOLTAGE}}\n"
        "VIN gate 0 {{SUPPLY_VOLTAGE}}\n"
        "XBUFFER gate 0 0 vdd vdd output sky130_fd_sc_hd__buf_1\n"
        ".control\n"
        "op\n"
        "print v(output)\n"
        "quit\n"
        ".endc\n"
        ".end\n",
        encoding="utf-8",
    )


def artifact_input(role: str, path: Path) -> dict[str, Any]:
    return {"role": role, "path": str(path), **file_digest(path)}


def probe_input_identity(probe_root: Path, manifest: dict[str, Any], root: Path) -> dict[str, Any]:
    inputs = [
        artifact_input("designContract", probe_root / "design-contract.json"),
        artifact_input("logicalNetlist", probe_root / "design.v"),
        artifact_input("electricalTemplate", probe_root / "electrical-template.cir"),
        artifact_input("physicalLayout", manifest_asset(manifest, root, "standardCellGDS")),
        artifact_input("schematicNetlist", manifest_asset(manifest, root, "standardCellSPICE")),
    ]
    canonical_bytes = json.dumps(
        [{"role": item["role"], "sha256": item["sha256"], "byteCount": item["byteCount"]} for item in inputs],
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return {
        "sha256": hashlib.sha256(canonical_bytes).hexdigest(),
        "designDefinition": load_json(probe_root / "design-contract.json"),
        "artifacts": inputs,
    }


def run_oracle(
    name: str,
    lock: dict[str, Any],
    manifest: dict[str, Any],
    root: Path,
    probe_root: Path,
    log_root: Path,
    design_identity: str,
    corner_id: str | None = None,
) -> dict[str, Any]:
    timeout = lock["timeouts"]["oracleSeconds"]
    consumed_inputs: list[dict[str, Any]] = []
    invocation_id = name if corner_id is None else f"{name}-{corner_id}"
    if name in {"openrcx", "opensta", "ngspice-dc"} and corner_id is None:
        raise MatrixFailure(
            "oracle_corner_missing",
            f"Oracle {name} requires an explicit locked corner.",
            "Execute the oracle once for every locked process corner.",
        )
    selected_corner_id = corner_id or manifest["process"]["corners"][0]["id"]
    if name == "magic-drc":
        script = probe_root / "magic-drc.tcl"
        physical_layout = manifest_asset(manifest, root, "standardCellGDS")
        extracted_netlist = probe_root / "magic-extracted.spice"
        script.write_text(
            f"tech load {manifest_asset(manifest, root, 'magicTechnology')}\n"
            f"gds read {physical_layout}\n"
            "load sky130_fd_sc_hd__buf_1\n"
            "select top cell\n"
            "drc check\n"
            "drc catchup\n"
            "extract do local\n"
            "extract all\n"
            "ext2spice lvs\n"
            f"ext2spice -o {extracted_netlist}\n"
            "puts HOSTED_MAGIC_DRC_COMPLETE\n"
            "quit -noprompt\n",
            encoding="utf-8",
        )
        command = [
            str(tool_path(lock, root, "magic")),
            "-dnull",
            "-noconsole",
            "-rcfile",
            str(manifest_asset(manifest, root, "magicStartup")),
            str(script),
        ]
        consumed_inputs = [
            artifact_input("driver", script),
            artifact_input("physicalLayout", physical_layout),
            artifact_input("magicStartup", manifest_asset(manifest, root, "magicStartup")),
            artifact_input("magicTechnology", manifest_asset(manifest, root, "magicTechnology")),
        ]
    elif name == "netgen-lvs":
        extracted_netlist = probe_root / "magic-extracted.spice"
        if not extracted_netlist.is_file():
            raise MatrixFailure(
                "physical_netlist_missing",
                "Netgen cannot run because Magic did not produce the physical netlist.",
                "Run the Magic physical projection before LVS.",
            )
        schematic_netlist = manifest_asset(manifest, root, "standardCellSPICE")
        command = [
            str(tool_path(lock, root, "netgen")),
            "-batch",
            "lvs",
            f"{extracted_netlist} sky130_fd_sc_hd__buf_1",
            f"{schematic_netlist} sky130_fd_sc_hd__buf_1",
            str(manifest_asset(manifest, root, "netgenSetup")),
            str(probe_root / "netgen-report.json"),
        ]
        consumed_inputs = [
            artifact_input("physicalExtractedNetlist", extracted_netlist),
            artifact_input("schematicNetlist", schematic_netlist),
            artifact_input("netgenSetup", manifest_asset(manifest, root, "netgenSetup")),
        ]
    elif name in ("openroad", "openrcx"):
        script = probe_root / f"{invocation_id}.tcl"
        commands = [
            f"read_lef {manifest_asset(manifest, root, 'technologyLEF')}",
            f"read_lef {manifest_asset(manifest, root, 'libraryLEF')}",
            f"read_liberty {manifest_corner_asset(manifest, root, selected_corner_id, 'timingLibrary')}",
            f"read_verilog {probe_root / 'design.v'}",
            "link_design hosted_probe",
            "initialize_floorplan -die_area {0 0 100 100} -core_area {10 10 90 90} -site unithd",
        ]
        if name == "openrcx":
            spef = probe_root / f"openrcx-{selected_corner_id}.spef"
            commands.extend(
                [
                    f"define_process_corner -ext_model_index 0 {selected_corner_id}",
                    f"extract_parasitics -ext_model_file {manifest_corner_asset(manifest, root, selected_corner_id, 'openRCXRules')} -corner_cnt 1",
                    f"write_spef -corner {selected_corner_id} {spef}",
                ]
            )
        commands.extend([f"puts HOSTED_{name.upper()}_COMPLETE", "exit"])
        script.write_text("\n".join(commands) + "\n", encoding="utf-8")
        executable_name = "openrcx" if name == "openrcx" else "openroad"
        command = [str(tool_path(lock, root, executable_name)), "-no_init", "-exit", str(script)]
        consumed_inputs = [
            artifact_input("driver", script),
            artifact_input("logicalNetlist", probe_root / "design.v"),
            artifact_input("technologyLEF", manifest_asset(manifest, root, "technologyLEF")),
            artifact_input("libraryLEF", manifest_asset(manifest, root, "libraryLEF")),
            artifact_input("timingLibrary", manifest_corner_asset(manifest, root, selected_corner_id, "timingLibrary")),
        ]
        if name == "openrcx":
            consumed_inputs.append(
                artifact_input("openRCXRules", manifest_corner_asset(manifest, root, selected_corner_id, "openRCXRules"))
            )
    elif name == "opensta":
        script = probe_root / f"opensta-{selected_corner_id}.tcl"
        script.write_text(
            f"read_liberty {manifest_corner_asset(manifest, root, selected_corner_id, 'timingLibrary')}\n"
            f"read_verilog {probe_root / 'design.v'}\n"
            "link_design hosted_probe\n"
            "create_clock -name hosted_clock -period 10 [get_ports a]\n"
            "set_input_delay 0.2 -clock hosted_clock [get_ports a]\n"
            "set_output_delay 0.2 -clock hosted_clock [get_ports y]\n"
            "report_checks -path_delay max -fields {slew cap input_pin}\n"
            "puts HOSTED_OPENSTA_COMPLETE\n"
            "exit\n",
            encoding="utf-8",
        )
        command = [str(tool_path(lock, root, "opensta")), "-no_init", "-exit", str(script)]
        consumed_inputs = [
            artifact_input("driver", script),
            artifact_input("logicalNetlist", probe_root / "design.v"),
            artifact_input("timingLibrary", manifest_corner_asset(manifest, root, selected_corner_id, "timingLibrary")),
        ]
    elif name == "ngspice-dc":
        corner = manifest_corner(manifest, selected_corner_id)
        model_library = manifest_corner_asset(manifest, root, selected_corner_id, "ngspiceModelLibrary")
        netlist = probe_root / f"electrical-{selected_corner_id}.cir"
        template = (probe_root / "electrical-template.cir").read_text(encoding="utf-8")
        netlist.write_text(
            template.replace("{{MODEL_LIBRARY}}", str(model_library))
            .replace("{{MODEL_SECTION}}", corner["ngspiceSection"])
            .replace("{{STANDARD_CELL_SPICE}}", str(manifest_asset(manifest, root, "standardCellSPICE")))
            .replace("{{SUPPLY_VOLTAGE}}", str(corner["supplyVoltage"])),
            encoding="utf-8",
        )
        command = [
            str(tool_path(lock, root, "ngspice")),
            "-b",
            "-o",
            str(log_root / f"ngspice-native-{selected_corner_id}.log"),
            str(netlist),
        ]
        consumed_inputs = [
            artifact_input("electricalDeck", netlist),
            artifact_input("schematicNetlist", manifest_asset(manifest, root, "standardCellSPICE")),
            artifact_input("ngspiceModelLibrary", model_library),
        ]
    else:
        raise MatrixFailure(
            "unknown_oracle",
            f"Unknown real-tool oracle {name}.",
            "Add an explicit oracle implementation before declaring it in the lock.",
        )
    record = run_command(command, cwd=probe_root, timeout=timeout, log_path=log_root / f"{invocation_id}.log")
    record["designIdentitySHA256"] = design_identity
    record["oracle"] = name
    record["cornerID"] = corner_id
    record["consumedInputs"] = consumed_inputs
    oracle_output = (log_root / f"{invocation_id}.log").read_text(encoding="utf-8", errors="replace")
    required_markers = {
        "magic-drc": "HOSTED_MAGIC_DRC_COMPLETE",
        "netgen-lvs": "Circuits match uniquely.",
        "openroad": "HOSTED_OPENROAD_COMPLETE",
        "openrcx": "HOSTED_OPENRCX_COMPLETE",
        "opensta": "HOSTED_OPENSTA_COMPLETE",
    }
    required_marker = required_markers.get(name)
    if required_marker is not None and required_marker not in oracle_output:
        raise MatrixFailure(
            "oracle_completion_unverified",
            f"Oracle {name} exited without its semantic completion marker.",
            "Inspect the retained oracle log and require a completed real-tool result.",
        )
    if name == "magic-drc":
        extracted_netlist = probe_root / "magic-extracted.spice"
        if not extracted_netlist.is_file() or extracted_netlist.stat().st_size == 0:
            raise MatrixFailure(
                "physical_netlist_output_missing",
                "Magic completed without producing the physical netlist projection.",
                "Inspect the retained Magic driver, layout input, and extraction log.",
            )
        record["outputArtifacts"] = [artifact_input("physicalExtractedNetlist", extracted_netlist)]
    if name == "openrcx":
        spef = probe_root / f"openrcx-{selected_corner_id}.spef"
        if not spef.is_file() or spef.stat().st_size == 0:
            raise MatrixFailure(
                "openrcx_output_missing",
                "OpenRCX completed without producing a non-empty SPEF artifact.",
                "Inspect the retained OpenRCX script and process assets.",
            )
        record["outputArtifact"] = artifact_input("parasiticNetlist", spef)
    if name == "ngspice-dc":
        native_log = log_root / f"ngspice-native-{selected_corner_id}.log"
        output = native_log.read_text(encoding="utf-8", errors="replace") if native_log.is_file() else ""
        match = re.search(r"v\(output\)\s*=\s*([0-9.eE+-]+)", output, re.IGNORECASE)
        supply_voltage = float(manifest_corner(manifest, selected_corner_id)["supplyVoltage"])
        if match is None or not 0 <= float(match.group(1)) < supply_voltage:
            raise MatrixFailure(
                "electrical_oracle_mismatch",
                f"ngspice did not produce a finite in-range operating point for {selected_corner_id}.",
                "Inspect the retained ngspice logs, corner model, and electrical oracle input.",
            )
        record["measuredOutputVoltage"] = float(match.group(1))
    return record


def ensure_remote_dependencies(package_root: Path, timeout: int, log_root: Path) -> dict[str, Any]:
    dump_log = log_root / "dump-package.log"
    record = run_command(
        ["swift", "package", "dump-package"],
        cwd=package_root,
        timeout=timeout,
        log_path=dump_log,
    )
    try:
        dump = json.loads(dump_log.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise MatrixFailure(
            "package_dump_invalid",
            f"swift package dump-package returned invalid JSON: {error}",
            "Correct the package manifest before running hosted qualification.",
        ) from error
    serialized = json.dumps(dump, sort_keys=True)
    if '"fileSystem"' in serialized:
        raise MatrixFailure(
            "local_package_dependency",
            "The hosted package resolved a local filesystem dependency.",
            "Use pinned remote package dependencies in the standalone repository.",
        )
    return record


def run_xcodebuild_lane(
    lane: dict[str, Any],
    package_root: Path,
    evidence_root: Path,
    environment: dict[str, str],
    timeouts: dict[str, int],
) -> list[dict[str, Any]]:
    derived_data = evidence_root / "derived-data"
    result_bundle = evidence_root / "test-results.xcresult"
    common = [
        "-scheme",
        lane["scheme"],
        "-destination",
        "platform=macOS",
        "-derivedDataPath",
        str(derived_data),
        "-parallel-testing-enabled",
        "NO",
        "-test-timeouts-enabled",
        "YES",
        "-maximum-test-execution-time-allowance",
        "120",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    invocations = [
        run_command(
            ["xcodebuild", "-resolvePackageDependencies", *common[:4]],
            cwd=package_root,
            timeout=timeouts["dependencyResolutionSeconds"],
            log_path=evidence_root / "resolve-package-dependencies.log",
            environment=environment,
        ),
        run_command(
            ["xcodebuild", "build-for-testing", *common],
            cwd=package_root,
            timeout=timeouts["buildForTestingSeconds"],
            log_path=evidence_root / "build-for-testing.log",
            environment=environment,
        ),
    ]
    test_command = ["xcodebuild", "test-without-building", *common, "-resultBundlePath", str(result_bundle)]
    for test_filter in lane["tests"]:
        test_command.append(f"-only-testing:{test_filter}")
    invocations.append(
        run_command(
            test_command,
            cwd=package_root,
            timeout=timeouts["testWithoutBuildingSeconds"],
            log_path=evidence_root / "test-without-building.log",
            environment=environment,
        )
    )
    return invocations


def run_lane(args: argparse.Namespace) -> int:
    lane_name = args.lane
    evidence_root = Path(args.evidence_root).resolve()
    evidence_path = evidence_root / "lane-evidence.json"
    evidence_root.mkdir(parents=True, exist_ok=True)
    toolchain_root = Path(args.toolchain_root).resolve()
    diagnostics: list[dict[str, str]] = []
    evidence: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "hosted-installed-tool-lane",
        "status": "blocked",
        "generatedAt": utc_now(),
        "lane": lane_name,
        "package": {"repository": None, "revision": None},
        "toolchainManifestSHA256": None,
        "process": None,
        "tools": None,
        "designInputIdentity": None,
        "qualifiedCornerIDs": [],
        "releaseHandoffTestFilters": [],
        "releaseHandoffEvidence": None,
        "oracleInvocations": [],
        "xcodebuildInvocations": [],
        "diagnostics": diagnostics,
    }
    try:
        lock = load_json(Path(args.lock).resolve())
        validate_lock(lock)
        if lane_name not in lock["lanes"]:
            raise MatrixFailure("unknown_lane", f"Unknown lane {lane_name}.", "Select a lane from the lock.")
        lane = lock["lanes"][lane_name]
        evidence["package"]["repository"] = lane["repository"]
        archive = Path(args.archive).resolve()
        extract_archive(archive, toolchain_root)
        manifest, manifest_digest = verify_toolchain(lock, toolchain_root)
        evidence["toolchainManifestSHA256"] = manifest_digest
        evidence["process"] = manifest["process"]
        evidence["tools"] = manifest["tools"]
        package_root, package_revision = prepare_package(
            lane_name,
            lane,
            Path(args.host_checkout).resolve(),
            Path(args.work_root).resolve(),
            lock["timeouts"]["dependencyResolutionSeconds"],
            evidence_root,
        )
        evidence["package"]["revision"] = package_revision
        ensure_remote_dependencies(package_root, lock["timeouts"]["dependencyResolutionSeconds"], evidence_root)
        probe_root = evidence_root / "oracle-inputs"
        write_probe_inputs(probe_root)
        design_input_identity = probe_input_identity(probe_root, manifest, toolchain_root)
        evidence["designInputIdentity"] = design_input_identity
        corner_sensitive_oracles = {"openrcx", "opensta", "ngspice-dc"}
        executed_corner_ids: set[str] = set()
        for oracle in lane["oracles"]:
            corner_ids = [corner["id"] for corner in manifest["process"]["corners"]] if oracle in corner_sensitive_oracles else [None]
            for corner_id in corner_ids:
                evidence["oracleInvocations"].append(
                    run_oracle(
                        oracle,
                        lock,
                        manifest,
                        toolchain_root,
                        probe_root,
                        evidence_root / "oracle-logs",
                        design_input_identity["sha256"],
                        corner_id,
                    )
                )
                if corner_id is not None:
                    executed_corner_ids.add(corner_id)
        evidence["qualifiedCornerIDs"] = sorted(executed_corner_ids)
        if lane_name == "xcircuite":
            evidence["releaseHandoffTestFilters"] = [
                test_filter
                for test_filter in lane["tests"]
                if "EndToEndDesignFlowTests" in test_filter
                or "ReleaseFlowStageExecutorTests" in test_filter
                or "ReleaseSignoffRawEvidenceValidatorTests" in test_filter
            ]
        evidence["xcodebuildInvocations"] = run_xcodebuild_lane(
            lane,
            package_root,
            evidence_root,
            package_environment(lock, manifest, toolchain_root),
            lock["timeouts"],
        )
        for invocation in evidence["xcodebuildInvocations"]:
            invocation["designIdentitySHA256"] = design_input_identity["sha256"]
        if lane_name == "xcircuite":
            evidence["releaseHandoffEvidence"] = {
                "designIdentitySHA256": design_input_identity["sha256"],
                "inputArtifacts": design_input_identity["artifacts"],
                "testFilters": evidence["releaseHandoffTestFilters"],
                "status": "passed",
            }
        evidence["status"] = "passed"
        evidence["generatedAt"] = utc_now()
        write_json(evidence_path, evidence)
        return 0
    except (MatrixFailure, OSError, tarfile.TarError) as error:
        failure = error if isinstance(error, MatrixFailure) else MatrixFailure(
            "lane_io_failure",
            str(error),
            "Inspect the retained lane workspace and retry after correcting the I/O failure.",
        )
        diagnostics.append(failure.diagnostic())
        evidence["generatedAt"] = utc_now()
        write_json(evidence_path, evidence)
        return 1


def validate_consumed_input_contract(lane_name: str, lane: dict[str, Any], evidence: dict[str, Any]) -> None:
    identity = evidence.get("designInputIdentity")
    if not isinstance(identity, dict) or not isinstance(identity.get("artifacts"), list):
        raise MatrixFailure(
            "canonical_corpus_missing",
            f"Lane {lane_name} has no canonical design corpus.",
            "Retain the exact logical, physical, schematic, and electrical corpus inputs.",
        )
    corpus_artifacts = identity["artifacts"]
    if identity.get("designDefinition") != {
        "schemaVersion": 1,
        "designID": "sky130-hd-buffer-1",
        "logicalTop": "hosted_probe",
        "physicalTop": "sky130_fd_sc_hd__buf_1",
        "standardCell": "sky130_fd_sc_hd__buf_1",
        "pinMapping": {"a": "A", "y": "X"},
    }:
        raise MatrixFailure(
            "canonical_design_definition_mismatch",
            f"Lane {lane_name} does not identify the locked buffer design.",
            "Use the canonical logical top, physical top, standard cell, and pin mapping.",
        )
    corpus_by_role = {item.get("role"): item for item in corpus_artifacts if isinstance(item, dict)}
    required_corpus_roles = {
        "designContract",
        "logicalNetlist",
        "electricalTemplate",
        "physicalLayout",
        "schematicNetlist",
    }
    if set(corpus_by_role) != required_corpus_roles:
        raise MatrixFailure(
            "canonical_corpus_incomplete",
            f"Lane {lane_name} does not retain the complete canonical corpus.",
            "Materialize every canonical design projection before executing tools.",
        )
    for artifact in corpus_by_role.values():
        validate_input_digest(artifact, f"canonical corpus {artifact.get('role')}")
    canonical_bytes = json.dumps(
        [
            {
                "role": item["role"],
                "sha256": item["sha256"],
                "byteCount": item["byteCount"],
            }
            for item in corpus_artifacts
        ],
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    computed_identity = hashlib.sha256(canonical_bytes).hexdigest()
    if identity.get("sha256") != computed_identity:
        raise MatrixFailure(
            "canonical_corpus_digest_mismatch",
            f"Lane {lane_name} canonical identity does not match its artifact bytes.",
            "Regenerate the corpus identity from the retained artifact digests.",
        )
    process = evidence.get("process")
    if not isinstance(process, dict):
        raise MatrixFailure("process_evidence_missing", f"Lane {lane_name} has no process evidence.", "Retain process inputs.")
    common_process = {
        item.get("role"): item
        for item in process.get("assets", [])
        if isinstance(item, dict)
    }
    grounding_pairs = (
        ("physicalLayout", "standardCellGDS"),
        ("schematicNetlist", "standardCellSPICE"),
    )
    for corpus_role, process_role in grounding_pairs:
        corpus_input = corpus_by_role[corpus_role]
        process_input = common_process.get(process_role)
        if not isinstance(process_input, dict) or (
            corpus_input.get("sha256") != process_input.get("sha256")
            or corpus_input.get("byteCount") != process_input.get("byteCount")
        ):
            raise MatrixFailure(
                "canonical_projection_grounding_mismatch",
                f"Lane {lane_name} {corpus_role} is not the locked {process_role} bytes.",
                "Materialize the canonical projection directly from the locked PDK artifact.",
            )
    corners = {
        item.get("id"): item
        for item in process.get("corners", [])
        if isinstance(item, dict)
    }
    expected_roles = {
        "magic-drc": {"driver", "physicalLayout", "magicStartup", "magicTechnology"},
        "netgen-lvs": {"physicalExtractedNetlist", "schematicNetlist", "netgenSetup"},
        "openroad": {"driver", "logicalNetlist", "technologyLEF", "libraryLEF", "timingLibrary"},
        "openrcx": {"driver", "logicalNetlist", "technologyLEF", "libraryLEF", "timingLibrary", "openRCXRules"},
        "opensta": {"driver", "logicalNetlist", "timingLibrary"},
        "ngspice-dc": {"electricalDeck", "schematicNetlist", "ngspiceModelLibrary"},
    }
    invocations = evidence.get("oracleInvocations")
    if not isinstance(invocations, list):
        raise MatrixFailure("oracle_evidence_missing", f"Lane {lane_name} has no oracle evidence.", "Rerun the lane.")
    expected_counts = {
        oracle: len(corners) if oracle in {"openrcx", "opensta", "ngspice-dc"} else 1
        for oracle in lane["oracles"]
    }
    actual_counts: dict[str, int] = {}
    magic_physical_outputs: list[dict[str, Any]] = []
    netgen_physical_inputs: list[dict[str, Any]] = []
    for invocation in invocations:
        if not isinstance(invocation, dict):
            raise MatrixFailure("oracle_evidence_invalid", f"Lane {lane_name} has malformed oracle evidence.", "Rerun the lane.")
        oracle = invocation.get("oracle")
        if oracle not in expected_roles or oracle not in expected_counts:
            raise MatrixFailure("oracle_evidence_unexpected", f"Lane {lane_name} contains unexpected oracle {oracle}.", "Use the locked oracle inventory.")
        actual_counts[oracle] = actual_counts.get(oracle, 0) + 1
        consumed = invocation.get("consumedInputs")
        if not isinstance(consumed, list):
            raise MatrixFailure("consumed_inputs_missing", f"Oracle {oracle} has no consumed input evidence.", "Hash every file actually read by the tool.")
        consumed_by_role = {item.get("role"): item for item in consumed if isinstance(item, dict)}
        if set(consumed_by_role) != expected_roles[oracle] or len(consumed_by_role) != len(consumed):
            raise MatrixFailure(
                "consumed_input_roles_mismatch",
                f"Oracle {oracle} consumed roles do not match its contract.",
                "Record every and only the actual tool input files.",
            )
        corner_id = invocation.get("cornerID")
        corner_assets = {
            item.get("role"): item
            for item in corners.get(corner_id, {}).get("assets", [])
            if isinstance(item, dict)
        }
        for role, consumed_input in consumed_by_role.items():
            validate_input_digest(consumed_input, f"{oracle}/{role}")
            expected = corpus_by_role.get(role) or common_process.get(role) or corner_assets.get(role)
            if expected is not None and (
                consumed_input.get("sha256") != expected.get("sha256")
                or consumed_input.get("byteCount") != expected.get("byteCount")
            ):
                raise MatrixFailure(
                    "consumed_input_digest_mismatch",
                    f"Oracle {oracle} did not consume the retained {role} bytes.",
                    "Rerun the tool from the canonical corpus and locked process artifact.",
                )
        if oracle == "magic-drc":
            outputs = invocation.get("outputArtifacts")
            if not isinstance(outputs, list) or len(outputs) != 1:
                raise MatrixFailure("physical_projection_missing", "Magic physical netlist output is missing.", "Retain the extracted netlist.")
            validate_input_digest(outputs[0], "Magic physicalExtractedNetlist")
            magic_physical_outputs.append(outputs[0])
        elif oracle == "netgen-lvs":
            netgen_physical_inputs.append(consumed_by_role["physicalExtractedNetlist"])
    if actual_counts != expected_counts:
        raise MatrixFailure(
            "oracle_execution_count_mismatch",
            f"Lane {lane_name} did not execute the locked oracle/corner matrix.",
            "Execute each non-corner oracle once and every corner oracle at all locked corners.",
        )
    if netgen_physical_inputs:
        if len(magic_physical_outputs) != 1 or any(
            item.get("sha256") != magic_physical_outputs[0].get("sha256")
            or item.get("byteCount") != magic_physical_outputs[0].get("byteCount")
            for item in netgen_physical_inputs
        ):
            raise MatrixFailure(
                "lvs_projection_lineage_mismatch",
                "Netgen did not consume the exact physical netlist emitted by Magic.",
                "Preserve byte-identical Magic-to-Netgen artifact lineage.",
            )


def validate_input_digest(value: dict[str, Any], context: str) -> None:
    digest = value.get("sha256")
    byte_count = value.get("byteCount")
    path = value.get("path")
    if (
        not isinstance(path, str)
        or not path
        or not isinstance(digest, str)
        or re.fullmatch(r"[0-9a-f]{64}", digest) is None
        or not isinstance(byte_count, int)
        or isinstance(byte_count, bool)
        or byte_count <= 0
    ):
        raise MatrixFailure(
            "consumed_input_identity_invalid",
            f"{context} lacks a valid path, byte count, or SHA-256 digest.",
            "Hash the exact bytes consumed by the external tool.",
        )


def finalize(args: argparse.Namespace) -> int:
    lock = load_json(Path(args.lock).resolve())
    validate_lock(lock)
    input_root = Path(args.input_root).resolve()
    output = Path(args.output).resolve()
    lanes: list[dict[str, Any]] = []
    diagnostics: list[dict[str, str]] = []
    manifest_digests: set[str] = set()
    all_evidence_paths = list(input_root.glob("**/lane-evidence.json"))
    parsed_evidence: list[tuple[Path, dict[str, Any]]] = []
    for path in all_evidence_paths:
        try:
            parsed_evidence.append((path, load_json(path)))
        except MatrixFailure as error:
            diagnostics.append(error.diagnostic())
    for lane_name in sorted(lock["lanes"]):
        candidates = [
            (path, evidence)
            for path, evidence in parsed_evidence
            if evidence.get("lane") == lane_name
        ]
        if len(candidates) != 1:
            diagnostics.append(
                MatrixFailure(
                    "lane_evidence_missing" if not candidates else "lane_evidence_ambiguous",
                    f"Expected one evidence file for {lane_name}, found {len(candidates)}.",
                    "Rerun the missing or duplicated hosted lane.",
                ).diagnostic()
            )
            lanes.append({"lane": lane_name, "status": "blocked", "evidence": None})
            continue
        evidence_path, lane_evidence = candidates[0]
        raw_status = lane_evidence.get("status")
        status = "passed" if raw_status == "passed" else "blocked"
        digest = lane_evidence.get("toolchainManifestSHA256")
        design_identity = lane_evidence.get("designInputIdentity")
        design_digest = design_identity.get("sha256") if isinstance(design_identity, dict) else None
        oracle_invocations = lane_evidence.get("oracleInvocations")
        if (
            not isinstance(design_digest, str)
            or re.fullmatch(r"[0-9a-f]{64}", design_digest) is None
            or not isinstance(oracle_invocations, list)
            or not oracle_invocations
            or any(
                not isinstance(invocation, dict)
                or invocation.get("designIdentitySHA256") != design_digest
                for invocation in oracle_invocations
            )
        ):
            status = "blocked"
            diagnostics.append(
                MatrixFailure(
                    "cross_oracle_design_identity_mismatch",
                    f"Hosted lane {lane_name} does not bind every oracle to one design identity.",
                    "Rerun every oracle from one immutable design input set.",
                ).diagnostic()
            )
        try:
            validate_consumed_input_contract(lane_name, lock["lanes"][lane_name], lane_evidence)
        except MatrixFailure as error:
            status = "blocked"
            diagnostics.append(error.diagnostic())
        if lane_name in {"pex", "timing", "electrical-signoff", "xcircuite"}:
            expected_corners = sorted(corner["id"] for corner in lock["process"]["corners"])
            if lane_evidence.get("qualifiedCornerIDs") != expected_corners:
                status = "blocked"
                diagnostics.append(
                    MatrixFailure(
                        "corner_coverage_incomplete",
                        f"Hosted lane {lane_name} does not cover every locked process corner.",
                        "Execute and retain TT, SS, and FF real-tool evidence.",
                    ).diagnostic()
                )
        if lane_name == "xcircuite":
            filters = lane_evidence.get("releaseHandoffTestFilters")
            handoff = lane_evidence.get("releaseHandoffEvidence")
            required_suites = {
                "EndToEndDesignFlowTests",
                "ReleaseFlowStageExecutorTests",
                "ReleaseSignoffRawEvidenceValidatorTests",
            }
            handoff_inputs = handoff.get("inputArtifacts") if isinstance(handoff, dict) else None
            corpus_inputs = design_identity.get("artifacts") if isinstance(design_identity, dict) else None
            handoff_by_role = {
                item.get("role"): item
                for item in handoff_inputs
                if isinstance(item, dict)
            } if isinstance(handoff_inputs, list) else {}
            corpus_by_role = {
                item.get("role"): item
                for item in corpus_inputs
                if isinstance(item, dict)
            } if isinstance(corpus_inputs, list) else {}
            handoff_inputs_match = set(handoff_by_role) == set(corpus_by_role) and all(
                handoff_by_role[role].get("sha256") == item.get("sha256")
                and handoff_by_role[role].get("byteCount") == item.get("byteCount")
                for role, item in corpus_by_role.items()
            )
            if (
                not isinstance(filters, list)
                or any(not any(suite in item for item in filters) for suite in required_suites)
                or not isinstance(handoff, dict)
                or handoff.get("status") != "passed"
                or handoff.get("designIdentitySHA256") != design_digest
                or not handoff_inputs_match
            ):
                status = "blocked"
                diagnostics.append(
                    MatrixFailure(
                        "release_handoff_evidence_missing",
                        "The Xcircuite lane lacks same-design flow and release handoff test evidence.",
                        "Run the required end-to-end, raw-evidence, and release handoff suites.",
                    ).diagnostic()
                )
        lane_record: dict[str, Any] = {
            "lane": lane_name,
            "status": status,
            "evidence": str(evidence_path.relative_to(input_root)),
            "toolchainManifestSHA256": digest if isinstance(digest, str) else None,
        }
        if isinstance(lane_evidence.get("package"), dict):
            lane_record["package"] = lane_evidence["package"]
        lane_record["designInputSHA256"] = design_digest
        lane_record["qualifiedCornerIDs"] = lane_evidence.get("qualifiedCornerIDs", [])
        lanes.append(lane_record)
        if status != "passed":
            diagnostics.append(
                MatrixFailure(
                    "lane_not_passed",
                    f"Hosted lane {lane_name} is {raw_status or 'invalid'}.",
                    "Inspect its retained diagnostics and rerun after correction.",
                ).diagnostic()
            )
        if isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None:
            manifest_digests.add(digest)
        else:
            diagnostics.append(
                MatrixFailure(
                    "lane_toolchain_digest_invalid",
                    f"Hosted lane {lane_name} has no valid toolchain manifest digest.",
                    "Rerun the lane from the acquired toolchain artifact.",
                ).diagnostic()
            )
    if len(manifest_digests) != 1:
        diagnostics.append(
            MatrixFailure(
                "toolchain_identity_not_uniform",
                f"Expected one toolchain identity across all lanes, found {len(manifest_digests)}.",
                "Run every lane from the same acquired toolchain artifact.",
            ).diagnostic()
        )
    report = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "hosted-installed-tool-publication-readiness",
        "status": "passed" if not diagnostics else "blocked",
        "generatedAt": utc_now(),
        "toolchainManifestSHA256": next(iter(manifest_digests)) if len(manifest_digests) == 1 else None,
        "lanes": lanes,
        "diagnostics": diagnostics,
    }
    write_json(output, report)
    return 0


def gate(args: argparse.Namespace) -> int:
    evidence = load_json(Path(args.evidence).resolve())
    if evidence.get("status") == "passed":
        return 0
    print(json.dumps(evidence.get("diagnostics", []), indent=2), file=sys.stderr)
    return 1


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    acquire_parser = commands.add_parser("acquire")
    acquire_parser.add_argument("--lock", required=True)
    acquire_parser.add_argument("--toolchain-root", required=True)
    acquire_parser.add_argument("--evidence", required=True)
    acquire_parser.add_argument("--archive", required=True)
    acquire_parser.set_defaults(handler=acquire)

    lane_parser = commands.add_parser("run-lane")
    lane_parser.add_argument("--lock", required=True)
    lane_parser.add_argument("--lane", required=True)
    lane_parser.add_argument("--archive", required=True)
    lane_parser.add_argument("--toolchain-root", required=True)
    lane_parser.add_argument("--host-checkout", required=True)
    lane_parser.add_argument("--work-root", required=True)
    lane_parser.add_argument("--evidence-root", required=True)
    lane_parser.set_defaults(handler=run_lane)

    finalize_parser = commands.add_parser("finalize")
    finalize_parser.add_argument("--lock", required=True)
    finalize_parser.add_argument("--input-root", required=True)
    finalize_parser.add_argument("--output", required=True)
    finalize_parser.set_defaults(handler=finalize)

    gate_parser = commands.add_parser("gate")
    gate_parser.add_argument("--evidence", required=True)
    gate_parser.set_defaults(handler=gate)
    return root


def main() -> int:
    arguments = parser().parse_args()
    try:
        return arguments.handler(arguments)
    except MatrixFailure as error:
        print(json.dumps(error.diagnostic(), indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
