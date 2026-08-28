#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
cd "${PROJECT_DIRECTORY}"

cargo test -p lightex-core
if ! git diff --exit-code -- crates/lightex-core/bindings; then
  echo "Generated TypeScript contracts are stale. Run: cargo test -p lightex-core" >&2
  exit 1
fi
