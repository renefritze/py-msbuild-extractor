# Local patches for the vendored msbuild-extractor-sample

`vendor/msbuild-extractor-sample` is a git submodule pinned to an upstream
commit in https://github.com/microsoft/msbuild-extractor-sample. We don't
have write access there, so fixes that can't wait for an upstream PR to land
(and get re-pinned) live here as patches instead.

`build.ps1` applies every `*.patch` file in this directory to the submodule's
working tree before running `dotnet publish`, then reverts them (`git
checkout -- .` inside the submodule) once publishing finishes, so the
submodule stays pinned to its pristine upstream commit in git history.

## 0001-msbuild-locator-hostfxr-fallback.patch

`RegisterMSBuild()` falls back to `MSBuildLocator.QueryVisualStudioInstances()`
/ `RegisterDefaults()` when the `--vs-path` (or auto-detected VS path) guess
doesn't contain `MSBuild.dll`. On `net10.0`, that fallback unconditionally
also probes the .NET SDK via `hostfxr` (Microsoft.Build.Locator's own
`VisualStudioSetup` COM-based discovery is compiled out entirely outside
`net46`/`net472`, so this is the *only* discovery path that runs). In our
self-contained, `PublishSingleFile=true` build there is no discoverable
`hostfxr.dll` for that P/Invoke to resolve — self-contained single-file
publish statically links hostfxr into the apphost rather than shipping it as
a loadable DLL, and there's no guarantee the target machine has a system-wide
`dotnet` SDK/runtime install either. The result was an unhandled
`DllNotFoundException` crashing the whole process instead of a clean error.

The patch wraps those MSBuildLocator calls in `try`/`catch (DllNotFoundException)`
and, if nothing can be found at all, prints an actionable message (pass
`--vs-path`, or install the VS Build Tools C++ workload) and exits with a
non-zero code instead of dumping a raw stack trace.

## Vendored hostfxr.dll

`build.ps1` also copies a real `hostfxr.dll` (from the .NET SDK doing the
build) next to `msbuild-extractor.exe` in the wheel's `bin/` directory — see
the "Local patches to the vendored sources" section of the top-level
`README.md`. That fixes the actual root cause described above: once a
loadable `hostfxr.dll` sits next to the exe, Windows' default DLL search
order (application directory first) lets Microsoft.Build.Locator's P/Invoke
resolve it, so .NET SDK discovery works instead of throwing
`DllNotFoundException`. The `try`/`catch` in this patch stays in place as a
defense-in-depth fallback in case that DLL is missing or fails to load for
some other environmental reason (e.g. it was stripped by an antivirus or
repackaging step) — in that case the tool still degrades to a clear error
instead of an unhandled crash.
