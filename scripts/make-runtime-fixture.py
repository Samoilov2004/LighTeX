#!/usr/bin/env python3
"""Create a tiny signed runtime fixture for local installer QA."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import zipfile


parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--private-key", type=Path, required=True)
parser.add_argument("--architecture", choices=("arm64", "x86_64"), required=True)
parser.add_argument("--proxy-tools-directory", type=Path)
args = parser.parse_args()

if args.output.exists():
    shutil.rmtree(args.output)
payload = args.output / "payload" / "runtime" / "bin"
payload.mkdir(parents=True)
tools = {}
for name in ("pdflatex", "xelatex", "lualatex", "latexmk", "synctex", "tlmgr"):
    executable = payload / name
    proxy = args.proxy_tools_directory / name if args.proxy_tools_directory else None
    if name != "tlmgr" and proxy and proxy.is_file():
        executable.write_text(
            "#!/bin/sh\n"
            # Keep the public symlink name (for example pdflatex -> pdftex).
            # TeX selects its format from argv[0], so resolving the symlink
            # would accidentally launch plain pdfTeX instead of LaTeX.
            f"exec {shlex.quote(str(proxy.absolute()))} \"$@\"\n"
        )
    elif name == "tlmgr":
        executable.write_text(
            "#!/bin/sh\n"
            "if [ \"${1:-}\" = \"search\" ]; then\n"
            "  echo 'lightex-demo-package:'\n"
            "  exit 0\n"
            "fi\n"
            "echo 'tlmgr demo fixture: no system packages were changed'\n"
        )
    else:
        executable.write_text(f"#!/bin/sh\necho '{name} fixture 1.0'\n")
    executable.chmod(0o755)
    tools[name] = f"runtime/bin/{name}"

archive = args.output / "runtime-standard.zip"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
    for item in sorted((args.output / "payload").rglob("*")):
        if item.is_file():
            info = zipfile.ZipInfo(item.relative_to(args.output / "payload").as_posix())
            info.external_attr = (item.stat().st_mode & 0xFFFF) << 16
            bundle.writestr(info, item.read_bytes())

digest = hashlib.sha256(archive.read_bytes()).hexdigest()
installed_size = sum(item.stat().st_size for item in payload.iterdir())
display_sizes = {
    "minimal": 680_000_000,
    "standard": 2_800_000_000,
    "full": 7_200_000_000,
}
manifest = {
    "schemaVersion": 1,
    "runtimeVersion": "fixture-1",
    "texLiveYear": 2026,
    "assets": [
        {
            "variant": variant,
            "architecture": args.architecture,
            "downloadURL": archive.resolve().as_uri(),
            "compressedSize": archive.stat().st_size,
            "displayCompressedSize": display_sizes[variant],
            "installedSize": installed_size,
            "sha256": digest,
            "tools": tools,
        }
        for variant in ("minimal", "standard", "full")
    ],
}
manifest_path = args.output / "runtime-manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
subprocess.run([
    "openssl", "pkeyutl", "-sign", "-rawin",
    "-inkey", str(args.private_key),
    "-in", str(manifest_path),
    "-out", str(args.output / "runtime-manifest.sig"),
], check=True)
print(args.output)
