#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"

if [[ -d "${COMPATIBLE_SDK}" ]]; then
    export SDKROOT="${COMPATIBLE_SDK}"
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lightex-clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${CLANG_MODULE_CACHE_PATH}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"

if ! xcrun --find xctest >/dev/null 2>&1; then
    echo "note: xctest is unavailable; SwiftPM will compile the test bundle but cannot execute it on this machine."
fi

swift test --quiet --disable-sandbox --package-path "${PROJECT_DIR}"
