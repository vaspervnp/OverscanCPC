# OverscanCPC - build with rasm (https://github.com/EdouardBERGE/rasm)
#
#   make              everything
#   make hello        the overscan proof of concept
#   make loukoumas    ΛΟΥΚΟΥΜΑΣ title screen, English and Greek
#   make assets       regenerate the font, strings and sprites (needs python3)
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
LOUNGE_ROUTE := FIRE@22-26,RIGHT@45-83,LEFT@84-106,FIRE@107-109,LEFT@135-143,RIGHT@145-189,FIRE@160-162,FIRE@192-194,DOWN@196-221,FIRE@198-200,RIGHT@209-231,LEFT@234-293,FIRE@254-256,RIGHT@296-376,FIRE@320-322

RASM   ?= rasm
PYTHON ?= python3
BUILD  := build
DEPS   := $(wildcard src/*.asm)

# The tables are assembled once on their own, packed, and only then built into
# the game - so this list may not mention anything the packed copy depends on,
# or the build chases its own tail.
LOWDEPS := src/lowblock.asm src/config.asm src/font.asm src/strings.asm \
           src/sprites.asm src/artwork.asm src/enemykind.asm src/rooms.asm

.PHONY: all hello loukoumas assets check clean

all: hello loukoumas

# ---------------------------------------------------------------------------
# Generated sources. Committed, so building needs only rasm; python3 is needed
# when the font art or the string files change.
# ---------------------------------------------------------------------------
TEXTSRC := assets/font.txt text/loukoumas.en.txt text/loukoumas.el.txt tools/mktext.py

assets: src/font.asm src/strings.asm src/sprites.asm src/artwork.asm \
        src/titlepic.asm

src/font.asm src/strings.asm: $(TEXTSRC)
	$(PYTHON) tools/mktext.py loukoumas

src/sprites.asm: assets/sprites.txt tools/mksprite.py
	$(PYTHON) tools/mksprite.py

# The Aseprite artwork: enemies and the scenery that is not a rectangle.
src/artwork.asm: $(wildcard assets/art/sprite/*.png) $(wildcard assets/art/decal/*.png) tools/mkart.py
	$(PYTHON) tools/mkart.py

# The title screen: a whole overscan screen, quantised to the sixteen pens and
# packed to about seven kilobytes. Also writes build/title.bin, the same
# picture raw - 96 bytes by 272 scanlines - for anything that wants to load it
# straight into a screen. Needs Pillow, which is why the .asm is committed.
src/titlepic.asm build/title.bin: assets/art/title.jpg tools/mkscreen.py
	$(PYTHON) tools/mkscreen.py assets/art/title.jpg title

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

$(BUILD)/loukoumas_en.dsk: $(DEPS) | $(BUILD)
	rm -f $@
	$(RASM) src/loukoumas.asm -DTARGET=2 -DLANG=0 -eo

$(BUILD)/loukoumas_el.dsk: $(DEPS) | $(BUILD)
	rm -f $@
	$(RASM) src/loukoumas.asm -DTARGET=2 -DLANG=1 -eo \
		-s -sa -os $(BUILD)/loukoumas_el_dsk.sym

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
# Executes each build on a Z80 interpreter and decodes screen RAM through the
# CRTC addressing - a layout check that needs no emulator. It models no timing
# at all; see the header of tools/z80check.py for the rest of the caveats.
# ---------------------------------------------------------------------------
# `all` is a dependency on purpose: the snapshots and disc images are what
# anyone actually runs, and without this they can sit a conversion behind the
# sources while check goes on passing against freshly built .bin files.
check: all $(BUILD)/hello.bin $(BUILD)/loukoumas_en.bin $(BUILD)/loukoumas_el.bin \
       $(BUILD)/loukoumas_lounge.bin $(BUILD)/loukoumas_yard.bin \
       $(BUILD)/loukoumas_roof.bin $(BUILD)/loukoumas_title.bin \
       $(BUILD)/title.bin
	@echo "=== every room climbable, every sausage and every saucer reachable ==="
	@./tools/roomcheck.py $(BUILD)/loukoumas_el.bin $(BUILD)/loukoumas_el.sym \
		$(BUILD)/tables.bin
	@echo "=== hello world ==="
	@./tools/z80check.py $(BUILD)/hello.bin --ascii
	@echo "=== loukoumas, English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_en.bin --frames 30 --ascii
	@echo "=== loukoumas, Greek ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 30 --ascii
	@echo "=== loukoumas, Greek build with L held - must come out English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 34 --keys L --ascii | sed -n '1,2p;15,20p'
	@echo "=== loukoumas, play field after walking right ==="
	@echo "    every sausage must survive the cat walking over one"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 90 --keys FIRE,RIGHT --ascii | sed -n '1,2p;33,38p'
	@echo "=== loukoumas, physics: stand, jump, land on the shelf above ==="
	@echo "    50 on the floor at 212, 51 leaves at -1088, 67 apex at 173,"
	@echo "    75 landed on the rack's lower shelf at 180 and back in state 0"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 80 \
		--keys "FIRE@22-26,FIRE@50-53" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s" | grep -E "frame ( 50| 51| 67| 75)"
	@echo "=== loukoumas, belly-flop: terminal velocity, screen shake, stun ==="
	@echo "    61 commits at 1536 and curls up, 65 lands flat and sets the"
	@echo "    shake and the stun"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 80 \
		--keys "FIRE@22-26,FIRE@50-53,DOWN@55-99,FIRE@60-63" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s,cat_h,cat_stun,shake_timer" \
		| grep -E "frame ( 59| 61| 65| 67)"
	@echo "=== loukoumas, a robot costs a life and respawns the cat ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 200 \
		--keys "FIRE@22-26,RIGHT@40-200" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,cat_invul" | grep -E "frame (105|107)"
	@echo "=== loukoumas, clean run of the lounge and out through the vent ==="
	@echo "    a sausage at 82, 144, 226, 292 and 356, the saucer of milk at 188"
	@echo "    for a fourth life, then cur_room 8 -> 9 at 358 into the vent"
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 390 --keys "$(LOUNGE_ROUTE)" \
		--sym $(BUILD)/loukoumas_lounge.sym \
		--watch "cur_room,cat_lives,sausages_got,milk_alive,level_done" \
		| grep -E "frame ( 82|144|188|226|292|356|358)"
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
	@echo "    them may be caught."
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 250 \
		--keys FIRE@22-26 --sym $(BUILD)/loukoumas_lounge.sym \
		--beam --beam-from 20 | tail -1 | tee $(BUILD)/beam.txt
	@grep -q "^    0 of" $(BUILD)/beam.txt \
		|| (echo "    the beam caught the sprites - that is flicker" && false)
	@echo "=== loukoumas, a room is lit by one pen, and it is pen 0 ==="
	@echo "    the back yard must report pen0=23, sky blue; the rooftops pen0=20,"
	@echo "    black; every room in the flat is pen0=4, navy"
	@./tools/z80check.py $(BUILD)/loukoumas_yard.bin --frames 70 --keys FIRE@22-26 \
		| grep -o "pen0=[0-9]* " | sed 's/^/    back yard  /'
	@./tools/z80check.py $(BUILD)/loukoumas_roof.bin --frames 70 --keys FIRE@22-26 \
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
		$(BUILD)/tables.bin $(BUILD)/title.bin $(BUILD)/emu; \
		s=$$?; test $$s -eq 0 -o $$s -eq 2
	@echo "=== what you can actually run ==="
	@ls -l $(BUILD)/*.sna $(BUILD)/*.dsk | awk '{printf "    %-28s %8s bytes  %s %s %s\n", $$9, $$5, $$6, $$7, $$8}'

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin $(BUILD)/*.sym
