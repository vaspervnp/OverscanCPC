#!/usr/bin/env python3
"""Photograph one of the second game's rooms on a real 6128.

    tools/mitsosshot.py 3 docs/mitsos-yard-6128.png

Everything in docs/mitsos-room*.png came out of tools/z80check.py, which
executes the code and decodes video RAM through the CPC's own MA/RA wiring -
so it is right about the layout, and it is a model. This boots floooh/chips'
6128 instead, with the machine's own ROMs, puts the disc in and types
RUN"MITSOS.BIN at it, which is what a person would do. What comes back is
what the gate array emitted.

The room is a -DSTARTROOM= build, because the alternative is playing four
rooms to the end to see the fourth: the disc this writes is a scratch disc
and not the one the repository ships.

The emulator is not part of this repository (~/repos/CPCTools/cpcemu), so
without it this says so and stops, the way tools/emucheck.py does.
"""

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMU = os.path.expanduser("~/repos/CPCTools/cpcemu")
sys.path.insert(0, EMU)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: mitsosshot.py <room 0-3> <out.png>")
    room, out = sys.argv[1], sys.argv[2]

    try:
        from cpc import CPC
    except Exception as e:
        sys.exit("mitsosshot: no emulator at %s (%s)" % (EMU, e))

    # rasm writes the disc where the SAVE in mitsos.asm says, so the real
    # one is put aside and handed back rather than quietly replaced by a
    # build that starts in the wrong room.
    real = os.path.join(ROOT, "build", "mitsos.dsk")
    with tempfile.TemporaryDirectory() as tmp:
        dsk = os.path.join(tmp, "room.dsk")
        kept = os.path.join(tmp, "kept.dsk") if os.path.exists(real) else None
        if kept:
            shutil.move(real, kept)
        try:
            subprocess.run(["rasm", "src/mitsos.asm", "-DTARGET=2",
                            "-DSTARTROOM=" + room, "-eo"],
                           cwd=ROOT, check=True,
                           stdout=subprocess.DEVNULL)
            shutil.move(real, dsk)
        finally:
            if kept:
                shutil.move(kept, real)

        c = CPC()
        c.run_frames(150)                   # to the BASIC prompt
        c.insert_disc(dsk)
        c.type_text('RUN"MITSOS.BIN\n')
        c.run_frames(600)                   # load, unpack, paint the title
        c.key_down(0x20)                    # space is fire
        c.run_frames(10)
        c.key_up(0x20)
        c.run_frames(301)                   # and draw_shop paints the room
        # An odd number, and that matters. run_frames stops on a frame
        # boundary, which is the tick the rebuild starts on - and the cast is
        # rebuilt top of the screen first, so whoever is lowest is put back
        # last and is exactly who a picture taken there is missing. The game
        # renders every second frame, so one more lands between two rebuilds
        # with the whole cast on the screen.
        if not 0x4000 <= c.pc < 0x6800:
            sys.exit("mitsosshot: PC is #%04X, which is not the game" % c.pc)
        c.screenshot(out, scale=1, aspect=True)
        print("wrote %s - room %s, mode %d, CRTC #%04X"
              % (out, room, c.mode, c.crtc_screen_addr))


if __name__ == "__main__":
    main()
