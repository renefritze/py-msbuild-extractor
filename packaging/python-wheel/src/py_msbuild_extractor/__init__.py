"""py-msbuild-extractor: a pip-installable launcher (Windows and Linux).

This package bundles a self-contained build of
`microsoft/msbuild-extractor-sample <https://github.com/microsoft/msbuild-extractor-sample>`_
and exposes it through the ``py-msbuild-extractor`` console script. It only
redistributes the launcher; the machine running it still needs a Visual C++
build toolchain (Visual Studio Build Tools on Windows, or a toolchain set up
via ``tools/setup-linux-toolchain.sh`` on Linux -- see the project README).
"""

from py_msbuild_extractor._launcher import main

__all__ = ["main"]
