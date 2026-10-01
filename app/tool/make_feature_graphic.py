#!/usr/bin/env python3
"""Generate the Play Store feature graphic (1024x500) for Arth.

Reuses the app's own design tokens (light theme) and the app icon's Devanagari
"अ" mark, plus a small mock of the in-app word card, so the graphic is drawn
from the product itself rather than generic stock design.

Run from app/:  python3 tool/make_feature_graphic.py     (needs Pillow; macOS system fonts)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FONTS = Path("assets/google_fonts")

PAPER = (244, 238, 227)      # ArthColors.light.paper
CARD = (252, 249, 242)       # ArthColors.light.card
INK = (27, 34, 51)           # ArthColors.light.ink
INK_MUTED = (107, 113, 128)  # ArthColors.light.inkMuted
ACCENT = (163, 39, 31)       # ArthColors.light.accent
RULE = (220, 210, 193)       # ArthColors.light.rule
BRICK = (155, 58, 49)        # icon glyph colour (tool/make_icon.py)
CREAM = (243, 237, 227)      # icon tile background

W, H = 1024, 500
S = 4  # supersample


def font(path, size):
    return ImageFont.truetype(str(FONTS / path), size)


def devanagari_font(size):
    # The अ glyph itself (no conjuncts/matras) renders fine without shaping.
    return ImageFont.truetype("/System/Library/Fonts/Supplemental/ITFDevanagari.ttc", size, index=1)


def measure(draw, text, f):
    l, t, r, b = draw.textbbox((0, 0), text, font=f)
    return r - l, b - t, l, t


def wrap(draw, text, f, max_w):
    words, lines, line = text.split(" "), [], ""
    for word in words:
        trial = (line + " " + word).strip()
        tw, *_ = measure(draw, trial, f)
        if tw > max_w and line:
            lines.append(line)
            line = word
        else:
            line = trial
    lines.append(line)
    return lines


def icon_tile(d, tx, ty, tile):
    d.rounded_rectangle((tx, ty, tx + tile, ty + tile), radius=int(tile * 0.22), fill=CREAM)
    target = tile * 0.60
    f = devanagari_font(int(target))
    bbox = f.getbbox("अ")
    ink_h = bbox[3] - bbox[1]
    f = devanagari_font(int(target * target / ink_h))
    left, top, right, bottom = f.getbbox("अ")
    ink_w, ink_h = right - left, bottom - top
    gx = tx + (tile - ink_w) / 2 - left
    gy = ty + (tile - ink_h) / 2 - top - tile * 0.04
    d.text((gx, gy), "अ", font=f, fill=BRICK)
    ul_w = ink_w * 0.42
    ul_h = tile * 0.018
    ul_y = gy + top + ink_h + tile * 0.075
    d.rounded_rectangle(
        (tx + tile / 2 - ul_w / 2, ul_y, tx + tile / 2 + ul_w / 2, ul_y + ul_h), radius=ul_h / 2, fill=BRICK
    )


def make():
    w, h = W * S, H * S
    img = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(img)

    tile = 340 * S
    tx = 64 * S
    icon_tile(d, tx, (h - tile) // 2, tile)

    rx = tx + tile + 56 * S
    max_w = w - rx - 56 * S

    f_word = font("Montserrat-Bold.ttf", 104 * S)
    f_tag = font("Literata-Regular.ttf", 38 * S)
    f_label = font("Literata-SemiBold.ttf", 21 * S)
    f_en = font("Literata-SemiBold.ttf", 38 * S)
    f_hi = font("Mukta-Regular.ttf", 30 * S)
    f_gloss = font("Mukta-Regular.ttf", 23 * S)

    tag_lines = wrap(d, "Read English books, meaning in Hindi", f_tag, max_w)

    # --- measure the whole right column so it can be centred vertically ---
    _, word_h, _, word_top = measure(d, "Arth", f_word)
    gap_word_tag = 20 * S
    tag_line_h, tag_gap = measure(d, "Ag", f_tag)[1], 6 * S
    tag_block_h = len(tag_lines) * tag_line_h + (len(tag_lines) - 1) * tag_gap
    gap_tag_card = 34 * S

    card_pad_v = 22 * S
    label_h = measure(d, "Word", f_label)[1]
    en_h = measure(d, "solitude", f_en)[1]
    gloss_h = measure(d, "being alone, often by choice", f_gloss)[1]
    inner_gap = 10 * S
    card_h = card_pad_v * 2 + label_h + inner_gap + en_h + inner_gap + gloss_h
    card_w = max_w

    total_h = word_h + gap_word_tag + tag_block_h + gap_tag_card + card_h
    y = (h - total_h) / 2 - word_top

    d.text((rx, y), "Arth", font=f_word, fill=INK)
    y += word_h + word_top + gap_word_tag

    for line in tag_lines:
        d.text((rx, y), line, font=f_tag, fill=INK_MUTED)
        y += tag_line_h + tag_gap
    y += gap_tag_card - tag_gap

    bar_w = 7 * S
    d.rounded_rectangle((rx, y, rx + card_w, y + card_h), radius=18 * S, fill=CARD, outline=RULE, width=2 * S)
    d.rounded_rectangle((rx, y, rx + bar_w, y + card_h), radius=bar_w / 2, fill=ACCENT)

    cx = rx + bar_w + 26 * S
    cy = y + card_pad_v
    d.text((cx, cy), "Word", font=f_label, fill=INK_MUTED)
    cy += label_h + inner_gap

    d.text((cx, cy), "solitude", font=f_en, fill=INK)
    en_w, _, _, en_top = measure(d, "solitude", f_en)
    hi_top = measure(d, "एकांत", f_hi)[3]
    d.text((cx + en_w + 20 * S, cy + en_top - hi_top), "एकांत", font=f_hi, fill=ACCENT)
    cy += en_h + inner_gap

    d.text((cx, cy), "being alone, often by choice", font=f_gloss, fill=INK_MUTED)

    img = img.resize((W, H), Image.LANCZOS)
    out = Path("tool/feature-graphic.png")
    img.save(out, "PNG")
    print(f"feature graphic -> {out} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    make()
