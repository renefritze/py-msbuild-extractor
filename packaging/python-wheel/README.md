# py-msbuild-extractor

Windows-only pip launcher that bundles a self-contained win-x64 build of
[`microsoft/msbuild-extractor-sample`](https://github.com/microsoft/msbuild-extractor-sample)
and exposes it as the `py-msbuild-extractor` command. It generates
`compile_commands.json` from Visual C++ MSBuild projects (`.vcxproj`, `.sln`,
`.slnx`).

```console
pip install py-msbuild-extractor
py-msbuild-extractor --help
```

This wheel only redistributes the launcher. The machine running it must have
**Visual Studio Build Tools with the C++ (Desktop development with C++)
workload** installed — the tool shells out to `vswhere.exe`, resolves
`VCTargetsPath`/`VCToolsInstallDir`, and invokes `cl.exe`.

See the [project repository](https://github.com/renefritze/py-msbuild-extractor)
for full documentation, the pinned upstream commit, and how it is built.
