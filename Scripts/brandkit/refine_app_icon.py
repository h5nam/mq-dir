"""Tighten app_icon_master.png so the squircle design fills the canvas.

The AI-generated master commonly arrives as a small squircle floating on a
solid black 1024x1024 background. macOS Dock renders the PNG verbatim, so
that black background shows up as a hard square frame around the icon.

This pass:
  1. Backs up the original to app_icon_master_original.png (once).
  2. Detects the squircle design's bounding box by ignoring near-black pixels.
  3. Crops to a centered square covering that bbox plus a small safety margin.
  4. Resizes back to 1024x1024.
  5. Applies an Apple-style rounded-rectangle alpha mask so the corners are
     clean transparent rather than residual dark edges.
  6. Overwrites app_icon_master.png in place. Run postprocess.py afterwards.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
SRC = HERE / "output" / "app_icon_master.png"
BACKUP = HERE / "output" / "app_icon_master_original.png"

CANVAS = 1024
# Apple Big Sur+ continuous-curvature squircle approximated as a rounded
# rectangle with corner radius ~22.37% of the canvas edge.
CORNER_RADIUS = int(CANVAS * 0.2237)
# Add a tiny safety margin around the detected design so anti-aliased glass
# borders aren't clipped.
MARGIN_FRAC = 0.01
# Pixels whose max RGB channel is at or below this are treated as background.
BG_THRESHOLD = 30


def detect_design_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    gray = im.convert("L")
    binarized = gray.point(lambda v: 255 if v > BG_THRESHOLD else 0, mode="1")
    bbox = binarized.getbbox()
    if bbox is None:
        raise SystemExit("ERROR: master is uniformly dark; nothing to crop")
    left, top, right, bottom = bbox
    return left, top, right - 1, bottom - 1


def square_crop_with_margin(im: Image.Image, bbox: tuple[int, int, int, int]) -> Image.Image:
    left, top, right, bottom = bbox
    w = right - left + 1
    h = bottom - top + 1
    side = max(w, h)
    margin = int(side * MARGIN_FRAC)
    side += margin * 2
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    half = side // 2
    iw, ih = im.size
    cl = max(0, min(iw - side, cx - half))
    ct = max(0, min(ih - side, cy - half))
    return im.crop((cl, ct, cl + side, ct + side))


def squircle_mask(canvas: int, radius: int) -> Image.Image:
    m = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1), radius=radius, fill=255
    )
    return m


# Sharp luma cutoff: pixels darker than CUTOFF_LUMA become fully transparent,
# everything brighter stays fully opaque. A graduated fade leaves a translucent
# grey rim that reads as a frame against the Dock backdrop; a binary cutoff
# gives a clean squircle silhouette while preserving interior glass shading.
CUTOFF_LUMA = 30


def luminance_alpha(im: Image.Image) -> Image.Image:
    gray = im.convert("L")
    return gray.point(lambda v: 255 if v >= CUTOFF_LUMA else 0)


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"ERROR: {SRC} not found. Run gen.py app_icon first.")

    if not BACKUP.exists():
        shutil.copyfile(SRC, BACKUP)
        print(f"backup: {BACKUP.name}")

    src = Image.open(BACKUP).convert("RGB")
    bbox = detect_design_bbox(src)
    cropped = square_crop_with_margin(src, bbox)
    fitted = cropped.resize((CANVAS, CANVAS), Image.LANCZOS).convert("RGBA")
    # Combine luma-based alpha with the squircle outline. Darker(a, b) keeps
    # the more transparent value at every pixel: dark rim fades out, plus
    # the squircle still trims the corners cleanly.
    final_alpha = ImageChops.darker(
        luminance_alpha(fitted),
        squircle_mask(CANVAS, CORNER_RADIUS),
    )
    fitted.putalpha(final_alpha)
    fitted.save(SRC, format="PNG")
    print(
        f"refined: {SRC.name} "
        f"(crop {bbox} → {cropped.size[0]}px square → {CANVAS}x{CANVAS}, "
        f"squircle radius {CORNER_RADIUS}px, "
        f"luma cutoff {CUTOFF_LUMA})"
    )
    print("next: python3 Brandkit/postprocess.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
