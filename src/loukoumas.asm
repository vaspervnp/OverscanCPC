;; ===========================================================================
;; ΛΟΥΚΟΥΜΑΣ / LOUKOUMAS - title screen, 384x272 full overscan, mode 1.
;;
;; Both languages live in the same binary: tools/mktext.py builds a string
;; table per language from text/loukoumas.*.txt and every line drawn here goes
;; through a message id, never a literal. LANG picks which table txt_lang
;; starts on, so switching language at run time is one byte.
;;
;; Build with TARGET=1 snapshot, 2 DSK, 3 raw binary; LANG=0 English, 1 Greek.
;; ===========================================================================

    include "config.asm"

    IF TARGET==1
BUILDSNA
BANKSET 0
    ENDIF

TITLE_YS        EQU 6           ; big text: 8 source rows * 6 = 48 px tall
BAND_H          EQU 12          ; the coral bands top and bottom

Y_LANGNAME      EQU 2           ; inside the top band
Y_TITLE         EQU 60
Y_SUBTITLE      EQU 120
Y_PRESS         EQU 180
Y_LANGHINT      EQU DISPLAY_LINES-BAND_H+2

    ORG #4000

;; ---------------------------------------------------------------------------
loukoumas_start
    di
    ld sp,STACK_TOP

    ld bc,#7F8D                 ; mode 1, both ROMs disabled
    out (c),c

    ld hl,pal_blank             ; build the screen unseen
    call set_pal

    ld a,LANG
    ld (txt_lang),a

    call build_line_tab
    call draw_title

    call setup_crtc             ; now switch the display to overscan
    ld hl,pal_loukoumas
    call set_pal

loukoumas_halt
    jr loukoumas_halt

;; ---------------------------------------------------------------------------
;; draw_title - navy background, a coral band across the top and bottom of the
;; overscan area, and five lines of text.
;;
;; The bands sit at the very edges of the 384x272 window, well outside the
;; 320x200 a stock CPC would show, so they only exist because of the overscan.
;; Text crossing them comes out white rather than yellow for free - see the
;; note about OR blending at the top of text.asm.
;; ---------------------------------------------------------------------------
draw_title
    xor a
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl

    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab
    ld de,DISPLAY_LINES
    call fill_rows

    ld a,PEN2_BYTE
    ld (fill_b),a
    ld hl,line_tab
    ld de,BAND_H
    call fill_rows

    ld a,PEN2_BYTE
    ld (fill_b),a
    ld hl,line_tab+(DISPLAY_LINES-BAND_H)*2
    ld de,BAND_H
    call fill_rows

    ld hl,line_tab+Y_LANGNAME*2
    ld (txt_row),hl
    ld a,MSG_LANGNAME
    call msg_small_centre

    ld a,1                      ; 1 byte per source pixel = 32 px per letter
    ld (txt_xs),a
    ld a,TITLE_YS
    ld (txt_ys),a
    ld hl,line_tab+Y_TITLE*2
    ld (txt_row),hl
    ld a,MSG_TITLE1
    call msg_big_centre

    ld hl,line_tab+Y_SUBTITLE*2
    ld (txt_row),hl
    ld a,MSG_TITLE2
    call msg_small_centre

    ld hl,line_tab+Y_PRESS*2
    ld (txt_row),hl
    ld a,MSG_PRESS
    call msg_small_centre

    ld hl,line_tab+Y_LANGHINT*2
    ld (txt_row),hl
    ld a,MSG_LANGHINT
    jp msg_small_centre

;; ---------------------------------------------------------------------------
;; Palette.
;;
;; The four colours are the ones loukoumas.md asks for, but the ink order is
;; not the document's. A glyph pixel only ever sets pen bit 0, so text lands on
;; pen 1 over the background and pen 3 over a band - the inks are assigned to
;; put a readable colour on each of those, which the document's order would
;; not (it would leave white text on bright yellow).
;;
;; The document's own Gate Array values are also not the colours it names:
;; &54 is hardware 20, black, not deep navy, and &5C is hardware 28, dark red,
;; not coral. These are the named colours.
;; ---------------------------------------------------------------------------
pal_loukoumas
    defb 0,   #40+4             ; pen 0 - deep navy, background
    defb 1,   #40+10            ; pen 1 - butter yellow, text on the background
    defb 2,   #40+7             ; pen 2 - coral, the overscan bands
    defb 3,   #40+11            ; pen 3 - white, text crossing a band
    defb #10, #40+4             ; border - navy, blends into the picture
    defb #FF

    include "crtc.asm"
    include "video.asm"
    include "text.asm"
    include "font.asm"
    include "strings.asm"

code_end

    include "workspace.asm"

    IF TARGET==1
RUN loukoumas_start
    ENDIF

    IF TARGET==2
      IF LANG==0
    SAVE "LOUK.BIN",loukoumas_start,code_end-loukoumas_start,DSK,"build/loukoumas_en.dsk"
      ENDIF
      IF LANG==1
    SAVE "LOUK.BIN",loukoumas_start,code_end-loukoumas_start,DSK,"build/loukoumas_el.dsk"
      ENDIF
    ENDIF
