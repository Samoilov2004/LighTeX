#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"

if [[ -d "${COMPATIBLE_SDK}" ]]; then
    export SDKROOT="${COMPATIBLE_SDK}"
fi

swift run --package-path "${PROJECT_DIR}" -- "$@"
