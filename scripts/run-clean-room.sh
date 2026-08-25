#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
SOURCE_APP="${PROJECT_DIRECTORY}/dist/LighTex.app"
MODE="fixture"

if [[ "${1:-}" == "--release" ]]; then
    MODE="release"
    shift
elif [[ "${1:-}" == "--fixture" ]]; then
    shift
fi

if [[ ! -x "${SOURCE_APP}/Contents/MacOS/LighTex" ]]; then
    "${SCRIPT_DIRECTORY}/build-app.sh"
fi

CLEAN_ROOM_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/lightex-clean-room.XXXXXX")"
DEFAULTS_SUITE="app.lightex.clean-room.$(date +%s).$$"
BUNDLE_IDENTIFIER="${DEFAULTS_SUITE}.application"
RUNTIME_DIRECTORY="${CLEAN_ROOM_DIRECTORY}/Runtimes"
mkdir -p "${RUNTIME_DIRECTORY}"

# A unique bundle identifier prevents AppKit from reopening a regular LighTex
# process that was already running without the clean-room configuration.
CLEAN_ROOM_APP="${CLEAN_ROOM_DIRECTORY}/LighTex Clean Room.app"
cp -R "${SOURCE_APP}" "${CLEAN_ROOM_APP}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_IDENTIFIER}" "${CLEAN_ROOM_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName LighTex Clean Room" "${CLEAN_ROOM_APP}/Contents/Info.plist"
codesign --force --deep --sign - "${CLEAN_ROOM_APP}" >/dev/null
APP_EXECUTABLE="${CLEAN_ROOM_APP}/Contents/MacOS/LighTex"

ENVIRONMENT=(
    "LIGHTEX_DEFAULTS_SUITE=${DEFAULTS_SUITE}"
    "LIGHTEX_RUNTIME_BASE_DIRECTORY=${RUNTIME_DIRECTORY}"
    "LIGHTEX_BUILD_CACHE_DIRECTORY=${CLEAN_ROOM_DIRECTORY}/Builds"
    "LIGHTEX_SIMULATE_NO_SYSTEM_TEX=1"
)

if [[ "${MODE}" == "fixture" ]]; then
    PRIVATE_KEY="${CLEAN_ROOM_DIRECTORY}/runtime-signing-key.pem"
    FIXTURE_DIRECTORY="${CLEAN_ROOM_DIRECTORY}/fixture"
    FIXTURE_ARGUMENTS=(
        --output "${FIXTURE_DIRECTORY}"
        --private-key "${PRIVATE_KEY}"
        --architecture "$(uname -m)"
    )
    if [[ -d "/Library/TeX/texbin" ]]; then
        FIXTURE_ARGUMENTS+=(--proxy-tools-directory "/Library/TeX/texbin")
    fi
    openssl genpkey -algorithm ED25519 -out "${PRIVATE_KEY}" >/dev/null 2>&1
    PUBLIC_KEY_BASE64="$(openssl pkey -in "${PRIVATE_KEY}" -pubout -outform DER | tail -c 32 | base64)"
    python3 "${SCRIPT_DIRECTORY}/make-runtime-fixture.py" "${FIXTURE_ARGUMENTS[@]}" >/dev/null
    ENVIRONMENT+=(
        "LIGHTEX_RUNTIME_MANIFEST_URL=file://${FIXTURE_DIRECTORY}/runtime-manifest.json"
        "LIGHTEX_RUNTIME_SIGNATURE_URL=file://${FIXTURE_DIRECTORY}/runtime-manifest.sig"
        "LIGHTEX_RUNTIME_PUBLIC_KEY_BASE64=${PUBLIC_KEY_BASE64}"
        "LIGHTEX_RUNTIME_DEMO_DOWNLOAD_SECONDS=${LIGHTEX_RUNTIME_DEMO_DOWNLOAD_SECONDS:-4}"
    )
    if [[ -d "/Library/TeX/texbin" ]]; then
        echo "Clean-room demo: isolated wrappers can compile projects; demo tlmgr never modifies system TeX."
    else
        echo "Clean-room UI demo: no local compiler was found, so the signed fixture cannot compile projects."
    fi
else
    echo "Clean-room release mode: managed runtime assets will be downloaded from GitHub Releases."
fi

echo "Isolated data: ${CLEAN_ROOM_DIRECTORY}"
echo "Isolated preferences: ${DEFAULTS_SUITE}"
env "${ENVIRONMENT[@]}" "${APP_EXECUTABLE}" "$@"

echo "The clean-room data was kept at ${CLEAN_ROOM_DIRECTORY} for inspection."
echo "Remove it manually when you no longer need it."
