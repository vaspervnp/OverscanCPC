#!/usr/bin/env python3
"""Walk the room tables in an assembled build and refuse a room the cat
cannot actually play.

    tools/roomcheck.py build/loukoumas_el.bin build/loukoumas_el.sym

The room data in src/rooms.asm is hand-placed: platforms on a 32-scanline
grid, sausages standing on them, furniture drawn to match. Nothing in the
assembler notices when a shelf drifts two bytes out of reach or a sausage ends
up hanging in mid-air - the game just becomes quietly unfinishable. This reads
the tables back out of the binary, through the symbol file, and checks:

  * every sausage rests on a platform, inside its span
  * every third room has a saucer of milk on one, and no other room does
  * the cat starts on one
  * every platform can be reached from the start, one jump at a time
  * the exit can be reached from a platform the cat can get to, and no shelf
    runs into it
  * enemies patrol within the room, on something solid
  * furniture stays inside the screen

The numbers below are measured off the physics, not guessed: the cat clears
32 scanlines from a standing jump and walks a byte - four pixels - per frame,
which over the frames it spends at that height is twenty bytes of travel.
Those two numbers are the whole level design.
"""

import re
import sys

JUMP_UP = 32            # scanlines the cat clears from a standing jump
JUMP_ACROSS = 20        # bytes of gap it can cross while climbing (80 px)
STEP_ACROSS = 28        # bytes of gap on a level or downward hop


class Build:
    """The binary as the Z80 sees it once the game has started.

    The tables are assembled to run at DATA_ORG but travel in the file at
    DATA_STORE, because AMSDOS cannot load into the sixteen kilobytes the
    lower ROM sits over - see config.asm. The game moves them down in its
    first dozen instructions, so this does the same before reading anything:
    the symbols are all low-block addresses.
    """

    def __init__(self, binpath, sympath, org=0x4000):
        self.mem = bytearray(0x10000)
        code = open(binpath, "rb").read()
        self.mem[org:org + len(code)] = code
        self.sym = {}
        for line in open(sympath):
            m = re.match(r"^(\S+)\s+#([0-9A-Fa-f]+)\s", line)
            if m:
                self.sym[m.group(1).upper()] = int(m.group(2), 16)
        store = self.c("DATA_STORE")
        dest = self.c("DATA_ORG")
        size = self.c("DATA_LEN")
        self.mem[dest:dest + size] = self.mem[store:store + size]

    def __getitem__(self, addr):
        return self.mem[addr]

    def word(self, addr):
        return self.mem[addr] | (self.mem[addr + 1] << 8)

    def c(self, name):
        try:
            return self.sym[name.upper()]
        except KeyError:
            sys.exit("roomcheck: %s is not in the symbol file - build with "
                     "-s -sa" % name)


def read_rooms(b):
    size = b.c("R_SIZE")
    base = b.c("ROOMS")
    rooms = []
    for i in range(b.c("ROOM_COUNT")):
        r = base + i * size
        rooms.append({
            "index": i,
            "name": b[r + b.c("R_NAME")],
            "plat": b.word(r + b.c("R_PLAT")),
            "saus": b.word(r + b.c("R_SAUS")),
            "nsaus": b[r + b.c("R_NSAUS")],
            "enem": b.word(r + b.c("R_ENEM")),
            "nenem": b[r + b.c("R_NENEM")],
            "props": b.word(r + b.c("R_PROPS")),
            "exit_px": b[r + b.c("R_EXITPX")],
            "exit_py": b[r + b.c("R_EXITPY")],
            "exit_x": b[r + b.c("R_EXITX")],
            "exit_y": b[r + b.c("R_EXITY")],
            "exit_w": b[r + b.c("R_EXITW")],
            "exit_h": b[r + b.c("R_EXITH")],
            "shut": b[r + b.c("R_EXITSHUT")],
            "open": b[r + b.c("R_EXITOPEN")],
            "startx": b[r + b.c("R_STARTX")],
            "starty": b[r + b.c("R_STARTY")],
            "milkx": b[r + b.c("R_MILKX")],
            "milky": b[r + b.c("R_MILKY")],
            "pal": b[r + b.c("R_PAL")],
            "floor": b[r + b.c("R_FLOOR")],
        })
    return rooms


def read_platforms(b, addr):
    out = []
    while b[addr] != 0xFF:
        out.append((b[addr], b[addr + 1], b[addr + 2]))   # x0, x1, y
        addr += 3
    return out


def read_sausages(b, addr, n):
    return [(b[addr + 2 * i], b[addr + 2 * i + 1]) for i in range(n)]


def read_enemies(b, addr, n):
    return [tuple(b[addr + 7 * i + k] for k in range(7)) for i in range(n)]


def read_props(b, addr):
    out = []
    while b[addr] != 0xFF:
        out.append((b[addr], b[addr + 1], b[addr + 2]))   # id, x, y
        addr += 3
    return out


def read_boxes(b, addr):
    out = []
    while b[addr] != 0xFF:
        out.append(tuple(b[addr + k] for k in range(5)))  # dx, dy, w, h, pen
        addr += 5
    return out


def gap(a0, a1, b0, b1):
    """Horizontal distance in bytes between two spans, 0 if they touch."""
    if a1 >= b0 and b1 >= a0:
        return 0
    return b0 - a1 if b0 > a1 else a0 - b1


def reachable(plats, start):
    """Platforms the cat can get to from the one it starts on."""
    seen = {start}
    edge = [start]
    while edge:
        i = edge.pop()
        x0, x1, y = plats[i]
        for j, (nx0, nx1, ny) in enumerate(plats):
            if j in seen:
                continue
            rise = y - ny                       # positive means climbing
            if rise > JUMP_UP:
                continue
            across = gap(x0, x1, nx0, nx1)
            limit = JUMP_ACROSS if rise > 0 else STEP_ACROSS
            if across > limit:
                continue
            seen.add(j)
            edge.append(j)
    return seen


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: roomcheck.py <binary> <symbols>")
    b = Build(sys.argv[1], sys.argv[2])

    floor_y = b.c("FLOOR_Y")
    cat_h = b.c("SPR_CAT_STAND_H")
    saus_h = b.c("SPR_SAUSAGE_H")
    saus_w = b.c("SPR_SAUSAGE_W")
    milk_h = b.c("SPR_MILK_H")
    milk_w = b.c("SPR_MILK_W")
    line_w = b.c("BYTES_PER_LINE")
    lines = b.c("DISPLAY_LINES")
    play_top = b.c("PLAY_TOP")
    prop_boxes = b.c("PROP_BOXES")
    decal_table = b.c("DECAL_TABLE")
    enemy_kinds = b.c("ENEMY_KINDS")

    bad = []
    for r in read_rooms(b):
        n = r["index"] + 1
        def fail(msg):
            bad.append("room %d: %s" % (n, msg))

        plats = read_platforms(b, r["plat"])
        if not plats:
            fail("no platforms")
            continue

        # Where does the cat start?
        start = None
        for i, (x0, x1, y) in enumerate(plats):
            if y == r["starty"] + cat_h and x0 <= r["startx"] <= x1:
                start = i
        if start is None:
            fail("starts at x=%d y=%d, which is not on any platform"
                 % (r["startx"], r["starty"]))
            continue

        got = reachable(plats, start)
        for i, (x0, x1, y) in enumerate(plats):
            if i not in got:
                fail("platform %d..%d at y=%d cannot be reached" % (x0, x1, y))

        # Sausages stand on a platform, and on one the cat can get to.
        for si, (sx, sy) in enumerate(read_sausages(b, r["saus"], r["nsaus"])):
            on = [i for i, (x0, x1, y) in enumerate(plats)
                  if y == sy + saus_h and x0 <= sx and sx + saus_w <= x1 + 1]
            if not on:
                fail("sausage %d at x=%d y=%d is not standing on a platform"
                     % (si + 1, sx, sy))
            elif not (set(on) & got):
                fail("sausage %d at x=%d y=%d is out of reach" % (si + 1, sx, sy))

        # A sausage under the cat's feet at frame one is a free point and a
        # HUD that starts at 1/5, which reads as a bug.
        cat_w = b.c("SPR_CAT_STAND_W")
        for si, (sx, sy) in enumerate(read_sausages(b, r["saus"], r["nsaus"])):
            if (sx < r["startx"] + cat_w and r["startx"] < sx + saus_w
                    and sy < r["starty"] + cat_h and r["starty"] < sy + saus_h):
                fail("sausage %d is where the cat starts" % (si + 1))

        # The saucer, in every third room, has to stand on a platform the
        # cat can get to - it is the only way to earn a life back, and one
        # hanging in mid-air would simply never be collected.
        if r["milkx"] != b.c("NO_MILK"):
            mx, my = r["milkx"], r["milky"]
            on = [i for i, (x0, x1, y) in enumerate(plats)
                  if y == my + milk_h and x0 <= mx and mx + milk_w <= x1 + 1]
            if not on:
                fail("the saucer at x=%d y=%d is not standing on a platform"
                     % (mx, my))
            elif not (set(on) & got):
                fail("the saucer at x=%d y=%d is out of reach" % (mx, my))
            for si, (sx, sy) in enumerate(read_sausages(b, r["saus"],
                                                        r["nsaus"])):
                if (sx < mx + milk_w and mx < sx + saus_w
                        and sy < my + milk_h and my < sy + saus_h):
                    fail("the saucer is on top of sausage %d" % (si + 1))
        if (r["index"] % 3 == 2) != (r["milkx"] != b.c("NO_MILK")):
            fail("every third room has a saucer and no other room does")

        # The exit has to overlap somewhere the cat can stand.
        ex0, ex1 = r["exit_x"], r["exit_x"] + r["exit_w"]
        ey0, ey1 = r["exit_y"], r["exit_y"] + r["exit_h"]
        if not any(ex1 > x0 and x1 + 1 > ex0 and ey1 > y - cat_h and y > ey0
                   for i, (x0, x1, y) in enumerate(plats) if i in got):
            fail("the way out at x=%d y=%d %dx%d is not reachable"
                 % (r["exit_x"], r["exit_y"], r["exit_w"], r["exit_h"]))

        # No shelf may run into the way out. draw_exit paints the door over
        # the shelf so it looks right, but the collision is still there and
        # the cat walks on nothing in the middle of the doorway.
        ex_w, ex_h = 0, 0
        for dx, dy, w, h, _pen in read_boxes(b, b.word(prop_boxes
                                                       + 2 * r["shut"])):
            ex_w = max(ex_w, dx + w)
            ex_h = max(ex_h, dy + h)
        for x0, x1, y in plats[1:]:                 # the floor is under it
            if (x1 >= r["exit_px"] and r["exit_px"] + ex_w > x0
                    and r["exit_py"] <= y < r["exit_py"] + ex_h):
                fail("the shelf %d..%d at y=%d runs into the way out at %d..%d"
                     % (x0, x1, y, r["exit_px"], r["exit_px"] + ex_w - 1))

        # Enemies patrol inside the room and stand on something. What an
        # enemy is comes out of enemy_kinds - the sprite it is drawn with and
        # which of the two behaviours moves it - so a wasp is measured as a
        # wasp rather than as whatever the first two types happened to be.
        for ei, e in enumerate(read_enemies(b, r["enem"], r["nenem"])):
            kind, ex, ey, _dx, x0p, x1p, _base = e
            if not 1 <= kind <= b.c("ET_COUNT"):
                fail("enemy %d is type %d, which does not exist" % (ei + 1, kind))
                continue
            row = enemy_kinds + (kind - 1) * b.c("EK_SIZE")
            spr = b.word(row)
            w, h, walks = b[spr], b[spr + 1], b[row + 4] == b.c("EB_WALK")
            if x1p + w > line_w:
                fail("enemy %d patrols to column %d, past the right edge"
                     % (ei + 1, x1p))
            if x0p > x1p:
                fail("enemy %d has an empty patrol %d..%d" % (ei + 1, x0p, x1p))
            if walks:
                if not any(y == ey + h and x0 <= x0p and x1p + w <= x1 + 1
                           for x0, x1, y in plats):
                    fail("enemy %d at y=%d patrols %d..%d, which is not a "
                         "platform" % (ei + 1, ey, x0p, x1p))

        # Furniture and scenery stay on screen. A prop id with bit 7 set is
        # a decal - a picture rather than a list of boxes - so its size comes
        # out of the decal table instead.
        for pid, px, py in read_props(b, r["props"]):
            if pid & 0x80:
                d = b.word(decal_table + 2 * (pid & 0x7F))
                pieces = [(0, 0, b[d], b[d + 1])]
                what = "decal %d" % (pid & 0x7F)
            else:
                pieces = [(dx, dy, w, h) for dx, dy, w, h, _pen
                          in read_boxes(b, b.word(prop_boxes + 2 * pid))]
                what = "prop %d" % pid
            for dx, dy, w, h in pieces:
                if px + dx + w > line_w:
                    fail("%s runs %d bytes past the right edge"
                         % (what, px + dx + w - line_w))
                    break
                if py + dy + h > lines:
                    fail("%s runs %d scanlines past the bottom"
                         % (what, py + dy + h - lines))
                    break
                if py + dy < play_top:
                    fail("%s starts above the play area" % what)
                    break

    if bad:
        for line in bad:
            print("roomcheck: " + line)
        sys.exit(1)
    print("roomcheck: %d rooms, every sausage and every way out reachable"
          % b.c("ROOM_COUNT"))


if __name__ == "__main__":
    main()
