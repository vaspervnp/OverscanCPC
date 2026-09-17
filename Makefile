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

# Scripted play. FLOP clears the shelf 2 robot with a belly-flop and takes the
# sausage it was guarding; it is the level design's test as much as the code's.
# Adding enemies made the old five-sausage route die, so completing the level
# is no longer scripted - see the note in README.
FLOP   := FIRE@12-13,FIRE@16-17,RIGHT@114-165,FIRE@136-137,FIRE@168-169,DOWN@172-195,FIRE@174-175,RIGHT@185-230

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
		--watch "cat_x,cat_lives,cat_invul" | grep -E "frame ( 77| 78)"
	@echo "=== loukoumas, belly-flop stuns the shelf robot and clears its sausage ==="
	@echo "    178 the flop lands and the robot freezes, 206 the sausage is taken,"
	@echo "    and all three lives survive walking straight through it"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 240 --keys "$(FLOP)" \
		--sym $(BUILD)/loukoumas_el.sym \
		--watch "cat_x,cat_lives,sausages_got,enemies+15,enemies+22" \
		| grep -E "frame (177|178|205|206|229)"

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin $(BUILD)/*.sym
