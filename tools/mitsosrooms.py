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

This reads what was actually assembled rather than the source. The rooms
are saved raw by src/mitsosbank.asm as the image that goes into bank 4 -
fixed blocks at fixed offsets, which is what makes them checkable without
knowing a single label - and the low block beside it holds the sprites
their pickups point at.

Nothing about the climb is checked - whether the platforms can be reached
from one another in the order the mezedes are on them is a judgement about
the jump arc, and the pictures in docs/ are how that was looked at.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOW = os.path.join(ROOT, "build", "mitsosart.bin")
ROOMS = os.path.join(ROOT, "build", "mitsosrooms.bin")
LOW_ORG = 0x0100                        # where mitsoslow.asm assembles it
ROOM_BANK = 0x4000                      # and where bank 4 holds a room

#: mitsosshop.asm, and the asserts in the generated source check the game
#: agrees. Duplicated rather than parsed because they are the format.
ROOM_BLOCK = 192
R_BASKX, R_BASKY = 1, 2
R_PLAT, R_PICKS = 12, 72
PICK_COUNT = 5
P_SIZE = 8
BASKET_W = 8
BASKET_H = 20                           # box_basket, and what it stands on


def load():
    mem = bytearray(0x10000)
    blob = open(LOW, "rb").read()
    mem[LOW_ORG:LOW_ORG + len(blob)] = blob
    rooms = open(ROOMS, "rb").read()
    if len(rooms) % ROOM_BLOCK:
        sys.exit("roomcheck: %d bytes of rooms is not a whole number of "
                 "%d-byte blocks" % (len(rooms), ROOM_BLOCK))
    return mem, rooms


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
    for path in (LOW, ROOMS):
        if not os.path.exists(path):
            sys.exit("roomcheck: build %s first" % os.path.relpath(path, ROOT))
    mem, image = load()
    count = len(image) // ROOM_BLOCK
    # the rooms where the game will read them, so the offsets are the offsets
    mem[ROOM_BANK:ROOM_BANK + len(image)] = image

    bad = 0
    for n in range(count):
        rec = ROOM_BANK + n * ROOM_BLOCK
        plats = platforms(mem, rec + R_PLAT)
        picks = rec + R_PICKS
        bx, by = mem[rec + R_BASKX], mem[rec + R_BASKY]

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
