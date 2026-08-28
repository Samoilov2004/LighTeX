# LighTex 1.1 architecture

LighTex is a cross-platform desktop application built with Tauri 2, Rust, React, TypeScript, CodeMirror 6, and PDF.js. The former Swift implementation remains available in Git history and the `v1.0.0` tag, but it is no longer part of the active source tree.

## Application layers

- `apps/desktop/src` renders the project hub, templates, settings, editor workspace, Insert Shelf, Problems, and PDF viewer.
- `apps/desktop/src-tauri` exposes a narrow command/event bridge and owns native menus, dialogs, window behavior, and application lifecycle.
- `crates/lightex-core` owns safe file operations, revisions, monitoring, search, Outline, completion indexing, TeX builds, SyncTeX, templates, settings, updates, and managed runtimes.
- `crates/lightex-core/bindings` contains TypeScript contracts generated from Rust models with `ts-rs`.

The frontend never executes arbitrary shell strings. Build and runtime commands receive validated arguments and launch absolute executable paths selected by the Rust core.

## Documents and projects

Projects are normal folders and require no LighTex-specific metadata file. The application keeps session state in platform application-data directories, performs atomic saves, tracks disk revisions, and pauses autosave/builds while an external edit conflict is unresolved.

## TeX and PDF

LighTex can use an existing system TeX installation or a managed TeX Live runtime. The build service supports `latexmk`, pdfLaTeX, XeLaTeX, LuaLaTeX, grouped diagnostics, missing-package installation, and SyncTeX in both directions.

PDF.js renders a continuous document with lazy page rendering, selectable text, search, zoom, and coordinate conversion for inverse SyncTeX.

## Platform data

- macOS configuration/data: `~/Library/Application Support/LighTeX/v2`
- Linux configuration: `$XDG_CONFIG_HOME/lightex`
- Linux data: `$XDG_DATA_HOME/lightex`
- Caches use the platform cache directory

Managed runtimes are isolated from system TeX and are activated only after signature, checksum, tool, and staging validation.

## Supported release targets

- macOS 11+ on Apple Silicon
- macOS 10.15+ on Intel
- Ubuntu 22.04+, Ubuntu 24.04+, and Debian 12+ on x86_64

The same Rust and React tests run for both macOS architectures and Linux in CI. Native package creation occurs on matching GitHub-hosted runners.

## Current limits

Version 1.1 is light-only. Windows, Linux ARM, AppImage, Flatpak, and automatic application updates are outside the current release scope.
