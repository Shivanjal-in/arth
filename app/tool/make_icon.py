"""Generate the Arth app icon for Android, iOS and the Play Store from one picture.

The artwork is tool/icon-source.png: a purple rounded square (the Devanagari
"अ" over a crescent, three cards and a circle of readers) on a cream ground.
It is cropped to the square, its cream corners are filled in with the
surrounding purple, and the result is scaled to every size the stores want.

Run from app/:  python3 tool/make_icon.py     (needs Pillow and numpy)
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

APP = Path(__file__).resolve().parents[1]
SOURCE = APP / "tool/icon-source.png"
CROP = (48, 31, 709, 679)  # the purple square within the source picture
INSET = 24  # px of the 1024 master trimmed off every edge
SCALE = 0.95  # how much of the canvas the trimmed artwork fills
RADIUS = 150  # corner radius of the source's rounded square, in master px


@lru_cache(maxsize=1)
def master() -> Image.Image:
    """The artwork as a 1024px opaque square. The source's cream corners and
    pale rim are trimmed off, the rest is set a little smaller on a purple
    field that fades between the colours at its four corners."""
    src = Image.open(SOURCE).convert("RGB").crop(CROP).resize((1024, 1024), Image.LANCZOS)
    a = np.array(src).astype(float)

    def purple(x: int, y: int) -> np.ndarray:
        return a[y - 12 : y + 12, x - 12 : x + 12].reshape(-1, 3).mean(axis=0)

    near, far = 90, 1024 - 90
    tl, tr, bl, br = purple(near, near), purple(far, near), purple(near, far), purple(far, far)
    u = np.linspace(0, 1, 1024)[None, :, None]
    v = np.linspace(0, 1, 1024)[:, None, None]
    field = (tl * (1 - u) + tr * u) * (1 - v) + (bl * (1 - u) + br * u) * v

    k = 2
    art = src.crop((INSET, INSET, 1024 - INSET, 1024 - INSET))
    side = round(1024 * SCALE)
    art = art.resize((side, side), Image.LANCZOS)
    mask = Image.new("L", (side * k, side * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side * k - 1, side * k - 1), radius=round((RADIUS - INSET) * side / (1024 - 2 * INSET)) * k, fill=255)
    mask = mask.resize((side, side), Image.LANCZOS).filter(ImageFilter.GaussianBlur(5))
    out = Image.fromarray(field.round().astype("uint8"), "RGB")
    off = (1024 - side) // 2
    out.paste(art, (off, off), mask)
    return out


@lru_cache(maxsize=1)
def ground() -> tuple[int, int, int]:
    """The purple at the icon's edge: the adaptive icon's background colour."""
    a = np.array(master()).astype(float)
    edge = np.concatenate([a[8:40, 100:924].reshape(-1, 3), a[984:1016, 100:924].reshape(-1, 3)])
    return tuple(int(v) for v in edge.mean(axis=0))


def draw_icon(size: int, *, card: float = 1.0, background: bool = True, radius: float = 0.0) -> Image.Image:
    """card: the artwork's side as a fraction of the canvas (adaptive icons keep
    it inside the central safe zone). radius: corner radius as a fraction (the
    legacy launcher shape)."""
    art = master().resize((round(size * card), round(size * card)), Image.LANCZOS).convert("RGBA")
    img = Image.new("RGBA", (size, size), ground() + (255,) if background else (0, 0, 0, 0))
    off = (size - art.width) // 2
    img.paste(art, (off, off))
    if radius > 0:
        s = 4
        mask = Image.new("L", (size * s, size * s), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * s - 1, size * s - 1), radius=int(size * s * radius), fill=255)
        img.putalpha(mask.resize((size, size), Image.LANCZOS))
    return img


def save(img: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        bg = Image.new("RGB", img.size, ground())
        bg.paste(img, mask=img.split()[3])
        bg.save(path, "PNG", optimize=True)
    else:
        img.save(path, "PNG", optimize=True)


def ios() -> None:
    aset = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((aset / "Contents.json").read_text())
    art = master().convert("RGBA")
    for entry in contents["images"]:
        pt = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = round(pt * scale)
        save(art.resize((px, px), Image.LANCZOS), aset / entry["filename"], opaque=True)  # iOS: no alpha
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
        save(draw_icon(px, card=0.66, background=False), res / f"mipmap-{name}/ic_launcher_foreground.png")
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
        f'    <color name="ic_launcher_background">#{ground()[0]:02X}{ground()[1]:02X}{ground()[2]:02X}</color>\n'
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
