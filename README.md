# py-msbuild-extractor

A pip-installable, **Windows-only** launcher that packages
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
  win-x64 build of the tool and exposes it as the `py-msbuild-extractor` command.
- `.github/workflows/build-and-publish.yml` — builds the wheel on
  `windows-latest` and publishes it to PyPI on version-tag pushes.

> **Windows-only by design.** The tool depends on `vswhere.exe`,
> `VCTargetsPath`/`VCToolsInstallDir` resolution, and `cl.exe` — none of which
> exist off Windows. There is deliberately no cross-platform support and no
> pure-Python fallback. The wheel is tagged `py3-none-win_amd64` so pip will not
> install it on Linux or macOS.

> **The .NET global tool / NuGet package is intentionally not built.** This
> repo ships only the Python wheel. `dotnet publish` is used solely to produce
> the bundled executable; no NuGet package is produced or published.

## Requirements on the machine running the tool

This package redistributes **only the launcher**, not the toolchain it drives.
The machine that runs `py-msbuild-extractor` must have:

- **Visual Studio Build Tools** (or a full Visual Studio) with the
  **"Desktop development with C++"** workload installed. The tool locates it via
  `vswhere.exe` and invokes `cl.exe` and the MSVC MSBuild targets.

No .NET runtime is required on the target machine — the bundled executable is a
self-contained single-file win-x64 build. It ships with its own `hostfxr.dll`
(see below) purely so Microsoft.Build.Locator's .NET SDK discovery has
something to load; it doesn't depend on anything installed system-wide.

### Troubleshooting: MSBuild not found

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
py-msbuild-extractor --solution path\to\MySolution.sln --output compile_commands.json
```

Only `win_amd64` (64-bit Windows) is supported; pip on other platforms will
refuse the wheel.

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
working tree by `build.ps1` right before `dotnet publish`, then reverted
(`git checkout -- .` inside the submodule) once publishing finishes — so the
submodule stays pinned to its pristine upstream commit in git history, and
only the *build output* reflects the patch. See
[`packaging/python-wheel/patches/README.md`](packaging/python-wheel/patches/README.md)
for what's patched and why.

`build.ps1` also copies a real `hostfxr.dll` from the .NET SDK doing the build
next to `msbuild-extractor.exe`. A self-contained `PublishSingleFile=true`
publish statically links `hostfxr` into the apphost instead of shipping it as
a loadable DLL, so without this step there's no `hostfxr.dll` anywhere for
Microsoft.Build.Locator's .NET SDK discovery to `P/Invoke` into — see the
patch notes above for the full story.

## How it is built

`packaging/python-wheel/build.ps1` runs:

```
dotnet publish vendor/msbuild-extractor-sample/msbuild-extractor-sample.csproj \
    --runtime win-x64 --self-contained true \
    /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true
```

and drops the resulting `msbuild-extractor.exe` — plus a vendored `hostfxr.dll`
and the upstream license — into the wheel's package-data directory.
`python -m build --wheel` then produces the `win_amd64` wheel. A custom
`bdist_wheel` in `setup.py` forces the platform tag so setuptools does not
mislabel the binary-bearing wheel as pure Python.

Build it yourself on Windows (requires the .NET 10 SDK):

```powershell
git clone --recurse-submodules https://github.com/renefritze/py-msbuild-extractor
cd py-msbuild-extractor
pwsh packaging/python-wheel/build.ps1
python -m build --wheel packaging/python-wheel
```

## Releasing / Publishing

Releases are cut by pushing a version tag; the wheel version is derived from the
tag so it never drifts from the release:

```console
git tag v0.2.0
git push origin v0.2.0
```

The `build-and-publish` workflow then builds the wheel and publishes it to PyPI.

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
- Vendored `hostfxr.dll` (from [`dotnet/runtime`](https://github.com/dotnet/runtime)):
  MIT — see [`NOTICE`](NOTICE).
