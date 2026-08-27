# LighTeX 1.1 cross-platform rewrite

LighTeX 1.1 is being developed beside the stable Swift application. The Swift sources remain the implementation shipped as 1.0.0 until the new desktop client reaches feature parity and passes the platform matrix below.

## Repository layout

- `apps/desktop` — Tauri 2 shell and React 19/TypeScript interface.
- `crates/lightex-core` — platform-neutral Rust core and generated TypeScript contracts.
- `Sources/LighTex` — current Swift implementation; intentionally unchanged by the rewrite.
- `scripts/build-runtime-v2.sh` — reproducible TeX Live runtime builder used by the runtime workflow.

## Local development

Requirements are Rust stable, Node 22, pnpm 11, and the platform dependencies listed in the Tauri 2 prerequisites.

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Run the complete local verification with:

```sh
pnpm check
```

Create a local native build without publishing anything:

```sh
pnpm --dir apps/desktop tauri build
```

## Implemented foundation

- Safe project and document operations, atomic saves, revisions, dirty conflicts, file monitoring, search/replace/undo, Outline, completion indexing, templates and versioned settings.
- Absolute-path TeX toolchains, three engines, latexmk, grouped diagnostics, missing-package installation, build cancellation and both SyncTeX directions.
- Signed managed-runtime manifests, SHA-256 archive verification, staging installs, inventory, cleanup and nine platform/preset assets in the release workflow.
- Project hub, personal and built-in templates, runtime onboarding, settings overlay, Files/Search/Outline sidebar, draggable tabs, CodeMirror editor, Insert Shelf, Problems and a custom PDF.js viewer.
- Native macOS/Linux menus, platform shortcuts, external file drop, keyboard alternatives for drag actions, visible focus and reduced-motion support.

## Compatibility gate

The frontend is emitted for Safari 13, uses the PDF.js legacy build, and includes the small runtime polyfills needed by the pinned dependencies. This is necessary but not sufficient evidence for Catalina support.

Before LighTeX 1.1 can claim support, the compatibility spike must pass on a real Intel Mac running Catalina or an Intel Catalina VM hosted on Apple hardware. The spike must verify Unicode and IME input, undo, completion, line numbers, large documents, PDF rendering/search/zoom, drag-and-drop, dialogs and a complete TeX build. If reliable text input fails, Catalina remains a release blocker; the minimum version must not be raised silently.

The Linux matrix must pass on Ubuntu 22.04, Ubuntu 24.04 and Debian 12, under both X11 and Wayland. CI provides compile and package checks, while window integration, file dialogs, external drops, TeX discovery and desktop-menu behavior still require native smoke testing.

## Release policy

The v2 release and runtime workflows are manual and default to `publish: false`. They build two DMGs, one `amd64.deb`, and nine managed-runtime archives. Publishing requires an explicit future decision; this rewrite does not change the current README download links or the 1.0.0 GitHub Release.

Only the Ed25519 public key is embedded in the application. The private signing key is read from GitHub Secrets by the runtime release workflow and must never be committed.

## Current limitations

- Dark mode, Windows, Linux ARM, AppImage/Flatpak and automatic application updates are outside the 1.1 scope.
- LighTeX 1 settings and runtimes are not imported automatically.
- Local macOS builds validate the current architecture only. Intel DMG and Linux `.deb` artifacts are produced and tested by their matching runners.
