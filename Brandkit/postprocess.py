"""Generate macOS App Icon size variants from app_icon_master.png.

Reads:  Brandkit/output/app_icon_master.png  (1024x1024)
Writes: Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png
        — 10 files: 16, 32, 32, 64, 128, 256, 256, 512, 512, 1024 px
        — names follow Apple's @1x / @2x convention
        Plus a fresh Contents.json with filename references.

Uses macOS-only `sips`. No PIL dependency.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(__file__).resolve().parent / "output" / "app_icon_master.png"
DST = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

# (logical_size, scale, pixel_size, filename)
VARIANTS: list[tuple[str, str, int, str]] = [
    ("16x16",    "1x",    16, "icon_16x16.png"),
    ("16x16",    "2x",    32, "icon_16x16@2x.png"),
    ("32x32",    "1x",    32, "icon_32x32.png"),
    ("32x32",    "2x",    64, "icon_32x32@2x.png"),
    ("128x128",  "1x",   128, "icon_128x128.png"),
    ("128x128",  "2x",   256, "icon_128x128@2x.png"),
    ("256x256",  "1x",   256, "icon_256x256.png"),
    ("256x256",  "2x",   512, "icon_256x256@2x.png"),
    ("512x512",  "1x",   512, "icon_512x512.png"),
    ("512x512",  "2x",  1024, "icon_512x512@2x.png"),
]


def main() -> int:
    if not SRC.exists():
        print(f"ERROR: {SRC} not found.", file=sys.stderr)
        print("Run `python gen.py app_icon` first.", file=sys.stderr)
        return 1

    if not shutil.which("sips"):
        print("ERROR: `sips` not found (macOS-only tool).", file=sys.stderr)
        return 1

    DST.mkdir(parents=True, exist_ok=True)

    for _, _, px, name in VARIANTS:
        out = DST / name
        shutil.copyfile(SRC, out)
        subprocess.run(
            ["sips", "-Z", str(px), str(out)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(f"  {name:32} {px}x{px}")

    contents = {
        "images": [
            {"idiom": "mac", "size": size, "scale": scale, "filename": name}
            for size, scale, _, name in VARIANTS
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (DST / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    print()
    print(f"wrote {len(VARIANTS)} icon variants to: {DST.relative_to(ROOT)}")
    print(f"wrote Contents.json with {len(VARIANTS)} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
