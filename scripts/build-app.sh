#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="${PROJECT_DIR}/dist/LighTex.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ -d "${COMPATIBLE_SDK}" ]]; then
    export SDKROOT="${COMPATIBLE_SDK}"
else
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lightex-clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${CLANG_MODULE_CACHE_PATH}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"

swift build --disable-sandbox -c release --package-path "${PROJECT_DIR}"
BIN_DIR="$(swift build --disable-sandbox -c release --package-path "${PROJECT_DIR}" --show-bin-path)"

if [[ -d "${APP_DIR}" ]]; then
    /bin/rm -rf "${APP_DIR}"
fi

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
ditto "${BIN_DIR}/LighTex" "${MACOS_DIR}/LighTex"
ditto "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

if [[ -n "${RUNTIME_PUBLIC_KEY_BASE64:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :LighTexRuntimePublicKey ${RUNTIME_PUBLIC_KEY_BASE64}" "${CONTENTS_DIR}/Info.plist"
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_OPTIONS=()
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    SIGN_OPTIONS=(--options runtime --timestamp)
fi
codesign --force --deep --sign "${SIGN_IDENTITY}" "${SIGN_OPTIONS[@]}" "${APP_DIR}"
echo "Built ${APP_DIR}"
