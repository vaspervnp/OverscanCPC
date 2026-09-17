# CLAUDE.md — OverscanCPC

Project guidance and the hardware background needed to work on it.
Target: **Amstrad CPC 6128**, Z80 @ 4 MHz, Gate Array 40010/40008, CRTC 6845.

---

## 1. The baseline the firmware gives you

The CPC's "normal" screen is a CRTC configuration, nothing more. Firmware defaults:

| Reg | Name | Default | Meaning |
|-----|------|---------|---------|
| R0 | Horizontal Total | 63 | 64 CRTC chars per line = 64 us |
| R1 | Horizontal Displayed | 40 | 40 chars = 80 bytes per line |
| R2 | HSYNC Position | 46 | where the line sync pulse starts |
| R3 | Sync Widths | &8E | HSYNC 14 chars (low nibble), VSYNC 8 lines (high nibble) |
| R4 | Vertical Total | 38 | 39 character rows per frame |
| R5 | Vertical Total Adjust | 0 | extra scanlines to pad the frame |
| R6 | Vertical Displayed | 25 | 25 rows displayed |
| R7 | VSYNC Position | 30 | row at which VSYNC starts |
| R8 | Interlace / Skew | 0 | non-interlaced |
| R9 | Max Raster Address | 7 | 8 scanlines per character row |
| R10/R11 | Cursor | - | unused on CPC (no hardware cursor wired) |
| R12/R13 | Display Start Address | &30 / &00 | page 3 (&C000), offset 0 |

Derived constants that must not drift:

- **1 CRTC char = 1 us = 4 Z80 T-states = 2 bytes of video RAM.**
- Line = (R0+1) = 64 us.
- Frame = (R4+1) x (R9+1) + R5 = 39 x 8 + 0 = **312 scanlines** = 19.968 ms = 50.08 Hz.
- Pixels per CRTC char: mode 0 = 4, mode 1 = 8, mode 2 = 16.
  So 40 chars = 160 / 320 / 640 pixels.

**Rule: the total frame stays 312 lines and lines stay 64 us.** Overscan grows the
*displayed* window inside that frame; it never grows the frame. Break this and the
monitor rolls and the Gate Array interrupt cadence falls apart.

---

## 2. Screen address decoding — the thing that actually constrains overscan

The CRTC emits MA0-MA13 (memory address) and RA0-RA2 (raster address). The CPC wires
them to the address bus like this:

```
A15 A14          = MA13 MA12          <- 16K page select
A13 A12 A11      = RA2 RA1 RA0        <- scanline within the character row
A10 ... A1       = MA9 ... MA0        <- character position (only 10 bits!)
A0               = byte 0/1 of the CRTC character
```

**MA10 and MA11 are not connected.** Consequences, and they are the whole story of
CPC overscan:

1. Scanlines within a character row are 2048 bytes apart (that's RA moving A11-A13),
   not consecutive. The familiar "add &800 for the next line, wrap and add &50" address
   arithmetic comes from here.
2. Only **1024 character positions** (2048 bytes) are addressable per raster slice.
   Past 1024 the address aliases back onto itself.
3. Therefore the display is alias-free only while **R1 x R6 <= 1024**.
   Standard screen: 40 x 25 = 1000. That is not a coincidence — it is why the CPC
   screen is 40x25 and why it uses 16000 of its 16384 bytes.
4. R12 bits 4-5 select the 16K page (0=&0000, 1=&4000, 2=&8000, 3=&C000); R12 bits 0-3
   plus R13 give the character offset within it. MA rolling past &3FFF advances into
   the next page, but the 1024-char alias bites long before that.

### What that means for a full overscan screen

A full overscan display of 48 x 35 characters is 1680 characters — well over 1024. It
**cannot** be a single linear buffer:

```
48 chars x 2 bytes          = 96 bytes per scanline
35 rows x 8                 = 280 scanlines
96 x 280                    = 26,880 bytes  -> needs 32 KB, not 16 KB
1680 chars                  > 1024          -> aliases without intervention
```

Two ways out:

- **Stay under the limit.** Any R1 x R6 <= 1024 works with one base address and 16 KB.
  48 x 21 = 1008 (wide, 168 lines). 32 x 32 = 1024 (narrow, full height). Good for a
  first milestone; not full overscan.
- **Rupture.** Split the frame into two or more vertical blocks and reprogram R12/R13
  (usually with R4/R9) between them so each block restarts the address counter at a new
  base, in a different 16K page. This is how real 32 KB overscan screens are done, and
  it is the core technique this project needs to get right.

Also worth knowing: the leftover bytes in each 2K slice (48 bytes x 8 = 384 in the
standard screen) are real, usable RAM. Overscan layouts have similar gaps.

---

## 3. Overscan register values

A reasonable starting point, to be tuned against a real monitor:

| Reg | Std | Overscan | Note |
|-----|-----|----------|------|
| R0 | 63 | 63 | never change |
| R1 | 40 | 48 | 96 bytes/line; 192/384/768 px in modes 0/1/2 |
| R2 | 46 | ~50 | must move to re-centre the wider window; R2 + HSYNC width should not exceed R0 |
| R3 | &8E | &8E | see CRTC-type caveat below |
| R4 | 38 | 38 | keep the 312-line frame |
| R5 | 0 | 0 | |
| R6 | 25 | 34-35 | 272-280 displayed lines |
| R7 | 30 | 35-36 | must be >= R6, and R7 + VSYNC width must fit before R4 |
| R9 | 7 | 7 | |
| R12/R13 | &30/&00 | per block | reprogrammed by the rupture |

Practical monitor ceiling on a CTM640/644 is roughly **96 bytes x 272 lines** of useful
picture. Push wider or taller and the picture runs off the tube or the set loses sync.
Modern LCDs via SCART are usually *less* tolerant, not more.

Widening R1 alone shifts the picture right — R2 must come with it, or the right side
falls off the screen.

---

## 4. Timing and interrupts

- The Gate Array counts HSYNCs and asserts /INT every **52 scanlines** — 6 interrupts
  per 312-line frame.
- VSYNC resets that counter two HSYNCs after VSYNC starts; if the counter is at/above 32
  at that moment an extra interrupt is issued first. That is how the interrupt phase
  stays locked to the frame.
- `HALT` gives you 52-line granularity for free. Finer raster timing means DI plus
  counted delays, measured in microseconds (1 us = 1 CRTC char = 4 T-states).
- Every Z80 instruction on the CPC is padded by Gate Array wait states to a whole number
  of microseconds. `NOP` = 1 us. This makes cycle counting pleasant, but interrupt
  acceptance still jitters by up to ~4 us depending on the instruction in flight — chain
  `HALT`s or use a known-length instruction stream when you need exact raster alignment.
- VSYNC can be polled directly: PPI port B (&F5xx) bit 0.
- Any rupture that changes R4 or R9 changes how many HSYNCs the frame contains. Get it
  wrong and the interrupt cadence, and the display, drift. Always verify the line count
  still totals 312.
- `src/irq.asm` is the implementation: handler at `#0038`, phase-locked to VSYNC at
  startup, counting six interrupts to a frame. Anything that must happen once per frame
  hangs off `frame_count`, never off a bare `HALT`. With the ROMs disabled `#0038` is
  plain RAM, so the jump there has to be written before `EI` - enabling interrupts
  without it is an immediate crash, and it is a mistake both design documents make.

---

## 5. CRTC types — the main portability hazard

The 6128 shipped with several CRTCs and they differ **precisely in the edge cases
overscan and rupture depend on**:

| Type | Part |
|------|------|
| 0 | HD6845S / UM6845 |
| 1 | UM6845R |
| 2 | MC6845 |
| 3 | Amstrad Plus ASIC |
| 4 | Amstrad "pre-ASIC" cost-down 6128 |

Areas where they disagree — check every one on target hardware before relying on it:

- When R12/R13 writes are latched (next scanline vs. next character row vs. next frame).
- Behaviour of R4/R9 changed *during* a character row (the basis of rupture).
- R1 changed mid-line.
- R6 = 0, and R6 reached while already past it.
- Whether the R3 VSYNC-width nibble is honoured or the width is fixed.
- R7 during vertical adjust, and R5 interaction.
- Status/read-back registers: type 1 has a status register at &BE00; types 0 and 2
  expose different subsets of R12-R17 at &BF00. Read-back is the basis of type detection.

**Guidance for this project:** detect the CRTC type at boot using a published detection
routine (Longshot's *CRTC Compendium* is the reference; do not invent bit tests), then
either branch on it or refuse to run and say which type is required. Whichever milestone
you are on, record in `docs/` which CRTC types it has actually been verified on. Do not
assume an effect that works in one emulator works on another type.

---

## 6. 6128-specific notes

- **Video follows the bank configuration.** The Gate Array fetches video through the same
  address decoding as the Z80, so on a 6128 the RAM configuration selected via port &7Fxx
  (&C0-&C7) determines which physical RAM is displayed. &C0 is the plain 64 KB map;
  &C2 maps banks 4-7 over the whole 64 KB. Page-flipping whole overscan screens between
  banks is possible, but the displayed region must be mapped *at fetch time*, not just
  when you wrote to it.
- Gate Array port &7Fxx: &00-&0F select pen, &10 selects border, &40+colour writes the
  hardware colour, &80+n sets mode and ROM enables, &C0+n sets the RAM configuration.
- CRTC ports: &BCxx select register, &BDxx write data, &BExx status (type 1),
  &BFxx read data (types 0/2).
- A 32 KB overscan screen collides with firmware territory. Firmware variables live around
  &B100-&BFFF and the firmware stack sits just below &C000. Overscan work runs with the
  firmware off: own IM 1 (or IM 2) handler, own stack placed somewhere the display does
  not touch, ROMs disabled.
- The firmware screen routines (SCR_*, TXT_*) assume 40x25 in 16 KB and are useless here.
  Everything is written directly.

---

## 7. Text and languages

Both games ship in Greek and English. The rules that keeps that from rotting:

- **No literal text in the Z80 sources.** Every user-visible string is a message id
  resolved through `txt_lang` at draw time. A string that only exists in one language is
  a build error.
- Text lives in `text/<game>.<lang>.txt` as UTF-8 `ID = text`, edited directly.
  `tools/mktext.py` generates `src/strings.asm` and `src/font.asm`; both are committed so
  a build needs only rasm.
- The font is one 8x8 set covering both scripts. Greek folds onto it: accents dropped,
  lowercase raised, and the fourteen Greek capitals that share a Latin shape reuse the
  Latin glyph. Only Γ Δ Θ Λ Ξ Π Σ Φ Ψ Ω are drawn separately.
- All-caps in both languages. Unaccented capitals are correct Greek typography, not a
  shortcut, and it halves the font.
- Glyph cells are 5x8 drawn 7 tall, and the tool adds a sixth column of letter spacing,
  because a mode 0 byte is two pixels and a cell has to be a whole number of them. That
  keeps every character 3 bytes wide and means no text routine ever has to shift a byte.
  A cell is 32 to the row rather than mode 1's 48, which is why the HUD is two rows.
- Greek in a rasm label breaks the assembler - `mktext.py` spells the Greek-only glyph
  names out (`GL_SIGMA`, not `GL_Σ`).

## 8. Sprites

- The screen is **mode 0**: 2 pixels per byte, 16 pens, 96 bytes to the line, so 192
  pixels across a 384-pixel-wide picture. A mode 0 pixel is two mode 1 pixels wide, so
  nothing changed size when the game moved over - only how finely it can be drawn. Every
  layout in the project is in bytes (rooms, furniture, collision boxes, sprite widths),
  which is why the move cost nothing outside the font and the sprite art.
- A solid-pen byte is not a nibble pattern the way it was in mode 1: a pixel's four pen
  bits are spread across bits 7,3,5,1 (left) and 6,2,4,0 (right). `PEN0_BYTE`..
  `PEN15_BYTE` in `config.asm` are the sixteen written out, and `pen_bytes` indexes them.
- No double buffer. A second 32 KB screen plus code does not fit comfortably in 128 KB,
  and repainting 26 KB a frame is impossible. Sprites save the background they cover and
  put it back before moving - which also makes static scenery underneath survive.
- Blit is `screen = (screen AND mask) OR data`, mask and data interleaved so one pointer
  feeds both. Art is ASCII in `assets/sprites.txt`; `tools/mksprite.py` generates
  `src/sprites.asm`.
- Byte aligned: 4 pixels per horizontal step, one scanline vertically. Pixel-exact
  horizontal movement needs four pre-shifted copies per frame. Do it when something
  looks wrong, not before.
- Everything walks `line_tab` rather than computing addresses, so the 2048-byte stride
  and the page 2 to page 3 crossing at row 21 never come up in game code.
- Order per frame is restore-all then save-and-draw-all, or the sprites erase each
  other. Within each pass the order is by screen position, worked out fresh every frame
  in `sprites_order`: draw from the top of the screen down, erase from the bottom up.
- **That ordering is not cosmetic.** There are only about 40 blanked scanlines after the
  frame tick - 2.5 ms - and the sprite work is five times that: a masked blit is roughly
  18 us a byte against 6 for an LDIR, and the cat alone is 144 bytes restored, 144 saved
  and 144 blitted. Nothing can be finished before the picture starts, so the only thing
  that keeps a sprite off-screen when the beam arrives is being redrawn before it gets
  there. A fixed order left the canary - highest on screen, so the least time - redrawn
  about 4 ms after the beam had already passed it, and it flickered every frame it moved.
- Keep work that only thinks out of the window between the erase and the draw. The HUD
  in particular repaints on the frame a sausage is collected; it lives above the play
  area, so it costs the sprites nothing if it is done before the erase.
- **Never pace anything in the game off `frame_count` parity.** It is a free-running
  interrupt counter, and a frame the loop overruns bumps it by two without changing the
  parity, so anything keyed on it either runs every update or none of them. The robots
  were paced that way and stopped and started for no visible reason. Count per object.

## 9. Physics

- Vertical position and velocity are 8.8 fixed point. Whole-pixel gravity at 50 Hz has
  no usable range between "brick" and "balloon".
- Platforms are one-way: landing is checked only while falling, by asking whether a
  platform top lies between where the feet were and where they now are. Going up passes
  through. Cheap, and right for a single-screen platformer.
- Sprite height is part of the state. `cat_set_sprite` keeps the feet anchored when it
  changes, so rolling and standing do not sink or hop.
- Screen shake moves R7 (VSYNC position), never R12/R13. The screen base is chosen so
  the page 2 to page 3 crossing lands on a character row boundary; moving it scrambles
  the row where the pages meet. R7 can only go *up* from 34, since below R6 the VSYNC
  would begin inside the display. Untested on a real monitor - a CTM may need a frame
  to re-lock.
- Level geometry and the jump have to be designed together: the jump clears about 40
  scanlines, so shelves are 32 apart. The first version had them 48 apart and nothing
  above the floor was reachable.

## 10. Rooms

- Rooms are composed from tables in `src/rooms.asm`, never painted. One 192x272 mode 0
  background is 26 KB; a flat's worth of bitmap art does not exist in this machine.
- A room record names its platforms, sausages, enemies, props, start position and exit.
  `play.asm` knows none of that - it walks whatever `room_load` points it at, so adding
  a room means adding a record, not editing the playing code.
- Furniture is masked sprites blitted once into the background. Outlined in white, not
  solid: solid white means a platform, outlined means scenery. That distinction is the
  level's visual grammar, so keep it.
- Props are shared across rooms, so a new room is usually free.
- Room 1's geometry is frozen - the scripted run in `make check` depends on every shelf,
  sausage and patrol being exactly where it is. Decoration can move; collision cannot.

## 11. Game state

- Score is packed BCD, most significant byte first: `DAA` does the arithmetic and
  printing is two nibbles a byte, no division.
- Anything that changes the background - collecting a sausage, say - must happen between
  the sprite erase and the sprite draw. Outside that window the cat's save buffer either
  restores what you removed or captures what you added.
- The HUD only repaints when something changed. Its captions come from the string table,
  so column positions have to leave room for the longer language.
- Once more than one thing moves, erase in the exact reverse of the draw order.
  `enemies_erase` walks the array backwards for that reason.
- Enemies are a fixed array of records addressed through IY, because IX is already the
  line_tab cursor inside the sprite routines.
- The belly-flop stuns everything at roughly the height it landed at, ignoring distance
  along the shelf. That is deliberate: it makes the flop the tool for getting past a
  robot patrolling a whole shelf, which a short shockwave did not.
- `make check` runs a clean scripted playthrough with the enemies in place: five
  sausages, no lives lost. It has to belly-flop past the shelf 2 robot to work. Treat it
  as the level design's test - if it stops passing after a change to a shelf, the jump
  height or a patrol, the level is no longer completable the way it was.

## 12. Working conventions

- Comment every CRTC register write with the value **and the reason** — a bare
  `LD BC,&BC01 / OUT (C),C` is unreadable six months later.
- Keep a single place that defines the overscan geometry (R1, R6, base addresses, bytes
  per line) and derive everything from it, rather than scattering 96s and 48s around.
- Timing-critical code: annotate with microsecond counts in the margin and keep the
  running total. Say what the code is synchronised to.
- When a technique only works on some CRTC types, say so at the top of the file.
- Test on at least two of ACE-DL / CPCEC / WinAPE with the CRTC type set explicitly, and
  treat real hardware as the only authority when they disagree.
- Prefer small, individually runnable test programs over one growing demo. Each milestone
  should be its own binary that shows one thing.

## 13. Confidence notes

Solid and safe to build on: the address decoding in section 2, the 1024-character limit,
the 312-line/64 us frame arithmetic, the 52-line interrupt cadence, the port numbers.
The screen layout in src/ is checked end to end by `make check`.

Needs verification on hardware or an accurate emulator before being treated as fact:
the specific overscan register values in section 3 (particularly R2 and R7 centring, which
vary by monitor), the exact VSYNC-width behaviour per CRTC type, and every per-type
difference listed in section 5. Nothing in this repository has yet run on an emulator
or on real hardware. Measure, then update this file with what was found.
