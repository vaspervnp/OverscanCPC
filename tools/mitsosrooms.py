#!/usr/bin/env python3
"""Check the second game's rooms against their own platform tables.

    tools/mitsosrooms.py

A room in src/mitsosrooms.asm is a record of pointers, and nothing in the
game checks that what those pointers say agrees. Two mistakes are easy and
neither shows up as a crash: a meze whose y does not land on a platform -
so it hangs in the air, or is buried in the furniture and can never be
collected - and a basket in the same position, which makes the room
impossible to leave. The scripted runs in make check only ever play the
first room, so they would not catch either one in the other three.

This reads what was actually assembled rather than the source: the low
block is saved raw by src/mitsoslow.asm and every label in it is in
build/mitsos.sym, so the tables here are the bytes the Z80 will read.

Nothing about the climb is checked - whether the platforms can be reached
from one another in the order the mezedes are on them is a judgement about
the jump arc, and the pictures in docs/ are how that was looked at.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYM = os.path.join(ROOT, "build", "mitsos.sym")
LOW = os.path.join(ROOT, "build", "mitsosart.bin")
LOW_ORG = 0x0100                        # where mitsoslow.asm assembles it

PICK_COUNT = 5
P_SIZE = 8
R_SIZE = 21
BASKET_W = 8
BASKET_H = 20                           # box_basket, and what it stands on


def load():
    syms = {}
    for line in open(SYM, encoding="utf-8"):
        p = line.split()
        if len(p) >= 2 and p[1].startswith("#"):
            syms[p[0].upper()] = int(p[1][1:], 16)
    mem = bytearray(0x10000)
    blob = open(LOW, "rb").read()
    mem[LOW_ORG:LOW_ORG + len(blob)] = blob
    return syms, mem


def word(mem, a):
    return mem[a] | (mem[a + 1] << 8)


def platforms(mem, a):
    """first column, last column, top scanline - #FF ends it."""
    out = []
    while mem[a] != 0xFF:
        out.append((mem[a], mem[a + 1], mem[a + 2]))
        a += 3
    return out


def standing_on(plats, x, w, top):
    """A platform whose top is exactly this, under the whole width of it."""
    for x0, x1, y in plats:
        if y == top and x >= x0 and x + w - 1 <= x1:
            return (x0, x1, y)
    return None


def main():
    if not os.path.exists(SYM) or not os.path.exists(LOW):
        sys.exit("roomcheck: build/mitsos.sym and build/mitsosart.bin first")
    syms, mem = load()
    rooms = syms["ROOMS"]
    count = sum(1 for n in range(1, 100) if "R%d_PLAT" % n in syms)

    bad = 0
    for n in range(count):
        rec = rooms + n * R_SIZE
        plats = platforms(mem, word(mem, rec + 0))
        picks = word(mem, rec + 6)
        bx, by = mem[rec + 11], mem[rec + 12]

        where = standing_on(plats, bx, BASKET_W, by + BASKET_H)
        if where is None:
            print("room %d: the basket at %d,%d is not standing on anything"
                  % (n + 1, bx, by))
            bad += 1

        for i in range(PICK_COUNT):
            p = picks + i * P_SIZE
            spr = word(mem, p)
            w, h = mem[spr], mem[spr + 1]
            x, y = mem[p + 2], mem[p + 3]
            where = standing_on(plats, x, w, y + h)
            if where is None:
                print("room %d: the pickup at %d,%d (%dx%d) has nothing under "
                      "it - its feet are on scanline %d"
                      % (n + 1, x, y, w, h, y + h))
                bad += 1

        print("    room %d  %d platforms, %d things to pick up, the way out "
              "at %d,%d" % (n + 1, len(plats), PICK_COUNT, bx, by))

    if bad:
        sys.exit("roomcheck: %d of them are standing on nothing" % bad)
    print("    every meze and every basket in %d rooms is standing on a "
          "platform its own room names" % count)


if __name__ == "__main__":
    main()
