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
LOUNGE_ROUTE := FIRE@12-13,RIGHT@18-56,LEFT@57-79,FIRE@80-81,LEFT@108-116,RIGHT@118-162,FIRE@133-134,FIRE@165-166,DOWN@169-194,FIRE@171-172,RIGHT@182-204,LEFT@207-266,FIRE@227-228,RIGHT@269-349,FIRE@293-294

RASM   ?= rasm
PYTHON ?= python3
BUILD  := build
DEPS   := $(wildcard src/*.asm)

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
	$(RASM) src/loukoumas.asm -DTARGET=2 -DLANG=1 -eo

# The raw builds also emit a symbol file, which is what lets z80check watch
# named variables frame by frame - and, with -sa, lets roomcheck read the EQUs
# the room tables are built out of.
$(BUILD)/loukoumas_en.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=0 -ob $@ -s -sa -os $(BUILD)/loukoumas_en.sym

$(BUILD)/loukoumas_el.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -ob $@ -s -sa -os $(BUILD)/loukoumas_el.sym

# The living room is room 9 of 29, so the scripted run that tests it would
# otherwise have to play the eight rooms in front of it first. The back yard
# and the rooftops are there to prove a room is lit by its own palette: the
# first daylight room in the game and the first night one.
$(BUILD)/loukoumas_lounge.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=8 -ob $@ \
		-s -sa -os $(BUILD)/loukoumas_lounge.sym

$(BUILD)/loukoumas_yard.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=10 -ob $@ \
		-s -sa -os $(BUILD)/loukoumas_yard.sym

# The one build that keeps the title picture, so the picture gets checked too.
$(BUILD)/loukoumas_title.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=1 -ob $@

$(BUILD)/loukoumas_roof.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DTITLEPIC=0 -DLANG=1 -DSTARTROOM=27 -ob $@ \
		-s -sa -os $(BUILD)/loukoumas_roof.sym

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
	@./tools/roomcheck.py $(BUILD)/loukoumas_el.bin $(BUILD)/loukoumas_el.sym
	@echo "=== hello world ==="
	@./tools/z80check.py $(BUILD)/hello.bin --ascii
	@echo "=== loukoumas, English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_en.bin --frames 20 --ascii
	@echo "=== loukoumas, Greek ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 20 --ascii
	@echo "=== loukoumas, Greek build with L held - must come out English ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 24 --keys L --ascii | sed -n '1,2p;15,20p'
	@echo "=== loukoumas, play field after walking right ==="
	@echo "    every sausage must survive the cat walking over one"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 60 --keys FIRE,RIGHT --ascii | sed -n '1,2p;33,38p'
	@echo "=== loukoumas, physics: stand, jump, land on the shelf above ==="
	@echo "    24 on the floor at 212, 25 leaves at -1152, 43 apex at 173,"
	@echo "    50 landed on the rack's lower shelf at 180 and back in state 0"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 55 \
		--keys "FIRE@12-13,FIRE@24-25" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s" | grep -E "frame ( 24| 25| 43| 50)"
	@echo "=== loukoumas, belly-flop: terminal velocity, screen shake, stun ==="
	@echo "    35 commits at 1536, 39 lands flat and sets the shake and stun"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 50 \
		--keys "FIRE@12-13,FIRE@24-25,DOWN@29-50,FIRE@34-35" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s,cat_h,cat_stun,shake_timer" \
		| grep -E "frame ( 34| 35| 39| 40)"
	@echo "=== loukoumas, a robot costs a life and respawns the cat ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 120 \
		--keys "FIRE@12-13,RIGHT@14-120" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,cat_invul" | grep -E "frame ( 88| 89)"
	@echo "=== loukoumas, clean run of the lounge and out through the vent ==="
	@echo "    a sausage at 55, 115, 200, 262 and 330, the saucer of milk at 162"
	@echo "    for a fourth life, then cur_room 8 -> 9 at 332 into the vent"
	@./tools/z80check.py $(BUILD)/loukoumas_lounge.bin --frames 350 --keys "$(LOUNGE_ROUTE)" \
		--sym $(BUILD)/loukoumas_lounge.sym \
		--watch "cur_room,cat_lives,sausages_got,milk_alive,level_done" \
		| grep -E "frame ( 55|115|162|200|262|330|332)"
	@echo "=== loukoumas, a room is lit by one pen, and it is pen 0 ==="
	@echo "    the back yard must report pen0=23, sky blue; the rooftops pen0=20,"
	@echo "    black; every room in the flat is pen0=4, navy"
	@./tools/z80check.py $(BUILD)/loukoumas_yard.bin --frames 40 --keys FIRE@12-13 \
		| grep -o "pen0=[0-9]* " | sed 's/^/    back yard  /'
	@./tools/z80check.py $(BUILD)/loukoumas_roof.bin --frames 40 --keys FIRE@12-13 \
		| grep -o "pen0=[0-9]* " | sed 's/^/    rooftops   /'
	@echo "=== loukoumas, the title picture unpacked onto the overscan screen ==="
	@echo "    26,112 bytes of screen, packed to about seven and unpacked by the"
	@echo "    Z80 itself. Every byte of it outside the two text panels has to"
	@echo "    come back identical to the picture tools/mkscreen.py made."
	@./tools/z80check.py $(BUILD)/loukoumas_title.bin --frames 95 \
		--dump $(BUILD)/title-screen.bin | tail -1
	@cmp -i 5184 -n 18240 $(BUILD)/title-screen.bin $(BUILD)/title.bin \
		&& echo "    the picture came back byte for byte"
	@echo "=== what you can actually run ==="
	@ls -l $(BUILD)/*.sna $(BUILD)/*.dsk | awk '{printf "    %-28s %8s bytes  %s %s %s\n", $$9, $$5, $$6, $$7, $$8}'

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin $(BUILD)/*.sym
