# LighTex managed runtime

The managed runtime is a portable TeX Live tree installed under the platform application-data directory. All variants contain pdfLaTeX, XeLaTeX, LuaLaTeX, latexmk, SyncTeX, and tlmgr.

- `minimal`: the small TeX Live scheme plus LuaTeX and latexmk.
- `standard`: Minimal plus common math, figures, bibliography, LaTeX-extra, and font collections.
- `full`: the full TeX Live scheme without package documentation and sources.

The checked-in profiles under `runtime/profiles` pin each unattended installation. `scripts/build-runtime.sh` creates one ZIP and one metadata file. The runtime workflow builds all three variants for macOS arm64, macOS x86_64, and Linux x86_64, creates a signed schema-v2 manifest, and publishes the approved assets under `runtime-v2-latest`.

The Ed25519 private key exists only in GitHub Actions Secrets. The application embeds the public key and verifies both the manifest signature and each archive's SHA-256 before activating a staged installation.
