#Requires -Version 5.1
<#
.SYNOPSIS
    Build the vendored msbuild-extractor-sample as a self-contained single-file
    win-x64 executable and drop it into the wheel's package-data directory.

.DESCRIPTION
    Runs `dotnet publish` against the pinned git submodule under
    vendor/msbuild-extractor-sample, then copies the resulting executable to
    src/py_msbuild_extractor/bin/msbuild-extractor.exe (the location the wheel
    ships as package data) and the upstream LICENSE alongside it.

    Before publishing, applies the local patches under patches/ to the
    submodule's working tree (and reverts them again afterwards, so the
    submodule stays pinned to its pristine upstream commit). We don't control
    the upstream repo, so fixes that can't wait for a merged PR there live as
    patches here instead.

    Also copies a real hostfxr.dll from the local .NET SDK install next to the
    published executable, so Microsoft.Build.Locator's .NET SDK discovery has
    something to load. See patches/README.md for why that's necessary.

    Run this before building the wheel:

        pwsh packaging/python-wheel/build.ps1
        python -m build --wheel packaging/python-wheel
#>
[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $here "..\..")).Path
$vendorDir = Join-Path $repoRoot "vendor\msbuild-extractor-sample"
$csproj = Join-Path $vendorDir "msbuild-extractor-sample.csproj"
$patchDir = Join-Path $here "patches"
$publishDir = Join-Path $here "build\publish\$Runtime"
$binDir = Join-Path $here "src\py_msbuild_extractor\bin"
$licenseDir = Join-Path $here "src\py_msbuild_extractor\licenses"

if (-not (Test-Path $csproj)) {
    throw "Vendored project not found at '$csproj'. Run 'git submodule update --init --recursive' first."
}

$dirtyStatus = git -C $vendorDir status --porcelain
if ($dirtyStatus) {
    throw "Submodule at '$vendorDir' has local changes; refusing to patch over them. Commit/stash them or run 'git -C $vendorDir checkout -- .' first."
}

$patches = @(Get-ChildItem -Path $patchDir -Filter "*.patch" | Sort-Object Name)
try {
    foreach ($patch in $patches) {
        Write-Host "Applying patch $($patch.Name) to vendored sources..."
        git -C $vendorDir apply $patch.FullName
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply patch '$($patch.FullName)'." }
    }

    Write-Host "Publishing $csproj ($Configuration / $Runtime)..."
    dotnet publish $csproj `
        --configuration $Configuration `
        --runtime $Runtime `
        --self-contained true `
        --output $publishDir `
        /p:PublishSingleFile=true `
        /p:IncludeNativeLibrariesForSelfExtract=true `
        /p:DebugType=embedded
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
}
finally {
    if ($patches.Count -gt 0) {
        git -C $vendorDir checkout -- .
    }
}

# Upstream produces 'msbuild-extractor-sample.exe' (AssemblyName defaults to the
# project name); rename to the shorter command the wheel exposes.
$sourceExe = Join-Path $publishDir "msbuild-extractor-sample.exe"
if (-not (Test-Path $sourceExe)) {
    throw "Expected published executable not found at '$sourceExe'."
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$targetExe = Join-Path $binDir "msbuild-extractor.exe"
Copy-Item $sourceExe $targetExe -Force
Write-Host "Bundled launcher -> $targetExe"

# Vendor a real hostfxr.dll alongside the executable. Microsoft.Build.Locator's
# .NET SDK discovery P/Invokes into "hostfxr" (hostfxr_resolve_sdk2 et al.), but
# a self-contained PublishSingleFile publish statically links hostfxr into the
# apphost instead of shipping it as a loadable DLL, so there is normally no
# hostfxr.dll anywhere for that P/Invoke to resolve (see patches/README.md).
# hostfxr's native ABI is stable across versions, so any reasonably recent
# win-x64 build works; grab it from the SDK doing this build rather than
# pulling in a separate NuGet package. Windows loads DLLs from the directory of
# the running executable before anything else, so dropping it next to
# msbuild-extractor.exe is enough for the P/Invoke to find it at run time.
$dotnetCmd = Get-Command dotnet -ErrorAction Stop
$dotnetRoot = Split-Path $dotnetCmd.Source -Parent
$hostfxrCandidates = @(Get-ChildItem -Path (Join-Path $dotnetRoot "host\fxr") -Filter "hostfxr.dll" -Recurse -ErrorAction SilentlyContinue)
if ($hostfxrCandidates.Count -eq 0) {
    throw "Could not find hostfxr.dll under '$dotnetRoot\host\fxr'. Is a win-x64 .NET SDK installed?"
}

function Get-FxrVersionPrefix([string]$folderName) {
    if ($folderName -match '^(\d+)\.(\d+)\.(\d+)') {
        return [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    }
    return [version]"0.0.0"
}
$hostfxrDll = $hostfxrCandidates | Sort-Object { Get-FxrVersionPrefix $_.Directory.Name } -Descending | Select-Object -First 1
Copy-Item $hostfxrDll.FullName (Join-Path $binDir "hostfxr.dll") -Force
Write-Host "Bundled hostfxr.dll ($($hostfxrDll.Directory.Name)) -> $binDir\hostfxr.dll"

# Ship the upstream MIT license inside the wheel, next to the redistributed binary.
New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
Copy-Item (Join-Path $vendorDir "LICENSE") `
          (Join-Path $licenseDir "msbuild-extractor-sample-LICENSE.txt") -Force
Write-Host "Bundled upstream license -> $licenseDir\msbuild-extractor-sample-LICENSE.txt"
