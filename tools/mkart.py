#!/usr/bin/env python3
"""Turn the Aseprite artwork in assets/art into src/artwork.asm.

Two kinds of picture come through here, and the difference is what they cost
while the game is running rather than how they are drawn:

  assets/art/sprite/*.png   the enemies, and the saucer of milk. Masked, so the
                            background shows through, and drawn by the same
                            routines as the hand-drawn cast, in the same format
                            tools/mksprite.py writes.

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
    tools/mkart.py --show TREETOP   print one picture, as the monitor shapes
                                    it: a mode 0 pixel is two scanlines wide
"""

import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
OUT = os.path.join(ROOT, "src", "artwork.asm")

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


# ---------------------------------------------------------------------------
# A PNG reader, so the build needs nothing that is not in the standard library.
# Aseprite writes 8-bit RGBA, uninterlaced; the other colour types are here
# because a one-line check beats a confusing failure.
# ---------------------------------------------------------------------------
def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("%s: not a PNG" % path)
    idat = b""
    plte = trns = None
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, colour, _comp, _filt, interlace = struct.unpack(
                ">IIBBBBB", body)
            if depth != 8 or interlace:
                sys.exit("%s: %d-bit%s PNG - save it as 8 bits, uninterlaced"
                         % (path, depth, " interlaced" if interlace else ""))
            if colour not in (2, 3, 6):
                sys.exit("%s: colour type %d is not supported" % (path, colour))
        elif kind == b"PLTE":
            plte = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length

    per = {2: 3, 3: 1, 6: 4}[colour]
    raw = zlib.decompress(idat)
    stride = w * per
    out = []
    prev = bytearray(stride)
    pos = 0
    for _y in range(h):
        filt = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - per] if i >= per else 0
            b = prev[i]
            c = prev[i - per] if i >= per else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
            elif filt:
                sys.exit("%s: filter %d" % (path, filt))
        prev = line
        out.append(bytes(line))
    return w, h, colour, plte, trns, out


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
    if "--show" in sys.argv:
        i = sys.argv.index("--show")
        show(sys.argv[i + 1] if len(sys.argv) > i + 1 else None)
        return

    sprites = load("sprite")
    decals = load("decal")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mkart.py from assets/art - do not "
                 "edit.\n;;\n")
        fh.write(";; The pictures are drawn in Aseprite by "
                 "assets/aseprite/*.lua.\n\n")

        fh.write(";; ---------------------------------------------------------"
                 "------------------\n")
        fh.write(";; Masked sprites - the enemies, and the saucer of milk.\n")
        fh.write(";; Width in bytes, height, then mask/data pairs:\n")
        fh.write(";;   screen = (screen AND mask) OR data\n")
        fh.write(";; ---------------------------------------------------------"
                 "------------------\n")
        for name, w, h, rows in sprites:
            fh.write("SPR_%-12s EQU %d\n" % (name + "_W", w // PIXELS_PER_BYTE))
            fh.write("SPR_%-12s EQU %d\n" % (name + "_H", h))
        for name, w, h, rows in sprites:
            fh.write("\n;; %s - %d x %d pixels\nspr_%s\n"
                     % (name, w, h, name.lower()))
            fh.write("    defb %d,%d\n" % (w // PIXELS_PER_BYTE, h))
            for row in rows:
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

    sbytes = sum(2 * (w // PIXELS_PER_BYTE) * h + 2 for _n, w, h, _r in sprites)
    dbytes = sum((w // PIXELS_PER_BYTE) * h + 2 for _n, w, h, _r in decals)
    print("mkart: %d masked sprites (%d bytes), %d decals (%d bytes)"
          % (len(sprites), sbytes, len(decals), dbytes))


if __name__ == "__main__":
    main()
