#!/usr/bin/env python3
"""The disc inlay, drawn the way one would have been in 1986.

    tools/mkcover.py assets/art/title.jpg en docs/cover-en.png \\
                     docs/loukoumas-lounge.png docs/loukoumas-park.png \\
                     docs/loukoumas-rooftops.png docs/loukoumas-gameover.png

A CPC game came in a 3" disc case with a printed card wrapped round the inside
of it - back, spine and front in one piece, folded twice - and they all had the
same furniture on them: a publisher's band across the top, a logo in heavy
italic with a hard extrude under it, the painted artwork filling the middle, a
starburst shouting a number, screen shots down the back with ACTUAL SCREEN SHOT
under them, and a strip along the bottom naming the machine.

This draws that, at ten pixels to the millimetre: two panels of 104 x 128 mm
with a 9 mm spine between them. It writes the whole wrap, and the front on its
own next to it, because the front is what a README wants.

The colours are not chosen here. They are pal_play - the sixteen pens the game
itself is drawn in - so the card and the screen agree, which is the one thing
the real ones never managed.

Everything is generated, like the rest of the art in this repository: the card
is not a file somebody drew once and lost the source of.
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

#: pal_play as RGB, the same sixteen tools/mkscreen.py works to.
NAVY, CORAL, YELLOW, WHITE = (0, 0, 128), (255, 128, 128), (255, 255, 0), (255, 255, 255)
BLACK, GREY, OLIVE, ORANGE = (0, 0, 0), (128, 128, 128), (128, 128, 0), (255, 128, 0)
RED, PALE = (255, 0, 0), (255, 255, 128)

PANEL_W, PANEL_H = 1040, 1280           # 104 x 128 mm at 10 px/mm
SPINE_W = 90                            # 9 mm, which is a 3" disc case
MARGIN = 24

FONTS = "/usr/share/fonts/truetype/noto/"
F_LOGO = FONTS + "NotoSans-CondensedBlackItalic.ttf"
F_BAND = FONTS + "NotoSans-CondensedBlack.ttf"
F_TEXT = FONTS + "NotoSans-CondensedBold.ttf"
F_BODY = FONTS + "NotoSans-Condensed.ttf"

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
        "blurb": [
            "A quarter past three in the morning. The robot vacuum is awake, "
            "the canary has the run of the house, and the big two-door Pitsos "
            "is shut.",
            "Loukoumas wants one sausage. It is going to take him twenty-nine "
            "rooms, a school, a vet's and every rooftop in Kypseli to get it.",
        ],
        "features": [
            "29 screens in three acts",
            "Full overscan - no border at all",
            "Greek and English, one key apart",
            "Three difficulties: 9, 6 or 3 lives",
            "Music from Arkos Tracker 3",
            "100% machine code",
        ],
        "loading":   "LOADING",
        "loadline":  'RUN"LOUK',
        "loadnote":  "Insert the disc in drive A. 128K machine required.",
        "made":      "MADE IN GREECE",
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
        "blurb": [
            "Τρεις και τέταρτο τα ξημερώματα. Η σκούπα-ρομπότ περιπολεί, το "
            "καναρίνι πετάει ελεύθερο, και το δίπορτο Pitsos είναι κλειστό.",
            "Ο Λουκουμάς θέλει ένα λουκάνικο. Θα του πάρει είκοσι εννιά "
            "πίστες, ένα σχολείο, ένα κτηνιατρείο και όλες τις ταράτσες της "
            "Κυψέλης.",
        ],
        "features": [
            "29 πίστες σε τρεις πράξεις",
            "Πλήρες overscan - χωρίς περιθώριο",
            "Ελληνικά και Αγγλικά με ένα πλήκτρο",
            "Τρεις δυσκολίες: 9, 6 ή 3 ζωές",
            "Μουσική από Arkos Tracker 3",
            "100% γλώσσα μηχανής",
        ],
        "loading":   "ΦΟΡΤΩΣΗ",
        "loadline":  'RUN"LOUK',
        "loadnote":  "Η δισκέτα στον οδηγό A. Απαιτείται μηχανή 128K.",
        "made":      "ΤΥΠΩΘΗΚΕ ΣΤΗΝ ΕΛΛΑΔΑ",
    },
}


# ---------------------------------------------------------------------------
# Small drawing helpers
# ---------------------------------------------------------------------------
def fit(path, text, width, cap, gap=0):
    """The largest size at which text fits in width, never above cap.

    gap is the letter spacing it will be drawn with, which has to be in the
    measurement or a band of spaced capitals runs off the end of the card."""
    size = cap
    while size > 8:
        font = ImageFont.truetype(path, size)
        if font.getbbox(text)[2] + gap * (len(text) - 1) <= width:
            return font
        size -= 2
    return ImageFont.truetype(path, 8)


def wrap(text, font, width):
    lines, cur = [], ""
    for word in text.split():
        trial = (cur + " " + word).strip()
        if font.getbbox(trial)[2] <= width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def spaced(draw, y, text, font, fill, gap, x0, x1):
    """Letter-spaced and centred - a band of it is the whole look of these."""
    widths = [font.getbbox(c)[2] - font.getbbox(c)[0] for c in text]
    x = x0 + (x1 - x0 - (sum(widths) + gap * (len(text) - 1))) // 2
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=font, fill=fill)
        x += w + gap


def logo(draw, text, x0, x1, y, cap=200, depth=14):
    """Heavy italic, extruded down-right into black, outlined in coral.

    The extrude is the period detail: every one of these was a solid shadow
    rather than a soft one, because it was cut out of film."""
    font = fit(F_LOGO, text, x1 - x0, cap)
    w = font.getbbox(text)[2] - font.getbbox(text)[0]
    x = x0 + (x1 - x0 - w) // 2 - font.getbbox(text)[0]
    for i in range(depth, 0, -1):
        draw.text((x + i, y + i), text, font=font, fill=BLACK)
    draw.text((x, y), text, font=font, fill=YELLOW,
              stroke_width=5, stroke_fill=CORAL)


def star(draw, cx, cy, r, fill=CORAL):
    pts = []
    for i in range(10):
        a = math.pi * i / 5 - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.42
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    draw.polygon(pts, fill=fill)


def starburst(draw, cx, cy, r_out, r_in, points=18):
    pts = []
    for i in range(points * 2):
        a = math.pi * i / points - math.pi / 2
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=YELLOW, outline=BLACK)


def halftone(img, box, step=6):
    """A dot screen over the artwork, because everything was printed."""
    dots = Image.new("L", (box[2] - box[0], box[3] - box[1]), 0)
    d = ImageDraw.Draw(dots)
    for y in range(0, dots.height, step):
        for x in range(0, dots.width, step):
            d.point((x, y), fill=36)
    img.paste(Image.new("RGB", dots.size, BLACK), box, dots)


def shot_at(img, draw, path, x, y, w, caption=None):
    """A screen shot with a white keyline, the way they were pasted up."""
    s = Image.open(path).convert("RGB")
    h = round(s.height * w / s.width)
    img.paste(s.resize((w, h), Image.LANCZOS), (x, y))
    draw.rectangle((x - 4, y - 4, x + w + 3, y + h + 3), outline=WHITE, width=4)
    if caption:
        f = ImageFont.truetype(F_TEXT, 22)
        cap = (x - 4, y + h + 4, x + w + 3, y + h + 32)
        draw.rectangle(cap, fill=WHITE)
        draw.text((cap[0] + 8, cap[1] + 2), caption, font=f, fill=BLACK)
    return h


def panel(img, draw, x0):
    """The navy field with its yellow keyline that both panels sit on."""
    box = (x0 + MARGIN, MARGIN, x0 + PANEL_W - MARGIN, PANEL_H - MARGIN)
    draw.rectangle(box, fill=NAVY, outline=YELLOW, width=5)
    return box


def band(draw, box, text, height=108):
    b = (box[0] + 5, box[1] + 5, box[2] - 5, box[1] + height - MARGIN)
    draw.rectangle(b, fill=CORAL)
    draw.rectangle((b[0], b[3] - 8, b[2], b[3]), fill=BLACK)
    f = fit(F_BAND, text, (b[2] - b[0]) - 80, 52, gap=7)
    top, bottom = f.getbbox(text)[1], f.getbbox(text)[3]
    y = b[1] + ((b[3] - 8 - b[1]) - (bottom - top)) // 2 - top
    spaced(draw, y, text, f, BLACK, 7, b[0], b[2])
    return b[3]


def foot(draw, box, t):
    """The strip that names the machine, at the bottom of either panel."""
    f = (box[0] + 5, box[3] - 101, box[2] - 5, box[3] - 5)
    draw.rectangle(f, fill=BLACK)
    fo = fit(F_BAND, t["machine"], f[2] - f[0] - 60, 44)
    draw.text(((f[0] + f[2]) // 2, f[1] + 10), t["machine"], font=fo,
              fill=YELLOW, anchor="ma")
    fo = ImageFont.truetype(F_TEXT, 26)
    draw.text(((f[0] + f[2]) // 2, f[1] + 62), t["credit"], font=fo,
              fill=GREY, anchor="ma")
    return f[1]


# ---------------------------------------------------------------------------
# The three panels
# ---------------------------------------------------------------------------
def draw_front(img, draw, x0, t, art_path, shot_path):
    box = panel(img, draw, x0)
    y = band(draw, box, t["presents"]) + 26

    logo(draw, t["logo"], box[0] + 40, box[2] - 40, y)
    y += 200
    f = fit(F_BAND, t["subtitle"], box[2] - box[0] - 120, 46, gap=5)
    spaced(draw, y, t["subtitle"], f, WHITE, 5, box[0], box[2])
    y += 64

    # The bands below are fixed, so the picture takes whatever is left and is
    # cropped to it rather than shrunk: a cover with a letterboxed painting on
    # it would not have got past the art director.
    strap_h, foot_h, gap = 66, 100, 14
    ax0, ax1 = box[0] + 24, box[2] - 24
    aw = ax1 - ax0
    ah = (box[3] - 5 - foot_h - 10 - strap_h - gap) - y
    art = Image.open(art_path).convert("RGB")
    scaled = round(art.height * aw / art.width)
    art = art.resize((aw, scaled), Image.LANCZOS)
    if scaled > ah:                     # off the ceiling, which is bare wall
        top = round((scaled - ah) * 0.75)
        art = art.crop((0, top, aw, top + ah))
    img.paste(art, (ax0, y))
    abox = (ax0, y, ax1, y + ah)
    halftone(img, abox)
    draw.rectangle((abox[0] - 5, abox[1] - 5, abox[2] + 4, abox[3] + 4),
                   outline=WHITE, width=5)

    h = shot_at(img, draw, shot_path, abox[0] + 18,
                abox[3] - round(544 * 300 / 768) - 46, 300, t["shot"])

    cx, cy = abox[2] - 120, abox[1] + 118
    starburst(draw, cx, cy, 116, 86)
    draw.text((cx, cy - 46), t["flash"][0], font=ImageFont.truetype(F_LOGO, 62),
              fill=BLACK, anchor="ma")
    draw.text((cx, cy + 16), t["flash"][1], font=fit(F_LOGO, t["flash"][1], 190, 34),
              fill=BLACK, anchor="ma")

    y = abox[3] + gap
    strap = (box[0] + 5, y, box[2] - 5, y + strap_h)
    draw.rectangle(strap, fill=YELLOW)
    f = fit(F_LOGO, t["strap"], strap[2] - strap[0] - 40, 40)
    draw.text(((strap[0] + strap[2]) // 2, strap[1] + 12), t["strap"],
              font=f, fill=BLACK, anchor="ma")

    foot(draw, box, t)


def draw_back(img, draw, x0, t, shots):
    box = panel(img, draw, x0)
    y = band(draw, box, t["subtitle"]) + 22

    # the blurb
    f = ImageFont.truetype(F_BODY, 31)
    for para in t["blurb"]:
        for line in wrap(para, f, box[2] - box[0] - 80):
            draw.text((box[0] + 40, y), line, font=f, fill=WHITE)
            y += 37
        y += 12

    # Everything below the shots is a fixed height, so it is placed from the
    # bottom up and the shots take whatever is left between.
    fo = foot(draw, box, t)
    load = (box[0] + 26, fo - 14 - 130, box[2] - 26, fo - 14)
    feat_top = load[1] - 24 - 3 * 40
    avail = feat_top - 24 - y
    sh = (avail - 18) // 2
    sw = round(sh * 768 / 544)
    sx0 = box[0] + ((box[2] - box[0]) - (2 * sw + 20)) // 2
    for i, path in enumerate(shots[:4]):
        shot_at(img, draw, path, sx0 + (i % 2) * (sw + 20),
                y + (i // 2) * (sh + 18), sw)

    # what it says on the box, in two columns - sized to the longest of them,
    # because the Greek of a feature is always longer than the English
    colw = (box[2] - box[0]) // 2 - 20
    f = fit(F_TEXT, max(t["features"], key=len), colw - 44, 30)
    for i, line in enumerate(t["features"]):
        fx = box[0] + 40 + (i % 2) * colw
        fy = feat_top + (i // 2) * 40
        star(draw, fx + 11, fy + 17, 13)
        draw.text((fx + 32, fy), line, font=f, fill=YELLOW)

    # the loading instructions, in a box, as they always were
    draw.rectangle(load, fill=BLACK, outline=WHITE, width=3)
    f = ImageFont.truetype(F_BAND, 26)
    draw.text((load[0] + 20, load[1] + 12), t["loading"], font=f, fill=CORAL)
    f = ImageFont.truetype(F_LOGO, 40)
    draw.text((load[0] + 20, load[1] + 42), t["loadline"], font=f, fill=YELLOW)
    f = ImageFont.truetype(F_BODY, 24)
    draw.text((load[0] + 20, load[1] + 94), t["loadnote"], font=f, fill=WHITE)
    f = ImageFont.truetype(F_TEXT, 22)
    draw.text((load[2] - 20, load[3] - 32), t["made"], font=f, fill=GREY,
              anchor="ra")


def draw_spine(img, draw, x0, t):
    box = (x0, MARGIN, x0 + SPINE_W, PANEL_H - MARGIN)
    draw.rectangle(box, fill=NAVY)
    draw.rectangle((box[0], box[1], box[0] + 3, box[3]), fill=YELLOW)
    draw.rectangle((box[2] - 3, box[1], box[2], box[3]), fill=YELLOW)
    draw.rectangle((box[0], box[1], box[2], box[1] + 70), fill=CORAL)
    draw.rectangle((box[0], box[3] - 70, box[2], box[3]), fill=CORAL)

    # The title runs up the spine, which means rendering it flat and turning
    # it: there is no rotated text in PIL.
    h = (box[3] - 70) - (box[1] + 70) - 40
    strip = Image.new("RGB", (h, SPINE_W), NAVY)
    sd = ImageDraw.Draw(strip)
    text = t["logo"] + "   ·   " + t["machine"].split("  ·")[0]
    f = fit(F_BAND, text, h - 20, 56)
    sd.text((h // 2, SPINE_W // 2), text, font=f, fill=YELLOW, anchor="mm")
    img.paste(strip.rotate(90, expand=True), (box[0], box[1] + 90))


def fold_marks(draw, x, height):
    """Where to fold it, in the black outside the panels."""
    for y in range(0, height, 24):
        draw.line((x, y, x, y + 10), fill=GREY, width=2)


def build(art_path, lang, out_path, shots):
    t = TEXT[lang]
    w = PANEL_W * 2 + SPINE_W
    img = Image.new("RGB", (w, PANEL_H), BLACK)
    draw = ImageDraw.Draw(img)

    draw_back(img, draw, 0, t, shots)
    draw_spine(img, draw, PANEL_W, t)
    draw_front(img, draw, PANEL_W + SPINE_W, t, art_path, shots[0])
    fold_marks(draw, PANEL_W - 1, PANEL_H)
    fold_marks(draw, PANEL_W + SPINE_W, PANEL_H)
    img.save(out_path)
    print("mkcover: %s (%dx%d, back + spine + front)" % (out_path, w, PANEL_H))

    front = img.crop((PANEL_W + SPINE_W, 0, w, PANEL_H))
    base, ext = os.path.splitext(out_path)
    front.save(base + "-front" + ext)
    print("mkcover: %s (%dx%d)" % (base + "-front" + ext, PANEL_W, PANEL_H))


def main():
    if len(sys.argv) < 5:
        sys.exit("usage: mkcover.py <artwork> <en|el> <out.png> <shot> ...")
    art, lang, out = sys.argv[1:4]
    shots = sys.argv[4:]
    if lang not in TEXT:
        sys.exit("mkcover: language must be en or el")
    if not os.path.exists(F_LOGO):
        sys.exit("mkcover: needs the Noto Sans Condensed fonts (fonts-noto-core)")
    build(art, lang, out, shots)


if __name__ == "__main__":
    main()
