# LOUKOUMAS title screen — exact brief

A specification of the existing title artwork, precise enough to redraw or improve it
without breaking the machine it has to run on. Two versions exist, Greek and English;
they differ **only** in the lettering.

Files: `assets/art/title/TITLE_EL.png`, `assets/art/title/TITLE_EN.png`
(192×272 PNG, RGBA, transparent where the background shows through).
Rendered previews at 2:1: `docs/title-poster-el.png`, `docs/title-poster-en.png`.

---

## 1. The machine, and the rules it imposes

Amstrad CPC 6128, screen mode 0, full overscan.

* **Canvas: exactly 192 × 272 pixels.** No other size is possible.
* **Pixel aspect ratio is 2:1 — every pixel is twice as wide as it is tall.** The picture
  fills a 384 × 272 display. This is the single most important constraint: a circle must
  be drawn **half as wide as it is tall** in the source image, or it comes out as a wide
  oval on the monitor. Preview any redraw stretched 2× horizontally before judging it.
* **Exactly 16 colours**, and they are fixed — see §2. No other RGB value may appear.
  No anti-aliasing, no gradients, no alpha blending. Every pixel is one of the 16.
* Shading is done by **dithering** — alternating two pens in a checkerboard or in
  vertical stripes. That is the native CPC look and it is currently under-used.
* There is no border. The picture runs to all four edges of the tube.

## 2. The palette — all 16 pens, fixed

Index, RGB, and what the pen means elsewhere in the game. These are CPC hardware
colours; nothing outside this list can be displayed.

| Pen | RGB | Role in the game |
|----|--------------------|------------------------------------------|
| 0  | `0, 0, 128`        | background — navy. Transparent in the PNG |
| 1  | `255, 128, 128`    | coral: nose, sausages, all small text |
| 2  | `255, 255, 0`      | butter yellow: the cat's fur |
| 3  | `255, 255, 255`    | white: eyes, floors, outlines |
| 4  | `0, 0, 0`          | black: shadow, pupils |
| 5  | `128, 128, 128`    | grey: steel, appliances, tarmac |
| 6  | `128, 128, 0`      | olive: wood in shadow |
| 7  | `255, 128, 0`      | orange: wood in light, brick, fur markings |
| 8  | `0, 128, 0`        | dark green: leaves — **currently unused here** |
| 9  | `0, 255, 0`        | bright green: grass — **12 pixels used** |
| 10 | `0, 128, 128`      | teal: deep water, tile — **currently unused here** |
| 11 | `0, 255, 255`      | bright cyan: water, glass, milk |
| 12 | `128, 0, 0`        | dark red: the robots, the title's shadow |
| 13 | `255, 0, 0`        | bright red: hobs, warning lamps |
| 14 | `128, 0, 128`      | purple: the bat, night through a window |
| 15 | `255, 255, 128`    | pale yellow: lamplight, the cat's belly |

Pens 8 and 10 are free. Pen 9 is all but free. That is the available headroom.

## 3. What the picture shows now, element by element

Coordinates are (x, y) of the top-left corner in source pixels, origin top-left.
"×2" means the art is the in-game sprite doubled in both directions.

### The lettering (the only difference between the two versions)

* **Title**, y = 6, height 42, centred. Nine letters: `ΛΟΥΚΟΥΜΑΣ` / `LOUKOUMAS`.
  Each letter is the game's own 5×8 bitmap font scaled ×3 horizontally and ×6
  vertically — 15 × 42 px per letter, 18 px advance, 159 px total, x = 16.
  Fill pen 2 (yellow), a shadow of the same letters offset (+2, +2) in pen 12
  (dark red), and a one-pixel outline of pen 4 (black) round the fill.
* **Subtitle**, y = 56, height 16, pen 1 (coral). Same font at ×1 horizontally,
  ×2 vertically — 5 × 16 per character, 6 px advance.
  Greek: `ΤΟ ΚΥΝΗΓΙ ΤΟΥ ΛΟΥΚΑΝΙΚΟΥ` (24 characters, x = 24).
  English: `THE GREAT SAUSAGE CHASE` (23 characters, x = 27).

### The scene

| Element | Position | Size | Notes |
|---|---|---|---|
| Crescent moon | (4, 64) | 14 × 22 | pen 15, opening to the right, 3 white stars in the tile |
| Stars | (28,70) (184,96) (150,88) (36,96) (176,128) | 1 px each | pen 3 |
| Fridge | (136, 100) | 52 × 140 | see below |
| The cat | (44, 156) | 52 × 84 | see below |
| Stray tom | (148, 72) | 24 × 28 | ×2, grey, sitting on top of the fridge |
| Bat | (114, 82) | 24 × 16 | ×2, purple wings, red eyes |
| Wasp | (66, 124) | 12 × 16 | ×2 |
| Canary | (20, 108) | 16 × 24 | ×2, yellow |
| Pigeon | (6, 152) | 16 × 20 | ×2, grey with a white wing |
| Football | (106, 146) | 12 × 24 | ×2, white with black patches, in mid-air |
| Dog | (114, 208) | 20 × 32 | ×2, orange terrier, standing on the floor |
| Robot vacuum | (4, 212) | 24 × 28 | ×2, dark red, on the floor |
| Saucer of milk | (28, 224) | 16 × 16 | ×2, white saucer, cyan milk |
| Two sausages | (94, 224), (104, 228) | 8 × 16 each | ×2, coral |
| Floor | y = 240 to 271 | 192 × 32 | pen 6 olive; a 2 px pen 7 line along the top; pen 7 plank divisions every 24 px |

**The fridge** (the vintage two-door Pitsos the whole game is about): grey body
(pen 5) with a white frame (pen 3); the interior 30 px wide is pen 15, lit; three
white shelves at 28, 60 and 92 px down, each with a coral sausage on it; the door
swung back on the right, 14 px wide, pen 5 with a white frame, an olive hinge and two
white handles; **four red (pen 13) digital locks** down the left edge at 100, 108, 116,
124 px down — these are plot-critical and must survive. Light spills out as two pale
yellow (pen 15) triangles lying across the floorboards to the left.

**The cat (Loukoumas)** — the hero, and the one thing that must stay recognisable.
Overweight European Shorthair, butter yellow (pen 2) with a pale yellow (pen 15)
belly, orange (pen 7) tabby stripes on the forehead and rings on the tail.
Seen front-on, sitting, 52 wide × 84 tall: triangular ears with coral (pen 1) inners;
a round head 42 px across; two large white (pen 3) eyes with black (pen 4) pupils and
a cyan (pen 11) glint; a pale yellow muzzle with a coral nose and a black mouth; three
white whiskers each side; a fat round body; pale yellow front and back paws; the tail
curling up behind him on the right. He is **holding a sausage in both front paws**.

## 4. Colour census of the current image

Background (pen 0) 51.7%, pale yellow 11.3%, olive 8.8%, yellow 7.3%, grey 6.4%,
black 3.2%, white 2.9%, dark red 2.9%, coral 2.5%, orange 2.5%, then purple, red,
cyan and green under half a percent each.

**Over half the picture is flat, empty navy.** That is the largest single opportunity.

## 5. What must not change

1. 192 × 272 pixels, 2:1 pixel aspect, the 16 RGB values in §2 and nothing else.
2. The game's name, in the correct alphabet for each version, legible and dominant.
3. The cat: fat, yellow, front-on, big-eyed, holding a sausage. He is the character.
4. The fridge with its four red locks, and sausages visible inside it.
5. The night reading — this is 3:15 in the morning, which is where the story starts.
6. The bottom 32 rows stay a plain floor band: the game will later draw a blinking
   "PRESS FIRE TO START" over the lower part of the screen, and it must stay readable.
7. Nothing may rely on colours per scanline changing (no raster tricks) — this is one
   flat picture with one palette.

## 6. Where it is weak — what to improve

In rough order of how much it would gain:

1. **The empty navy.** Half the canvas is a flat field. It wants to become a room: a
   kitchen wall with a skirting board, tiles or wallpaper, a window with the moon
   actually behind it, a hint of worktop, cupboards, a clock reading 3:15. Dithering
   between navy (0) and black (4), or navy and purple (14), would give it depth at no
   cost in colours.
2. **No dithering anywhere.** Every surface is a flat fill. Classic mode 0 art uses
   two-pen checkerboards for every curved surface — the cat's body, the fridge, the
   floor. This alone would lift it from "programmer art" to "CPC art".
3. **The cat's pose is static and perfectly symmetrical.** He should have attitude:
   caught in the act, eyes wide, one ear back, leaning, mouth full. Front-on and
   mirrored is the weakest possible pose for a character piece.
4. **The lettering is the in-game font scaled up, not a designed logo.** It reads, but
   it is a bitmap font at 6×. A proper logo — chunkier, with a bevel, a highlight, a
   slight arch or perspective, maybe a sausage forming one stroke — would transform
   the screen. It must remain legible in both alphabets.
5. **The cast is scattered, not composed.** Nine characters sit at nine unrelated
   points. They want grouping, overlap and a sense of depth — some behind the cat,
   some in front, a diagonal leading the eye from the title down to him.
6. **The floor is a flat olive band with orange lines.** Perspective, a skirting board,
   tile joins, or the light from the fridge picked out properly across it.
7. **Pens 8 (dark green) and 10 (teal) are completely unused**, and pen 9 (bright
   green) is used for twelve pixels. There are three colours free.
8. **The second half of the story is not represented.** The subtitle promises a chase;
   the picture is entirely the kitchen. A hint of what comes after — a school bus, a
   satchel, rooftops through the window — would do a lot.

## 7. Deliverable

A PNG, exactly 192 × 272, indexed or RGB, using only the 16 RGB values in §2, with no
anti-aliasing and no colour outside the list. One for each language, differing only in
the lettering. If the tool cannot hold the palette exactly, send it anyway at 192 × 272
and say so — it can be quantised back, but anything relying on intermediate tones will
be lost, so it is better to draw within the palette from the start.

Judge the result **stretched 2× horizontally**, never at 1:1.
