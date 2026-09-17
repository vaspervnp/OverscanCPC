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
  * the cat starts on one
  * every platform can be reached from the start, one jump at a time
  * the exit can be reached from a platform the cat can get to
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
    def __init__(self, binpath, sympath, org=0x4000):
        self.mem = bytearray(0x10000)
        code = open(binpath, "rb").read()
        self.mem[org:org + len(code)] = code
        self.sym = {}
        for line in open(sympath):
            m = re.match(r"^(\S+)\s+#([0-9A-Fa-f]+)\s", line)
            if m:
                self.sym[m.group(1).upper()] = int(m.group(2), 16)

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
    robot_h = b.c("SPR_ROBOT_H")
    robot_w = b.c("SPR_ROBOT_W")
    canary_w = b.c("SPR_CANARY_W")
    line_w = b.c("BYTES_PER_LINE")
    lines = b.c("DISPLAY_LINES")
    play_top = b.c("PLAY_TOP")
    prop_boxes = b.c("PROP_BOXES")

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

        # The exit has to overlap somewhere the cat can stand.
        ex0, ex1 = r["exit_x"], r["exit_x"] + r["exit_w"]
        ey0, ey1 = r["exit_y"], r["exit_y"] + r["exit_h"]
        if not any(ex1 > x0 and x1 + 1 > ex0 and ey1 > y - cat_h and y > ey0
                   for i, (x0, x1, y) in enumerate(plats) if i in got):
            fail("the way out at x=%d y=%d %dx%d is not reachable"
                 % (r["exit_x"], r["exit_y"], r["exit_w"], r["exit_h"]))

        # Enemies patrol inside the room and stand on something.
        for ei, e in enumerate(read_enemies(b, r["enem"], r["nenem"])):
            kind, ex, ey, _dx, x0p, x1p, _base = e
            w = robot_w if kind == 1 else canary_w
            if x1p + w > line_w:
                fail("enemy %d patrols to column %d, past the right edge"
                     % (ei + 1, x1p))
            if x0p > x1p:
                fail("enemy %d has an empty patrol %d..%d" % (ei + 1, x0p, x1p))
            if kind == 1:
                if not any(y == ey + robot_h and x0 <= x0p and x1p + w <= x1 + 1
                           for x0, x1, y in plats):
                    fail("robot %d at y=%d patrols %d..%d, which is not a "
                         "platform" % (ei + 1, ey, x0p, x1p))

        # Furniture stays on screen.
        for pid, px, py in read_props(b, r["props"]):
            for dx, dy, w, h, _pen in read_boxes(b, b.word(prop_boxes + 2 * pid)):
                if px + dx + w > line_w:
                    fail("prop %d runs %d bytes past the right edge"
                         % (pid, px + dx + w - line_w))
                    break
                if py + dy + h > lines:
                    fail("prop %d runs %d scanlines past the bottom"
                         % (pid, py + dy + h - lines))
                    break
                if py + dy < play_top:
                    fail("prop %d starts above the play area" % pid)
                    break

    if bad:
        for line in bad:
            print("roomcheck: " + line)
        sys.exit(1)
    print("roomcheck: %d rooms, every sausage and every way out reachable"
          % b.c("ROOM_COUNT"))


if __name__ == "__main__":
    main()
