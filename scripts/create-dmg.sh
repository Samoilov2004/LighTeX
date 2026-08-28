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
BACKGROUND_PATH="${PROJECT_DIRECTORY}/Resources/DMGBackground.png"
DMGBUILD="${DMGBUILD_EXECUTABLE:-}"

if [[ ! -d "${APP_SOURCE}" ]]; then
    echo "Application bundle not found: ${APP_SOURCE}" >&2
    exit 1
fi
if [[ ! -f "${BACKGROUND_PATH}" ]]; then
    echo "DMG background not found: ${BACKGROUND_PATH}" >&2
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
