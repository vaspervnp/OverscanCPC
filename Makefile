# OverscanCPC - build with rasm (https://github.com/EdouardBERGE/rasm)
#
#   make          snapshot + disc image
#   make sna      build/hello.sna   - drag into an emulator
#   make dsk      build/hello.dsk   - then RUN"HELLO
#   make bin      build/hello.bin   - raw binary, loads at #4000
#   make check    run it on a Z80 interpreter and decode the screen
#   make clean

RASM  ?= rasm
SRC   := src/main.asm
DEPS  := $(wildcard src/*.asm)
BUILD := build

.PHONY: all sna dsk bin check clean

all: sna dsk

sna: $(BUILD)/hello.sna
dsk: $(BUILD)/hello.dsk
bin: $(BUILD)/hello.bin

# TARGET=1 wraps the code in a 128K snapshot with PC at the entry point.
$(BUILD)/hello.sna: $(DEPS) | $(BUILD)
	$(RASM) $(SRC) -DTARGET=1 -oi $@

# TARGET=2 emits an AMSDOS binary inside a DATA-format disc image.
# The image path lives in the SAVE directive at the end of src/main.asm, so
# this has to run from the project root.
$(BUILD)/hello.dsk: $(DEPS) | $(BUILD)
	rm -f $@
	$(RASM) $(SRC) -DTARGET=2 -eo

# TARGET=3 is a headerless dump of the assembled code, handy for tooling.
$(BUILD)/hello.bin: $(DEPS) | $(BUILD)
	$(RASM) $(SRC) -DTARGET=3 -ob $@

# Executes the code on a Z80 interpreter and decodes screen RAM through the
# CRTC addressing - checks the layout without an emulator. It models no timing
# at all; see the header of tools/z80check.py for the rest of the caveats.
check: $(BUILD)/hello.bin
	./tools/z80check.py $< --ascii

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -f $(BUILD)/hello.sna $(BUILD)/hello.dsk $(BUILD)/hello.bin
