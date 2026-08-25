# LighTex

LighTex is a lightweight native LaTeX workspace for macOS. It keeps the source editor, project files, and compiled PDF in one quiet, resizable window.

## Current features

- Create a local project with a clean, minimal `main.tex`.
- Open any existing LaTeX folder without a proprietary project file.
- Persistent Recent Projects with contextual removal.
- Native project navigator for TeX, BibTeX, style, image, and PDF files.
- Resizable document Outline with chapter/section navigation into both source and PDF through SyncTeX.
- Compact multi-file tabs with unsaved-state indicators.
- SF Mono source editor with line numbers, current-line and matching-bracket highlighting, restrained LaTeX syntax colors, indentation, bracket completion, Undo/Redo, and the standard macOS Find panel.
- Autosave plus configurable Auto Compile delay (2, 5, or 10 seconds).
- `latexmk` or direct compilation with pdfLaTeX, XeLaTeX, or LuaLaTeX.
- Mandatory first-run TeX setup with system MacTeX detection or a managed Minimal, Standard, or Full LighTeX Runtime.
- Signed runtime manifests, SHA-256 archive verification, atomic installation, and one-click missing-package installation.
- PDFKit preview with page, zoom, fit-page, and fit-width controls.
- Actionable Problems panel plus access to the full compiler log.
- Auxiliary build files live in `~/Library/Caches/LighTex`; only the final PDF is copied into the project.
- A non-modal Settings overlay with General, Editor, and LaTeX sections.

The current visual phase intentionally implements only the light appearance.

## Requirements

- macOS 14 or newer.
- Apple Silicon or Intel Mac.
- Xcode Command Line Tools.
- For development before runtime assets are published: MacTeX or BasicTeX with `latexmk`.

## Run from source

```bash
./scripts/run.sh
```

To open a project directly during development:

```bash
./scripts/run.sh /path/to/project
```

## Clean-room first launch

To inspect the first-run flow as if the Mac had no TeX installation, without
touching MacTeX or the app's real preferences:

```bash
./scripts/run-clean-room.sh
```

This default mode serves a tiny locally signed runtime fixture. When a local
TeX installation is available, isolated wrapper executables let the demo build
projects while its mock `tlmgr` remains unable to modify system packages. To
exercise a real managed runtime download after the GitHub assets have been
published:

```bash
./scripts/run-clean-room.sh --release
```

Both modes hide system TeX detection and use isolated preferences and a fresh
temporary runtime directory. The directory path is printed when the script
starts and is kept for inspection after the app exits.

## Build the app bundle

```bash
./scripts/build-app.sh
open dist/LighTex.app
```

The generated bundle is ad-hoc signed for local use. The GitHub app-release workflow uses Developer ID, hardened runtime, and Apple notarization for public artifacts.

## Managed runtime releases

`scripts/build-runtime.sh` creates a portable TeX Live archive and metadata for one preset and architecture. `.github/workflows/runtime-release.yml` builds all six assets, signs their executables, notarizes the archives, creates an Ed25519-signed manifest, and publishes the stable `runtime-latest` GitHub release.

Required repository secrets:

- `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_APPLICATION`
- `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`
- `RUNTIME_SIGNING_PRIVATE_KEY_BASE64`, `RUNTIME_SIGNING_PUBLIC_KEY_BASE64`

The private runtime key must be an Ed25519 PEM key. The matching raw 32-byte public key is Base64-encoded into the release app's Info.plist. Runtime assets live in `~/Library/Application Support/LighTeX/Runtimes`; incomplete downloads and staging directories never become active.

Signing credentials are configured only through GitHub Actions secrets. Private
keys, certificates, `.env` files, and provisioning profiles are ignored by git
and must never be committed. Both release workflows run a preflight that reports
missing secret names without printing their values before any build begins.

## Keyboard workflow

- `Command-N` — new project
- `Command-O` — open project
- `Command-S` — save
- `Command-F` — native Find/Replace panel
- `Command-B` — recompile PDF
- `Command-0` — show/hide Project Navigator
- `Command-Option-0` — show/hide PDF preview
- `Command-Shift-M` — show/hide Problems
- `Command-,` — Settings

## Architecture

```text
Local folder
    → ProjectScanner (tree + main document)
    → RuntimeManager (signed manifest, provider, absolute tool paths)
    → AppModel (tabs, recent projects, autosave, build state)
    → NSTextView editor / LatexBuildService / managed tlmgr
    → user cache (auxiliary files)
    → PDFKit preview + final project PDF
```

The build cache retains SyncTeX data so Outline navigation can target the matching source line and PDF location without adding generated files to the project tree.
