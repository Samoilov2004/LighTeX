#!/bin/zsh
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 <minimal|standard|full> <arm64|x86_64> <runtime-version> <output-directory>" >&2
    exit 2
fi

VARIANT="$1"
ARCHITECTURE="$2"
RUNTIME_VERSION="$3"
OUTPUT_DIRECTORY="${4:A}"
SCRIPT_DIRECTORY="${0:A:h}"
WORK_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "${WORK_DIRECTORY}"' EXIT

case "${VARIANT}" in
    minimal|standard|full) PROFILE="${SCRIPT_DIRECTORY:h}/runtime/profiles/${VARIANT}.profile" ;;
    *) echo "Unknown runtime variant: ${VARIANT}" >&2; exit 2 ;;
esac

mkdir -p "${OUTPUT_DIRECTORY}"
INSTALLER_ARCHIVE="${WORK_DIRECTORY}/install-tl-unx.tar.gz"
curl --fail --location --retry 3 \
    --output "${INSTALLER_ARCHIVE}" \
    "https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"
tar -xzf "${INSTALLER_ARCHIVE}" -C "${WORK_DIRECTORY}"
INSTALLER_DIRECTORY="$(find "${WORK_DIRECTORY}" -maxdepth 1 -type d -name 'install-tl-*' | head -n 1)"
PAYLOAD_DIRECTORY="${WORK_DIRECTORY}/payload/runtime"
TEXLIVE_DIRECTORY="${PAYLOAD_DIRECTORY}/texlive"

perl "${INSTALLER_DIRECTORY}/install-tl" \
    --no-interaction \
    --profile="${PROFILE}" \
    --texdir="${TEXLIVE_DIRECTORY}"

BIN_DIRECTORY="$(find "${TEXLIVE_DIRECTORY}/bin" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
TLMGR="${BIN_DIRECTORY}/tlmgr"

if [[ "${VARIANT}" == "minimal" || "${VARIANT}" == "standard" ]]; then
    "${TLMGR}" install collection-luatex latexmk
fi

if [[ "${VARIANT}" == "standard" ]]; then
    "${TLMGR}" install \
        collection-bibtexextra \
        collection-fontsextra \
        collection-fontsrecommended \
        collection-latexextra \
        collection-latexrecommended \
        collection-mathscience \
        collection-pictures
fi

for tool in pdflatex xelatex lualatex latexmk synctex tlmgr; do
    if [[ ! -x "${BIN_DIRECTORY}/${tool}" ]]; then
        echo "Runtime is missing required tool ${tool}" >&2
        exit 1
    fi
done

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    while IFS= read -r executable; do
        if file "${executable}" | grep -q 'Mach-O'; then
            codesign --force --options runtime --timestamp --sign "${CODE_SIGN_IDENTITY}" "${executable}"
        fi
    done < <(find "${BIN_DIRECTORY}" -type f -perm -111)
fi

ARCHIVE="${OUTPUT_DIRECTORY}/lightex-runtime-${VARIANT}-${ARCHITECTURE}-${RUNTIME_VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "${PAYLOAD_DIRECTORY}" "${ARCHIVE}"
BIN_RELATIVE="runtime/texlive/bin/${BIN_DIRECTORY:t}"
python3 "${SCRIPT_DIRECTORY}/generate-runtime-metadata.py" \
    --variant "${VARIANT}" \
    --architecture "${ARCHITECTURE}" \
    --archive "${ARCHIVE}" \
    --payload "${PAYLOAD_DIRECTORY}" \
    --bin-relative "${BIN_RELATIVE}" \
    --output "${OUTPUT_DIRECTORY}/lightex-runtime-${VARIANT}-${ARCHITECTURE}.metadata.json"

echo "Built ${ARCHIVE}"
