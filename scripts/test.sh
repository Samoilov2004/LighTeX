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

zsh -n "${PROJECT_DIR}/scripts/create-dmg.sh"
python3 -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); compile(path.read_text(), str(path), "exec")' \
    "${PROJECT_DIR}/scripts/dmg-settings.py"

HAS_XCTEST=1
if ! xcrun --find xctest >/dev/null 2>&1; then
    HAS_XCTEST=0
    echo "note: xctest is unavailable; SwiftPM will compile the test bundle but cannot execute it on this machine."
    if [[ "${LIGHTEX_REQUIRE_TEST_EXECUTION:-0}" == "1" || "${CI:-false}" == "true" ]]; then
        echo "error: this environment requires tests to execute, but xctest is unavailable." >&2
        exit 1
    fi
fi

swift test --quiet --disable-sandbox --package-path "${PROJECT_DIR}"

if [[ "${LIGHTEX_REQUIRE_TEST_EXECUTION:-0}" == "1" && "${HAS_XCTEST}" != "1" ]]; then
    echo "error: tests were compiled but not executed." >&2
    exit 1
fi
