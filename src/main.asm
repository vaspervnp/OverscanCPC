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

HELLO_XS        EQU 2       ; 2 bytes per source pixel = 64 px per letter
HELLO_YS        EQU 12      ; 8 source rows * 12 = 96 px tall
TEXT1_Y         EQU 8       ; HELLO!: starts 24 lines above the normal screen
TEXT2_Y         EQU 168     ; WORLD!: ends 32 lines below it

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

;; ---------------------------------------------------------------------------
;; Six cells at 64 px each is exactly 384, so these two lines span the whole
;; overscan window and cross the left and right edges of the normal screen as
;; well as the top and bottom.
;; ---------------------------------------------------------------------------
draw_all_text
    ld a,HELLO_XS
    ld (txt_xs),a
    ld a,HELLO_YS
    ld (txt_ys),a

    ld hl,line_tab+TEXT1_Y*2
    ld (txt_row),hl
    ld hl,txt_hello
    call big_centre

    ld hl,line_tab+TEXT2_Y*2
    ld (txt_row),hl
    ld hl,txt_world
    jp big_centre

txt_hello   defb 6,GL_H,GL_E,GL_L,GL_L,GL_O,GL_BANG
txt_world   defb 6,GL_W,GL_O,GL_R,GL_L,GL_D,GL_BANG

    include "crtc.asm"
    include "video.asm"
    include "text.asm"
    include "font.asm"
    include "strings.asm"

code_end

    include "workspace.asm"

    IF TARGET==1
RUN main_start
    ENDIF

    IF TARGET==2
    SAVE "HELLO.BIN",main_start,code_end-main_start,DSK,"build/hello.dsk"
    ENDIF
