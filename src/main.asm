;; ===========================================================================
;; OverscanCPC - "HELLO WORLD" in a 384x272 full-overscan screen.
;;
;; Amstrad CPC 6128, mode 1, 32 KB screen at #8000-#FFFF, no firmware.
;; The letters are deliberately drawn past the edges of the area a normal
;; 40x25 screen covers - that area is painted black, everything around it is
;; blue, and all the blue used to be border.
;;
;; Build with TARGET=1 for a snapshot, 2 for a DSK, 3 for a raw binary.
;; See the Makefile.
;; ===========================================================================

    include "config.asm"

    IF TARGET==1
BUILDSNA
BANKSET 0
    ENDIF

    ORG #4000               ; RAM whatever the ROM configuration is, and clear
                            ; of the screen at #8000

;; ---------------------------------------------------------------------------
;; Entry point.
;; ---------------------------------------------------------------------------
main_start
    di                      ; the firmware's interrupt handler is about to go
    ld sp,STACK_TOP

    ld bc,#7F8D             ; Gate Array: mode 1, upper and lower ROM disabled
    out (c),c

    ld hl,pal_blank         ; everything black while we build the screen, so
    call set_pal            ; the firmware screen does not visibly fill with junk

    call build_line_tab
    call fill_screen
    call draw_all_text

    call setup_crtc         ; only now switch the display over to overscan
    ld hl,pal_main
    call set_pal

main_halt
    jr main_halt            ; interrupts are off; nothing else to do

    include "crtc.asm"
    include "video.asm"
    include "text.asm"
    include "font.asm"

code_end

;; ---------------------------------------------------------------------------
;; Workspace. Built at run time, so it lives past code_end and is not saved.
;; ---------------------------------------------------------------------------
line_tab    defs DISPLAY_LINES*2    ; 272 scanline addresses
dg_pat      defs GLYPH_W_BYTES      ; one expanded glyph row
dg_x        defs 1                  ; current x, in bytes
dg_row      defs 2                  ; line_tab pointer for the current text row
fill_x      defs 1
fill_w      defs 2
fill_b      defs 1
workspace_end

    IF TARGET==1
RUN main_start
    ENDIF

    IF TARGET==2
    SAVE "HELLO.BIN",main_start,code_end-main_start,DSK,"build/hello.dsk"
    ENDIF
