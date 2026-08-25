#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <LighTex.app> <output.dmg> [volume-name]" >&2
    exit 2
fi

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
APP_SOURCE="${1:A}"
OUTPUT_DMG="${2:A}"
VOLUME_NAME="${3:-LighTex}"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/lightex-dmg.XXXXXX")"
BACKGROUND_PATH="${WORK_DIRECTORY}/background.png"
DMGBUILD="${DMGBUILD_EXECUTABLE:-}"

cleanup() {
    rm -rf "${WORK_DIRECTORY}"
}
trap cleanup EXIT INT TERM

if [[ ! -d "${APP_SOURCE}" ]]; then
    echo "Application bundle not found: ${APP_SOURCE}" >&2
    exit 1
fi

if [[ -z "${DMGBUILD}" ]]; then
    DMGBUILD="$(command -v dmgbuild || true)"
fi
if [[ -z "${DMGBUILD}" || ! -x "${DMGBUILD}" ]]; then
    echo "dmgbuild is required to create the release image." >&2
    exit 1
fi

mkdir -p "${OUTPUT_DMG:h}"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ -d "${COMPATIBLE_SDK}" ]]; then
    SDK_ROOT="${COMPATIBLE_SDK}"
else
    SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi
MODULE_CACHE="${WORK_DIRECTORY}/module-cache"
mkdir -p "${MODULE_CACHE}"
env \
    SDKROOT="${SDK_ROOT}" \
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" \
    SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE}" \
    swift "${SCRIPT_DIRECTORY}/generate-dmg-background.swift" \
    "${BACKGROUND_PATH}"

if [[ -e "${OUTPUT_DMG}" ]]; then
    rm -f "${OUTPUT_DMG}"
fi
"${DMGBUILD}" \
    -s "${SCRIPT_DIRECTORY}/dmg-settings.py" \
    -D "app=${APP_SOURCE}" \
    -D "background=${BACKGROUND_PATH}" \
    -D "volume_icon=${PROJECT_DIRECTORY}/Resources/AppIcon.icns" \
    "${VOLUME_NAME}" \
    "${OUTPUT_DMG}"

echo "Built ${OUTPUT_DMG}"
