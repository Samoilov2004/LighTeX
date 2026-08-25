#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
parser.add_argument("--release-limit", type=int, default=2_000_000_000)
parser.add_argument("--part-size", type=int, default=1_900_000_000)
args = parser.parse_args()

if args.part_size <= 0 or args.part_size >= args.release_limit:
    raise SystemExit("Part size must be positive and below the release limit")

for metadata_path in sorted(args.directory.glob("lightex-runtime-full-*.metadata.json")):
    metadata = json.loads(metadata_path.read_text())
    archive = args.directory / metadata["archiveName"]
    if not archive.exists() or archive.stat().st_size < args.release_limit:
        continue

    parts = []
    with archive.open("rb") as source:
        index = 0
        while chunk := source.read(args.part_size):
            part = archive.with_name(f"{archive.name}.part-{index:02d}")
            part.write_bytes(chunk)
            parts.append({"archiveName": part.name, "compressedSize": len(chunk)})
            index += 1

    if sum(part["compressedSize"] for part in parts) != metadata["compressedSize"]:
        raise SystemExit(f"Multipart size mismatch for {archive.name}")
    metadata["archiveParts"] = parts
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    archive.unlink()
    print(f"Split {archive.name} into {len(parts)} release assets")
