# py-msbuild-extractor

A pip-installable launcher, for **Windows and Linux**, that packages
[`microsoft/msbuild-extractor-sample`](https://github.com/microsoft/msbuild-extractor-sample)
for internal redistribution as a Python wheel.

The upstream tool generates `compile_commands.json` (a Clang-compatible
compilation database) from Visual C++ MSBuild solutions and projects
(`.vcxproj`, `.sln`, `.slnx`) by driving the MSBuild API — no full build
required. That database powers IntelliSense, `clangd`, and other tooling.

## What this repository is

This repo does **not** fork or modify the upstream tool. It vendors it verbatim
as a pinned git submodule and wraps it:

- `vendor/msbuild-extractor-sample/` — the upstream project as a git submodule,
  pinned to a specific commit (never a branch).
- `packaging/python-wheel/` — a setuptools project that bundles a self-contained
  win-x64 or linux-x64 build of the tool and exposes it as the
  `py-msbuild-extractor` command.
- `.github/workflows/build-and-publish.yml` — builds both wheels (on
  `windows-latest` and `ubuntu-latest`) and publishes them to PyPI on
  version-tag pushes.

> **The tool itself is Windows-only in what it does** — it drives the MSVC
> compiler toolchain and the win_amd64 wheel runs it against a real Windows
> install of Visual Studio Build Tools, resolved via `vswhere.exe`. The Linux
> wheel (`manylinux_2_35_x86_64`) runs the same upstream binary natively on
> Linux (no Wine), against an MSVC toolchain and Windows SDK downloaded onto
> the Linux machine — see "Linux" below for what that takes.

> **The .NET global tool / NuGet package is intentionally not built.** This
> repo ships only the Python wheel. `dotnet publish` is used solely to produce
> the bundled executable; no NuGet package is produced or published.

## Requirements on the machine running the tool

This package redistributes **only the launcher**, not the toolchain it drives.

### Windows

- **Visual Studio Build Tools** (or a full Visual Studio) with the
  **"Desktop development with C++"** workload installed. The tool locates it via
  `vswhere.exe` and invokes `cl.exe` and the MSVC MSBuild targets.

No .NET runtime is required on the target machine — the bundled executable is a
self-contained single-file win-x64 build. It ships with its own `hostfxr.dll`
(see below) purely so Microsoft.Build.Locator's .NET SDK discovery has
something to load; it doesn't depend on anything installed system-wide.

#### Troubleshooting: MSBuild not found

If `msbuild-extractor` can't find MSBuild via your Visual Studio install path,
it prints an actionable error (which paths it tried, and how to point it at
the right install) instead of crashing with a raw
`DllNotFoundException`/`hostfxr` stack trace — see
[the patch notes](packaging/python-wheel/patches/README.md) for why that
crash could happen and how the vendored `hostfxr.dll` (below) fixes the root
cause. If you still hit it, pass `--vs-path` pointing at your Visual Studio
installation root (e.g.
`"C:\Program Files\Microsoft Visual Studio\2022\Professional"`), or install
the Visual Studio Build Tools with the "Desktop development with C++"
workload.

### Linux

Two things, both on the machine that will *run* the tool (not needed to build
the wheel itself):

1. **A system-wide .NET SDK** (e.g. `sudo apt install dotnet-sdk-10.0`). The
   bundled executable is self-contained, but `Microsoft.Build.dll` and
   friends are deliberately excluded from the publish
   (`ExcludeAssets="runtime"` in the upstream `.csproj`) and are instead
   resolved at run time from an installed SDK via
   `Microsoft.Build.Locator` — the same way the Windows build resolves them
   from a Visual Studio install rather than bundling them.
2. **An MSVC toolchain + Windows SDK on disk**, since there's no Visual
   Studio (and no registry, and no `vswhere.exe`) to discover one from. Get
   one with:

   ```console
   packaging/python-wheel/tools/setup-linux-toolchain.sh
   ```

   This downloads MSVC, the Windows SDK, and the MSBuild VC++ target files
   directly from Microsoft (via
   [`mstorsjo/msvc-wine`](https://github.com/mstorsjo/msvc-wine)'s
   `vsdownload.py`, which this script accepts the Visual Studio Build Tools
   license on your behalf to run — nothing it downloads is redistributed by
   this repo or the wheel), fixes up a handful of case-sensitivity mismatches
   those target files have against a case-sensitive filesystem, and builds a
   small native-import shim (see
   `packaging/python-wheel/tools/kernel32-shim.c`) so the MSBuild VC++ tasks'
   Win32 P/Invokes used during design-time evaluation resolve without Wine.
   Run `--help` for options (custom install location, download cache).

   Then point the tool at it:

   ```console
   export MSBUILD_EXTRACTOR_TOOLCHAIN=~/.cache/py-msbuild-extractor/toolchain
   py-msbuild-extractor --project path/to/MyProject.vcxproj
   ```

   `py-msbuild-extractor` reads `MSBUILD_EXTRACTOR_TOOLCHAIN` and translates
   it into the `--vc-targets-path`/`--vc-tools-install-dir` flags and MSBuild
   property environment variables the upstream tool expects (normally sourced
   from the Windows registry) — see `_linux_toolchain.py`. Pass
   `--vc-targets-path`/`--vc-tools-install-dir` yourself instead if you want
   to point at a differently-laid-out toolchain; either disables the
   auto-detection.

   `--validate` (which shells out to `cl.exe` to sanity-check the generated
   commands) isn't supported on Linux — extraction doesn't invoke the
   compiler, only formats its command line, but validation actually runs it.

## Installation

### pip (Python wheel)

```console
pip install py-msbuild-extractor
```

This installs the `py-msbuild-extractor` console command (and
`python -m py_msbuild_extractor`), which forwards its arguments straight to the
bundled executable:

```console
py-msbuild-extractor --help
py-msbuild-extractor --solution path/to/MySolution.sln --output compile_commands.json
```

pip picks the wheel matching your platform (`win_amd64` or
`manylinux_2_35_x86_64`); it will refuse to install either on an unsupported
platform (e.g. macOS).

## Pinned upstream commit

The vendored submodule is pinned to:

| | |
|---|---|
| Upstream | https://github.com/microsoft/msbuild-extractor-sample |
| Commit | `4ae6d2f344424a4eb408d88c614b1a73a7e48045` |
| Tag | `v0.2.0` |
| License | MIT (see [`NOTICE`](NOTICE)) |

We pin to a commit and never track a branch. **Bumping the pin is a deliberate,
human-reviewed action** — see [`CONTRIBUTING.md`](CONTRIBUTING.md). CI never
advances the submodule on its own.

## Local patches to the vendored sources

We don't fork or carry a divergent copy of the upstream tool — the submodule
pin always points at a real upstream commit. But occasionally a bug needs
fixing sooner than an upstream PR can land and get re-pinned. For those cases,
`packaging/python-wheel/patches/*.patch` are applied to the submodule's
working tree by `build.ps1`/`build.sh` right before `dotnet publish`, then
reverted (`git checkout -- .` inside the submodule) once publishing finishes — so the
submodule stays pinned to its pristine upstream commit in git history, and
only the *build output* reflects the patch. See
[`packaging/python-wheel/patches/README.md`](packaging/python-wheel/patches/README.md)
for what's patched and why.

`build.ps1` also copies a real `hostfxr.dll` from the .NET SDK doing the build
next to `msbuild-extractor.exe` (Windows only). A self-contained
`PublishSingleFile=true` publish statically links `hostfxr` into the apphost
instead of shipping it as a loadable DLL, so without this step there's no
`hostfxr.dll` anywhere for Microsoft.Build.Locator's .NET SDK discovery to
`P/Invoke` into — see the patch notes above for the full story. On Linux,
that same discovery shells out to `dotnet` on `PATH` instead of `P/Invoke`ing
a loadable host library, so `build.sh` has no equivalent step; a system-wide
.NET SDK on the *target* machine takes its place at run time (see
"Requirements on the machine running the tool" above).

## How it is built

`packaging/python-wheel/build.ps1` (Windows) / `build.sh` (Linux) run:

```
dotnet publish vendor/msbuild-extractor-sample/msbuild-extractor-sample.csproj \
    --runtime <win-x64|linux-x64> --self-contained true \
    /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true
```

and drop the resulting executable — plus a vendored `hostfxr.dll` on Windows,
and the upstream license — into the wheel's package-data directory.
`python -m build --wheel` then produces a `win_amd64` or
`manylinux_2_35_x86_64` wheel, depending on which OS it's run on. A custom
`bdist_wheel` in `setup.py` picks the platform tag from `platform.system()`
so setuptools does not mislabel the binary-bearing wheel as pure Python.

Build it yourself (requires the .NET 10 SDK):

```powershell
# Windows
git clone --recurse-submodules https://github.com/renefritze/py-msbuild-extractor
cd py-msbuild-extractor
pwsh packaging/python-wheel/build.ps1
python -m build --wheel packaging/python-wheel
```

```console
# Linux
git clone --recurse-submodules https://github.com/renefritze/py-msbuild-extractor
cd py-msbuild-extractor
packaging/python-wheel/build.sh
python -m build --wheel packaging/python-wheel
```

## Releasing / Publishing

Releases are cut by pushing a version tag; the wheel version is derived from the
tag so it never drifts from the release:

```console
git tag v0.2.0
git push origin v0.2.0
```

The `build-and-publish` workflow then builds both wheels (win_amd64 and
manylinux_2_35_x86_64) and publishes them to PyPI.

Publishing uses **PyPI Trusted Publishing (OIDC)** — no API token is stored in
the repo. One-time setup on PyPI: add a trusted publisher for this project
pointing at the `renefritze/py-msbuild-extractor` repo, the
`build-and-publish.yml` workflow, and the `pypi` environment. (To use an API
token instead, add a `PYPI_API_TOKEN` secret and pass it as `password:` to the
publish step.)

## License

- This wrapper repository: MIT — see [`LICENSE`](LICENSE).
- Vendored/redistributed `msbuild-extractor-sample`: MIT (Microsoft) — see
  [`NOTICE`](NOTICE) and `vendor/msbuild-extractor-sample/LICENSE`.
- Vendored `hostfxr.dll` (win_amd64 wheel only, from
  [`dotnet/runtime`](https://github.com/dotnet/runtime)): MIT — see
  [`NOTICE`](NOTICE).
