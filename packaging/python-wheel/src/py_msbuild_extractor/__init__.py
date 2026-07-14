"""py-msbuild-extractor: a pip-installable win-x64 launcher.

This package bundles a self-contained build of
`microsoft/msbuild-extractor-sample <https://github.com/microsoft/msbuild-extractor-sample>`_
and exposes it through the ``msbuild-extractor`` console script. It only
redistributes the launcher; the machine running it still needs the Visual Studio
C++ build toolchain (see the project README).
"""

from py_msbuild_extractor._launcher import main

__all__ = ["main"]
