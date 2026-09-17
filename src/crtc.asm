;; ===========================================================================
;; crtc.asm - CRTC 6845 and Gate Array programming.
;;
;; Verified on: no emulator or hardware yet. The memory layout these values
;; imply has been checked against a software model of the CRTC fetch, but the
;; picture position has not - R2 (horizontal centring) and R7 (vertical
;; centring) are the knobs to tune against a real monitor. See CLAUDE.md
;; section 3.
;; CRTC type: uses nothing type-specific - plain register writes outside the
;; display, no mid-frame reprogramming. Should behave identically on types 0-4.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; setup_crtc - write the overscan register set.
;; Port #BCxx selects a register, #BDxx writes its value.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
setup_crtc
    ld hl,crtc_data
setup_crtc_loop
    ld a,(hl)
    inc hl
    cp #FF                  ; end of table
    ret z
    ld c,a
    ld b,#BC                ; select register C
    out (c),c
    ld c,(hl)
    inc hl
    ld b,#BD                ; write the value
    out (c),c
    jr setup_crtc_loop

crtc_data
    defb 0,  CRTC_R0        ; horizontal total
    defb 1,  CRTC_R1        ; horizontal displayed
    defb 2,  CRTC_R2        ; HSYNC position
    defb 3,  CRTC_R3        ; sync widths
    defb 4,  CRTC_R4        ; vertical total
    defb 5,  CRTC_R5        ; vertical total adjust
    defb 6,  CRTC_R6        ; vertical displayed
    defb 7,  CRTC_R7        ; VSYNC position
    defb 8,  CRTC_R8        ; interlace / skew
    defb 9,  CRTC_R9        ; max raster address
    defb 12, CRTC_R12       ; display start address high
    defb 13, CRTC_R13       ; display start address low
    defb #FF

;; ---------------------------------------------------------------------------
;; set_pal - write a palette table through the Gate Array at port #7Fxx.
;; Each entry is a pen selector (0-15, or #10 for the border) followed by
;; #40 + hardware colour. Table ends with #FF.
;; HL = table. Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
set_pal
    ld bc,#7F00
set_pal_loop
    ld a,(hl)
    inc hl
    cp #FF
    ret z
    out (c),a               ; select pen
    ld a,(hl)
    inc hl
    out (c),a               ; set its colour
    jr set_pal_loop

;; Hardware colour numbers (not firmware INK numbers):
;;   20 black, 4 blue, 10 bright yellow, 11 bright white
pal_blank
    defb 0,   #40+20
    defb 1,   #40+20
    defb 2,   #40+20
    defb 3,   #40+20
    defb #10, #40+20
    defb #FF

pal_main
    defb 0,   #40+20        ; pen 0 - black, inside the normal 320x200 area
    defb 1,   #40+10        ; pen 1 - bright yellow, the letters
    defb 2,   #40+4         ; pen 2 - blue, the overscan region
    defb 3,   #40+11        ; pen 3 - bright white, the letters where they
                            ;         cross out into the overscan region
    defb #10, #40+20        ; border - black, so what little is left shows up
    defb #FF

;; ---------------------------------------------------------------------------
;; crtc_set - write one register. A = register number, E = value.
;; Destroys AF, BC.
;; ---------------------------------------------------------------------------
crtc_set
    ld b,#BC
    ld c,a
    out (c),c
    ld b,#BD
    ld c,e
    out (c),c
    ret
