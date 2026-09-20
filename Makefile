# OverscanCPC - build with rasm (https://github.com/EdouardBERGE/rasm)
#
#   make              everything
#   make hello        the overscan proof of concept
#   make loukoumas    ΛΟΥΚΟΥΜΑΣ title screen, English and Greek
#   make mitsos       ΠΑΝΙΚΟΣ ΣΤΟ ΠΑΝΤΟΠΩΛΕΙΟ, the mode 1 game
#   make assets       regenerate the font, strings and sprites (needs python3)
#   make shots        retake every screen shot in docs/, both languages
#   make check        run each binary on a Z80 interpreter and decode the screen
#   make clean
#
# Snapshots (.sna) drag into an emulator; disc images boot with RUN"<name>.

# A clean playthrough with the enemies in place: all five sausages, the saucer
# of milk, no lives lost. It has to belly-flop to get past the robot patrolling
# shelf 2, so it tests that mechanic as well as the physics, and the saucer sits
# at the near end of that same shelf, so it tests the extra life too. It is the
# level design's own test - change a shelf, the jump height or an enemy's patrol
# and it stops passing.
# Two screens stand between a scripted run and the game now - the title and
# the difficulty chooser behind it - so every route starts with two presses
# of fire, and everything that used to happen at frame n happens at n+8.
START := FIRE@22-26,FIRE@30-34
LOUNGE_ROUTE := $(START),RIGHT@53-91,LEFT@92-114,FIRE@115-117,LEFT@143-151,RIGHT@153-197,FIRE@168-170,FIRE@200-202,DOWN@204-229,FIRE@206-208,RIGHT@217-239,LEFT@242-301,FIRE@262-264,RIGHT@304-384,FIRE@328-330

RASM   ?= rasm
PYTHON ?= python3
BUILD  := build
DEPS   := $(wildcard src/*.asm)

# The tables are assembled once on their own, packed, and only then built into
# the game - so this list may not mention anything the packed copy depends on,
# or the build chases its own tail.
LOWDEPS := src/lowblock.asm src/config.asm src/font.asm src/strings.asm \
           src/sprites.asm src/artwork.asm src/enemykind.asm src/rooms.asm

# rasm can only put what it assembles on a disc, so iDSK adds the rest: the
# BASIC loader as ASCII - with the carriage returns the CPC wants at the end
# of a line, which is why it goes through sed - and the REVIVE8BIT screen with
# a header that loads it at &C000.
define add_loader
	@command -v iDSK >/dev/null || \
		(echo "    the disc needs iDSK to carry the loader - " \
		      "http://github.com/cpcsdk" && false)
	@$(PYTHON) -c "import sys; open(sys.argv[2],'wb').write(open(sys.argv[1],'rb').read().replace(b'\n', b'\r\n'))" src/louk.bas $(BUILD)/louk.bas
	@iDSK $(1) -i $(BUILD)/louk.bas -t 0 -f > /dev/null
	@iDSK $(1) -i assets/revive8b.scr -t 1 -c C000 -e C000 -f > /dev/null
endef

.PHONY: all hello loukoumas mitsos assets shots covers manuals check clean

all: hello loukoumas mitsos

# ---------------------------------------------------------------------------
# Generated sources. Committed, so building needs only rasm; python3 is needed
# when the font art or the string files change.
# ---------------------------------------------------------------------------
TEXTSRC := assets/font.txt text/loukoumas.en.txt text/loukoumas.el.txt tools/mktext.py

assets: src/font.asm src/strings.asm src/sprites.asm src/artwork.asm \
        src/titlepic.asm src/mitsosart.asm

src/font.asm src/strings.asm: $(TEXTSRC)
	$(PYTHON) tools/mktext.py loukoumas

src/sprites.asm: assets/sprites.txt tools/mksprite.py
	$(PYTHON) tools/mksprite.py

# Mitsos and his cast, drawn in Aseprite through its MCP server - one file
# per subject in assets/aseprite/mitsos, every frame in it, and the PNGs
# beside them are what the converter reads. Same converter and same sixteen
# pens as the other game: both are mode 0.
src/mitsosart.asm: $(wildcard assets/art/mitsos/sprite/*.png) tools/mkart.py tools/cpcpng.py
	$(PYTHON) tools/mkart.py mitsos

# The Aseprite artwork: enemies and the scenery that is not a rectangle.
src/artwork.asm: $(wildcard assets/art/sprite/*.png) $(wildcard assets/art/decal/*.png) tools/mkart.py
	$(PYTHON) tools/mkart.py

# The title screen: a whole overscan screen, quantised to the sixteen pens and
# packed to about seven kilobytes. Also writes build/title.bin, the same
# picture raw - 96 bytes by 272 scanlines - for anything that wants to load it
# straight into a screen. Needs Pillow, which is why the .asm is committed.
src/titlepic.asm build/title.bin: assets/art/title.jpg tools/mkscreen.py
	$(PYTHON) tools/mkscreen.py assets/art/title.jpg title

# The screen shots the manuals and the inlay are made of, in both languages -
# the HUD and the room name are text, so an English booklet cannot carry a
# Greek screen. Each one is a build that starts in the room it wants and a
# scripted route to the frame worth keeping, taken off the same Z80
# interpreter make check reads the screen with. Committed, because taking
# them needs rasm and Pillow; `make shots` takes the lot again.
SCENES := title difficulty lounge kitchen backyard park rooftops gameover
SHOTS  := $(foreach s,$(SCENES),docs/loukoumas-$(s)-en.png docs/loukoumas-$(s)-el.png)
COVER_SCENES := lounge park rooftops gameover

shots:
	$(PYTHON) tools/mkshots.py

# The disc inlay, in both languages: back, spine and front in one piece, the
# way it was printed and folded into a 3" case, plus the front on its own.
# Committed, because the fonts it wants are not everywhere.
COVERS := docs/cover-en.png docs/cover-el.png

covers: $(COVERS)

# The manuals as the printed booklet, A5, out of the same markdown anybody
# reads on the web. Needs fpdf2 (pip install fpdf2), so they are committed.
MANUALS := docs/manual-en.pdf docs/manual-el.pdf

manuals: $(MANUALS)

docs/manual-%.pdf: MANUAL.%.md docs/cover-%-front.png $(SHOTS) tools/mkmanual.py
	$(PYTHON) tools/mkmanual.py $< $@

docs/cover-%.png: assets/art/title.jpg $(SHOTS) tools/mkcover.py
	$(PYTHON) tools/mkcover.py assets/art/title.jpg $* $@ \
		$(foreach s,$(COVER_SCENES),docs/loukoumas-$(s)-$*.png)

# The tables - font, strings, sprites, artwork, enemy kinds, rooms - assembled
# at the address they run at and saved raw, then packed. Twelve and a half
# kilobytes of the file becomes eight and a half, and the game unpacks them in
# its first instruction. build/tables.bin is also what roomcheck.py reads.
$(BUILD)/tables.bin: $(LOWDEPS) | $(BUILD)
	$(RASM) src/lowblock.asm -DLANG=1

src/tablepack.asm: $(BUILD)/tables.bin tools/mkpack.py
	$(PYTHON) tools/mkpack.py $(BUILD)/tables.bin $@ 0x0100

# ---------------------------------------------------------------------------
# HELLO WORLD - the overscan proof of concept
# ---------------------------------------------------------------------------
hello: $(BUILD)/hello.sna $(BUILD)/hello.dsk

$(BUILD)/hello.sna: $(DEPS) | $(BUILD)
	$(RASM) src/main.asm -DTARGET=1 -oi $@

$(BUILD)/hello.dsk: $(DEPS) | $(BUILD)
	rm -f $@
	$(RASM) src/main.asm -DTARGET=2 -eo

$(BUILD)/hello.bin: $(DEPS) | $(BUILD)
	$(RASM) src/main.asm -DTARGET=3 -ob $@

# ---------------------------------------------------------------------------
# ΛΟΥΚΟΥΜΑΣ - one binary holds both string tables; LANG only picks the one
# txt_lang starts on, so a run-time language switch is a single byte.
# ---------------------------------------------------------------------------
loukoumas: $(BUILD)/loukoumas_en.sna $(BUILD)/loukoumas_el.sna \
           $(BUILD)/loukoumas_en.dsk $(BUILD)/loukoumas_el.dsk

$(BUILD)/loukoumas_en.sna: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=1 -DLANG=0 -oi $@

$(BUILD)/loukoumas_el.sna: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=1 -DLANG=1 -oi $@

$(BUILD)/loukoumas_en.dsk: $(DEPS) src/louk.bas assets/revive8b.scr | $(BUILD)
	rm -f $@
	$(RASM) src/loukoumas.asm -DTARGET=2 -DLANG=0 -eo
	$(call add_loader,$@)

$(BUILD)/loukoumas_el.dsk: $(DEPS) src/louk.bas assets/revive8b.scr | $(BUILD)
	rm -f $@
	$(RASM) src/loukoumas.asm -DTARGET=2 -DLANG=1 -eo \
		-s -sa -os $(BUILD)/loukoumas_el_dsk.sym
	$(call add_loader,$@)

# The raw builds also emit a symbol file, which is what lets z80check watch
# named variables frame by frame - and, with -sa, lets roomcheck read the EQUs
# the room tables are built out of.
$(BUILD)/loukoumas_en.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=0 -s -sa -os $(BUILD)/loukoumas_en.sym
	mv $(BUILD)/out.bin $@

$(BUILD)/loukoumas_el.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -s -sa -os $(BUILD)/loukoumas_el.sym
	mv $(BUILD)/out.bin $@

# The living room is room 9 of 29, so the scripted run that tests it would
# otherwise have to play the eight rooms in front of it first. The back yard
# and the rooftops are there to prove a room is lit by its own palette: the
# first daylight room in the game and the first night one.
$(BUILD)/loukoumas_lounge.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=8 \
		-s -sa -os $(BUILD)/loukoumas_lounge.sym
	mv $(BUILD)/out.bin $@

$(BUILD)/loukoumas_yard.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=10 \
		-s -sa -os $(BUILD)/loukoumas_yard.sym
	mv $(BUILD)/out.bin $@

# The one build that keeps the title picture, so the picture gets checked too.
$(BUILD)/loukoumas_title.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=1
	mv $(BUILD)/out.bin $@

$(BUILD)/loukoumas_roof.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=27 \
		-s -sa -os $(BUILD)/loukoumas_roof.sym
	mv $(BUILD)/out.bin $@

# ---------------------------------------------------------------------------
# ΠΑΝΙΚΟΣ ΣΤΟ ΠΑΝΤΟΠΩΛΕΙΟ - the second game on the engine, and the first one
# in mode 1: four pens and 384 square pixels across the same 32 KB screen.
# One milestone so far - the shop floor, and Mitsos walking it.
# ---------------------------------------------------------------------------
mitsos: $(BUILD)/mitsos.sna $(BUILD)/mitsos.dsk

$(BUILD)/mitsos.sna: $(DEPS) | $(BUILD)
	$(RASM) src/mitsos.asm -DTARGET=1 -oi $@

$(BUILD)/mitsos.dsk: $(DEPS) | $(BUILD)
	rm -f $@
	$(RASM) src/mitsos.asm -DTARGET=2 -eo

$(BUILD)/mitsos.bin: $(DEPS) | $(BUILD)
	$(RASM) src/mitsos.asm -DTARGET=3 -s -sa -os $(BUILD)/mitsos.sym
	mv $(BUILD)/out.bin $@

# ---------------------------------------------------------------------------
# Executes each build on a Z80 interpreter and decodes screen RAM through the
# CRTC addressing - a layout check that needs no emulator. It models no timing
# at all; see the header of tools/z80check.py for the rest of the caveats.
# ---------------------------------------------------------------------------
# `all` is a dependency on purpose: the snapshots and disc images are what
# anyone actually runs, and without this they can sit a conversion behind the
# sources while check goes on passing against freshly built .bin files.
check: all $(BUILD)/hello.bin $(BUILD)/mitsos.bin \
       $(BUILD)/loukoumas_en.bin $(BUILD)/loukoumas_el.bin \
       $(BUILD)/loukoumas_lounge.bin $(BUILD)/loukoumas_yard.bin \
       $(BUILD)/loukoumas_roof.bin $(BUILD)/loukoumas_title.bin \
       $(BUILD)/title.bin
	@echo "=== every room climbable, every sausage and every saucer reachable ==="
	@./tools/roomcheck.py $(BUILD)/loukoumas_el.bin $(BUILD)/loukoumas_el.sym \
		$(BUILD)/tables.bin
	@echo "=== hello world ==="
	@./tools/z80check.py $(BUILD)/hello.bin --ascii
	@echo "=== mitsos, the grocery ==="
	@echo "    the same overscan screen as the other game and the same sixteen"
	@echo "    pens, with a shop painted on it out of boxes - wall, dado, tiled"
	@echo "    floor, shelving, counter, crates - and the cast standing in it."
	@echo "    Painting it takes thirteen frames of LDIR, which is a quarter of"
	@echo "    a second at the top of the game and nothing after that. He comes"
	@echo "    in at byte 8 facing right, walks to 45 on 37 frames of right,"
	@echo "    and stands still again when it is let go."
	@./tools/z80check.py $(BUILD)/mitsos.bin --frames 60 --keys "RIGHT@20-56" \
		--sym $(BUILD)/mitsos.sym --watch "mitsos_x,mitsos_face,mitsos_frame" \
		| grep -E "frame +(14|40|59) "
	@echo "=== loukoumas, English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_en.bin --frames 30 --ascii
	@echo "=== loukoumas, Greek ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 30 --ascii
	@echo "=== loukoumas, Greek build with L held - must come out English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 34 --keys L --ascii | sed -n '1,2p;15,20p'
	@echo "=== loukoumas, play field after walking right ==="
	@echo "    every sausage must survive the cat walking over one"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 98 --keys "$(START),RIGHT@36-98" --ascii | sed -n '1,2p;33,38p'
	@echo "=== loukoumas, physics: stand, jump, land on the shelf above ==="
	@echo "    58 on the floor at 212, 59 leaves at -1088, 75 apex at 173,"
	@echo "    83 landed on the rack's lower shelf at 180 and back in state 0"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 88 \
		--keys "$(START),FIRE@58-61" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s" | grep -E "frame ( 58| 59| 75| 83)"
	@echo "=== loukoumas, belly-flop: terminal velocity, screen shake, stun ==="
	@echo "    69 commits at 1536 and curls up, 73 lands flat and sets the"
	@echo "    shake and the stun"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 88 \
		--keys "$(START),FIRE@58-61,DOWN@63-107,FIRE@68-71" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s,cat_h,cat_stun,shake_timer" \
		| grep -E "frame ( 67| 69| 73| 75)"
	@echo "=== loukoumas, a robot costs a life and respawns the cat ==="
	@echo "    118 walking into it at column 74, 119 back at the start with"
	@echo "    a life gone and a hundred frames of grace. Three to begin with,"
	@echo "    because the chooser was left on hard"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 208 \
		--keys "$(START),RIGHT@48-208" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,cat_invul" | grep -E "frame (118|119)"
	@echo "=== loukoumas, the same walk into the same robot, on easy ==="
	@echo "    two presses of left in the chooser, and the three bytes that"
	@echo "    pace the cast come out 4, 3 and 200 instead of 2, 1 and 100: a"
	@echo "    step every fourth update instead of every second, a wingbeat"
	@echo "    every third instead of every one, and four seconds flat on its"
	@echo "    back after a belly-flop instead of two - and nine lives to lose"
	@echo "    rather than three. The robot has covered half the ground by the"
	@echo "    time the cat reaches it, so the cat is caught at column 50"
	@echo "    rather than 74."
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 120 \
		--keys "FIRE@22-26,LEFT@28-30,LEFT@32-34,FIRE@38-42,RIGHT@56-120" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,start_lives,walk_period,fly_period,stun_time" \
		| grep -E "frame (102|103)"
	@echo "=== loukoumas, nothing of the cast is left behind in the room ==="
	@echo "    every sprite saves the ground it is about to cover and puts it"
	@echo "    back before it moves. Two of them standing in each other save"
	@echo "    pieces of each other, and whichever hands its piece back last"
	@echo "    leaves it in the room for good - which is what the cat dying on"
	@echo "    a robot used to do. This walks it into one and counts the ink"
	@echo "    left standing on ground the room painted empty."
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 268 \
		--keys "$(START),RIGHT@48-268" --sym $(BUILD)/loukoumas_el.sym \
		--debris | tail -1
	@echo "=== loukoumas, clean run of the lounge and out through the vent ==="
	@echo "    a sausage at 91, 149, 237, 295 and 367, the saucer of milk at"
	@echo "    225 - which he has all nine lives for, so it is worth points"
	@echo "    instead - then cur_room 8 -> 9 at 369 into the vent"
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 398 --keys "$(LOUNGE_ROUTE)" \
		--sym $(BUILD)/loukoumas_lounge.sym \
		--watch "cur_room,cat_lives,sausages_got,milk_alive,level_done" \
		| grep -E "frame ( 91|149|225|237|295|367|369)"
	@echo "=== loukoumas, and the saucer when a life is missing ==="
	@echo "    the saucer never takes him past the number the difficulty"
	@echo "    started him on, so a clean run - which loses nothing - always"
	@echo "    takes the points and never the life. One life poked in before"
	@echo "    he reaches it, and 225 has to hand one back instead."
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 240 \
		--keys "$(LOUNGE_ROUTE)" --sym $(BUILD)/loukoumas_lounge.sym \
		--poke "cat_lives=1@200" --watch "cat_lives,start_lives,milk_alive" \
		| grep -E "poked|frame (224|225)"
	@echo "=== loukoumas, the tables unpacked by the Z80 itself ==="
	@echo "    twelve and a half kilobytes of font, sprites, artwork and rooms"
	@echo "    packed to eight and a half and unpacked into #0100 before the"
	@echo "    game does anything else. Every byte has to come back."
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 30 \
		--save-mem "0x0100:$$(stat -c%s $(BUILD)/tables.bin)=$(BUILD)/unpacked.bin" \
		| grep "^wrote"
	@cmp $(BUILD)/tables.bin $(BUILD)/unpacked.bin \
		&& echo "    the tables came back byte for byte"
	@echo "=== loukoumas, every sprite back on the screen before the beam ==="
	@echo "    the cast is lifted off and put back once every two VSYNCs. A"
	@echo "    sprite is missing from the moment its erase starts to the moment"
	@echo "    its redraw ends, and if the beam crosses its own rows in that"
	@echo "    window it draws a hole. That is what flicker is, and none of"
	@echo "    A frame where two sprites stand in each other is not rebuilt"
	@echo "    one at a time at all: it is unwound whole and laid down again,"
	@echo "    which is the only order that leaves nothing of either of them"
	@echo "    behind. That costs the frame its flicker, and what it costs it"
	@echo "    is the canary - the highest thing on the screen, so the one"
	@echo "    with the least time - waiting through everybody else's erase"
	@echo "    before its own. Every one of these is that, and every one of"
	@echo "    them is a frame the cat is inside something. A sixteenth of the"
	@echo "    run, and the budget says it stays that way."
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 398 \
		--keys "$(LOUNGE_ROUTE)" --sym $(BUILD)/loukoumas_lounge.sym \
		--beam --beam-from 20 | tail -1 | tee $(BUILD)/beam.txt
	@$(PYTHON) -c "import re,sys; n,t = map(int, re.search(r'(\d+) of (\d+)', \
		open('$(BUILD)/beam.txt').read()).groups()); \
		print('    %d%% of them, and the budget is 6%%' % (100*n//t)); \
		sys.exit(0 if 100*n <= 6*t else 1)"
	@echo "=== loukoumas, a room is lit by one pen, and it is pen 0 ==="
	@echo "    the back yard must report pen0=23, sky blue; the rooftops pen0=20,"
	@echo "    black; every room in the flat is pen0=4, navy"
	@./tools/z80check.py $(BUILD)/loukoumas_yard.bin --frames 78 --keys "$(START)" \
		| grep -o "pen0=[0-9]* " | sed 's/^/    back yard  /'
	@./tools/z80check.py $(BUILD)/loukoumas_roof.bin --frames 78 --keys "$(START)" \
		| grep -o "pen0=[0-9]* " | sed 's/^/    rooftops   /'
	@echo "=== loukoumas, the title picture unpacked onto the overscan screen ==="
	@echo "    26,112 bytes of screen, packed to about seven and unpacked by the"
	@echo "    Z80 itself. Every byte of it outside the two text panels - rows"
	@echo "    54 to 235 - has to come back identical to the picture that"
	@echo "    tools/mkscreen.py made."
	@./tools/z80check.py $(BUILD)/loukoumas_title.bin --frames 220 \
		--dump $(BUILD)/title-screen.bin | tail -1
	@cmp -i 5184 -n 17472 $(BUILD)/title-screen.bin $(BUILD)/title.bin \
		&& echo "    the picture came back byte for byte"
	@echo "=== loukoumas, on a real 6128 ==="
	@echo "    everything above reasons about the machine. This runs it:"
	@echo "    floooh/chips' 6128 with the real ROMs, booted, RUN\"LOUK off the"
	@echo "    disc image through AMSDOS, and then asked what actually came out"
	@echo "    - the tables, the overscan picture, the keyboard and the game."
	@./tools/emucheck.py $(BUILD)/loukoumas_el.dsk $(BUILD)/loukoumas_el_dsk.sym \
		$(BUILD)/tables.bin $(BUILD)/title.bin assets/revive8b.scr \
		$(BUILD)/emu; \
		s=$$?; test $$s -eq 0 -o $$s -eq 2
	@echo "=== what you can actually run ==="
	@ls -l $(BUILD)/*.sna $(BUILD)/*.dsk | awk '{printf "    %-28s %8s bytes  %s %s %s\n", $$9, $$5, $$6, $$7, $$8}'

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin $(BUILD)/*.sym
