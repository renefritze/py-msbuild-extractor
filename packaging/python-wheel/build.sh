#!/usr/bin/env bash
#
# Build the vendored msbuild-extractor-sample as a self-contained single-file
# linux-x64 executable and drop it into the wheel's package-data directory.
#
# Runs `dotnet publish` against the pinned git submodule under
# vendor/msbuild-extractor-sample, then copies the resulting executable to
# src/py_msbuild_extractor/bin/msbuild-extractor (the location the wheel ships
# as package data) and the upstream LICENSE alongside it.
#
# Before publishing, applies the local patches under patches/ to the
# submodule's working tree (and reverts them again afterwards, so the
# submodule stays pinned to its pristine upstream commit). See build.ps1 for
# the Windows equivalent and patches/README.md for what's patched and why.
#
# Unlike build.ps1, this does not vendor hostfxr.dll: Microsoft.Build.Locator's
# .NET SDK discovery on Linux resolves libhostfxr.so by shelling out to
# `dotnet` on PATH rather than P/Invoking a loadable host library next to the
# executable, so there's nothing to bundle here. A system-wide .NET SDK still
# has to be present at runtime (`apt install dotnet-sdk-10.0` or similar) for
# that discovery, and to run the extracted C++ project system a Linux-side
# MSVC toolchain has to be set up separately — see
# tools/setup-linux-toolchain.sh.
#
# Run this before building the wheel:
#
#     packaging/python-wheel/build.sh
#     python -m build --wheel packaging/python-wheel
set -euo pipefail

CONFIGURATION="${1:-Release}"
RUNTIME="${2:-linux-x64}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor/msbuild-extractor-sample"
CSPROJ="$VENDOR_DIR/msbuild-extractor-sample.csproj"
PATCH_DIR="$HERE/patches"
PUBLISH_DIR="$HERE/build/publish/$RUNTIME"
BIN_DIR="$HERE/src/py_msbuild_extractor/bin"
LICENSE_DIR="$HERE/src/py_msbuild_extractor/licenses"

if [[ ! -f "$CSPROJ" ]]; then
    echo "Vendored project not found at '$CSPROJ'. Run 'git submodule update --init --recursive' first." >&2
    exit 1
fi

if [[ -n "$(git -C "$VENDOR_DIR" status --porcelain)" ]]; then
    echo "Submodule at '$VENDOR_DIR' has local changes; refusing to patch over them. Commit/stash them or run 'git -C $VENDOR_DIR checkout -- .' first." >&2
    exit 1
fi

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
shopt -u nullglob

cleanup() {
    if [[ ${#patches[@]} -gt 0 ]]; then
        git -C "$VENDOR_DIR" checkout -- .
    fi
}
trap cleanup EXIT

for patch in "${patches[@]}"; do
    echo "Applying patch $(basename "$patch") to vendored sources..."
    git -C "$VENDOR_DIR" apply "$patch"
done

echo "Publishing $CSPROJ ($CONFIGURATION / $RUNTIME)..."
dotnet publish "$CSPROJ" \
    --configuration "$CONFIGURATION" \
    --runtime "$RUNTIME" \
    --self-contained true \
    --output "$PUBLISH_DIR" \
    /p:PublishSingleFile=true \
    /p:IncludeNativeLibrariesForSelfExtract=true \
    /p:DebugType=embedded

# Upstream produces 'msbuild-extractor-sample' (AssemblyName defaults to the
# project name); rename to the shorter command the wheel exposes.
SOURCE_EXE="$PUBLISH_DIR/msbuild-extractor-sample"
if [[ ! -f "$SOURCE_EXE" ]]; then
    echo "Expected published executable not found at '$SOURCE_EXE'." >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
TARGET_EXE="$BIN_DIR/msbuild-extractor"
cp -f "$SOURCE_EXE" "$TARGET_EXE"
chmod +x "$TARGET_EXE"
echo "Bundled launcher -> $TARGET_EXE"

# Ship the upstream MIT license inside the wheel, next to the redistributed binary.
mkdir -p "$LICENSE_DIR"
cp -f "$VENDOR_DIR/LICENSE" "$LICENSE_DIR/msbuild-extractor-sample-LICENSE.txt"
echo "Bundled upstream license -> $LICENSE_DIR/msbuild-extractor-sample-LICENSE.txt"
