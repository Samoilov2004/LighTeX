#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--metadata-directory", type=Path, required=True)
parser.add_argument("--runtime-version", required=True)
parser.add_argument("--texlive-year", type=int, required=True)
parser.add_argument("--release-base-url", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()

assets = []
for path in sorted(args.metadata_directory.glob("*.metadata.json")):
    item = json.loads(path.read_text())
    archive_name = item.pop("archiveName")
    archive_parts = item.pop("archiveParts", [])
    if archive_parts:
        item["downloadParts"] = [
            {
                "downloadURL": f"{args.release_base_url.rstrip('/')}/{part['archiveName']}",
                "compressedSize": part["compressedSize"],
            }
            for part in archive_parts
        ]
    else:
        item["downloadURL"] = f"{args.release_base_url.rstrip('/')}/{archive_name}"
    assets.append(item)

if len(assets) != 6:
    raise SystemExit(f"Expected six runtime assets, found {len(assets)}")

manifest = {
    "schemaVersion": 1,
    "runtimeVersion": args.runtime_version,
    "texLiveYear": args.texlive_year,
    "assets": assets,
}
args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
