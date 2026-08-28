#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <minimal|standard|full> <macOs|linux> <arm64|x86_64> <runtime-version> <output-directory>" >&2
  exit 2
fi

VARIANT="$1"
PLATFORM="$2"
ARCHITECTURE="$3"
RUNTIME_VERSION="$4"
OUTPUT_DIRECTORY="$(mkdir -p "$5" && cd "$5" && pwd)"
SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
WORK_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "${WORK_DIRECTORY}"' EXIT

case "${VARIANT}" in
  minimal|standard|full) PROFILE="${SCRIPT_DIRECTORY}/../runtime/profiles/${VARIANT}.profile" ;;
  *) echo "Unknown runtime variant: ${VARIANT}" >&2; exit 2 ;;
esac
case "${PLATFORM}:${ARCHITECTURE}" in
  macOs:arm64|macOs:x86_64|linux:x86_64) ;;
  *) echo "Unsupported runtime target: ${PLATFORM}/${ARCHITECTURE}" >&2; exit 2 ;;
esac

INSTALLER_ARCHIVE="${WORK_DIRECTORY}/install-tl-unx.tar.gz"
curl --fail --location --retry 3 --output "${INSTALLER_ARCHIVE}" \
  "https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"
tar -xzf "${INSTALLER_ARCHIVE}" -C "${WORK_DIRECTORY}"
INSTALLER_DIRECTORY="$(find "${WORK_DIRECTORY}" -maxdepth 1 -type d -name 'install-tl-*' | head -n 1)"
PAYLOAD_DIRECTORY="${WORK_DIRECTORY}/payload"
TEXLIVE_DIRECTORY="${PAYLOAD_DIRECTORY}/runtime/texlive"

perl "${INSTALLER_DIRECTORY}/install-tl" --no-interaction --profile="${PROFILE}" --texdir="${TEXLIVE_DIRECTORY}"
BIN_DIRECTORY="$(find "${TEXLIVE_DIRECTORY}/bin" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
TLMGR="${BIN_DIRECTORY}/tlmgr"

if [[ "${VARIANT}" == "minimal" || "${VARIANT}" == "standard" ]]; then
  "${TLMGR}" install collection-luatex latexmk
fi
if [[ "${VARIANT}" == "standard" ]]; then
  "${TLMGR}" install collection-bibtexextra collection-fontsextra collection-fontsrecommended \
    collection-latexextra collection-latexrecommended collection-mathscience collection-pictures
fi

for tool in pdflatex xelatex lualatex latexmk synctex tlmgr; do
  test -x "${BIN_DIRECTORY}/${tool}" || { echo "Runtime is missing ${tool}" >&2; exit 1; }
done

if [[ "${PLATFORM}" == "macOs" ]]; then
  while IFS= read -r executable; do
    if file "${executable}" | grep -q 'Mach-O'; then
      codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "${executable}"
    fi
  done < <(find "${BIN_DIRECTORY}" -type f -perm -111)
fi

ARCHIVE="${OUTPUT_DIRECTORY}/lightex-runtime-${VARIANT}-${PLATFORM}-${ARCHITECTURE}-${RUNTIME_VERSION}.zip"
(cd "${PAYLOAD_DIRECTORY}" && zip -qry "${ARCHIVE}" runtime)
BIN_RELATIVE="runtime/texlive/bin/$(basename "${BIN_DIRECTORY}")"
python3 "${SCRIPT_DIRECTORY}/generate-runtime-metadata.py" \
  --variant "${VARIANT}" \
  --platform "${PLATFORM}" \
  --architecture "${ARCHITECTURE}" \
  --archive "${ARCHIVE}" \
  --payload "${PAYLOAD_DIRECTORY}" \
  --bin-relative "${BIN_RELATIVE}" \
  --output "${OUTPUT_DIRECTORY}/lightex-runtime-${VARIANT}-${PLATFORM}-${ARCHITECTURE}.metadata.json"
echo "Built ${ARCHIVE}"
