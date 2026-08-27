#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def directory_size(path: Path) -> int:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("--variant", choices=("minimal", "standard", "full"), required=True)
parser.add_argument("--platform", choices=("macOs", "linux"), required=True)
parser.add_argument("--architecture", choices=("arm64", "x86_64"), required=True)
parser.add_argument("--archive", type=Path, required=True)
parser.add_argument("--payload", type=Path, required=True)
parser.add_argument("--bin-relative", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

metadata = {
    "variant": args.variant,
    "platform": args.platform,
    "architecture": args.architecture,
    "archiveName": args.archive.name,
    "compressedSize": args.archive.stat().st_size,
    "installedSize": directory_size(args.payload),
    "sha256": sha256(args.archive),
    "tools": {
        name: f"{args.bin_relative}/{name}"
        for name in ("pdflatex", "xelatex", "lualatex", "latexmk", "synctex", "tlmgr")
    },
}
args.output.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
