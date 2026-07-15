# Contributing

## Bumping the vendored upstream (deliberate, human-reviewed)

This repository pins
[`microsoft/msbuild-extractor-sample`](https://github.com/microsoft/msbuild-extractor-sample)
to a **specific commit** via the git submodule at
`vendor/msbuild-extractor-sample`. We never track a branch, and CI never bumps
the submodule automatically — a human reviews upstream changes before we pull
them in.

Current pin: **`4ae6d2f344424a4eb408d88c614b1a73a7e48045`** (tag `v0.2.0`).

To bump to a new upstream commit:

1. Review the upstream changes you intend to adopt (diff since the current pin):

   ```bash
   git -C vendor/msbuild-extractor-sample fetch origin
   git -C vendor/msbuild-extractor-sample log --oneline 4ae6d2f..origin/main
   ```

   Prefer a tagged release commit over an arbitrary `main` HEAD. Confirm the
   commit is stable (not mid-feature) before adopting it.

2. Move the submodule to the chosen commit (use the full SHA, not a branch):

   ```bash
   git -C vendor/msbuild-extractor-sample checkout <NEW_SHA>
   git add vendor/msbuild-extractor-sample
   ```

3. Update the pin references so they stay in sync with the submodule:
   - `CONTRIBUTING.md` (this file — the "Current pin" line above)
   - `NOTICE` (the "Vendored at commit" line)
   - `README.md` (the "Pinned upstream commit" section)

4. Check whether `packaging/python-wheel/patches/*.patch` still apply cleanly
   against the new commit (`build.ps1`/`build.sh` will fail loudly if not):

   ```bash
   for p in packaging/python-wheel/patches/*.patch; do
       git -C vendor/msbuild-extractor-sample apply --check "$p" || echo "NEEDS REBASE: $p"
   done
   ```

   If a patch no longer applies, rebase it against the new commit (or drop it
   if upstream already fixed the underlying issue) and update
   `packaging/python-wheel/patches/README.md` accordingly.

5. Commit with a message that records the old → new SHA and a one-line summary
   of why, then open a pull request for review:

   ```bash
   git commit -m "Bump msbuild-extractor-sample to <NEW_SHA> (<upstream tag/reason>)"
   ```

6. Cut a new release tag (`vX.Y.Z`) once merged — see below.

## Cutting a release

The wheel version is derived from the git tag, so releasing is just tagging:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The `build-and-publish` workflow builds the `win_amd64` and
`manylinux_2_35_x86_64` wheels from the tag and publishes both to PyPI (see
the "Publishing" section of the README for the one-time PyPI
trusted-publisher setup). Do not hand-edit a version string — `setup.py`
reads `MSBUILD_EXTRACTOR_VERSION`, which CI sets from the tag.

## Building the wheel locally

Requires the .NET 10 SDK. To *run* the built tool, also requires Visual
Studio Build Tools with the C++ workload (Windows) or a toolchain from
`tools/setup-linux-toolchain.sh` (Linux) — see the README.

```powershell
# Windows
git submodule update --init --recursive
pwsh packaging/python-wheel/build.ps1
python -m build --wheel packaging/python-wheel
```

```console
# Linux
git submodule update --init --recursive
packaging/python-wheel/build.sh
python -m build --wheel packaging/python-wheel
```
