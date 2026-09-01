#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
SOURCE_ICON="${1:-${PROJECT_DIRECTORY}/Resources/AppIcon.png}"
ICONSET_DIRECTORY="${PROJECT_DIRECTORY}/Resources/AppIcon.iconset"
OUTPUT_ICON="${PROJECT_DIRECTORY}/Resources/AppIcon.icns"
TAURI_ICON="${PROJECT_DIRECTORY}/apps/desktop/src-tauri/icons/icon.png"
FRONTEND_ICON="${PROJECT_DIRECTORY}/apps/desktop/src/assets/AppIcon128.png"

if [[ ! -f "${SOURCE_ICON}" ]]; then
    echo "Icon source not found: ${SOURCE_ICON}" >&2
    exit 1
fi

mkdir -p "${ICONSET_DIRECTORY}"

resize_icon() {
    local pixels="$1"
    local filename="$2"
    sips -s format png -z "${pixels}" "${pixels}" "${SOURCE_ICON}" \
        --out "${ICONSET_DIRECTORY}/${filename}" >/dev/null
}

resize_icon 16 icon_16x16.png
resize_icon 32 icon_16x16@2x.png
resize_icon 32 icon_32x32.png
resize_icon 64 icon_32x32@2x.png
resize_icon 128 icon_128x128.png
resize_icon 256 icon_128x128@2x.png
resize_icon 256 icon_256x256.png
resize_icon 512 icon_256x256@2x.png
resize_icon 512 icon_512x512.png
resize_icon 1024 icon_512x512@2x.png

python3 "${SCRIPT_DIRECTORY}/make-icns.py" "${ICONSET_DIRECTORY}" "${OUTPUT_ICON}"
sips -s format png -z 1024 1024 "${SOURCE_ICON}" --out "${TAURI_ICON}" >/dev/null
sips -s format png -z 128 128 "${SOURCE_ICON}" --out "${FRONTEND_ICON}" >/dev/null

echo "Updated the macOS, Linux, README, and in-app icon assets from ${SOURCE_ICON}"
