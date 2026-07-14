"""Locate the bundled win-x64 executable and forward argv to it."""

from __future__ import annotations

import os
import subprocess
import sys
from importlib import resources

_EXE_NAME = "msbuild-extractor.exe"


def _resolve_exe() -> str:
    """Return the filesystem path to the bundled win-x64 executable.

    ``importlib.resources`` yields a real on-disk path here because the exe is
    ordinary package data extracted alongside the installed package, not a
    zip-imported resource.
    """
    resource = resources.files(__package__).joinpath("bin", _EXE_NAME)
    with resources.as_file(resource) as path:
        return os.fspath(path)


def main(argv: "list[str] | None" = None) -> int:
    """Invoke the bundled executable, forwarding command-line arguments.

    Returns the executable's exit code so the console script propagates it.
    """
    if os.name != "nt":
        sys.stderr.write(
            "py-msbuild-extractor is Windows-only: it wraps a win-x64 native "
            "executable and depends on the Visual Studio C++ toolchain "
            "(vswhere.exe, VCTargetsPath/VCToolsInstallDir, cl.exe). "
            f"Current platform: {sys.platform}.\n"
        )
        return 1

    exe = _resolve_exe()
    if not os.path.exists(exe):
        sys.stderr.write(
            f"Bundled executable not found at {exe!r}. This wheel appears to be "
            "missing its packaged launcher; reinstall py-msbuild-extractor from "
            "a win_amd64 wheel.\n"
        )
        return 1

    args = sys.argv[1:] if argv is None else list(argv)
    try:
        completed = subprocess.run([exe, *args])
    except OSError as err:  # pragma: no cover - defensive
        sys.stderr.write(f"Failed to launch {exe!r}: {err}\n")
        return 1
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
