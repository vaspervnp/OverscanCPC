#!/usr/bin/env python3
"""Turn a picture into a mode 0 overscan screen.

    tools/mkscreen.py assets/art/title.png TITLE

The output is 192 mode 0 pixels across by 272 scanlines - the whole overscan
window, 384x272 on the monitor, because a mode 0 pixel is two scanlines wide.
Everything is quantised to the sixteen pens of pal_play and nothing else; the
source can be any size and is scaled to fit, horizontally by half as much as
vertically so it comes out the right shape on the tube.

Two things are written:

  build/<name>.bin      the picture raw: 96 bytes per scanline, 272 scanlines,
                        top to bottom. 26,112 bytes. This is the plain form -
                        load it into an overscan screen and it is the picture.

  src/<name>pic.asm     the same picture LZSS-compressed, which is the form
                        that actually fits in the machine. 26 KB of screen does
                        not fit anywhere in a game that has already spent its
                        sixteen kilobytes; around seven does.

The compressed format, decoded by src/unpack.asm:

  * a flag byte, bits taken from the top: 1 means a literal byte follows,
    0 means a two-byte match.
  * a match is  offset low 8 bits, then (offset high 3 bits) << 5 | (len - 3).
    Offset is 1..2047 bytes back through the output, length 3..34.
  * there is no end marker: the decoder stops when it has filled 272 rows.

The window is 2047 bytes because the decoder does not keep one. The output is
the screen, and the screen is the window: a back reference is at most twenty-two
rows up, which line_tab can address directly. That is what makes a decompressor
this small possible on a machine with nothing to spare.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

BYTES_PER_LINE = 96
DISPLAY_LINES = 272
PIXELS_PER_BYTE = 2
WIDTH = BYTES_PER_LINE * PIXELS_PER_BYTE       # 192 mode 0 pixels

MAX_OFFSET = 2047
MIN_LEN = 3
MAX_LEN = 34

#: Where each of a pixel's four pen bits lives, left pixel then right.
PEN_BITS = ((7, 3, 5, 1), (6, 2, 4, 0))

#: pal_play, as RGB - the same sixteen tools/mkart.py works to.
PENS = [
    (0, 0, 128), (255, 128, 128), (255, 255, 0), (255, 255, 255),
    (0, 0, 0), (128, 128, 128), (128, 128, 0), (255, 128, 0),
    (0, 128, 0), (0, 255, 0), (0, 128, 128), (0, 255, 255),
    (128, 0, 0), (255, 0, 0), (128, 0, 128), (255, 255, 128),
]


def quantise(path):
    """The picture as rows of pen numbers, 192 by 272."""
    from PIL import Image
    src = Image.open(path).convert("RGB")
    small = src.resize((WIDTH, DISPLAY_LINES), Image.LANCZOS)
    pal = Image.new("P", (1, 1))
    flat = [c for pen in PENS for c in pen]
    pal.putpalette(flat + [0, 0, 0] * (256 - len(PENS)))
    q = small.quantize(palette=pal, dither=Image.Dither.NONE)
    px = q.load()
    return q, [[px[x, y] for x in range(WIDTH)] for y in range(DISPLAY_LINES)]


def encode(rows):
    """Pen numbers -> mode 0 bytes, two pixels to a byte."""
    out = bytearray()
    for row in rows:
        for x in range(0, WIDTH, PIXELS_PER_BYTE):
            byte = 0
            for j, pen in enumerate(row[x:x + PIXELS_PER_BYTE]):
                for k, bit in enumerate(PEN_BITS[j]):
                    if pen & (1 << k):
                        byte |= 1 << bit
            out.append(byte)
    return bytes(out)


def compress(data):
    """LZSS, parsed for the smallest output rather than the longest match.

    Greedy costs a few hundred bytes here: taking the longest match at every
    step is not the same as taking the fewest tokens overall, and a literal
    now can buy a longer match next. Working backwards from the end, the
    cheapest way to finish from every position is known before the position
    before it is decided, so the parse is exact.
    """
    n = len(data)
    from collections import defaultdict
    index = defaultdict(list)
    for i in range(n - MIN_LEN + 1):
        index[data[i:i + MIN_LEN]].append(i)

    best = [0] * (n + 1)            # bits to encode from here to the end
    choice = [None] * (n + 1)
    for i in range(n - 1, -1, -1):
        best[i] = 9 + best[i + 1]   # a literal: one flag bit and a byte
        choice[i] = None
        cand = index.get(data[i:i + MIN_LEN])
        if cand:
            longest = 0
            for j in reversed(cand):
                if j >= i:
                    continue
                if i - j > MAX_OFFSET:
                    break
                ln = MIN_LEN
                while (ln < MAX_LEN and i + ln < n
                       and data[j + ln] == data[i + ln]):
                    ln += 1
                if ln <= longest:
                    continue
                longest = ln
                for l in range(MIN_LEN, ln + 1):
                    cost = 17 + best[i + l]     # a flag bit and two bytes
                    if cost < best[i]:
                        best[i] = cost
                        choice[i] = (l, i - j)
                if ln == MAX_LEN:
                    break

    out = bytearray()
    flags = 0
    nflag = 0
    pending = bytearray()
    i = 0
    while i < n:
        flags <<= 1
        if choice[i] is None:
            flags |= 1
            pending.append(data[i])
            i += 1
        else:
            ln, off = choice[i]
            pending.append(off & 0xFF)
            pending.append(((off >> 8) << 5) | (ln - MIN_LEN))
            i += ln
        nflag += 1
        if nflag == 8:
            out.append(flags)
            out += pending
            flags = 0
            nflag = 0
            pending = bytearray()
    if nflag:
        out.append(flags << (8 - nflag))
        out += pending
    return bytes(out)


def verify(packed, original):
    """Decode it again the way the Z80 will, and insist it matches."""
    out = bytearray()
    i = 0
    while len(out) < len(original):
        flags = packed[i]
        i += 1
        for _ in range(8):
            if len(out) >= len(original):
                break
            if flags & 0x80:
                out.append(packed[i])
                i += 1
            else:
                lo, hi = packed[i], packed[i + 1]
                i += 2
                off = lo | ((hi >> 5) << 8)
                ln = (hi & 0x1F) + MIN_LEN
                for _ in range(ln):
                    out.append(out[len(out) - off])
            flags = (flags << 1) & 0xFF
    if bytes(out) != original:
        sys.exit("mkscreen: the packed picture does not decode back")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mkscreen.py <image> <name>")
    path, name = sys.argv[1], sys.argv[2].lower()

    q, rows = quantise(path)
    raw = encode(rows)
    assert len(raw) == BYTES_PER_LINE * DISPLAY_LINES

    binpath = os.path.join(ROOT, "build", name + ".bin")
    os.makedirs(os.path.dirname(binpath), exist_ok=True)
    open(binpath, "wb").write(raw)

    packed = compress(raw)
    verify(packed, raw)

    asmpath = os.path.join(ROOT, "src", name + "pic.asm")
    with open(asmpath, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mkscreen.py from %s - do not edit.\n;;\n"
                 % os.path.relpath(path, ROOT))
        fh.write(";; %d x %d mode 0 pixels - the whole overscan screen - packed\n"
                 % (WIDTH, DISPLAY_LINES))
        fh.write(";; from %d bytes to %d. Unpacked by src/unpack.asm.\n\n"
                 % (len(raw), len(packed)))
        fh.write("%s_PACKED_LEN EQU %d\n\n" % (name.upper(), len(packed)))
        fh.write("%s_packed\n" % name)
        for i in range(0, len(packed), 16):
            fh.write("    defb " + ",".join("#%02X" % b for b in packed[i:i + 16])
                     + "\n")

    # a preview at the shape the monitor will show, for looking at
    prev = os.path.join(ROOT, "docs", name + "-screen.png")
    q.convert("RGB").resize((WIDTH * 2, DISPLAY_LINES),
                            0).resize((WIDTH * 4, DISPLAY_LINES * 2), 0).save(prev)

    print("mkscreen: %s %d x %d, %d bytes raw, %d packed (%.0f%%)"
          % (name, WIDTH, DISPLAY_LINES, len(raw), len(packed),
             100.0 * len(packed) / len(raw)))


if __name__ == "__main__":
    main()
