"""setuptools build hook that forces a platform-specific wheel tag.

The wheel bundles a self-contained native executable as package data. Left to
its defaults, setuptools would emit a pure ``py3-none-any`` wheel, which is
wrong: pip on any platform would happily "install" a binary built for a
different one and then fail at runtime. Overriding the tag keeps the wheel
installable on any Python 3 (it only shells out to the exe) while pinning it
to the platform it was actually built for, so mismatched environments reject
it up front. build.ps1/build.sh each produce a binary for exactly one
platform, so the tag is derived from the OS running this build, not from a
target the caller chooses.

The version is single-sourced from the ``MSBUILD_EXTRACTOR_VERSION`` environment
variable (set from the git tag in CI); it falls back to a dev version for local
builds so the two never drift from the tag.
"""

from __future__ import annotations

import os
import platform

from setuptools import Distribution, setup

try:  # setuptools >= 70.1 vendors bdist_wheel
    from setuptools.command.bdist_wheel import bdist_wheel as _bdist_wheel
except ImportError:  # older setuptools: fall back to the standalone wheel package
    from wheel.bdist_wheel import bdist_wheel as _bdist_wheel


def _platform_tag() -> str:
    system = platform.system()
    if system == "Windows":
        return "win_amd64"
    if system == "Linux":
        # Self-contained linux-x64 .NET publish. manylinux_2_35 (Ubuntu
        # 22.04's glibc) is a conservative floor for the .NET 10 runtime it
        # embeds; it isn't verified against the manylinux symbol-version
        # policy the tag usually implies, since this isn't built in a
        # manylinux container.
        return "manylinux_2_35_x86_64"
    raise RuntimeError(
        f"py-msbuild-extractor only builds on Windows and Linux, not {system!r}."
    )


class BinaryDistribution(Distribution):
    """Report a platform-specific distribution so files land at the wheel root.

    The package carries a native executable, so it is not pure Python. Saying
    so keeps the payload at the package root (rather than under a
    ``.data/purelib`` sub-tree) and lets a platform tag be emitted.
    """

    def has_ext_modules(self):
        return True


class bdist_wheel(_bdist_wheel):
    def get_tag(self):
        # Python-agnostic (we only subprocess to the exe) but platform-locked.
        return "py3", "none", _platform_tag()


setup(
    version=os.environ.get("MSBUILD_EXTRACTOR_VERSION", "0.0.0.dev0"),
    distclass=BinaryDistribution,
    cmdclass={"bdist_wheel": bdist_wheel},
)
