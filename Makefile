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

$(BUILD)/loukoumas_en.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=0 -ob $@

$(BUILD)/loukoumas_el.bin: $(DEPS) | $(BUILD)
	$(RASM) src/loukoumas.asm -DTARGET=3 -DLANG=1 -ob $@

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
	@echo "    all three sausages must survive the cat walking over one"
	@./tools/z80check.py $(BUILD)/loukoumas_el.bin --frames 60 --keys FIRE,RIGHT --ascii | sed -n '1,2p;33,38p'

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/*.sna $(BUILD)/*.dsk $(BUILD)/*.bin
