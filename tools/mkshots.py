#!/usr/bin/env python3
"""Every screen shot the manuals and the inlay use, in both languages.

    tools/mkshots.py            all of them
    tools/mkshots.py lounge     just that one, both languages

A shot is a build and a route: which room the game starts in, which keys are
held on which frames, and the frame to stop on. It is taken the same way
`make check` reads the screen - the game is run on the Z80 interpreter in
tools/z80check.py and screen RAM is decoded through the CRTC's addressing -
so a shot is the picture the hardware would put up, not a photograph of an
emulator window, and it comes out the same on any machine that builds this.

Everything is shot on easy, which is nine lives, and the route is the same in
both languages because only the text differs between the two builds.
"""

import os
import subprocess
import sys

BUILD = "build"
DOCS = "docs"
RASM = os.environ.get("RASM", "rasm")
LANGS = {"en": 0, "el": 1}

#: Two presses of fire with two of left between them: past the title, then the
#: difficulty chooser walked from hard down to easy. The room starts at 46.
START = "FIRE@22-26,LEFT@28-30,LEFT@32-34,FIRE@38-42"

#: The clean run of the lounge out of the Makefile, ten frames later because
#: the chooser is being walked rather than accepted where it stands.
LOUNGE = ("RIGHT@63-101,LEFT@102-124,FIRE@125-127,LEFT@153-161,RIGHT@163-207,"
          "FIRE@178-180,FIRE@210-212,DOWN@214-239,FIRE@216-218")

#: The kitchen is the end of act one and it is only worth a picture with the
#: fridge standing open, which happens on the fifth sausage - so four of them
#: are poked in and the cat collects the fifth. The game over is the same
#: trick from the other end: one life poked in, and the robot in the basement
#: takes it.
SHOTS = [
    # name        room  keys                                       frame  poke
    ("title",     None, "",                                          220, None),
    ("difficulty",None, "FIRE@190-194",                              210, None),
    ("lounge",       8, START + "," + LOUNGE,                        228, None),
    ("kitchen",      9, START + ",RIGHT@60-78,FIRE@74-78,RIGHT@84-96", 104,
                        "sausages_got=4@55"),
    ("backyard",    10, START + ",RIGHT@60-120,FIRE@96-99",          120, None),
    ("park",        13, START + ",RIGHT@52-64,FIRE@60-64,RIGHT@66-78", 70, None),
    ("rooftops",    27, START + ",RIGHT@60-120,FIRE@96-99",          120, None),
    ("gameover",     0, START + ",RIGHT@56-130",                     125,
                        "cat_lives=1@90"),
]


def newest_source():
    src = ["src/" + f for f in os.listdir("src") if f.endswith(".asm")]
    return max(os.path.getmtime(f) for f in src + [__file__])


def build(lang, room):
    """One binary per language and starting room, kept in build/."""
    name = "%s/shot_%s_%s.bin" % (BUILD, lang, "title" if room is None else room)
    if os.path.exists(name) and os.path.getmtime(name) > newest_source():
        return name
    args = [RASM, "src/loukoumas.asm", "-DTARGET=3", "-DLANG=%d" % LANGS[lang]]
    if room is None:                    # the one build that keeps the picture
        args.append("-DSTARTROOM=0")
    else:
        args += ["-DTITLEPIC=0", "-DSTARTROOM=%d" % room]
    args += ["-s", "-sa", "-os", name[:-4] + ".sym"]
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
    os.replace(BUILD + "/out.bin", name)
    return name


def shoot(name, room, keys, frame, poke):
    for lang in LANGS:
        binary = build(lang, room)
        out = "%s/loukoumas-%s-%s.png" % (DOCS, name, lang)
        args = ["./tools/z80check.py", binary, "--frames", str(frame),
                "--keys", keys, "--png", out]
        if poke:
            args += ["--sym", binary[:-4] + ".sym", "--poke", poke]
        subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
        print("mkshots: %s" % out)


def main():
    wanted = sys.argv[1:]
    for shot in SHOTS:
        if not wanted or shot[0] in wanted:
            shoot(*shot)


if __name__ == "__main__":
    main()
