# LOUKOUMAS: THE GREAT SAUSAGE CHASE
### (ΛΟΥΚΟΥΜΑΣ: Το Κυνήγι του Λουκάνικου)
**Machine:** Amstrad CPC 6128 (128 KB RAM)
**Graphics:** Mode 0 (16 colours), full overscan - 96 bytes x 272 scanlines, 384x272 pixels on the tube
**Sound:** Arkos Tracker 3 (AKG player) on the title screen, one channel of effects in the game
**Tools:** RASM, iDSK, Aseprite, Python - all behind one `make`

> **Note.** This document started life as a design, written before there was a
> line of code. The game then got built, and in several places it disagreed:
> the machine has sixteen kilobytes for everything that is not the screen, and
> half the promises in the first draft either did not fit or did not work. What
> follows describes the game **as it is**, and where the design was wrong it
> says so and what took its place. For how the machine is driven, see
> `CLAUDE.md`; this is the game.
>
> Το ίδιο κείμενο στα ελληνικά: [loukoumas.md](loukoumas.md).
> Player's manual: [MANUAL.en.md](MANUAL.en.md).

---

## 1. Summary & Identity

* **Title:** *LOUKOUMAS - The Great Sausage Chase*
* **Genre:** Arcade / single-screen platformer, 29 rooms
* **Tone:** Comic, cute, slapstick cartoon at a fast pace.
* **Look:** Chibi pixel art in **mode 0**, sixteen colours at once, in overscan
  with no trace of a border.
* **Audience:** Retro gamers, Amstrad CPC people, and the demoscene end of
  retro engineering.
* **Languages:** Greek and English, switched from the title screen with `L`.
  There is not one literal word of either inside the source.

> **What changed:** the design said mode 1 and four colours. The game is mode 0
> with sixteen. A mode 0 pixel is twice as wide, so nothing changed size on the
> screen - only how finely it can be drawn. What that bought: a fridge is now
> grey with red sausages in it, rather than an outline drawn on nothing.

---

## 2. The Story

It is a quarter past three in the morning in Mrs Evdokia's flat in Kypseli.
Everybody is asleep. Everybody except one.

**Loukoumas**, a plump, overweight European Shorthair with short legs, enormous
eyes and an unappeasable love of cured meats, has been woken by a rumble in his
own stomach. Mrs Evdokia has him on a diet, though, and the house is not his
any more: a robot vacuum patrols the floor at night, and her canary, the
**Tweety-Boxer**, flies free from one end of the room to the other.

Loukoumas starts in the basement with one purpose: to climb to the kitchen and
open the two-door vintage *Pitsos*.

**And he finds it empty.**

The last one, the big one, went to school in the lunchbox of **Myrto**, Mrs
Evdokia's granddaughter. Outside, the school bus is starting its engine. From
here on the game is not a raid; it is a **chase**, and it lasts another
nineteen rooms.

### 2.1. Three acts, 29 rooms

**Act One - the flat (rooms 1-10, quarter past three in the morning).**
Basement, garage, garden, hallway, bedroom, wardrobe, bathroom, study, lounge,
kitchen. It ends at the empty fridge.

**Act Two - the neighbourhood and the school (rooms 11-24, in daylight).**
Out through the back yard and after the lunchbox across the neighbourhood and
the whole school: back yard, the lemonade stand, playground, park, school gate,
the corridor with the lockers, classroom, staff room, science lab, gym, pitch,
car park, inside the school bus, and back out onto the pavement.

**Act Three - the vet's, and the way home (rooms 25-29).**
On the pavement somebody picks him up for a stray, and he ends up at the vet's
along with the lunchbox. He escapes through reception, the surgery and the
storeroom - where the lunchbox has been impounded - and goes home over the
rooftops, down the chimney into the lounge fireplace. Myrto has left him a bowl
of milk.

The shape does not change from room to room: every room is one floor, four
shelves a jump apart, **five sausages**, **three enemies** and one way out.
What changes is the light (navy / sky blue / black), the floor, the furniture,
and what is chasing you.

### 2.2. What fell out of the first draft

Written down because somebody may remember it and go looking for it:

| In the first draft | In the game |
|---|---|
| Four digital padlocks on the fridge | Not there. The way out opens on the room's five sausages |
| Four "Golden Sausages" per room | Five, and they are just sausages |
| The Mythical Smoked Salmon of Norway | Never existed. The fridge is empty, and that is the turn the story is built on |
| Sentient frozen burgers from 2019 | Did not get made |
| Catnip that reverses gravity | Did not get made |
| The milk bowl gives 6 seconds of speed | It gives **a life back** - see 2.4 |
| The canary throws ice cubes | It flies an arc, and that is all. Nothing in this game has a projectile |
| Robots are killed by dropping a vase on them | They are stunned by the belly-flop - see 3.1 |
| The game ends at the fridge | That is where the **first of three acts** ends |

### 2.3. The enemies, by theme

Only two behaviours - something that walks a platform and something that flies
an arc across the room - but twelve creatures, because a robot vacuum patrolling
a park bench is not a joke that survives being told nineteen times. An enemy's
type byte is an index into a table (`src/enemykind.asm`), not a branch in the
movement code: a new creature costs three bytes there plus its picture.

| Enemy | Moves | Where |
|---|---|---|
| Robot vacuum | walks | the flat |
| The canary | flies | the flat |
| Next door's terrier | walks | back yard, pavement, the vet's |
| Pigeon | flies | park, street, rooftops |
| Wasp | flies | anywhere with flowers |
| Football | rolls (walks) | playground, gym, pitch |
| Paper plane | flies | the school |
| The caretaker's bucket | walks | the school |
| Something green | walks | the chemistry lab |
| Syringe | flies | the vet's |
| Bat | flies | rooftops, chimney |
| The stray tom | walks | rooftops, car park |

### 2.4. The saucer of milk

The design had it as a speed power-up. Over 29 rooms something more basic was
wanted: **one life back, and never past the number the difficulty started him
on** (points instead, while he still has all of them). There is one in **every third room** (3, 6, 9, 12, 15,
18, 21, 24, 27), always on the most awkward shelf - usually the one something is
patrolling - and the way out does not wait for it: a room can be finished
without it.

Collecting it **flashes the border of the screen**, because the lives digit in
the corner of a two-row HUD is not something anyone sees while they are being
chased - and in a game with no border left to speak of, the frame around the
picture is exactly the right place to say something.

---

## 3. Core Mechanics

### 3.1. Controls (joystick / keyboard)

| Key | Joystick | What it does |
|---|---|---|
| Left / Right | yes | Walk, 4 pixels a step |
| Up or Space | up / fire | Jump - low, on account of the... weight: it clears 40 scanlines |
| Down (on the ground) | down | **Roll**: curls into a ball, twice the speed and shorter, to get under things |
| Down + Space (in the air) | down + fire | **Belly-flop** |
| `L` (title screen) | - | Greek / English |
| `ESC` | - | Back to the title screen |

The **belly-flop** is the game's tool, not a flourish: the landing shakes the
screen and **stuns everything at roughly the height it landed at**, however far
along the shelf it happens to be. That is deliberate - it makes the flop the way
to get past a robot patrolling a whole shelf, which a short shockwave did not. A
stunned enemy neither dies nor hurts: it is scenery, until it gets up.

### 3.2. Screen elements and objects

* **Sausages:** 5 per room. Take all five and the door or the vent **changes
  picture** and becomes a way through. Each one is worth points.
* **Saucer of milk:** a life back, up to what he started with - see 2.4.
* **Enemies:** three per room. Contact costs a life, Loukoumas restarts at the
  beginning of the room with **two seconds of grace**, and the room does not
  refill: what you collected stays collected.
* **Furniture:** not sprites. Lists of filled rectangles, drawn once into the
  background - about fifty bytes for a fridge, however large it is. The white
  outline means **scenery**; anything you can stand on is **pen 2**, butter
  yellow, in every room. That distinction is the level's grammar and it never
  changes.
* **Trees, clouds, moons:** a tree is not a box. Those are **decals** - bitmaps
  drawn in Aseprite that are simply ORed into the background when the room
  loads. They carry no mask, because the screen underneath has just been cleared
  to pen 0 and ORing 0 changes nothing: half the bytes of a masked sprite, and
  the cost is paid once.
* **Lives and score:** nine, six or three, from the difficulty - see 3.3. The
  number he started on is also his ceiling, so the saucer of milk tops him back
  up rather than past it, and nine is as high as any of them goes because the
  HUD prints the lives with one digit. The score is packed BCD, so the
  arithmetic is `DAA` and printing is two digits a byte - no division.
* **HUD:** two rows above the play field - score, lives, sausages, room name -
  and it only repaints when something has changed.

### 3.3. Three difficulties

Chosen **after the title screen**, in the footer of the same picture, with left
and right and fire. Hard is the game exactly as it was before there was a
choice - the chooser only ever makes it kinder.

| | Lives | Walker's step | Flyer's wingbeat | Stun after a flop |
|---|:---:|:---:|:---:|:---:|
| **Easy** | 9 | every 4th update | every 3rd | four seconds |
| **Medium** | 6 | every 3rd | every 2nd | three seconds |
| **Hard** | 3 | every 2nd | every one | two seconds |

The cast is slowed down by taking **fewer steps**, not smaller ones: nothing in
the movement code has to know about fractions of a byte, and a robot on easy
covers the same shelf in twice the time.

The four numbers are one record in `diff_tab`, copied over `walk_period`,
`fly_period`, `stun_time` and `start_lives` when fire accepts the setting -
which is why adding a fifth thing for the difficulty to move is a byte in a
table rather than a branch anywhere.

---

## 4. Visual and Audio Design

### 4.1. The mode 0 palette (16 colours)

Sixteen pens at once out of the Gate Array's 27. Pen 0 is both the background
and the border, and it is **the only colour that changes from room to room**:
navy is a wall at three in the morning, sky blue is nine o'clock outside a
school, black is a roof at midnight. Nothing else moves, so Loukoumas is butter
yellow in all twenty-nine of them.

| Pen | Colour | HW | Role |
|:---:|---|:---:|---|
| 0 | Navy | 4 | background and border - **changes per room** |
| 1 | Coral | 7 | paws, nose, sausages, text |
| 2 | Butter yellow | 10 | fur, light, brass, **shelves** |
| 3 | White | 11 | eyes, floor, furniture outlines |
| 4 | Black | 20 | shadow, pupils, the back of a cupboard |
| 5 | Grey | 0 | steel - shelving, the car, appliances |
| 6 | Olive | 30 | wood in shadow |
| 7 | Orange | 14 | wood in the light, brick, rust |
| 8 | Dark green | 22 | leaves, painted metal |
| 9 | Green | 18 | grass |
| 10 | Teal | 6 | deep water, glazed tile |
| 11 | Cyan | 19 | water, glass, porcelain |
| 12 | Dark red | 28 | the robots' bodies |
| 13 | Red | 12 | hobs, warning lamps |
| 14 | Purple | 24 | night through a window, the wardrobe |
| 15 | Pale yellow | 3 | lamplight |

> **What changed:** pen 2 is not only the fur - it is also "you can stand here".
> The shelves stay pen 2 in **every** room, even where the floor is concrete or
> grass, because "you can stand on this" has to read the same everywhere.

### 4.2. Sound and music

**There is music on the title screen and nowhere else.** It is played by Arkos
Tracker 3's AKG player (`src/playerakg.asm`, the tune in `src/loukmus.asm`), one
tick a frame. It stops when the game starts and the chip goes over to effects.

**Why:** lifting this cast off a 32 KB overscan screen and putting it back is
thirteen milliseconds, and a frame is twenty. Three channels of music on top of
that is a different game.

**The effects** are one channel, one at a time, four of them (`src/sound.asm`):

| Effect | Sound |
|---|---|
| Jump | a tone from 312 Hz up to about 650, eight frames |
| Eating a sausage | a short high blip, rising |
| Death | a tone sliding a long way down, half a second |
| Belly-flop | noise - a thud, pitched low |

An effect is a starting period, a signed step added to it every frame, and a
length; the **volume is whatever is left of the length**, so everything fades as
it ends without costing a single byte of state.

> **A trap worth knowing:** the PSG is not on the bus - you reach it through the
> same 8255 PPI as the keyboard. Bit 6 of the mixer is the direction of the
> PSG's own port A, and the keyboard is read through that port: every mixer
> value here keeps it at 0. Set it and you silently kill the keyboard, and
> nothing else looks wrong.

---

## 5. Technical: 96 bytes x 272 lines of overscan on a 6128

### 5.1. Dimensions and memory

* **Horizontally:** 48 CRTC characters x 2 bytes = **96 bytes per line**. In
  mode 0 that is 192 pixels - which come out 384 pixels wide on the tube,
  because a mode 0 pixel is double width.
* **Vertically:** 34 character rows x 8 = **272 scanlines**.
* **Total:** 96 x 272 = **26,112 bytes**, which is half the machine.

### 5.2. Two pages, and no rupture

MA starts at **#2C10**: page 2 (#8000), at a character offset of 16. Rows 0-20
are 21 x 48 = 1008 characters and run from offset 16 to 1023 - exactly filling
the 1024-character window. Row 21 begins at MA #3000, which flips MA12 and
carries the fetch into page 3 (#C000) with the character counter back at 0.

That is what buys a 32 KB screen with **no mid-frame reprogramming at all**: no
rupture, and no dependence on CRTC type.

> **What changed:** the design talked about a second buffer in extended RAM
> banks for "flicker-free double buffering". There is no double buffer and there
> could not be one: a second 32 KB screen plus code does not fit comfortably in
> 128 KB, and repainting 26 KB a frame is impossible. Sprites **save the
> background they cover** and put it back before they move.

### 5.3. The register values that are actually written

From `src/config.asm` - these are the numbers that go out, not the ones the
design hoped for:

| Register | Description | Firmware | Here | Why |
|:---|:---|:---:|:---:|:---|
| **R0** | Horizontal Total | 63 | **63** | 64 characters = 64 us. Never changes |
| **R1** | Horizontal Displayed | 40 | **48** | 96 bytes = 192 mode 0 pixels |
| **R2** | HSYNC Position | 46 | **50** | re-centres the wider window |
| **R3** | Sync Widths | &8E | **&8E** | HSYNC 14 chars, VSYNC 8 lines |
| **R4** | Vertical Total | 38 | **38** | keeps the frame at 312 lines |
| **R5** | Vertical Total Adjust | 0 | **0** | |
| **R6** | Vertical Displayed | 25 | **34** | 34 x 8 = 272 lines |
| **R7** | VSYNC Position | 30 | **34** | vertical centring; the screen shake moves it |
| **R8** | Interlace | 0 | **0** | |
| **R9** | Max Raster | 7 | **7** | 8 scanlines per character row |
| **R12/R13** | Screen Start | &30/&00 | **&2C/&10** | MA = #2C10 - see 5.2 |

> **The old table in this document was wrong** in three places: R0=64 (which
> grows the frame and wrecks the interrupt cadence), R7=35, and R12/R13=&10/&00,
> which points at page 1. None of them puts a picture on a tube.

### 5.4. The screen shake

It moves **R7**, never R12/R13. The screen base is chosen so that the crossing
from page 2 to page 3 lands exactly on a character row boundary; move the base
and the row where the pages meet is scrambled. R7 can only go **up** from 34,
because below R6 the VSYNC would begin inside the display.

### 5.5. Where everything fits

The screen is half the machine. What is left:

* **#0100-#3240:** the tables - font, strings, sprites, artwork, enemies, 29
  rooms. Twelve and a half kilobytes, which travel **packed** inside the file
  and are unpacked into place in the first few milliseconds.
* **#35E0-#3FFF:** the line table and the background the pickups keep - RAM the
  program builds for itself. Below #4000 it **costs the disc file nothing**,
  while anything declared above #4000 costs a byte whether it is ever written
  from the file or not.
* **#4000-#65B5:** the code and the workspace.
* **#6700 upwards:** the title picture packed, and behind it the packed tables.
  The file ends just below **#A67B**, where AMSDOS's buffers start.

The title picture is the whole overscan screen - 26,112 bytes - packed into
about seven kilobytes. The decompressor keeps **no window at all**: the screen
is its own window, and a back reference is two cursors walking the picture, one
behind the other. Eleven bytes of state and no buffer, which is the only reason
a full-screen picture fits in this game.

---

## 6. Toolchain

One `make` does all of it. The tools are Python and live in `tools/`:

| Tool | What it does |
|---|---|
| `mktext.py` | `text/*.txt` -> `src/strings.asm` + `src/font.asm`. A word missing from one language is a build error |
| `mksprite.py` | `assets/sprites.txt` (ASCII art) -> `src/sprites.asm` |
| `mkart.py` | Aseprite PNGs -> `src/artwork.asm`, mirrored copies included |
| `mkscreen.py` | the title artwork -> a packed overscan screen |
| `mkpack.py` | the tables -> LZSS, then unpacks them again to prove they come back |
| `mkcover.py` | the disc inlay, in both languages |
| `z80check.py` | a Z80 simulator on the CPC's own clock: scripted keys, `--beam`, `--debris`, `--profile` |
| `roomcheck.py` | every room climbable, every sausage and every saucer reachable |
| `emucheck.py` | boots a real 6128 (floooh/chips) with its own ROMs and runs the disc |

The graphics are drawn in **Aseprite** through Lua scripts
(`assets/aseprite/`), with the MCP server driving Aseprite. The scripts are in
the repository, so the art can be rebuilt from nothing without a committed
`.aseprite` file.

### 6.1. What is on the disc

| File | What |
|---|---|
| `LOUK.BAS` | the loader: mode 0, the sixteen inks, loads the splash screen, and starts the game on space or after ten seconds |
| `REVIVE8B.SCR` | the splash screen, 16 KB at &C000 |
| `LOUK.BIN` | the game |

> A BASIC file on a CPC disc wants **carriage returns** at the end of its lines.
> `src/louk.bas` is kept with ordinary newlines so it reads like source, and the
> Makefile converts it on the way in. Without that the machine reads the whole
> file as one line and says `Line too long`, which is not a helpful clue.

---

## 7. The game loop

The real code is in `src/` - this is its shape, because two decisions inside it
explain everything else:

```
play_loop
    wait_render            ; two VSYNCs: the picture is rebuilt 25 times a second
    sprites_update         ; the SCREEN first - the beam does not wait
    read_controls
    2 x (cat_update, enemies_update, pickups, collisions, sfx_update)
    update_hud             ; anything that only thinks goes after the drawing
    sprites_order
```

**The screen first, the thinking after.** Everything the beam is about to draw
has to be back before it gets there, and the only currency is the microseconds
after the tick. Six milliseconds of keys, physics and collisions **in front of**
the drawing pushed it a hundred scanlines into the picture.

**25 pictures a second, 50 thoughts.** `wait_render` counts two ticks and the
loop takes two logic steps inside one picture, so the jump arc, the patrol speed
and every timer are exactly what they were - only how often the screen is
rebuilt changed.

**Sprites are lifted off and put back one at a time, from the top of the screen
down** - that way the beam finds each of them already drawn. When two sprites
stand inside each other the frame is unwound whole and laid down again instead,
because that is the only order that leaves no piece of either of them behind in
the room.

---

## 8. `make check` - what says it works

There is no `build.sh`; there is `make` and `make check`, and the second is what
keeps the game standing up:

* every one of the 29 rooms is climbable, and every sausage and every saucer is
  reachable (`roomcheck.py`),
* a **clean run** through the lounge with the enemies in place: five sausages,
  the milk on the shelf the robot patrols, no lives lost - and it has to
  belly-flop to get past. If that stops passing after a change to a shelf, the
  jump height or a patrol, **the room is no longer completable the way it was**,
* no piece of any sprite is left behind in the room (`--debris`),
* fewer than one rebuild in sixteen fails to beat the beam (`--beam`),
* the tables and the title picture come back out of the decompressor **byte for
  byte**,
* and all of it then runs on a **real 6128** with its own ROMs: the loader,
  AMSDOS, the CRTC, the keyboard, the difficulty chooser and the cat walking.

---

## 9. What did not get made

Listed because it was on the list and did not happen - not because it was
forgotten:

1. **Boss fights.** The "Freezer of Terror" with falling ice crystals. The game
   has one enemy behaviour that walks and one that flies; a boss is a third, and
   the code for it has nowhere to go.
2. **Music during play.** See 4.2 - that is a question of microseconds, not of
   bytes.
3. **Easter eggs**, PlayCity dual-AY sound, pixel-exact horizontal movement
   (which wants four pre-shifted copies of every sprite).
4. **Confirmation on a real monitor.** The emulator is happy with the centring;
   a CTM640 may not be, and R2/R7 are the knobs. Also: there are five CRTC types
   and the emulator is one of them.
