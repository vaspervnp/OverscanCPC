# OverscanCPC

A proof of concept for Amstrad CPC programs running in **overscan mode**, driving the
CRTC 6845 to its full capability instead of the 40x25 / 16 KB screen the firmware sets up.

## What this is

The stock CPC display is a firmware convention, not a hardware limit: 40 characters by
25 rows, one 16 KB page, surrounded by a border. The 6845 CRTC can be reprogrammed to
display far more than that — enough to push the picture out over the border on all four
sides. This repository is a proof of concept that does exactly that, and explores what
becomes possible once the CRTC is treated as a programmable raster engine rather than a
fixed-mode text controller.

Target machine: **Amstrad CPC 6128** (128 KB, CRTC types 0/1/2 as shipped).

## Goals

- Set up and hold a stable full-overscan display (48 CRTC characters wide, ~34-35 rows tall)
  on a 6128 without firmware assistance.
- Handle the >16 KB screen that overscan requires: 32 KB of video RAM, the CRTC address
  wrap, and the bank layout that makes it work.
- Demonstrate **rupture** — reprogramming R4/R9/R12/R13 mid-frame to split the display
  into independently-addressed blocks.
- Demonstrate hardware scrolling (R12/R13 coarse, R3/R5 fine) across an overscan screen.
- Demonstrate mid-screen Gate Array effects (palette and mode changes per raster line)
  inside the overscan area.
- Stay within a 312-line, 50 Hz frame so a real CTM monitor keeps sync.

## Non-goals

- Firmware compatibility. Overscan and the CPC firmware do not coexist; this runs with
  interrupts and ROMs under our own control.
- CPC Plus / ASIC-specific features. Plus hardware is out of scope except where CRTC
  type 3/4 behaviour affects compatibility.
- A finished demo or game. This is a testbed for techniques, kept small and readable.

## Status

First milestone done: a 384x272 full-overscan screen with HELLO WORLD in 64x96-pixel
letters. See [CLAUDE.md](CLAUDE.md) for the technical groundwork it is built on.

## Building

Needs [rasm](https://github.com/EdouardBERGE/rasm) on your PATH. Then:

```bash
make
```

| Target | Output | How to run it |
|--------|--------|---------------|
| `make sna` | `build/hello.sna` | drop it on an emulator |
| `make dsk` | `build/hello.dsk` | insert the disc, then `RUN"HELLO` |
| `make bin` | `build/hello.bin` | raw code, loads and runs at `#4000` |

## What the demo shows

![expected screen](docs/expected-screen.png)

Everything blue is picture where a stock CPC would be showing border. The black
rectangle is exactly the area a normal 40x25 mode 1 screen covers, so the demo draws
the letters straight across its edges — and because the glyphs are OR-ed onto the
background, each letter changes from yellow to white at precisely the point where a
normal screen would have clipped it.

Under the hood:

- 48x34 CRTC characters — 96 bytes by 272 scanlines, 26,112 bytes of video RAM.
- A 32 KB screen spanning `#8000-#FFFF`, with **no rupture**: the display start address
  is set to `#2C10` so that MA rolls from `#2FFF` to `#3000` after exactly 21 character
  rows, flipping MA12 and carrying the fetch from page 2 into page 3 on a row boundary.
  That sidesteps the 1024-character wrap described in CLAUDE.md section 2.
- No firmware: ROMs off, interrupts off, own stack.
- The frame stays 312 lines at 50 Hz — overscan grows the window, not the frame.

The image above is a software render of screen RAM decoded through the CPC's CRTC
addressing, not a capture from an emulator or real hardware.

## Tools

`tools/z80check.py` runs the assembled code on a small Z80 interpreter, watches the CRTC
and Gate Array writes it makes, and decodes screen RAM through the CPC's real MA/RA
address wiring. It is how the picture above was produced, and how a screen layout gets
checked without an emulator:

```bash
make check
```

Add `--png out.png` for an image instead of the terminal preview (needs Pillow).

It models **no timing whatsoever** — no cycles, no interrupts, no ROMs, no banking, and
one static frame decoded from the registers left set at the end of the run. It can tell
you whether your addresses and fills are right. It can tell you nothing about rupture,
raster splits or anything else that depends on *when* a write happens. It aborts on any
opcode it does not implement rather than guessing.

## Layout

```
src/        Z80 sources (rasm)
tools/      host-side helpers
build/      assembled binaries and .dsk images (not in git)
docs/       notes, register tables, measurements from real hardware
```

## Testing

CRTC behaviour is where emulators disagree most, so anything here is checked on more
than one: **ACE-DL**, **CPCEC** and **WinAPE** are the accurate references, with real
6128 hardware as the final word. Emulator CRTC type must be set explicitly for every test.
