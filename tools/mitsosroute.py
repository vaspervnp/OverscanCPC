#!/usr/bin/env python3
"""Take the second game through all of its rooms and show that it ends.

    tools/mitsosroute.py                    the whole route
    tools/mitsosroute.py --step 60          a slower cadence, if one drifts
    tools/mitsosroute.py --verbose          every line z80check printed

Every other scripted run in make check plays the first room. This one
visits all twenty-nine and comes out the other side: each room loaded from
bank 4, painted, played for a moment, left through its basket, and after
the last one main_title, which is the only thing that says the game has an
end rather than a twenty-ninth room that goes nowhere.

It is a skip, not a playthrough, and the difference matters. Nothing here
jumps to a shelf or collects a meze: per room it pokes basket_open, drops
him where the basket is and drums fire. So it proves the machinery - the
bank paging, room_load, draw_shop, the room advance and the wrap back to
the title - and proves nothing whatever about whether a room is climbable.
That is tools/mitsosrooms.py's job, and the two are meant to be read
together.

Where he is put is the fix in mitsos_escape written the other way round:
his feet have to be inside the basket's own BASKET_H scanlines, so the
only y that works is the platform the basket is standing on. Poke him onto
the floor underneath it instead and the room does not finish, which is how
the escape test is known to be two-sided.

The geometry comes out of build/mitsos.sym rather than being copied here,
because rasm writes every EQU into it and a constant copied into a tool is
a constant that will one day disagree.
"""

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
GAME = os.path.join(BUILD, "mitsos.bin")
SYM = os.path.join(BUILD, "mitsos.sym")
ROOMS = os.path.join(BUILD, "mitsosrooms.bin")
Z80CHECK = os.path.join(ROOT, "tools", "z80check.py")

#: The first room is playable about this many frames after fire leaves the
#: title, and every room after it that many frames after the advance.
FIRST = 54
#: One room's whole turn: the advance, draw_shop repainting 26 KB of shop,
#: the pokes, and the WELL DONE panel that has to be up before fire counts.
STEP = 48
#: When inside a room's turn he is put in the basket. Four attempts rather
#: than one because how long draw_shop takes is the room's own business.
PUT = (22, 26, 30, 34, 38)
#: Fire every so many frames for the whole run. A press during the panel is
#: swallowed, so what matters is not when one lands but that the next one is
#: never far away - a drum does not drift, and a schedule does.
DRUM = 6

WATCH = re.compile(r"frame\s+(\d+)\s+cur_room=(\d+)\s+mitsos_over=(\d+)"
                   r"\s+mitsos_y=(\d+)")


def symbols():
    """The EQUs rasm wrote out, as a dict of name -> value."""
    out = {}
    with open(SYM, encoding="utf-8") as fh:
        for line in fh:
            bits = line.split()
            if len(bits) >= 2 and bits[1].startswith("#"):
                out[bits[0].upper()] = int(bits[1][1:], 16)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", type=int, default=STEP,
                    help="frames per room (default %d)" % STEP)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    for path in (GAME, SYM, ROOMS):
        if not os.path.exists(path):
            sys.exit("%s: not built - run make first" % path)

    sym = symbols()
    block = sym["ROOM_BLOCK"]
    baskx, basky = sym["R_BASKX"], sym["R_BASKY"]
    #: Standing on what the basket stands on: the basket's feet are
    #: basky + BASKET_H, and his own are mitsos_y + MITSOS_H - 1.
    drop = sym["BASKET_H"] - sym["MITSOS_H"] + 1

    img = open(ROOMS, "rb").read()
    rooms = len(img) // block

    pokes, keys = [], ["FIRE@30-30"]
    for i in range(rooms):
        f = FIRST + args.step * i
        rec = i * block
        pokes += ["--poke", "mitsos_lives=3@%d" % (f + PUT[0] - 2)]
        for d in PUT:
            pokes += ["--poke", "basket_open=1@%d" % (f + d),
                      "--poke", "mitsos_x=%d@%d" % (img[rec + baskx], f + d),
                      "--poke", "mitsos_y=%d@%d"
                      % (img[rec + basky] + drop, f + d)]
    #: Long enough after the last basket for main_title to repaint and for a
    #: press to start the game over again, which is what proves it wrapped.
    frames = FIRST + args.step * rooms + 120
    keys += ["FIRE@%d-%d" % (k, k + 1) for k in range(60, frames, DRUM)]

    cmd = [sys.executable, Z80CHECK, GAME, "--org", "0x4000",
           "--frames", str(frames), "--frame-instr", "40000",
           "--sym", SYM,
           "--watch", "cur_room,mitsos_over,mitsos_y"] + pokes \
        + ["--keys", ",".join(keys)]
    run = subprocess.run(cmd, capture_output=True, text=True)
    if args.verbose:
        sys.stdout.write(run.stdout)
    if run.returncode:
        sys.stderr.write(run.stderr)
        sys.exit("z80check failed")

    seen = [m.groups() for m in (WATCH.search(l)
                                 for l in run.stdout.splitlines()) if m]
    if not seen:
        sys.exit("z80check printed nothing to read - is --watch still right?")

    advance, painted, basket = {}, {}, {}
    here = None
    wrapped = None
    for f, r, o, y in ((int(a), int(b), int(c), int(d)) for a, b, c, d in seen):
        if r != here:
            here = r
            #: cur_room is only written by the advance and by game_start, so
            #: seeing room 0 again after the last basket is the wrap itself.
            if r in advance:
                wrapped = wrapped or f
                continue
            advance[r] = f
        if r in advance and r not in painted and y == sym["MITSOS_Y0"]:
            painted[r] = f             # room_start has put him on its floor
        if r in painted and r not in basket and o == 2:
            basket[r] = f              # and he has gone out through it

    print("    room  advance  painted   basket")
    bad = 0
    for r in range(rooms):
        cells = [advance.get(r), painted.get(r), basket.get(r)]
        #: room 0 is not advanced into - it is what fire leaves the title for
        shown = ["title" if r == 0 and i == 0 else
                 ("%d" % c if c is not None else "-")
                 for i, c in enumerate(cells)]
        print("    %4d %8s %8s %8s" % (r, *shown))
        if None in cells:
            bad += 1
    if bad:
        sys.exit("%d of %d rooms did not finish - try a larger --step"
                 % (bad, rooms))
    if wrapped is None:
        sys.exit("the last basket did not take the game back to the title")
    print("    all %d rooms played and left through the basket; the last one"
          % rooms)
    print("    went back to the title, and fire started the game again at"
          " frame %d" % wrapped)


if __name__ == "__main__":
    main()
