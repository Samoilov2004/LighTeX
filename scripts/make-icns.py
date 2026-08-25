#!/usr/bin/env python3
"""Pack modern PNG icon representations into an ICNS container."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


MEMBERS = (
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
)


def pack(iconset: Path, output: Path) -> None:
    chunks: list[bytes] = []

    for icon_type, filename in MEMBERS:
        png = (iconset / filename).read_bytes()
        chunks.append(icon_type + struct.pack(">I", len(png) + 8) + png)

    body = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-icns.py INPUT.iconset OUTPUT.icns")

    pack(Path(sys.argv[1]), Path(sys.argv[2]))
