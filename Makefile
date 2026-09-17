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

# A clean playthrough with the enemies in place: all five sausages, no lives
# lost. It has to belly-flop to get past the robot patrolling shelf 2, so it
# tests that mechanic as well as the physics, and it is the level design's own
# test - change a shelf, the jump height or an enemy's patrol and it stops
# passing.
ROUTE  := FIRE@12-13,RIGHT@14-52,LEFT@53-75,FIRE@76-77,LEFT@104-112,RIGHT@114-158,FIRE@129-130,FIRE@161-162,DOWN@165-190,FIRE@167-168,RIGHT@178-200,LEFT@203-262,FIRE@223-224,RIGHT@265-345,FIRE@285-286

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
TEXTSRC := assets/font8.txt text/loukoumas.en.txt text/loukoumas.el.txt tools/mktext.py

assets: src/font.asm src/strings.asm src/sprites.asm

src/font.asm src/strings.asm: $(TEXTSRC)
	$(PYTHON) tools/mktext.py loukoumas

src/sprites.asm: assets/sprites.txt tools/mksprite.py
	$(PYTHON) tools/mksprite.py

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
# named variables frame by frame.
$(BUILD)/loukoumas_en.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=0 -ob $@ -s -sl -os $(BUILD)/loukoumas_en.sym

$(BUILD)/loukoumas_el.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=1 -ob $@ -s -sl -os $(BUILD)/loukoumas_el.sym

# ---------------------------------------------------------------------------
# Executes each build on a Z80 interpreter and decodes screen RAM through the
# CRTC addressing - a layout check that needs no emulator. It models no timing
# at all; see the header of tools/z80check.py for the rest of the caveats.
# ---------------------------------------------------------------------------
check: $(BUILD)/hello.bin $(BUILD)/loukoumas_en.bin $(BUILD)/loukoumas_el.bin
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
	@echo "    20 on the floor at 212, 21 leaves at -1152, 39 apex near 173,"
	@echo "    46 landed on the shelf at 180 and back in state 0"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 50 \
		--keys "FIRE@12-13,FIRE@20-21" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s" | grep -E "frame ( 20| 21| 39| 46)"
	@echo "=== loukoumas, belly-flop: terminal velocity, screen shake, stun ==="
	@echo "    31 commits at 1536, 35 lands flat and sets the shake and stun"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 40 \
		--keys "FIRE@12-13,FIRE@20-21,DOWN@25-40,FIRE@30-31" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_y,cat_state,cat_vy:s,cat_h,cat_stun,shake_timer" \
		| grep -E "frame ( 30| 31| 35| 36)"
	@echo "=== loukoumas, a robot costs a life and respawns the cat ==="
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 120 \
		--keys "FIRE@12-13,RIGHT@14-120" --sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,cat_invul" | grep -E "frame ( 79| 80)"
	@echo "=== loukoumas, clean run of the lounge and out through the vent ==="
	@echo "    a sausage at 52, 109, 197, 256 and 327, never below three lives,"
	@echo "    then cur_room 0 -> 1 at 330 as the cat steps into the vent"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 340 --keys "$(ROUTE)" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cur_room,cat_lives,sausages_got,level_done" \
		| grep -E "frame ( 52|109|172|197|256|327|330)"

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin $(BUILD)/*.sym
