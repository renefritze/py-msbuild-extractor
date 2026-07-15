"""Derive MSBuild environment/CLI overrides from a Linux-side MSVC toolchain.

The toolchain directory is produced by tools/setup-linux-toolchain.sh, which
downloads MSVC, the Windows SDK, and the MSBuild VC++ target files via
mstorsjo/msvc-wine's vsdownload.py. On Windows, VCToolsInstallDir, the Windows
SDK directory, and friends are normally resolved from the registry and
vswhere.exe; neither exists here, so this module derives the equivalent
MSBuild properties directly from the toolchain's on-disk layout and injects
them as environment variables -- mirroring what msvc-wine's own
``wrappers/msbuild`` script sets up for its Wine-based use case.
"""

from __future__ import annotations

import os


class ToolchainError(Exception):
    """The toolchain directory is missing, incomplete, or ambiguous."""


def _one_subdir(path: str) -> str:
    if not os.path.isdir(path):
        raise ToolchainError(
            f"Expected a directory at {path!r}; the toolchain at "
            "MSBUILD_EXTRACTOR_TOOLCHAIN looks incomplete or wasn't produced "
            "by tools/setup-linux-toolchain.sh."
        )
    entries = sorted(
        name for name in os.listdir(path) if os.path.isdir(os.path.join(path, name))
    )
    if len(entries) != 1:
        raise ToolchainError(
            f"Expected exactly one subdirectory under {path!r}, found {entries!r}."
        )
    return entries[0]


def _find_vc_targets_path(toolchain_root: str) -> str:
    vc_dir = os.path.join(toolchain_root, "MSBuild", "Microsoft", "VC")
    if not os.path.isdir(vc_dir):
        raise ToolchainError(f"No MSBuild VC target files found under {vc_dir!r}.")
    candidates = sorted(
        (
            name
            for name in os.listdir(vc_dir)
            if os.path.exists(os.path.join(vc_dir, name, "Microsoft.Cpp.Default.props"))
        ),
        reverse=True,
    )
    if not candidates:
        raise ToolchainError(
            f"No versioned VC target directory (e.g. v180) found under {vc_dir!r}."
        )
    return os.path.join(vc_dir, candidates[0])


def resolve(toolchain_root: str) -> "tuple[dict[str, str], list[str]]":
    """Return ``(extra_env, extra_args)`` for running the bundled extractor
    against the toolchain rooted at ``toolchain_root``."""
    toolchain_root = os.path.abspath(toolchain_root)

    vc_tools_version = _one_subdir(os.path.join(toolchain_root, "VC", "Tools", "MSVC"))
    vc_tools_install_dir = os.path.join(
        toolchain_root, "VC", "Tools", "MSVC", vc_tools_version
    )
    vc_targets_path = _find_vc_targets_path(toolchain_root)

    sdk_root = os.path.join(toolchain_root, "Windows Kits", "10")
    sdk_version = _one_subdir(os.path.join(sdk_root, "Include"))

    vc_install_dir = os.path.join(toolchain_root, "VC") + os.sep
    vc_tools_install_dir_slash = vc_tools_install_dir + os.sep
    kit_root = toolchain_root + os.sep
    sdk_root_slash = sdk_root + os.sep

    extra_env = {
        "VCToolsVersion": vc_tools_version,
        "VCInstallDir_180": vc_install_dir,
        "VCToolsInstallDir_180": vc_tools_install_dir_slash,
        "MicrosoftKitRoot": kit_root,
        "SDKReferenceDirectoryRoot": kit_root,
        "SDKExtensionDirectoryRoot": kit_root,
        "MSBUILDSDKREFERENCEDIRECTORY": kit_root,
        "MSBUILDMULTIPLATFORMSDKREFERENCEDIRECTORY": kit_root,
        "WindowsSdkDir_10": sdk_root_slash,
        "UniversalCRTSdkDir_10": sdk_root_slash,
        "WindowsSdkDir": sdk_root_slash,
        "UniversalCRTSdkDir": sdk_root_slash,
        "UCRTContentRoot": sdk_root_slash,
        "WindowsTargetPlatformVersion": sdk_version,
    }
    extra_args = [
        "--vc-targets-path",
        vc_targets_path,
        "--vc-tools-install-dir",
        vc_tools_install_dir,
    ]
    return extra_env, extra_args
