"""setuptools build hook that forces a ``win_amd64`` platform wheel tag.

The wheel bundles a self-contained win-x64 native executable as package data.
Left to its defaults, setuptools would emit a pure ``py3-none-any`` wheel, which
is wrong: pip on Linux/macOS would happily "install" a Windows-only binary and
then fail at runtime. Overriding the tag to ``py3-none-win_amd64`` keeps the
wheel installable on any Python 3 (it only shells out to the exe) while pinning
it to the correct platform so non-Windows environments reject it up front.

The version is single-sourced from the ``MSBUILD_EXTRACTOR_VERSION`` environment
variable (set from the git tag in CI); it falls back to a dev version for local
builds so the two never drift from the tag.
"""

from __future__ import annotations

import os

from setuptools import Distribution, setup

try:  # setuptools >= 70.1 vendors bdist_wheel
    from setuptools.command.bdist_wheel import bdist_wheel as _bdist_wheel
except ImportError:  # older setuptools: fall back to the standalone wheel package
    from wheel.bdist_wheel import bdist_wheel as _bdist_wheel


class BinaryDistribution(Distribution):
    """Report a platform-specific distribution so files land at the wheel root.

    The package carries a native win-x64 executable, so it is not pure Python.
    Saying so keeps the payload at the package root (rather than under a
    ``.data/purelib`` sub-tree) and lets a platform tag be emitted.
    """

    def has_ext_modules(self):
        return True


class bdist_wheel(_bdist_wheel):
    def get_tag(self):
        # Python-agnostic (we only subprocess to the exe) but platform-locked.
        return "py3", "none", "win_amd64"


setup(
    version=os.environ.get("MSBUILD_EXTRACTOR_VERSION", "0.0.0.dev0"),
    distclass=BinaryDistribution,
    cmdclass={"bdist_wheel": bdist_wheel},
)
