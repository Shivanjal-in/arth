#!/usr/bin/env python3
"""Generate the Arth app icon for Android, iOS and the Play Store from one drawing.

Design (the app's neo-brutalist look): a marigold ground, a cream card with a
thick ink outline and a hard maroon shadow, and a big red Devanagari "अ" (for
अर्थ, "meaning") with an ink outline, over a highlighter bar like the one that
marks a word in the reader.

Run from app/:  python3 tool/make_icon.py     (needs Pillow)
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parents[1]
MARIGOLD = (245, 183, 38)
CARD = (247, 247, 242)
INK = (16, 32, 29)
RED = (179, 40, 28)
SHADOW = (103, 25, 18)
FONT = APP / "assets/google_fonts/Mukta-SemiBold.ttf"


def draw_icon(size: int, *, card: float = 0.595, background: bool = True, radius: float = 0.0) -> Image.Image:
    """card: the card's side as a fraction of the canvas (the shadow adds ~7.5%).
    radius: corner radius of the ground as a fraction (the legacy launcher shape)."""
    s = 4  # supersample for crisp edges
    w = size * s
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if background:
        if radius > 0:
            d.rounded_rectangle((0, 0, w - 1, w - 1), radius=int(w * radius), fill=MARIGOLD)
        else:
            d.rectangle((0, 0, w, w), fill=MARIGOLD)

    c = w * card  # card side
    off = c * 0.075  # shadow offset
    border = max(2, round(c * 0.045))
    x0 = (w - (c + off)) / 2
    y0 = (w - (c + off)) / 2
    # Hard shadow, then the outlined card.
    d.rectangle((x0 + off, y0 + off, x0 + off + c, y0 + off + c), fill=SHADOW)
    d.rectangle((x0, y0, x0 + c, y0 + c), fill=INK)
    d.rectangle((x0 + border, y0 + border, x0 + c - border, y0 + c - border), fill=CARD)

    # The glyph: fit its ink box to a share of the card, centred a little high.
    target = c * 0.60
    font = ImageFont.truetype(str(FONT), int(target))
    left, top, right, bottom = font.getbbox("अ")
    font = ImageFont.truetype(str(FONT), int(target * target / (bottom - top)))
    left, top, right, bottom = font.getbbox("अ")
    gw, gh = right - left, bottom - top
    stroke = max(1, round(c * 0.018))
    gx = x0 + (c - gw) / 2 - left
    gy = y0 + (c - gh) / 2 - top - c * 0.045

    # Highlighter bar behind the letter's lower half, with its own outline.
    bar_h = c * 0.12
    bar_y = gy + top + gh - bar_h * 0.15
    bx0, bx1 = x0 + c * 0.17, x0 + c * 0.83
    d.rectangle((bx0 - stroke, bar_y - stroke, bx1 + stroke, bar_y + bar_h + stroke), fill=INK)
    d.rectangle((bx0, bar_y, bx1, bar_y + bar_h), fill=MARIGOLD)

    d.text((gx, gy), "अ", font=font, fill=RED, stroke_width=stroke, stroke_fill=INK)
    return img.resize((size, size), Image.LANCZOS)


def save(img: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        bg = Image.new("RGB", img.size, MARIGOLD)
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
        save(draw_icon(px, card=0.42, background=False), res / f"mipmap-{name}/ic_launcher_foreground.png")
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
        f'    <color name="ic_launcher_background">#{MARIGOLD[0]:02X}{MARIGOLD[1]:02X}{MARIGOLD[2]:02X}</color>\n'
        "</resources>\n"
    )
    print(f"Android: legacy + adaptive icons → {res.relative_to(APP)}")


def playstore() -> None:
    """The 512x512 Play Console 'App icon' (32-bit PNG, full square: Play rounds it)."""
    out = APP / "tool/playstore-icon-512.png"
    draw_icon(512).save(out, "PNG", optimize=True)
    print(f"Play Store icon → {out.relative_to(APP)}")


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
    playstore()
    preview()
