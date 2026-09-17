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

Early. Nothing implemented yet — see [CLAUDE.md](CLAUDE.md) for the technical groundwork
the implementation is built on.

## Proposed layout

```
src/        Z80 sources (assembler TBD — rasm is the current front-runner)
build/      assembled binaries and .dsk images
docs/       notes, register tables, measurements from real hardware
tools/      host-side helpers (image conversion, disk image building)
```

## Testing

CRTC behaviour is where emulators disagree most, so anything here is checked on more
than one: **ACE-DL**, **CPCEC** and **WinAPE** are the accurate references, with real
6128 hardware as the final word. Emulator CRTC type must be set explicitly for every test.
