#!/usr/bin/env bash
#
# Downloads a Microsoft Visual C++ toolchain (MSVC, the Windows SDK, and the
# MSBuild VC++ target files) onto this Linux machine, using
# mstorsjo/msvc-wine's vsdownload.py, then fixes up a few case-sensitivity
# mismatches its target files have against a case-sensitive filesystem and
# builds the small native-import shim py-msbuild-extractor needs (see
# kernel32-shim.c) so design-time MSBuild evaluation runs without Wine.
#
# This is a one-time setup step on the machine that will *run*
# py-msbuild-extractor. It has nothing to do with building the wheel itself.
#
# vsdownload.py downloads Microsoft-licensed binaries directly from
# Microsoft's servers under the Visual Studio Build Tools license
# (https://visualstudio.microsoft.com/license-terms/vs2022-ga-community/).
# Running this script (which passes --accept-license to vsdownload.py) means
# you accept that license; nothing here is redistributed by this repo or the
# wheel it builds.
set -euo pipefail

DEST="${HOME}/.cache/py-msbuild-extractor/toolchain"
CACHE="${HOME}/.cache/py-msbuild-extractor/vsdownload-cache"
MSVC_WINE_REF="master"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dest DIR] [--cache DIR] [--msvc-wine-ref REF]

  --dest DIR         Where to install the toolchain (default: $DEST)
  --cache DIR        Download cache for vsdownload.py (default: $CACHE)
  --msvc-wine-ref REF  git ref of mstorsjo/msvc-wine to use (default: master)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --cache) CACHE="$2"; shift 2 ;;
        --msvc-wine-ref) MSVC_WINE_REF="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

for cmd in git python3 msiextract gcc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required but not found on PATH." >&2
        case "$cmd" in
            msiextract) echo "  Install it with: sudo apt install msitools" >&2 ;;
            gcc) echo "  Install it with: sudo apt install gcc" >&2 ;;
            git) echo "  Install it with: sudo apt install git" >&2 ;;
        esac
        exit 1
    fi
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Cloning msvc-wine (mstorsjo/msvc-wine@${MSVC_WINE_REF})..."
git clone --quiet --depth 1 --branch "$MSVC_WINE_REF" \
    https://github.com/mstorsjo/msvc-wine "$WORKDIR/msvc-wine"

mkdir -p "$DEST" "$CACHE"
echo "Downloading MSVC + Windows SDK + MSBuild VC targets to $DEST (several GB)..."
python3 "$WORKDIR/msvc-wine/vsdownload.py" \
    --accept-license --dest "$DEST" --with-msbuild --cache "$CACHE"

VC_TARGETS_DIR="$(find "$DEST/MSBuild/Microsoft/VC" -maxdepth 1 -type d -name 'v*' \
    -exec test -e '{}/Microsoft.Cpp.Default.props' \; -print | sort -r | head -1)"
if [[ -z "$VC_TARGETS_DIR" ]]; then
    echo "Error: could not find a versioned VC target directory (e.g. v180) under $DEST/MSBuild/Microsoft/VC." >&2
    exit 1
fi

echo "Fixing up case-sensitive imports under $VC_TARGETS_DIR..."
# Microsoft.CppBuild.targets imports "Microsoft.BuildSteps.Targets" (capital
# T), but the file on disk is "Microsoft.BuildSteps.targets" (lowercase);
# Windows' case-insensitive filesystem hides the mismatch, Linux's doesn't.
ln -sf "Microsoft.BuildSteps.targets" "$VC_TARGETS_DIR/Microsoft.BuildSteps.Targets"

# Microsoft.BuildSteps.targets itself imports "$(MSBuildToolsPath)/Microsoft.Common.Targets"
# (capital T); the .NET SDK ships it as "Microsoft.Common.targets" (lowercase).
# Fix the casing in our own copy rather than touching the system-wide SDK
# install (which may be root-owned and shared with other tools).
sed -i 's/Microsoft\.Common\.Targets/Microsoft.Common.targets/' \
    "$VC_TARGETS_DIR/Microsoft.BuildSteps.targets"

# UAP.props locates WindowsSdkDir by searching upward for "sdkmanifest.xml"
# (lowercase); the SDK installer only ships "SDKManifest.xml".
ln -sf "SDKManifest.xml" "$DEST/Windows Kits/10/sdkmanifest.xml"

# Microsoft.Cpp.WindowsSDK.props imports
# "$(UniversalCRTSdkDir)/DesignTime/CommonConfiguration/Neutral/ucrt.props"
# (lowercase); the SDK installer ships "uCRT.props".
ln -sf "uCRT.props" \
    "$DEST/Windows Kits/10/DesignTime/CommonConfiguration/Neutral/ucrt.props"

echo "Building the KERNEL32 shim..."
gcc -shared -fPIC -O2 -o "$VC_TARGETS_DIR/KERNEL32.DLL.so" "$HERE/kernel32-shim.c"

cat <<EOF

Toolchain installed at: $DEST

Run py-msbuild-extractor against it with:
  MSBUILD_EXTRACTOR_TOOLCHAIN="$DEST" py-msbuild-extractor --project path/to/your.vcxproj

A system-wide .NET SDK is also required at run time (Microsoft.Build.dll et
al. are resolved from it, not bundled) -- e.g. 'sudo apt install dotnet-sdk-10.0'.
EOF
