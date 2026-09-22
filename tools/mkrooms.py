#!/usr/bin/env python3
"""Turn assets/mitsos/rooms.txt into src/mitsosrooms.asm.

    tools/mkrooms.py

A room in the second game is a fixed 192-byte block in bank 4, with its
tables at fixed offsets inside it - so room_read is one LDIR and every
read afterwards is an absolute address. Written by hand that means an ORG
per field per room, and with twenty-nine rooms one of them would be wrong
and nothing would say so. This does the offsets; rasm still does the
arithmetic, because every number here is passed through as an expression
and SHELF_2-8 means what it means in mitsosshop.asm.

The format is one room per block and one thing per line:

    room store-room
      light  wall=10 mortar=10 dado=10 floor=6 grout=15 border=6
      start  8                     where he comes in
      basket 66 SHELF_4-20         the way out, and it opens on the last meze
      beat   24 56                 the two ends of Grandma's walk
      stand  0 95 FLOOR_TOP        first column, last column, top scanline
      prop   66 76 shelving        x, y, and a box list in mitsosfurniture
      soap   54 66 FLOOR_TOP       somewhere he will not stop
      meze   sausage 10 SHELF_1-8  a picture, a column, and the top it sits on
      catnip 78 SHELF_3            the one the basket does not wait for
      mouse  30 FLOOR_TOP 24 62 1  x, the top it walks, its beat, its way
      gull   34 60 24 66 1         x, the line it hangs about on, beat, way

`light` names the five pens the painter uses and the border colour; give
any of the five the pen of the thing behind it and that feature is simply
not there. A pen is a number 0-15, as in pal_shop.

`meze` and `catnip` take the scanline they stand **on** rather than their
own y, because a meze whose feet are not on a platform is the mistake this
format exists to make impossible - tools/mitsosrooms.py checks the result
of that as well, out of the assembled image.

A mouse or a gull may be followed by `steal` (it starts its clock part-run,
so the first meze is not gone before he has had a chance at it), `rest`, or
a number of frames to wait.

Every room has three of them after him and five things to pick up, four of
which the basket waits for. That is the game's grammar rather than a
room's business, and a room that breaks it is refused here.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "mitsos", "rooms.txt")
OUT = os.path.join(ROOT, "src", "mitsosrooms.asm")

#: The block, and where each table starts in it. mitsosshop.asm has the same
#: numbers, and the asserts at the bottom of the output check they agree.
ROOM_BLOCK = 192
R_PLAT, PLAT_MAX = 12, 8
R_PROPS, PROPS_MAX = 37, 6
R_SOAP, SOAP_MAX = 62, 3
R_PICKS, PICK_COUNT = 72, 5
R_FOES, FOE_COUNT = 112, 3
MEZE_COUNT = 4

PENS = ("wall", "mortar", "dado", "floor", "grout", "border")
#: The pen Mitsos himself is drawn in. A room painted in it loses him: he is
#: an orange cat, and against an orange wall what is left of him is the dark
#: red of his stripes and the white of his belly. It is the same mistake
#: Grandma's face made against the coral brick of the shop, and it does not
#: show up in anything but a picture - the game knows exactly where he is.
HIS_PEN = "7"
#: and the ones a room may not paint the ground he walks on in. `mortar` and
#: `grout` are lines a pixel or two wide and he is twenty-four scanlines, so
#: those may be anything.
HIS_GROUND = ("wall", "dado", "floor")
KINDS = {"mouse": "K_MOUSE", "gull": "K_GULL"}
#: What a foe's E_REST starts at. A mouse that steals wants a head start.
REST = {"steal": "STEAL_START", "rest": "STEAL_REST"}


def die(n, msg):
    sys.exit("mkrooms: %s line %d: %s" % (os.path.relpath(SRC, ROOT), n, msg))


def read():
    rooms = []
    cur = None
    for n, raw in enumerate(open(SRC, encoding="utf-8"), 1):
        line = raw.split(";")[0].strip()
        if not line:
            continue
        word, _, rest = line.partition(" ")
        rest = rest.strip()
        if word == "room":
            cur = {"name": rest, "line": n, "stand": [], "prop": [],
                   "soap": [], "pick": [], "foe": []}
            rooms.append(cur)
            continue
        if cur is None:
            die(n, "%r before any room" % word)
        f = rest.split()
        if word == "light":
            pens = {}
            for item in f:
                k, _, v = item.partition("=")
                if k not in PENS:
                    die(n, "%r is not one of %s" % (k, ", ".join(PENS)))
                pens[k] = v
            missing = [p for p in PENS if p not in pens]
            if missing:
                die(n, "light is missing %s" % ", ".join(missing))
            cur["light"] = pens
        elif word in ("start",):
            cur["start"] = f[0]
        elif word == "basket":
            cur["basket"] = f[:2]
        elif word == "beat":
            cur["beat"] = f[:2]
        elif word == "stand":
            cur["stand"].append(f[:3])
        elif word == "prop":
            cur["prop"].append(f[:3])
        elif word == "soap":
            cur["soap"].append(f[:3])
        elif word in ("meze", "catnip"):
            if word == "catnip":
                cur["pick"].append(("catnip", f[0], f[1], 0))
            else:
                cur["pick"].append((f[0], f[1], f[2], 1))
        elif word in KINDS:
            cur["foe"].append((word, f))
        else:
            die(n, "%r is not a thing a room has" % word)
    return rooms


def check(r):
    n = r["line"]
    for key in ("light", "start", "basket", "beat"):
        if key not in r:
            die(n, "room %s has no %s" % (r["name"], key))
    for key, most in (("stand", PLAT_MAX), ("prop", PROPS_MAX),
                      ("soap", SOAP_MAX)):
        if len(r[key]) > most:
            die(n, "room %s has %d %s and there is room for %d"
                % (r["name"], len(r[key]), key, most))
    if not r["stand"]:
        die(n, "room %s has nothing to stand on" % r["name"])
    for key in HIS_GROUND:
        if r["light"][key] == HIS_PEN:
            die(n, "room %s paints its %s in pen %s, which is the pen Mitsos "
                   "is drawn in - he would walk about in it invisible"
                % (r["name"], key, HIS_PEN))
    if len(r["pick"]) != PICK_COUNT:
        die(n, "room %s has %d things to pick up and every room has %d"
            % (r["name"], len(r["pick"]), PICK_COUNT))
    mezes = sum(1 for p in r["pick"] if p[3])
    if mezes != MEZE_COUNT:
        die(n, "room %s has %d mezedes and the basket waits for %d"
            % (r["name"], mezes, MEZE_COUNT))
    if len(r["foe"]) != FOE_COUNT:
        die(n, "room %s has %d after him and every room has %d"
            % (r["name"], len(r["foe"]), FOE_COUNT))


def foe_bytes(kind, f):
    """kind, x, y, the line a flier bobs about, the two ends, and its way."""
    if kind == "gull":
        x, y0, x0, x1, d = f[0], f[1], f[2], f[3], f[4]
        extra = f[5:]
        head = "K_GULL, %s, %s, %s, %s, %s, %s" % (x, y0, y0, x0, x1, d)
    else:
        x, top, x0, x1, d = f[0], f[1], f[2], f[3], f[4]
        extra = f[5:]
        head = "K_MOUSE, %s, %s-SPR_MOUSE_A_H, 0, %s, %s, %s" % (
            x, top, x0, x1, d)
    rest = "0"
    if extra:
        rest = REST.get(extra[0], extra[0])
    return head, rest


def main():
    rooms = read()
    if not rooms:
        sys.exit("mkrooms: no rooms in %s" % SRC)
    for r in rooms:
        check(r)

    w = []
    w.append(";; Generated by tools/mkrooms.py from assets/mitsos/rooms.txt")
    w.append(";; - do not edit. The format, and why there is a generator at")
    w.append(";; all, are at the top of the tool.")
    w.append(";;")
    w.append(";; These are assembled at ROOM_BANK for bank 4 and never run in")
    w.append(";; place: src/mitsosbank.asm saves the image, the file carries")
    w.append(";; it, and rooms_to_bank puts it where it belongs at boot.")
    w.append("")
    w.append("ROOM_COUNT      EQU %d" % len(rooms))
    w.append("")

    for i, r in enumerate(rooms):
        base = "ROOM_BANK+%d*ROOM_BLOCK" % i
        w.append(";; --- %d: %s %s" % (i + 1, r["name"],
                                       "-" * max(0, 58 - len(r["name"]))))
        w.append("    ORG %s" % base)
        L = r["light"]
        w.append("    defb %-26s ; where he comes in" % r["start"])
        w.append("    defb %s, %-18s ; the way out" % tuple(r["basket"]))
        w.append("    defb %s, %-18s ; her beat" % tuple(r["beat"]))
        w.append("    defb PEN%s_BYTE, PEN%s_BYTE, PEN%s_BYTE, PEN%s_BYTE, "
                 "PEN%s_BYTE" % tuple(L[p] for p in PENS[:5]))
        w.append("    defb #40+%s" % L["border"])

        w.append("    ORG %s+R_PLAT" % base)
        for s in r["stand"]:
            w.append("    defb %s, %s, %s" % tuple(s))
        w.append("    defb #FF")
        w.append("    ASSERT $ <= %s+R_PROPS" % base)

        w.append("    ORG %s+R_PROPS" % base)
        for p in r["prop"]:
            w.append("    defb %s, %s" % (p[0], p[1]))
            w.append("    defw box_%s" % p[2])
        w.append("    defb #FF")
        w.append("    ASSERT $ <= %s+R_SOAP" % base)

        w.append("    ORG %s+R_SOAP" % base)
        for s in r["soap"]:
            w.append("    defb %s, %s, %s" % tuple(s))
        w.append("    defb #FF")
        w.append("    ASSERT $ <= %s+R_PICKS" % base)

        w.append("    ORG %s+R_PICKS" % base)
        for name, x, top, meze in r["pick"]:
            w.append("    defw spr_%s" % name)
            w.append("    defb %s, %s-SPR_FISH_H, %d, 1, #FF, 0"
                     % (x, top, meze))
        w.append("    ASSERT $ == %s+R_FOES" % base)

        w.append("    ORG %s+R_FOES" % base)
        for kind, f in r["foe"]:
            head, rest = foe_bytes(kind, f)
            w.append("    defb %s" % head)
            w.append("    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, "
                     "%s, 0, 0" % rest)
        w.append("    ASSERT $ == %s+ROOM_USED" % base)
        w.append("")

    w.append("    ORG ROOM_BANK+ROOM_COUNT*ROOM_BLOCK")
    w.append("rooms_end")

    open(OUT, "w", encoding="utf-8").write("\n".join(w) + "\n")
    print("mkrooms: %d rooms, %d bytes in the bank"
          % (len(rooms), len(rooms) * ROOM_BLOCK))


if __name__ == "__main__":
    main()
