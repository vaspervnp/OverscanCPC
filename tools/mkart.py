#!/usr/bin/env python3
"""Turn the Aseprite artwork in assets/art into src/artwork.asm.

Two kinds of picture come through here, and the difference is what they cost
while the game is running rather than how they are drawn:

  assets/art/sprite/*.png   the enemies, and the saucer of milk. Masked, so the
                            background shows through, and drawn by the same
                            routines as the hand-drawn cast, in the same format
                            tools/mksprite.py writes.

                            Each one is also written out mirrored, as spr_<name>_l,
                            so an enemy can face the way it is walking: flipping a
                            mode 0 sprite means shuffling four pen bits per pixel
                            and reversing the row, which is not something to do
                            three times a frame. A sprite that is symmetric costs
                            nothing - the mirror is the same bytes, and the label
                            is an alias for the original.

  assets/art/decal/*.png    scenery. A tree, a cloud, a slide: painted once
                            into the background when the room loads and never
                            touched again. They are ORed down onto a screen
                            that has just been cleared to pen 0, so a pixel
                            that should let the background through is simply
                            pen 0 and there is no mask to carry - half the
                            bytes of a sprite the same size.

Every pixel must be one of the sixteen pens in pal_play, exactly; anything
else is a mistake in the art and is refused rather than guessed at. The PNGs
come out of Aseprite, which is where the colours are chosen - see
assets/aseprite/cpcart.lua.

    tools/mkart.py                  write src/artwork.asm
    tools/mkart.py mitsos           write src/mitsosart.asm, out of the other
                                    game's pictures in assets/art/mitsos
    tools/mkart.py --show TREETOP   print one picture, as the monitor shapes
                                    it: a mode 0 pixel is two pixels wide

Both games are mode 0 and draw from the same sixteen pens, so there is one
converter and one palette. A game is a directory of pictures and a file to
write them to; everything else about it is in its own sources.
"""

import os
import sys

from cpcpng import read_png     # tools/ is on the path: this is run from there

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: game -> where its pictures are, and the file they are written to.
GAMES = {
    "loukoumas": ("assets/art", "src/artwork.asm"),
    "mitsos": ("assets/art/mitsos", "src/mitsosart.asm"),
}
DRAWN = {
    "loukoumas": "by assets/aseprite/*.lua",
    "mitsos": "- assets/aseprite/mitsos/*.aseprite, one file per subject",
}
MASKED = {
    "loukoumas": "the enemies, and the saucer of milk",
    "mitsos": "Mitsos himself, what is after him, and what he is after",
}
#: Sprites the game never turns round, so the mirrored copy is an EQU rather
#: than a second picture. A meze sitting on a shelf does not face anything,
#: and Grandma sweeps facing the shop whichever way her feet are going - and
#: at ten bytes by ninety-six a mirror of her is two kilobytes of a sixteen
#: kilobyte address space.
NOFLIP = {
    "loukoumas": set(),
    "mitsos": {"FISH", "SAUSAGE", "CHEESE", "MEATBALL", "CATNIP",
               "GRANNY_A", "GRANNY_B", "GRANNY_SAT"},
}
ART = OUT = None
GAME = "loukoumas"

PIXELS_PER_BYTE = 2

#: Where each of a pixel's four pen bits lives, left pixel then right. Mode 0
#: spreads them across the byte; see config.asm.
PEN_BITS = ((7, 3, 5, 1), (6, 2, 4, 0))

#: pal_play, as RGB. The comment is the hardware colour number.
PENS = [
    (0, 0, 128),        # 0   4 navy
    (255, 128, 128),    # 1   7 coral
    (255, 255, 0),      # 2  10 butter yellow
    (255, 255, 255),    # 3  11 white
    (0, 0, 0),          # 4  20 black
    (128, 128, 128),    # 5   0 grey
    (128, 128, 0),      # 6  30 olive
    (255, 128, 0),      # 7  14 orange
    (0, 128, 0),        # 8  22 dark green
    (0, 255, 0),        # 9  18 bright green
    (0, 128, 128),      # 10  6 teal
    (0, 255, 255),      # 11 19 bright cyan
    (128, 0, 0),        # 12 28 dark red
    (255, 0, 0),        # 13 12 bright red
    (128, 0, 128),      # 14 24 purple
    (255, 255, 128),    # 15  3 pale yellow
]
BY_RGB = {rgb: i for i, rgb in enumerate(PENS)}


def read_art(path):
    """One PNG -> rows of pen numbers, with None for transparent."""
    w, h, colour, plte, trns, rows = read_png(path)
    name = os.path.basename(path)
    pixels = []
    for y, line in enumerate(rows):
        row = []
        for x in range(w):
            if colour == 6:
                r, g, b, a = line[4 * x:4 * x + 4]
            elif colour == 2:
                r, g, b = line[3 * x:3 * x + 3]
                a = 255
            else:
                i = line[x]
                r, g, b = plte[3 * i:3 * i + 3]
                a = trns[i] if trns and i < len(trns) else 255
            if a < 128:
                row.append(None)
                continue
            pen = BY_RGB.get((r, g, b))
            if pen is None:
                sys.exit("%s: pixel %d,%d is #%02X%02X%02X, which is not one "
                         "of the sixteen pens" % (name, x, y, r, g, b))
            row.append(pen)
        pixels.append(row)
    if w % PIXELS_PER_BYTE:
        sys.exit("%s: %d pixels wide; mode 0 packs two to a byte" % (name, w))
    return w, h, pixels


def encode_masked(row):
    """A sprite row -> (mask, data) pairs. Transparent keeps the background."""
    out = []
    for i in range(0, len(row), PIXELS_PER_BYTE):
        mask = data = 0
        for j, pen in enumerate(row[i:i + PIXELS_PER_BYTE]):
            bits = PEN_BITS[j]
            if pen is None:
                for b in bits:
                    mask |= 1 << b
            else:
                for k, b in enumerate(bits):
                    if pen & (1 << k):
                        data |= 1 << b
        out.append((mask, data))
    return out


def encode_raw(row):
    """A decal row -> plain bytes. Transparent is pen 0, which ORs to nothing."""
    out = []
    for i in range(0, len(row), PIXELS_PER_BYTE):
        byte = 0
        for j, pen in enumerate(row[i:i + PIXELS_PER_BYTE]):
            if pen:
                for k, b in enumerate(PEN_BITS[j]):
                    if pen & (1 << k):
                        byte |= 1 << b
        out.append(byte)
    return out


def picture(row):
    return "".join("." if p is None else "%X" % p for p in row)


def mirrored(rows):
    """The same picture facing the other way."""
    return [list(reversed(r)) for r in rows]


def load(kind):
    here = os.path.join(ART, kind)
    if not os.path.isdir(here):
        return []
    names = sorted(n for n in os.listdir(here) if n.endswith(".png"))
    return [(n[:-4].upper(),) + read_art(os.path.join(here, n)) for n in names]


def show(want):
    for kind in ("sprite", "decal"):
        for name, w, h, rows in load(kind):
            if want and name != want.upper():
                continue
            print("%s  %s  %d x %d pixels, %d bytes across"
                  % (kind, name, w, h, w // PIXELS_PER_BYTE))
            for row in rows:
                # a mode 0 pixel is two scanlines wide, so double it to see
                # the shape the monitor will actually show
                print("  " + "".join(
                    ".." if p is None else "%X%X" % (p, p) for p in row))
            print()


def main():
    global ART, OUT, GAME
    game = GAME = next((a for a in sys.argv[1:] if not a.startswith("-")
                        and a in GAMES), "loukoumas")
    art, out = GAMES[game]
    ART = os.path.join(ROOT, art)
    OUT = os.path.join(ROOT, out)

    if "--show" in sys.argv:
        i = sys.argv.index("--show")
        show(sys.argv[i + 1] if len(sys.argv) > i + 1 else None)
        return

    sprites = load("sprite")
    decals = load("decal")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mkart.py from %s - do not "
                 "edit.\n;;\n" % art)
        fh.write(";; The pictures are drawn in Aseprite %s.\n\n" % DRAWN[game])

        fh.write(";; ---------------------------------------------------------"
                 "------------------\n")
        fh.write(";; Masked sprites - %s.\n" % MASKED[game])
        fh.write(";; Width in bytes, height, then mask/data pairs:\n")
        fh.write(";;   screen = (screen AND mask) OR data\n")
        fh.write(";; ---------------------------------------------------------"
                 "------------------\n")
        for name, w, h, rows in sprites:
            fh.write("SPR_%-12s EQU %d\n" % (name + "_W", w // PIXELS_PER_BYTE))
            fh.write("SPR_%-12s EQU %d\n" % (name + "_H", h))
        fh.write(";; The widest of them, for the length of the unrolled blit.\n")
        fh.write("ART_MAX_W        EQU %d\n"
                 % max((w // PIXELS_PER_BYTE for _n, w, _h, _r in sprites),
                       default=0))
        for name, w, h, rows in sprites:
            for suffix, art in (("", rows), ("_l", mirrored(rows))):
                if suffix and (art == rows or name in NOFLIP[GAME]):
                    # symmetric, or never turned round: either way both
                    # directions can point at the one copy
                    fh.write("\nspr_%s_l EQU spr_%s          ; the same either way\n"
                             % (name.lower(), name.lower()))
                    continue
                fh.write("\n;; %s - %d x %d pixels%s\nspr_%s%s\n"
                         % (name, w, h, ", facing the other way" if suffix else "",
                            name.lower(), suffix))
                fh.write("    defb %d,%d\n" % (w // PIXELS_PER_BYTE, h))
                for row in art:
                    pairs = encode_masked(row)
                    fh.write("    defb %-40s ; %s\n"
                             % (",".join("#%02X,#%02X" % p for p in pairs),
                                picture(row)))

        fh.write("\n;; ---------------------------------------------------------"
                 "------------------\n")
        fh.write(";; Scenery, ORed into a freshly cleared background when the "
                 "room loads.\n")
        fh.write(";; No mask: pen 0 is the background, and ORing it changes "
                 "nothing.\n")
        fh.write(";; ---------------------------------------------------------"
                 "------------------\n")
        for i, (name, w, h, rows) in enumerate(decals):
            fh.write("DECAL_%-11s EQU %d\n" % (name, i))
        fh.write("DECAL_COUNT      EQU %d\n\n" % len(decals))
        fh.write("decal_table\n")
        for name, _w, _h, _rows in decals:
            fh.write("    defw dec_%s\n" % name.lower())
        for name, w, h, rows in decals:
            fh.write("\nDEC_%-12s EQU %d\n" % (name + "_W", w // PIXELS_PER_BYTE))
            fh.write("DEC_%-12s EQU %d\n" % (name + "_H", h))
            fh.write(";; %s - %d x %d pixels\ndec_%s\n"
                     % (name, w, h, name.lower()))
            fh.write("    defb %d,%d\n" % (w // PIXELS_PER_BYTE, h))
            for row in rows:
                fh.write("    defb %-40s ; %s\n"
                         % (",".join("#%02X" % b for b in encode_raw(row)),
                            picture(row)))

    sbytes = sum((2 if mirrored(r) != r and n not in NOFLIP[game] else 1)
                 * (2 * (w // PIXELS_PER_BYTE) * h + 2)
                 for n, w, h, r in sprites)
    dbytes = sum((w // PIXELS_PER_BYTE) * h + 2 for _n, w, h, _r in decals)
    print("mkart: %d masked sprites (%d bytes), %d decals (%d bytes)"
          % (len(sprites), sbytes, len(decals), dbytes))


if __name__ == "__main__":
    main()
