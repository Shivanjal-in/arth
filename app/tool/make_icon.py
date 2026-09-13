#!/usr/bin/env python3
"""Generate the Arth app icon for Android and iOS from one drawing.

Design: cream ground, a large serif Devanagari "अ" (for अर्थ, "meaning") in the
brick red of the reader UI, a thin underline like the tab indicator in the design.

Run from app/:  python3 tool/make_icon.py     (needs Pillow; macOS system fonts)
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parents[1]
CREAM = (243, 237, 227)
BRICK = (155, 58, 49)
FONT = "/System/Library/Fonts/Supplemental/ITFDevanagari.ttc"  # index 1 = Bold


def draw_icon(size: int, *, glyph_scale: float = 0.60, background: bool = True, radius: float = 0.0) -> Image.Image:
    """glyph_scale: glyph height as a fraction of the canvas. radius: corner radius as a fraction."""
    s = 4  # supersample for crisp edges
    w = size * s
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        if radius > 0:
            d.rounded_rectangle((0, 0, w - 1, w - 1), radius=int(w * radius), fill=CREAM)
        else:
            d.rectangle((0, 0, w, w), fill=CREAM)

    # Fit the glyph's ink box to glyph_scale of the canvas, then centre it optically
    # (a touch above centre so the underline sits in the lower third).
    target = w * glyph_scale
    font = ImageFont.truetype(FONT, int(target), index=1)
    left, top, right, bottom = font.getbbox("अ")
    ink_h = bottom - top
    font = ImageFont.truetype(FONT, int(target * target / ink_h), index=1)
    left, top, right, bottom = font.getbbox("अ")
    ink_w, ink_h = right - left, bottom - top
    x = (w - ink_w) / 2 - left
    y = (w - ink_h) / 2 - top - w * 0.04
    d.text((x, y), "अ", font=font, fill=BRICK)

    # Underline: same weight as the design's tab indicator, ~40% of the glyph width.
    ul_w = ink_w * 0.42
    ul_h = w * 0.018
    ul_y = y + top + ink_h + w * 0.075
    d.rounded_rectangle(((w - ul_w) / 2, ul_y, (w + ul_w) / 2, ul_y + ul_h), radius=ul_h / 2, fill=BRICK)

    return img.resize((size, size), Image.LANCZOS)


def save(img: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        bg = Image.new("RGB", img.size, CREAM)
        bg.paste(img, mask=img.split()[3])
        bg.save(path, "PNG", optimize=True)
    else:
        img.save(path, "PNG", optimize=True)


def ios() -> None:
    aset = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((aset / "Contents.json").read_text())
    master = draw_icon(1024)
    for entry in contents["images"]:
        pt = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = round(pt * scale)
        save(master.resize((px, px), Image.LANCZOS), aset / entry["filename"], opaque=True)  # iOS: no alpha
    print(f"iOS: {len(contents['images'])} sizes → {aset.relative_to(APP)}")


def android() -> None:
    res = APP / "android/app/src/main/res"
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    # Legacy launcher icon (pre-API 26): 48dp rounded square with transparency outside.
    for name, mult in densities.items():
        px = round(48 * mult)
        save(draw_icon(px, radius=0.18), res / f"mipmap-{name}/ic_launcher.png")
    # Adaptive icon (API 26+): 108dp canvas, content inside the central 66dp safe zone.
    for name, mult in densities.items():
        px = round(108 * mult)
        save(draw_icon(px, glyph_scale=0.40, background=False), res / f"mipmap-{name}/ic_launcher_foreground.png")
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">#{CREAM[0]:02X}{CREAM[1]:02X}{CREAM[2]:02X}</color>\n'
        "</resources>\n"
    )
    print(f"Android: legacy + adaptive icons → {res.relative_to(APP)}")


def preview() -> None:
    out = APP / "tool/icon-preview.png"
    sheet = Image.new("RGB", (1024 + 40 + 180 + 40 + 60 + 40, 1024), (255, 255, 255))
    sheet.paste(draw_icon(1024, radius=0.22), (0, 0))
    sheet.paste(draw_icon(180, radius=0.22), (1064, 0), draw_icon(180, radius=0.22))
    sheet.paste(draw_icon(60, radius=0.22), (1284, 0), draw_icon(60, radius=0.22))
    sheet.save(out)
    print(f"preview → {out.relative_to(APP)}")


if __name__ == "__main__":
    ios()
    android()
    preview()
