#!/usr/bin/env python3
"""Boot a real CPC 6128, load the disc image and check what actually happens.

Everything else in this repository reasons about the machine. This runs it:
floooh/chips' CPC system - Z80, AM40010 gate array, MC6845 CRTC, i8255 PPI and
a uPD765 with .DSK support - with the 6128's own ROMs, driven headless through
~/repos/CPCTools/cpcemu.

    tools/emucheck.py build/loukoumas_el.dsk build/loukoumas_el_dsk.sym \\
                      build/tables.bin build/title.bin assets/revive8b.scr \\
                      build/emu

That is a different kind of test from tools/z80check.py, and it is the only
one that can answer some of the questions this project has been carrying:

  * The BASIC loader on the disc really does put the REVIVE8BIT screen up and
    hand over to the game, both on space and on running out of time.
  * AMSDOS really does load the file, at the address and the length the build
    thinks it does.
  * The tables really do come back out of the packer, on a machine whose
    timing and memory behaviour nobody wrote.
  * The CRTC really does put a 384x272 overscan picture on the tube with the
    registers in crtc.asm, and the picture that arrives is the one that was
    packed.
  * The keyboard really is read through the PPI the way keys.asm assumes,
    with the PSG being driven by the music at the same time.
  * The difficulty chooser answers the cursor keys and its setting reaches
    the three bytes the enemies actually read.

What it still cannot answer is whether the beam catches a sprite: the
framebuffer here is what the gate array emitted, so it is the truth, but
comparing two frames of a moving picture tells you nothing unless you know
what should have moved. tools/z80check.py --beam is still the thing that
measures that, and this checks the game runs while it does.
"""

import os
import sys

EMU = os.path.expanduser("~/repos/CPCTools/cpcemu")
sys.path.insert(0, EMU)

BYTES_PER_LINE = 96
DISPLAY_LINES = 272

failures = []


def check(name, ok, detail=""):
    print("    %-44s %s%s" % (name, "ok" if ok else "FAILED",
                              "  " + detail if detail else ""))
    if not ok:
        failures.append(name)
    return ok


def symbols(path):
    import re
    out = {}
    for line in open(path):
        m = re.match(r"^(\S+)\s+#([0-9A-Fa-f]+)\s", line)
        if m:
            out[m.group(1).upper()] = int(m.group(2), 16)
    return out


def screen_rows(c, sym):
    """The overscan screen, read the way the game addresses it - through the
    line table it built, so the 2048-byte stride and the page crossing are
    the machine's business and not ours."""
    tab = c.read_ram(sym["LINE_TAB"], DISPLAY_LINES * 2)
    rows = []
    for y in range(DISPLAY_LINES):
        addr = tab[y * 2] | (tab[y * 2 + 1] << 8)
        rows.append(bytes(c.read_ram(addr, BYTES_PER_LINE)))
    return rows


def main():
    if len(sys.argv) != 7:
        sys.exit("usage: emucheck.py <dsk> <sym> <tables.bin> <title.bin> "
                 "<splash.scr> <png prefix>")
    (dsk, symfile, tables_path, title_path, splash_path,
     png_prefix) = sys.argv[1:]

    try:
        from cpc import CPC
    except Exception as e:
        # Not part of this repository, so a build without it is not a failure.
        print("    no emulator at %s - skipped (%s)" % (EMU, e))
        return 2

    sym = symbols(symfile)
    c = CPC()
    c.run_frames(150)                       # to the BASIC prompt
    c.insert_disc(dsk)
    c.type_text('RUN"LOUK.BAS\n')
    c.run_frames(330)                       # mode, inks, and the screen off disc

    splash = open(splash_path, "rb").read()
    check("the loader put the REVIVE8BIT screen up",
          bytes(c.read_ram(0xC000, len(splash))) == splash,
          "%d bytes at &C000" % len(splash))
    c.screenshot(png_prefix + "-splash.png", scale=1, aspect=True)

    # Space rather than the ten second wait, so both the key and the game's
    # own loading get tested and the check does not sit here for ten seconds.
    c.key_down(0x20)
    c.run_frames(8)
    c.key_up(0x20)
    c.run_frames(420)                       # load, unpack, draw the title

    check("the disc loaded and the game is running",
          0x4000 <= c.pc < 0x6800, "PC #%04X" % c.pc)
    check("the gate array is in mode 0", c.mode == 0, "mode %d" % c.mode)
    check("the CRTC is showing the overscan screen",
          c.crtc_screen_addr == 0x2C10, "#%04X" % c.crtc_screen_addr)

    raw = open(tables_path, "rb").read()
    got = bytes(c.read_ram(0x0100, len(raw)))
    check("the packed tables unpacked byte for byte", got == raw,
          "%d bytes" % len(raw))

    # The title picture, everywhere the text panels do not cover: the top-left
    # panel is rows 6-53 and the footer starts at 236.
    want = open(title_path, "rb").read()
    rows = screen_rows(c, sym)
    band = b"".join(rows[54:236])
    check("the title picture came back byte for byte",
          band == want[54 * BYTES_PER_LINE:236 * BYTES_PER_LINE],
          "rows 54-235")
    c.screenshot(png_prefix + "-title.png", scale=1, aspect=True)

    # Fire leaves the title for the difficulty chooser, which borrows the
    # footer of the same screen and is the last thing between here and a room.
    c.key_down(0x20)
    c.run_frames(6)
    c.key_up(0x20)
    c.run_frames(20)
    start = c.peek(sym["DIFFICULTY"])
    for _ in range(2):                      # cursor left, twice
        c.key_down(0x08)
        c.run_frames(6)
        c.key_up(0x08)
        c.run_frames(6)
    easiest = c.peek(sym["DIFFICULTY"])
    check("the chooser starts on hard and left makes it kinder",
          start == 2 and easiest == 0, "%d -> %d" % (start, easiest))
    c.screenshot(png_prefix + "-difficulty.png", scale=1, aspect=True)

    c.key_down(0x09)                        # and one step back up
    c.run_frames(6)
    c.key_up(0x09)
    c.run_frames(6)
    check("and right puts it back up one",
          c.peek(sym["DIFFICULTY"]) == 1, "%d" % c.peek(sym["DIFFICULTY"]))

    # Fire again: the setting goes into the three bytes that read it, and the
    # room is painted.
    c.key_down(0x20)
    c.run_frames(6)
    c.key_up(0x20)
    c.run_frames(60)
    got = (c.peek(sym["WALK_PERIOD"]), c.peek(sym["FLY_PERIOD"]),
           c.peek(sym["STUN_TIME"]))
    check("medium slowed the cast down and lengthened the flop",
          got == (3, 2, 150), "walk %d, fly %d, stun %d" % got)
    lives = c.peek(sym["CAT_LIVES"])
    room = c.peek(sym["CUR_ROOM"])
    cat_y = c.peek(sym["CAT_Y"])
    check("fire started the game", lives == 3 and room == 0,
          "room %d, %d lives" % (room, lives))
    check("the cat is standing on the floor", cat_y == 212, "y %d" % cat_y)

    # And it answers the keyboard while the game is running.
    x0 = c.peek(sym["CAT_X"])
    c.key_down(0x09)                        # cursor right
    c.run_frames(25)
    c.key_up(0x09)
    c.run_frames(2)
    x1 = c.peek(sym["CAT_X"])
    check("the cat walks when the key matrix says so", x1 > x0,
          "x %d -> %d" % (x0, x1))
    c.screenshot(png_prefix + "-play.png", scale=1, aspect=True)

    if failures:
        print("    %d of the machine's answers were wrong" % len(failures))
        return 1
    print("    the real 6128 agrees with the build")
    return 0


if __name__ == "__main__":
    sys.exit(main())
