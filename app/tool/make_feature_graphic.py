#!/usr/bin/env python3
"""Generate the Play Store feature graphic (1024x500) for Arth.

Drawn from the app itself, in its neo-brutalist look: sage paper, the app icon
as an outlined tile on a hard shadow, a condensed bold title, and a mock of the
in-app word card (ink outline, hard maroon shadow, the word highlighted).

Run from app/:  python3 tool/make_feature_graphic.py     (needs Pillow)
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from make_icon import draw_icon  # noqa: E402

FONTS = Path("assets/google_fonts")

PAPER = (228, 229, 218)  # ArthColors.light.paper
CARD = (247, 247, 242)   # ArthColors.light.card
INK = (16, 32, 29)       # ArthColors.light.ink
INK_MUTED = (82, 99, 95) # ArthColors.light.inkMuted
ACCENT = (179, 40, 28)   # ArthColors.light.accent
MARIGOLD = (245, 183, 38)
SHADOW = (103, 25, 18)   # the hard shadow

W, H = 1024, 500
S = 3  # supersample


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def measure(d, text, f):
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    return r - l, b - t, l, t


def wrap(d, text, f, max_w):
    lines, line = [], ""
    for word in text.split(" "):
        trial = (line + " " + word).strip()
        if measure(d, trial, f)[0] > max_w and line:
            lines.append(line)
            line = word
        else:
            line = trial
    lines.append(line)
    return lines


def boxed(d, x0, y0, x1, y1, *, fill, border, shadow, off):
    """An outlined box on a hard shadow."""
    d.rectangle((x0 + off, y0 + off, x1 + off, y1 + off), fill=SHADOW)
    d.rectangle((x0, y0, x1, y1), fill=INK)
    d.rectangle((x0 + border, y0 + border, x1 - border, y1 - border), fill=fill)


def make():
    w, h = W * S, H * S
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)

    # --- icon tile ---
    tile = 330 * S
    tx, ty = 70 * S, (h - tile) // 2 - 8 * S
    off = 16 * S
    d.rectangle((tx + off, ty + off, tx + tile + off, ty + tile + off), fill=SHADOW)
    img.paste(draw_icon(tile).convert("RGB"), (tx, ty))
    d.rectangle((tx, ty, tx + tile, ty + tile), outline=INK, width=6 * S)

    rx = tx + tile + off + 52 * S
    max_w = w - rx - 56 * S

    f_title = font("BarlowSemiCondensed-ExtraBold.ttf", 150 * S)
    f_tag = font("Inter-SemiBold.ttf", 34 * S)
    f_label = font("MartianMono-Medium.ttf", 17 * S)
    f_en = font("Inter-Bold.ttf", 40 * S)
    f_hi = font("Mukta-SemiBold.ttf", 34 * S)
    f_gloss = font("Inter-Medium.ttf", 21 * S)

    tag_lines = ["Read English books,", "meaning in Hindi"]

    title_h, title_top = measure(d, "Arth", f_title)[1], measure(d, "Arth", f_title)[3]
    gap_title_tag = 8 * S
    tag_line_h, tag_gap = measure(d, "Ag", f_tag)[1], 8 * S
    tag_block = len(tag_lines) * tag_line_h + (len(tag_lines) - 1) * tag_gap
    gap_tag_card = 30 * S
    pad_v = 20 * S
    label_h = measure(d, "WORD", f_label)[1]
    en_h = measure(d, "solitude", f_en)[1]
    gloss_h = measure(d, "being alone, often by choice", f_gloss)[1]
    inner = 10 * S
    card_h = pad_v * 2 + label_h + inner + en_h + inner + gloss_h
    card_w = max_w - 14 * S  # leave room for the shadow

    total = title_h + gap_title_tag + tag_block + gap_tag_card + card_h
    y = (h - total) / 2 - title_top - 6 * S

    d.text((rx, y), "Arth", font=f_title, fill=INK)
    y += title_h + title_top + gap_title_tag
    for line in tag_lines:
        d.text((rx, y), line, font=f_tag, fill=INK_MUTED)
        y += tag_line_h + tag_gap
    y += gap_tag_card - tag_gap

    boxed(d, rx, y, rx + card_w, y + card_h, fill=CARD, border=4 * S, shadow=SHADOW, off=12 * S)
    cx, cy = rx + 26 * S, y + pad_v
    d.text((cx, cy), "WORD", font=f_label, fill=ACCENT)
    cy += label_h + inner

    en_w, _, en_left, en_top = measure(d, "solitude", f_en)
    # the tapped word, highlighted like in the reader
    d.rectangle((cx - 6 * S, cy + en_top - 3 * S, cx + en_w + 8 * S, cy + en_top + en_h + 5 * S), fill=MARIGOLD)
    d.text((cx, cy), "solitude", font=f_en, fill=INK)
    hi_top = measure(d, "एकांत", f_hi)[3]
    d.text((cx + en_w + 28 * S, cy + en_top - hi_top + 2 * S), "एकांत", font=f_hi, fill=ACCENT)
    cy += en_h + inner + 6 * S
    d.text((cx, cy), "being alone, often by choice", font=f_gloss, fill=INK_MUTED)

    img = img.resize((W, H), Image.LANCZOS)
    out = Path("tool/feature-graphic.png")
    img.save(out, "PNG", optimize=True)
    print(f"feature graphic -> {out} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    make()
