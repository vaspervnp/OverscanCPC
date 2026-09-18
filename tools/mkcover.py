#!/usr/bin/env python3
"""The disc inlay, drawn the way one would have been in 1986.

    tools/mkcover.py assets/art/title.jpg docs/loukoumas-lounge.png \\
                     en docs/cover-en.png

A CPC game came in a 3" disc case with a printed card in the front of it,
about 104 by 128 millimetres, and they all had the same five things on them:
a publisher's band across the top, a logo in heavy italic with a hard extrude
under it, the painted artwork filling the middle, a starburst shouting a
number at you, and a strip along the bottom naming the machine. This draws
that, at ten pixels to the millimetre.

The colours are not chosen here. They are pal_play - the sixteen pens the game
itself is drawn in - so the card and the screen agree, which is the one thing
the real ones never managed.

Everything is generated, like the rest of the art in this repository: the card
is not a file somebody drew once and lost the source of.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

#: pal_play as RGB, the same sixteen tools/mkscreen.py works to.
NAVY, CORAL, YELLOW, WHITE = (0, 0, 128), (255, 128, 128), (255, 255, 0), (255, 255, 255)
BLACK, GREY, OLIVE, ORANGE = (0, 0, 0), (128, 128, 128), (128, 128, 0), (255, 128, 0)
RED, PALE = (255, 0, 0), (255, 255, 128)

W, H = 1040, 1280                       # 104 x 128 mm at 10 px/mm
MARGIN = 24

FONTS = "/usr/share/fonts/truetype/noto/"
F_LOGO = FONTS + "NotoSans-CondensedBlackItalic.ttf"
F_BAND = FONTS + "NotoSans-CondensedBlack.ttf"
F_TEXT = FONTS + "NotoSans-CondensedBold.ttf"

TEXT = {
    "en": {
        "presents":  "REVIVE8BIT PRESENTS",
        "logo":      "LOUKOUMAS",
        "subtitle":  "THE GREAT SAUSAGE CHASE",
        "flash":     ["29", "SCREENS!"],
        "strap":     "HE'S FAT.  HE'S HUNGRY.  AND THE FRIDGE IS EMPTY.",
        "machine":   'AMSTRAD CPC 6128  ·  3" DISK  ·  128K',
        "credit":    "© 2026 REVIVE8BIT · VASPER",
        "shot":      "ACTUAL SCREEN SHOT",
        "corner":    "FULL\nOVERSCAN",
    },
    "el": {
        "presents":  "Η REVIVE8BIT ΠΑΡΟΥΣΙΑΖΕΙ",
        "logo":      "ΛΟΥΚΟΥΜΑΣ",
        "subtitle":  "ΤΟ ΚΥΝΗΓΙ ΤΟΥ ΛΟΥΚΑΝΙΚΟΥ",
        "flash":     ["29", "ΠΙΣΤΕΣ!"],
        "strap":     "ΧΟΝΤΡΟΣ.  ΠΕΙΝΑΣΜΕΝΟΣ.  ΚΑΙ ΤΟ ΨΥΓΕΙΟ ΑΔΕΙΟ.",
        "machine":   'AMSTRAD CPC 6128  ·  ΔΙΣΚΕΤΑ 3"  ·  128K',
        "credit":    "© 2026 REVIVE8BIT · VASPER",
        "shot":      "ΑΠΟ ΤΟ ΠΑΙΧΝΙΔΙ",
        "corner":    "ΠΛΗΡΕΣ\nOVERSCAN",
    },
}


def fit(path, text, width, cap, start=None):
    """The largest size at which text fits in width, never above cap."""
    size = start or cap
    while size > 8:
        font = ImageFont.truetype(path, size)
        if font.getbbox(text)[2] <= width:
            return font
        size -= 2
    return ImageFont.truetype(path, 8)


def spaced(draw, xy, text, font, fill, gap, centre_in=None):
    """Letter-spaced text - a band of it is the whole look of these covers."""
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in text]
    total = sum(widths) + gap * (len(text) - 1)
    x, y = xy
    if centre_in is not None:
        x = centre_in[0] + (centre_in[1] - centre_in[0] - total) // 2
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=font, fill=fill)
        x += w + gap
    return total


def logo(draw, text, box, depth=14):
    """Heavy italic, extruded down-right into black, outlined in coral.

    The extrude is the period detail: every one of these logos was a solid
    shadow rather than a soft one, because it was cut out of film."""
    font = fit(F_LOGO, text, box[2] - box[0], 200)
    w = font.getbbox(text)[2] - font.getbbox(text)[0]
    x = box[0] + (box[2] - box[0] - w) // 2 - font.getbbox(text)[0]
    y = box[1]
    for i in range(depth, 0, -1):
        draw.text((x + i, y + i), text, font=font, fill=BLACK)
    draw.text((x, y), text, font=font, fill=YELLOW,
              stroke_width=5, stroke_fill=CORAL)
    return font.getbbox(text)[3]


def starburst(draw, cx, cy, r_out, r_in, points=18, fill=YELLOW, edge=BLACK):
    import math
    pts = []
    for i in range(points * 2):
        a = math.pi * i / points - math.pi / 2
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=fill, outline=edge)
    draw.polygon(pts, outline=edge)


def halftone(img, box, step=6):
    """A dot screen over the artwork, because everything was printed."""
    dots = Image.new("L", (box[2] - box[0], box[3] - box[1]), 0)
    d = ImageDraw.Draw(dots)
    for y in range(0, dots.height, step):
        for x in range(0, dots.width, step):
            d.point((x, y), fill=36)
    img.paste(Image.new("RGB", dots.size, BLACK), box, dots)


def build(art_path, shot_path, lang, out_path):
    t = TEXT[lang]
    img = Image.new("RGB", (W, H), BLACK)
    draw = ImageDraw.Draw(img)

    inner = (MARGIN, MARGIN, W - MARGIN, H - MARGIN)
    draw.rectangle(inner, fill=NAVY, outline=YELLOW, width=5)

    # --- the publisher's band ------------------------------------------------
    band_h = 108
    band = (inner[0] + 5, inner[1] + 5, inner[2] - 5, inner[1] + band_h)
    draw.rectangle(band, fill=CORAL)
    draw.rectangle((band[0], band[3] - 8, band[2], band[3]), fill=BLACK)
    f = fit(F_BAND, t["presents"], (band[2] - band[0]) - 160, 52)
    spaced(draw, (0, band[1] + 24), t["presents"], f, BLACK, 7,
           centre_in=(band[0], band[2]))

    # --- the name ------------------------------------------------------------
    y = band[3] + 26
    logo(draw, t["logo"], (inner[0] + 40, y, inner[2] - 40, 0))
    y += 200
    f = fit(F_BAND, t["subtitle"], inner[2] - inner[0] - 120, 46)
    spaced(draw, (0, y), t["subtitle"], f, WHITE, 5,
           centre_in=(inner[0], inner[2]))
    y += 64

    # --- the artwork ---------------------------------------------------------
    # The bands below it are fixed, so the picture takes whatever is left and
    # is cropped to it rather than shrunk: a cover with a letterboxed painting
    # on it would not have got past the art director.
    strap_h, foot_h, gap = 66, 100, 14
    art_x0, art_x1 = inner[0] + 24, inner[2] - 24
    art_w = art_x1 - art_x0
    art_h = (inner[3] - 5 - foot_h - 10 - strap_h - gap) - y
    art = Image.open(art_path).convert("RGB")
    scaled_h = round(art.height * art_w / art.width)
    art = art.resize((art_w, scaled_h), Image.LANCZOS)
    if scaled_h > art_h:                # off the ceiling, which is bare wall
        top = round((scaled_h - art_h) * 0.75)
        art = art.crop((0, top, art_w, top + art_h))
    img.paste(art, (art_x0, y))
    art_box = (art_x0, y, art_x1, y + art_h)
    halftone(img, art_box)
    draw.rectangle((art_box[0] - 5, art_box[1] - 5, art_box[2] + 4,
                    art_box[3] + 4), outline=WHITE, width=5)

    # a screen shot pasted into the corner, captioned, as they all were
    shot = Image.open(shot_path).convert("RGB")
    sw = 300
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    sx, sy = art_box[0] + 18, art_box[3] - shot.height - 46
    img.paste(shot, (sx, sy))
    draw.rectangle((sx - 4, sy - 4, sx + sw + 3, sy + shot.height + 3),
                   outline=WHITE, width=4)
    f = ImageFont.truetype(F_TEXT, 22)
    cap = (sx - 4, sy + shot.height + 4, sx + sw + 3, sy + shot.height + 32)
    draw.rectangle(cap, fill=WHITE)
    draw.text((cap[0] + 8, cap[1] + 2), t["shot"], font=f, fill=BLACK)

    # the starburst, shouting a number
    cx, cy = art_box[2] - 120, art_box[1] + 118
    starburst(draw, cx, cy, 116, 86)
    f1 = ImageFont.truetype(F_LOGO, 62)
    f2 = fit(F_LOGO, t["flash"][1], 190, 34)
    draw.text((cx, cy - 46), t["flash"][0], font=f1, fill=BLACK, anchor="ma")
    draw.text((cx, cy + 16), t["flash"][1], font=f2, fill=BLACK, anchor="ma")

    # --- the strapline -------------------------------------------------------
    y = art_box[3] + gap
    strap = (inner[0] + 5, y, inner[2] - 5, y + strap_h)
    draw.rectangle(strap, fill=YELLOW)
    f = fit(F_LOGO, t["strap"], strap[2] - strap[0] - 40, 40)
    draw.text(((strap[0] + strap[2]) // 2, strap[1] + 12), t["strap"],
              font=f, fill=BLACK, anchor="ma")

    # --- the machine ---------------------------------------------------------
    foot = (inner[0] + 5, strap[3] + 10, inner[2] - 5, inner[3] - 5)
    draw.rectangle(foot, fill=BLACK)
    f = fit(F_BAND, t["machine"], foot[2] - foot[0] - 60, 44)
    draw.text(((foot[0] + foot[2]) // 2, foot[1] + 10), t["machine"],
              font=f, fill=YELLOW, anchor="ma")
    f = ImageFont.truetype(F_TEXT, 26)
    draw.text(((foot[0] + foot[2]) // 2, foot[1] + 62), t["credit"],
              font=f, fill=GREY, anchor="ma")

    img.save(out_path)
    print("mkcover: %s (%dx%d)" % (out_path, W, H))


def main():
    if len(sys.argv) != 5:
        sys.exit("usage: mkcover.py <artwork> <screenshot> <en|el> <out.png>")
    art, shot, lang, out = sys.argv[1:]
    if lang not in TEXT:
        sys.exit("mkcover: language must be en or el")
    if not os.path.exists(F_LOGO):
        sys.exit("mkcover: needs the Noto Sans Condensed fonts (fonts-noto-core)")
    build(art, shot, lang, out)


if __name__ == "__main__":
    main()
