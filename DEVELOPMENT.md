# LighTex development

LighTex 1.1 is a Tauri 2 application with a Rust core and a React/TypeScript interface.

## Requirements

- Rust stable
- Node.js 22
- pnpm 11
- macOS: Xcode Command Line Tools
- Linux: the Tauri WebKitGTK development packages listed in `.github/workflows/ci.yml`
- A local TeX installation is optional; the editor can use a managed runtime

## Run from source

```bash
pnpm install --frozen-lockfile
pnpm dev
```

Run all Rust tests, React tests, TypeScript checks, and the production frontend build:

```bash
pnpm check
```

## Native packages

Build the macOS application on a Mac:

```bash
pnpm --dir apps/desktop tauri build --bundles app
```

Build the Debian package on Ubuntu or Debian:

```bash
pnpm --dir apps/desktop tauri build --bundles deb
```

The release workflow builds on native runners rather than cross-compiling:

- Apple Silicon DMG on `macos-15`;
- Intel DMG on `macos-15-intel`;
- `amd64.deb` on Ubuntu 22.04.

The macOS jobs ad-hoc sign the application and use `scripts/create-dmg.sh` to create the drag-to-Applications image. Public builds are not Developer ID signed or notarized yet.

## Release workflow

`.github/workflows/release.yml` accepts a semantic version and creates the three stable asset names used by the README:

- `LighTex-macOS-Apple-Silicon.dmg`
- `LighTex-macOS-Intel.dmg`
- `LighTex-Linux-amd64.deb`

Publishing is disabled by default and is accepted only when the workflow runs from `main`. After all package jobs pass, the publish job creates or updates `v<version>`, uploads checksums, and marks it as the latest release.

## Managed runtimes

`scripts/build-runtime.sh` installs a portable TeX Live tree from the checked-in profile and produces an archive plus metadata. `.github/workflows/runtime-release.yml` builds Minimal, Standard, and Full for:

- macOS arm64;
- macOS x86_64;
- Linux x86_64.

The workflow creates a nine-asset schema-v2 manifest, splits archives that exceed the GitHub asset limit, signs the manifest with Ed25519, and publishes `runtime-v2-latest` only after explicit approval.

Required GitHub Actions secret:

- `RUNTIME_SIGNING_PRIVATE_KEY_BASE64`

Only the matching public key is embedded in the Rust core. Never commit private keys, certificates, `.env` files, provisioning profiles, or access tokens.

## Repository layout

```text
apps/desktop          Tauri shell and React/TypeScript interface
crates/lightex-core   Files, builds, SyncTeX, runtime, templates, and settings
runtime/profiles      Reproducible TeX Live presets
scripts               Packaging and managed-runtime tooling
DemoProjects          A multi-file mathematical sample project
```
