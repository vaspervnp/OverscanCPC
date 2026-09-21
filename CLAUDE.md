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
- **The frame is recognised, not counted.** Six interrupts to a frame is true, but
  counting to six only tells you which frame you are in if you know which of the six you
  started on - and you do not. VSYNC is eight scanlines and the interrupts are fifty-two
  apart, so exactly one of them falls inside VSYNC; the handler reads PPI port B and
  treats that one as the top of the frame. Counting is kept as a fallback in case a
  machine never lands one there.
- Getting that wrong does not break anything you can see in a debugger: the game runs at
  exactly 50 Hz either way. What it does is put every frame's work at a fixed, arbitrary
  offset into the picture, and since the sprite work is about ten milliseconds of a
  twenty millisecond frame, that can drop the erase-and-redraw straight under the beam.
  The bottom of the screen goes first, because the sprites down there are absent the
  longest - erased first, redrawn last.
- `src/irq.asm` is the implementation: handler at `#0038`, locked to VSYNC every frame. Anything that must happen once per frame
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
- **Anything declared in the #4000 block costs a byte of the disc file**, even
  uninitialised workspace: the file spans from the load address to the end of
  the packed tables riding along behind it, and everything in between is
  written out. RAM the program builds for itself belongs below #4000, where it
  costs nothing - that is what PICK_BUFS is, and LINE_TAB_AT after it, which
  moved 544 bytes of line table out of the file for free. The limit that
  matters is #A67B, where AMSDOS's buffers start, and the three asserts at the
  bottom of loukoumas.asm are what catch a build that has grown past it.
  The second game ended up with the same three regions as the first, for the
  same reasons and in the same order: **code from #4000, the title picture,
  then the packed low block.** That block is assembled at #0100 for its labels
  only, and what the file actually carries is the packed copy, exactly the way
  `lowblock.asm`/`tablepack.asm` work for the first game: `src/mitsoslow.asm`
  assembles the same files at the address they run at and saves them raw,
  `tools/mkpack.py` packs that, and `unpack_tables` puts it back in the first
  dozen instructions. Eleven kilobytes becomes under three, most of the saving
  coming from the masked sprites, which are mostly transparent corner - and a
  transparent byte is the same two bytes of mask and data over and over.
  **What belongs down there is everything that is never written to and never
  executed**, and the test is that and nothing else: the sprites went first,
  then the song, then the font and the two string tables, then the box lists
  the shop is drawn from, `pickups_init` and the palette (`mitsosdata.asm`,
  with the shelf constants both passes need split out into
  `mitsosshop.asm`). The box lists and the song barely pack at all - they go
  down for the address space, not for the file. Each move is a byte off
  `code_end` and a byte the title picture can have, and it is the right end to
  squeeze: the alternative is blurring the picture, which costs detail. The
  one rule is that `mitsoslow.asm` and the game's own `ORG ART_ORG` block must
  include the same files in the same order - `make check` unpacks what the Z80
  produces and `cmp`s it against the raw binary.
  **The picture has to be below #8000 and the sprites do not.** The sprites
  are moved before anything looks at the screen, so the file may lie over the
  screen while it loads; the picture is read from where the file left it,
  *while* it is being written to the screen, so a byte of it above #8000 is a
  byte the decompressor overwrites and reads back as noise. The packed sprites
  also have to be above the stack, which sits just under #8000: the unpack is
  a call, and a return address landing in the middle of the stream is the same
  bug from the other end.
  Under #4000 are the unpacked low block at #0100, the line table after it -
  `LINE_TAB_AT`, which has had to move up twice as the block grew - the four
  buffers of saved background, and then **the whole of the workspace** -
  uninitialised RAM costs a byte of disc for every byte of it if it is
  declared above #4000, and two hundred and sixty-four bytes of this one were
  being carried for no reason.
- A 32 KB overscan screen collides with firmware territory. Firmware variables live around
  &B100-&BFFF and the firmware stack sits just below &C000. Overscan work runs with the
  firmware off: own IM 1 (or IM 2) handler, own stack placed somewhere the display does
  not touch, ROMs disabled.
- The firmware screen routines (SCR_*, TXT_*) assume 40x25 in 16 KB and are useless here.
  Everything is written directly.
- **The screen leaves sixteen kilobytes for everything else, and that is not enough.**
  32 KB of screen at #8000-#FFFF, and AMSDOS only hands control to a program the lower
  ROM is not sitting over, so code loads at #4000-#7FFF. Ten rooms fitted in that.
  Twenty-nine do not. #0000-#3FFF is sixteen more kilobytes nothing is using once both
  ROMs are off - the only thing in it is the interrupt jump at #0038 - but a program
  cannot be *loaded* there, because the lower ROM is still enabled when the loader
  jumps to us and it would execute ROM. It can be loaded high and copied down: rasm's
  second ORG argument (`ORG DATA_ORG,DATA_STORE`) assembles the tables to run at #0100
  while storing them at #6000 inside the file, and the first dozen instructions of the
  game move them with one LDIR. Everything down there is read and never executed - the
  font, the strings, the sprites, the artwork, the enemy table and every room - so it
  never has to be in place before that.
- The file may run over the screen at #8000 while it is loading, because nothing has
  looked at the screen yet. It must not run over AMSDOS's own buffers, which start at
  #A67B; that is why HIMEM drops when a disc drive is attached.
- **The tables are packed too, and that is where the room came from.** Twelve and a
  half kilobytes of font, strings, sprites, artwork and rooms was carried verbatim
  for no reason: it is read-only and it goes into place before anything else runs.
  `tools/mkpack.py` packs it to eight and a half and `unpack_tables` in
  `src/unpack.asm` - forty bytes - puts it back, which paid for the music with
  change. It costs about a fifth of a second at boot.
- That needs a build pass of its own: `src/lowblock.asm` assembles the same six
  files at the address they run at and saves them raw, the tool packs that, and the
  game includes the packed copy. The game still assembles the six files as well, at
  `ORG DATA_ORG` - but only for their labels. Their bytes are never saved, because
  every SAVE in `loukoumas.asm` starts at `loukoumas_start`, which is why the raw
  binary the tools read is an explicit SAVE and not `-ob`: `-ob` would write the
  sixteen kilobytes of nothing between #0100 and #4000.
- **The file is code from #4000 to `PIC_STORE`, the packed title picture from there
  to `DATA_STORE`, and the packed tables after it.** It ends 58 bytes below #A67B.
  All three regions are set by hand in `config.asm` and all three are nearly tight;
  growing any of them means moving the two constants and watching that last number.

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

## 7b. Two games, one engine

- **There are two games on this engine and both are mode 0** - sixteen pens,
  192 pixels across a 384-pixel-wide picture. ΛΟΥΚΟΥΜΑΣ is the first;
  ΠΑΝΙΚΟΣ ΣΤΟ ΠΑΝΤΟΠΩΛΕΙΟ (`src/mitsos.asm`, `pantopoleio.md`) is the second.
  They share every engine file and differ only in their own sources, their own
  art directory and their own palette table.
- `config.asm` can do mode 1 as well - `-DSCRMODE=1` swaps the solid-pen bytes
  and PIXELS_PER_BYTE, and `GA_MODE` is the Gate Array byte that goes with it.
  The second game was built that way first and moved to mode 0 for the colours.
  Nothing else in the engine noticed either time: crtc.asm, video.asm, irq.asm,
  keys.asm, boxes.asm and sprite.asm all work in bytes, and a byte is a byte.
  That is not luck - every layout in the project is in bytes rather than
  pixels, which is the same property that made the first game's own move from
  mode 1 to mode 0 cost nothing outside the art.
- Mode 1 packs four pixels to a byte and the **top** nibble holds the least
  significant pen bit: pixel i is bits 7-i and 3-i, low bit first. So four
  pixels of one pen are #00, #F0, #0F and #FF. The design document had this the
  other way round, along with its CRTC table; `tools/z80check.py` decodes mode 1
  independently and is the thing to check against.
- `src/boxes.asm` is the furniture painter both games use: a box list is dx,
  dy, width in bytes, height in scanlines and a pen, ending in #FF, drawn
  relative to (prop_x),(prop_y). Later boxes draw over earlier ones, so an
  outline is a box with a smaller box inside it.
- The text routines are still mode 0 only in the sense that matters - the font
  is 3 bytes to a cell - so a mode 1 game would need a second pass in
  `mktext.py` before it could have a HUD. Neither game needs that now.
- The second game's art is drawn in **Aseprite through its MCP server**, which
  runs on Windows: it cannot see WSL paths, so files go through
  `C:\Users\<user>\` and are copied back. `assets/aseprite/mitsos/` holds one
  file per subject with every frame in it, `assets/art/mitsos/sprite/*.png` is
  what the converter reads, and `tools/mkart.py mitsos` writes
  `src/mitsosart.asm`. One converter, one sixteen-pen palette, both games.

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
- The per-scanline cost is what a sprite costs, not the per-byte cost. `ld e,(ix+0)` is
  5 us because of the index prefix, a call and a return are 7, and reloading a variable
  is 4: a subroutine that worked out one row's screen address came to nearly 30 us, and
  there are about 200 rows of sprite in a frame. The line table walk is inlined in every
  pass, spr_x is held in a register for the whole sprite, and the background save is
  folded into the blit so the rows are walked twice instead of three times.
- Never clear and redraw a whole panel to change a digit. The HUD strip is 96 bytes by
  16 scanlines, which is 9 ms of LDIR - half a frame - and it was being done every time
  a sausage was collected. `txt_solid` makes small text overwrite instead of blend, so
  the numbers can be written straight over where they stand.
- **Two sprites standing in each other cannot be rebuilt one at a time.** The
  interleaved rebuild saves the background under a sprite while everything
  after it in the order is still showing last frame's picture, so the save
  catches a picture that is about to move, and hands it back to the room a
  frame later where nothing will ever erase it again. `enemy_tangled` tests
  all the ground each of them covers between where it is and where its picture
  still is, and a frame that finds anything is unwound whole and laid down
  again instead. `tools/z80check.py --debris` counts what is left standing on
  ground the room painted empty, and `make check` fails on one byte of it.
- `tools/z80check.py --profile` counts instructions per routine and is how all of the
  above was found rather than guessed. Its virtual frame is a fixed instruction budget,
  so when the game stops overrunning it the scripted routes shift and have to be
  re-derived - which is itself the signal that the frame got faster.
- **A full-screen picture is 26,112 bytes and there is nowhere to keep it.** The screen
  is half the machine; the code and the tables are most of the rest. The title screen is
  LZSS-packed to about seven kilobytes by `tools/mkscreen.py` and unpacked straight onto
  the screen by `src/unpack.asm`.
- That decompressor keeps **no window**. A back reference is at most 2047 bytes, which is
  at most twenty-two rows up, and line_tab already knows where every row is - so the
  screen is its own window and a match is two cursors walking the picture, one behind the
  other. It costs eleven bytes of state and no buffer at all, which is the only reason a
  full-screen picture fits in this game.
- It takes about a second and a half. That is fine for a curtain and impossible for
  anything else, so the scripted runs in `make check` are built with `-DTITLEPIC=0`: every
  frame number they pin would otherwise be eighty frames later than it is. One build keeps
  the picture, and the screen it unpacks is compared byte for byte with `build/title.bin`.
- **Text over a picture cannot blend.** `txt_big_solid` writes the pen where the letter is
  and skips where it is not, so the name is drawn twice - black one byte right and two
  scanlines down, then yellow - and comes out with a shadow instead of in a box. Small
  text still wants ground cleared under it, which is why the title screen has two panels:
  pressing L has to repaint a line, and a line lying on a picture can only be repainted if
  something cleared the ground first.
- **The second game's title screen is not a picture at all - it is the room.** There was
  no seven kilobytes to spare for a packed one, and `draw_shop` already paints the whole
  26 KB out of box lists in about a second: so the title is the shop drawn the way the
  game draws it, with the shelves stocked by an LDIR from `pickups_init`, him by the door
  and Grandma by the crates, and a cleared panel with the name on it over the top. The
  cast goes down before the panel, so the panel covers what falls inside it rather than
  leaving a fish floating on the blue. Pressing L repaints the lot, which is why it takes
  about a second and why `make check` cannot press fire for another forty virtual frames
  after it.
- **The game renders 25 times a second, on every second VSYNC, and thinks 50.**
  `wait_render` counts two ticks; `play_loop` then takes FRAMES_PER_RENDER logic
  steps inside one picture, so the jump arc, the patrol speed and every timer are
  exactly what they were - only how often the screen is rebuilt changed. Lifting
  this cast off a 32 KB overscan screen and putting it back is thirteen
  milliseconds; a frame is twenty, of which two and a half are blanked. It does
  not fit, it never fitted, and no choice of which interrupt starts the frame
  makes it fit - that only moves which band of the screen flickers.
- **The screen work comes first in the loop and the thinking comes after it.**
  Everything the beam is about to draw has to be back before it arrives, and the
  only currency is the microseconds after the tick. Six milliseconds of keys,
  physics and collisions in front of the redraw pushed it a hundred scanlines
  into the picture. Anything that only computes belongs after the draw, for the
  next frame; the one thing that cannot is a change to the background, which has
  to happen while the sprite over it is lifted off.
- **Sprites are erased and redrawn one at a time, top of the screen first.**
  Erase-all-then-draw-all leaves each sprite off the screen for the whole gap
  between the two passes. One at a time closes that to the sprite's own work, and
  top-down spends the head start on the sprite the beam reaches first - which is
  earliest-deadline-first, and provably the right order. The cost is that two
  overlapping sprites can bite into each other for a frame; in this game
  overlapping means the cat has just been caught.
- **`tools/z80check.py --beam` is the only thing that can tell you whether any of
  this worked**, and `make check` fails if it reports a single sprite caught. The
  simulator charges every instruction the CPC's own microseconds - a microsecond
  per machine cycle, `US_EXTRA` for the rest - and its frame is 19968 us, not a
  number of instructions. Before that it could not see beam timing at all, which
  is why two attempts at this bug were guesses.
- **A picture of a room beats drawing one, when there is room for it.** The
  second game's title screen was the shop drawn out of its own box lists,
  which cost nothing to carry and a second to paint. It is now a painted
  picture put through `tools/mkscreen.py`, and two of that tool's switches are
  worth knowing. `--repen` changes one pen to another inside a rectangle:
  sixteen pens is few enough that two things which are different colours in
  the source land on the same pen, and if they touch, the thing in front
  disappears into the thing behind it - Grandma's face came out the same coral
  as the brick wall she stands against. `--smooth` blurs the source before it
  is scaled down, which takes several hundred bytes off the packed size
  because what does not survive the scaling arrives as stray single pixels the
  packer spends a literal on each. **Do not reach for `--smooth` until there
  is nothing left to move out of the #4000 block.** It was carrying this
  picture at 1.6 pixels of blur; sending the font, the strings and the box
  lists down to #0100 freed a kilobyte of code space and it is now packed with
  no blur at all, which is 6357 bytes against 5896 and visibly sharper. Blur
  spends picture to buy code; moving read-only data spends nothing.
- **Something the size of a person can be a sprite, but only if it is rarely
  redrawn - and "rarely" does not save the frame it is redrawn in.** Grandma
  at ten bytes by ninety-six is nine milliseconds to lift and twenty-three to
  save and blit back, and a picture is forty. The picture she moved in
  overran and handed its lateness to the next one, which is why the whole shop
  flickered and not only her. Only rebuilding her sometimes fixes the average
  load and nothing else; the deadline is per picture, and a picture is forty
  milliseconds. **The deadline is not the budget either**: her top row is
  scanline 140, the beam is there eleven and a half milliseconds after the
  frame starts, and half of her is sixteen. A quarter is eight. So she is
  rebuilt a quarter at a time, each quarter its own slice of the picture and
  the buffer and its own record of where its picture is. Four quarters is four
  pictures to a step, so her step had to slow to match - hunting now covers
  two bytes in eight frames rather than one in four, the same ground in the
  same time - and what is left is one seam, two bytes wide, walking down her
  while she does. A change of pose that only moves the broom waits for the top
  of the next cycle rather than costing a rebuild; a change of pose *height*,
  or a change to the shop underneath her, still needs the whole of her.
- **Erase-all-then-draw-all is what makes everything flicker, not the sprite
  that is expensive.** Every sprite is missing for the whole window, which for
  this cast was two hundred and fifty scanlines of a two hundred and
  seventy-two line picture. `cast_rebuild` in the second game lifts each of
  them off and puts it straight back before going on to the next, in the order
  the beam reaches them, which closes the window to the sprite's own work -
  five milliseconds for the cat instead of twenty-seven. `cast_tangled` is
  what keeps it sound: when two of them cover any of the same ground, or when
  the shop itself is about to change under them, the whole cast comes off
  before any of it goes back. In ordinary play that is one picture in thirty.
- **The starting gun is the frame tick and nothing may stand between them.**
  There are forty blanked scanlines after it - two and a half milliseconds -
  and they are the whole head start the rebuild gets on the beam. Reading the
  keyboard is eight hundred microseconds of that and working out whether the
  cast is tangled is another thousand; both are about the *next* picture, so
  both belong after the draw. Moving them out bought thirty scanlines for
  nothing. The music went the same way, off the frame's own interrupt onto the
  third of the six, for the same reason: the game is waiting on that
  interrupt.
- **The cheapest sprite is the one that is already right.** A foe showing the
  right picture in the right place is left alone - `foe_still` against
  `E_OX`/`E_OY`/`E_OPOSE`, which is the frame with bit 7 for facing left -
  and two and a half milliseconds of a twenty millisecond frame is what that
  is worth each time. Growing that record is also a reminder that `foes_init`
  is a table of the same shape: it has an ASSERT under it now because getting
  that wrong lays every foe out one byte further along than the last and the
  game comes up with no cast at all.
- **Nothing that only thinks may sit between the erase and the draw.** Four
  and a half milliseconds of physics in the middle of the window is four and a
  half milliseconds every sprite is off the screen for nothing. The price of
  moving it after the draw is that every change to the background has to be
  deferred into the next rebuild - which is why a meze knows both where it is
  and where its picture is, and why opening the basket sets a flag instead of
  painting a lid. Grandma Evdoxia is 10 bytes by 96 scanlines - four of the cat, 960 bytes
  - and saving, blitting and handing back that rectangle is about nineteen
  milliseconds, most of a frame for one figure. She was boxes over a saved rectangle
  first, which is half the cost and no art at all, and the thing that made a real
  sprite affordable was not making the blit cheaper: it was **only rebuilding her on
  the frames she changes on**. An old woman crosses a shop floor a byte every eighth
  frame and swings the broom every sixteenth, so three pictures out of four she is left
  exactly where she is and costs nothing, and the profile puts the whole game at
  two thirds of its time rather than three fifths.
- The price of that is `granny_off`: anything that changes the background under
  something being left standing has to take it off the screen first, or its buffer
  hands the old background back the next time it moves, and that is debris nothing will
  ever clean up. Collecting a meze and opening the basket both call it.
- **A picture that is never turned round should not be assembled twice.** `mkart.py`
  writes a mirrored copy of every masked sprite; `NOFLIP` names the ones that never
  face the other way - the mezedes sitting on shelves, and Grandma, who sweeps facing
  the shop whichever way her feet are going - and writes `spr_x_l EQU spr_x` instead.
  Her mirror alone would be two kilobytes of a sixteen kilobyte address space.
- **`SPR_UNROLL_MAX` is per game.** The unrolled blit and LDI chains in sprite.asm are
  entered at a computed offset, so writing them out for a wider sprite costs a few
  bytes of code and no time at all - but those bytes should come out of the game that
  asked for them. Mitsos sets it to `ART_MAX_W`; Loukoumas leaves it at 6 and its
  binary does not move a byte.
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
- Furniture is drawn once into the background and outlined in white. Outlined means
  scenery; anything the cat can stand on is pen 2, which is the level's visual grammar
  and does not change from room to room. It stopped being masked sprites early: drawn
  at the size these things should be - a sofa is two metres, a fridge is taller than a
  person - the lot came to about 30 KB.
- Props are shared across rooms, so a new room is usually free. Twenty-nine rooms come
  to about four kilobytes of tables between them.
- Furniture is boxes because boxes are almost free and a fridge is a box. A tree, a
  cloud, a slide, a street lamp and a crescent moon are not, so those are **decals**:
  bitmaps drawn in Aseprite (`assets/aseprite/*.lua`), converted by `tools/mkart.py`
  and ORed into the background when the room loads. A prop id with bit 7 set is a
  decal, anything else is a box list, and draw_props tells them apart. They carry no
  mask, because the screen underneath has just been cleared to pen 0 and ORing pen 0
  changes nothing: half the bytes of a masked sprite the same size, and the whole cost
  is paid once, when the room loads.
- **A decal ORs, so it has to land on empty background.** Draw one over a box and the
  pens mix - a trunk running up through a canopy comes out neither wood nor leaf.
  Start the trunk inside the leaves, or put the box in the list after the decal.
- A room's light is one byte: the hardware colour of pen 0, which is the background and
  the border both. Navy is a wall at three in the morning, sky blue is nine o'clock
  outside a school, black is a roof at midnight. Nothing else in the palette moves, so
  the cat is butter yellow in every room and every piece of furniture keeps the colour
  it was drawn in. The floor band has its own pen as well - boards, grass, tarmac,
  slate - but the shelves stay pen 2, because "you can stand on this" has to read the
  same everywhere.
- Room 1's geometry is frozen - the scripted run in `make check` depends on every shelf,
  sausage and patrol being exactly where it is. Decoration can move; collision cannot.

## 10b. Sound

- The PSG is not on the bus. It is reached through the same 8255 PPI as the key
  matrix: register number out on port A, port C told to select, value out on
  port A, port C told to write. Port A has to be an output for that, which is
  where `read_keyboard` leaves it.
- **Bit 6 of the mixer is the PSG's own port A direction, and the keyboard is
  read through that port.** Every mixer value in `sound.asm` keeps it at 0.
  Setting it silently kills the keyboard, and nothing else would look wrong.
- One channel, one effect at a time, four effects: jump, eat, die, belly-flop.
  An effect is a starting tone period, a signed step added to it every 50 Hz
  frame, and a length; the volume is whatever is left of the length, capped at
  15, so everything fades out without costing a byte of state. Noise effects
  carry the noise pitch in the period's low byte, which the tone effects do not
  mind because their noise is switched off in the mixer.
- `sfx_update` is stepped once per 50 Hz logic step, so an effect lasts the same
  length of time whatever the render rate is - but it is stepped in `play_over`,
  the one place every path through a rendered frame goes past, and **not** with
  the rest of the logic. The logic steps are skipped once the game is over, and
  an effect that stops being stepped never reaches its last frame, which is the
  frame that shuts the channel up. The death effect held its note for ever.
- There is no music in the first game's rooms. Three channels and a tracker replay
  is a different job and there are about ninety bytes left between `game_end` and
  `PIC_STORE`; its title screen has a tune and `PLY_AKG_Stop` hands the chip back
  to `sound.asm` before the room is painted.
- **The second game has a tune and it never stops, because nothing else wants the
  chip** - it has no effects at all. Arkos Tracker 3 again: `src/pantomusic.asm` is
  the song, `src/playerakg.asm` is the same player, and three kilobytes of it moved
  `ART_STORE` from #6000 to #6600.
- **A tracker replay is stepped from the interrupt, not from the game loop**, and
  `irq.asm` has a hook for it: define `HAS_MUSIC` and provide `music_tick`, and the
  handler calls it on the one interrupt in six that is the frame. A game that does
  not assembles the bytes it always did. Two reasons it belongs there and not in the
  loop: the replay wants fifty ticks a second and the loop comes round twenty-five,
  and from the interrupt it keeps its beat through a second-long repaint of the room
  that would otherwise be silence. It is also the only place it cannot be re-entered,
  which matters more than it sounds - the player moves SP into the song while it
  reads, so an interrupt landing inside it would push onto the music.
- The price is everything the player destroys: both register sets, both index
  registers and the alternate accumulator - and `sprite.asm` blits out of the shadow
  set. So the handler pushes sixteen more words around the call, about eighty
  microseconds, against the forty blanked scanlines the frame opens with. The player
  itself is about fifty instructions a tick, which is why this was affordable at all;
  `tools/z80check.py` was what said so, by counting the instructions with the call in
  and with it out.

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
- Enemies are a table, not a branch. There are two behaviours - walk a platform at
  half the cat's speed, fly an arc across the room - and twelve creatures, because a
  robot vacuum patrolling a park bench is not a joke that survives being told
  nineteen times. `src/enemykind.asm` maps the type byte to a sprite and a behaviour;
  adding one costs three bytes there plus its picture.
- **How many lives he starts with is the difficulty**: nine, six or three, out of
  the same `diff_tab` record as the three bytes that pace the cast. The number he
  started on is also his ceiling, because the HUD prints the lives with
  `print_digit` and ten would print whatever follows 9 - so the saucer of milk tops
  him back up rather than past it. That means a clean scripted run never sees the
  saucer give a life at all, only the points it is worth instead, which is why
  `make check` pokes a life away first (`z80check.py --poke`).
- Every third room has a saucer of milk in it, worth one life back. It is not
  one of the sausages and the way out does not wait for it, so a room can be finished
  without it - and it is always on the awkward shelf, usually one something is
  patrolling. Collecting it flashes the border, because the lives digit in the corner
  of a two-row HUD is not something anyone sees while they are being chased, and a
  game with no border left to speak of has exactly one frame around the picture that
  cannot be missed.
- The belly-flop stuns everything at roughly the height it landed at, ignoring distance
  along the shelf. That is deliberate: it makes the flop the tool for getting past a
  robot patrolling a whole shelf, which a short shockwave did not.
- **Three difficulties, and the hardest one is the game as it was.** Easy and
  medium slow the cast down by stepping it less often rather than by moving it
  less far - `walk_period`, `fly_period` - so nothing in the movement code has
  to know about fractions of a byte, and they lengthen the belly-flop stun.
  It sets the starting lives as well - nine, six and three. The chooser borrows
  the title screen's footer between the title and the room. It also means every scripted route in `make check` has to press fire
  twice to reach a room, and everything in a route happens eight frames later
  than it did before there was a second screen.
- `make check` runs a clean scripted playthrough with the enemies in place: five
  sausages, the saucer of milk on the shelf the robot patrols, no lives lost. It has to
  belly-flop past that robot to work. Treat it as the level design's test - if it stops
  passing after a change to a shelf, the jump height or a patrol, the level is no
  longer completable the way it was.

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

## 12b. What is on the disc

Three files, and rasm can only write one of them:

- `LOUK.BIN` - the game, saved by rasm with an AMSDOS header.
- `LOUK.BAS` - the loader, `src/louk.bas`, put on by iDSK as ASCII. It sets
  mode 0 and the sixteen inks from `assets/revive8b.txt`, loads the screen,
  and starts the game on space or after ten seconds - `TIME` counts three
  hundred to the second, and space is key 47.
- `REVIVE8B.SCR` - a 16 KB mode 0 screen, put on by iDSK with a header that
  loads it at &C000.

**A BASIC file on a CPC disc wants carriage returns at the end of its lines.**
`src/louk.bas` is kept with ordinary newlines so it reads like source; the
Makefile converts it on the way in. Without that the machine reads the whole
file as one line and says `Line too long`, which is not a helpful clue.

The splash is the firmware's 16 KB screen at &C000, and the game's overscan
screen covers it - so it is visible while BASIC waits and while AMSDOS loads,
and goes when the game blanks the palette to draw the title unseen. That is
about two seconds of black between the two pictures.

## 13. Confidence notes

**It runs.** `tools/emucheck.py` boots floooh/chips' CPC 6128 - Z80, AM40010 gate
array, MC6845 CRTC, i8255 PPI, uPD765 - with the machine's own ROMs, types
`RUN"LOUK` at the disc image and asks what came out. `make check` runs it, and it
fails the build if the answers are wrong. It is not part of this repository
(`~/repos/CPCTools/cpcemu`), so a build without it says "skipped" rather than
failing.

What that has settled, on the machine rather than on paper: AMSDOS loads the file
where and how the build thinks; the packed tables come back byte for byte at #0100;
the CRTC really does put a 384x272 overscan picture up from the registers in
crtc.asm and the picture that arrives is the one that was packed; and the keyboard
is read through the PPI the way keys.asm assumes, while the music is driving the
PSG through the same chip.

Solid and safe to build on: the address decoding in section 2, the 1024-character
limit, the 312-line/64 us frame arithmetic, the 52-line interrupt cadence, the port
numbers, and now the whole load-and-draw path above.

Still not verified, and still worth being careful about: the overscan register
values in section 3 on a **real monitor** - an emulator is happy with a centring a
CTM might not be; the per-CRTC-type differences in section 5, because the emulator
is one type and there are five; whether the beam catches a sprite, which
`z80check.py --beam` measures in a model of the timing rather than in silicon; and
the screen shake, which moves R7 and may need a frame to re-lock on a real set.
