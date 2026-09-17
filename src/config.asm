;; ===========================================================================
;; config.asm - overscan geometry, derived from the CRTC register values.
;;
;; Everything else in the project derives its addresses from these constants.
;; Change a register here and the line table, the fills and the text placement
;; all follow.
;; ===========================================================================

;; --- CRTC register values --------------------------------------------------
;; R0 and the frame total are fixed: 64 us lines, 312 lines per frame, 50 Hz.
;; R1/R6 set the size of the displayed window, R2/R7 where it sits on the tube.

CRTC_R0     EQU 63          ; horizontal total - 64 chars = 64 us. Never change.
CRTC_R1     EQU 48          ; horizontal displayed - 48 chars = 96 bytes = 384 px (mode 1)
CRTC_R2     EQU 50          ; HSYNC position - re-centres the wider window
CRTC_R3     EQU #8E         ; sync widths: HSYNC 14 chars, VSYNC 8 lines
CRTC_R4     EQU 38          ; vertical total - 39 rows
CRTC_R5     EQU 0           ; vertical total adjust
CRTC_R6     EQU 34          ; vertical displayed - 34 rows = 272 lines
CRTC_R7     EQU 34          ; VSYNC position - vertical centring knob
CRTC_R8     EQU 0           ; non-interlaced
CRTC_R9     EQU 7           ; 8 scanlines per character row
CRTC_R12    EQU #2C         ; display start high - MA = #2C10
CRTC_R13    EQU #10         ; display start low

;; (R4+1)*(R9+1)+R5 = 39*8 = 312 scanlines = 19.968 ms = 50.08 Hz
FRAME_LINES EQU (CRTC_R4+1)*(CRTC_R9+1)+CRTC_R5

;; --- Screen geometry -------------------------------------------------------
BYTES_PER_LINE  EQU CRTC_R1*2           ; 96
DISPLAY_ROWS    EQU CRTC_R6             ; 34 character rows
DISPLAY_LINES   EQU DISPLAY_ROWS*8      ; 272 scanlines

;; MA starts at #2C10:
;;   page 2 (#8000), character offset 16 -> byte offset 32 in each 2K slice.
;; Rows 0..20 are 21*48 = 1008 characters and run from offset 16 to 1023,
;; exactly filling the 1024-character window of page 2. Row 21 begins at
;; MA #3000, which flips MA12 and moves the fetch into page 3 (#C000) with
;; the character offset back at 0. That is what buys us a 32 KB screen with
;; no rupture: see CLAUDE.md section 2.
PAGE2_ROWS      EQU 21
PAGE2_BASE      EQU #8000+32
PAGE3_BASE      EQU #C000

;; --- Where the *normal* 320x200 screen would sit inside our window ---------
;; Horizontally the picture is positioned relative to HSYNC, so moving R2 from
;; the firmware's 46 to 50 buys 4 characters (32 pixels) on each side.
;; Vertically the monitor locks to VSYNC: the firmware leaves 312-30*8 = 72
;; lines between VSYNC and row 0, we leave 312-34*8 = 40, so our picture starts
;; 32 lines earlier.
STD_R2          EQU 46
STD_R7          EQU 30

INNER_X0        EQU (CRTC_R2-STD_R2)*2  ; 8 bytes  = 32 px
INNER_W         EQU 80                  ; 320 px
INNER_Y0        EQU (CRTC_R7-STD_R7)*8  ; 32 lines
INNER_H         EQU 200

;; --- Mode 1 solid-pen bytes ------------------------------------------------
;; Mode 1 packs 4 pixels per byte: pen bit 0 from bits 7..4, bit 1 from 3..0.
PEN0_BYTE       EQU #00
PEN1_BYTE       EQU #F0
PEN2_BYTE       EQU #0F
PEN3_BYTE       EQU #FF

;; --- Text layout -----------------------------------------------------------
;; 8x8 glyphs blown up 8x horizontally (1 source pixel = 2 bytes) and 12x
;; vertically, so each letter is 64x96 pixels.
SCALE_Y         EQU 12
GLYPH_W_BYTES   EQU 16                          ; 8 source px * 8 = 64 px
GLYPH_GAP       EQU 2                           ; 8 px between letters
GLYPH_ADV       EQU GLYPH_W_BYTES+GLYPH_GAP     ; 18 bytes = 72 px

;; 5 letters = 4*18+16 = 88 bytes, centred in 96 -> 4 bytes (16 px) each side.
TEXT_X          EQU 4
TEXT1_Y         EQU 8       ; HELLO: 24 lines above the normal screen top
TEXT2_Y         EQU 168     ; WORLD: ends 32 lines below the normal screen bottom

STACK_TOP       EQU #7FFE   ; safely below the screen at #8000
