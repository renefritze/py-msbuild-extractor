"""Locate the bundled executable and forward argv to it."""

from __future__ import annotations

import os
import subprocess
import sys
from importlib import resources

_TOOLCHAIN_ENV_VAR = "MSBUILD_EXTRACTOR_TOOLCHAIN"


def _is_windows() -> bool:
    return os.name == "nt"


def _is_linux() -> bool:
    return sys.platform.startswith("linux")


def _exe_name() -> str:
    return "msbuild-extractor.exe" if _is_windows() else "msbuild-extractor"


def _resolve_exe() -> str:
    """Return the filesystem path to the bundled native executable.

    ``importlib.resources`` yields a real on-disk path here because the exe is
    ordinary package data extracted alongside the installed package, not a
    zip-imported resource.
    """
    resource = resources.files(__package__).joinpath("bin", _exe_name())
    with resources.as_file(resource) as path:
        return os.fspath(path)


def main(argv: "list[str] | None" = None) -> int:
    """Invoke the bundled executable, forwarding command-line arguments.

    Returns the executable's exit code so the console script propagates it.
    """
    if not (_is_windows() or _is_linux()):
        sys.stderr.write(
            "py-msbuild-extractor only supports Windows and Linux: it wraps a "
            "native executable that drives the Visual C++ MSBuild toolchain "
            "(vswhere.exe/cl.exe on Windows; an MSVC toolchain fetched via "
            "tools/setup-linux-toolchain.sh on Linux). "
            f"Current platform: {sys.platform}.\n"
        )
        return 1

    exe = _resolve_exe()
    if not os.path.exists(exe):
        sys.stderr.write(
            f"Bundled executable not found at {exe!r}. This wheel appears to be "
            "missing its packaged launcher; reinstall py-msbuild-extractor from "
            "a wheel matching this platform.\n"
        )
        return 1
    if _is_linux() and not os.access(exe, os.X_OK):
        # Defensive: some wheel install paths don't preserve the executable
        # bit set at build time (see build.sh).
        os.chmod(exe, 0o755)

    args = sys.argv[1:] if argv is None else list(argv)
    env = os.environ

    if _is_linux():
        toolchain_root = os.environ.get(_TOOLCHAIN_ENV_VAR)
        if (
            toolchain_root
            and "--vc-targets-path" not in args
            and "--vc-tools-install-dir" not in args
        ):
            from py_msbuild_extractor._linux_toolchain import ToolchainError, resolve

            try:
                extra_env, extra_args = resolve(toolchain_root)
            except ToolchainError as err:
                sys.stderr.write(f"Error: {err}\n")
                return 1
            env = {**os.environ, **{k: v for k, v in extra_env.items() if k not in os.environ}}
            args = [*args, *extra_args]

    try:
        completed = subprocess.run([exe, *args], env=env)
    except OSError as err:  # pragma: no cover - defensive
        sys.stderr.write(f"Failed to launch {exe!r}: {err}\n")
        return 1
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
