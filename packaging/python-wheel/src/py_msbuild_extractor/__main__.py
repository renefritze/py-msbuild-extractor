"""Allow ``python -m py_msbuild_extractor`` to run the bundled executable."""

from py_msbuild_extractor._launcher import main

if __name__ == "__main__":
    raise SystemExit(main())
