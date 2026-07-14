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
$csproj = Join-Path $repoRoot "vendor\msbuild-extractor-sample\msbuild-extractor-sample.csproj"
$publishDir = Join-Path $here "build\publish\$Runtime"
$binDir = Join-Path $here "src\py_msbuild_extractor\bin"
$licenseDir = Join-Path $here "src\py_msbuild_extractor\licenses"

if (-not (Test-Path $csproj)) {
    throw "Vendored project not found at '$csproj'. Run 'git submodule update --init --recursive' first."
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

# Ship the upstream MIT license inside the wheel, next to the redistributed binary.
New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
Copy-Item (Join-Path $repoRoot "vendor\msbuild-extractor-sample\LICENSE") `
          (Join-Path $licenseDir "msbuild-extractor-sample-LICENSE.txt") -Force
Write-Host "Bundled upstream license -> $licenseDir\msbuild-extractor-sample-LICENSE.txt"
