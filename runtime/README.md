# LighTeX Runtime

The managed runtime is a portable TeX Live tree installed under the user's
Application Support directory. All variants contain pdfLaTeX, XeLaTeX,
LuaLaTeX, latexmk, SyncTeX, and tlmgr.

- `minimal`: TeX Live small scheme plus LuaTeX and latexmk.
- `standard`: minimal plus the common math, figures, bibliography, LaTeX-extra,
  and font collections used by books and textbooks.
- `full`: TeX Live full scheme without package documentation and sources.

The checked-in profiles under `runtime/profiles` pin each unattended installer
selection. `scripts/build-runtime.sh` produces one ZIP and one metadata file.
The GitHub workflow builds all three variants for both supported architectures,
creates a signed manifest, and publishes the assets under the stable
`runtime-latest` release tag.
