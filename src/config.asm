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
CRTC_R1     EQU 48          ; horizontal displayed - 48 chars = 96 bytes = 192 px (mode 0)
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

;; --- Mode 0 solid-pen bytes ------------------------------------------------
;; Mode 0 packs 2 pixels per byte and spreads each pixel's four pen bits right
;; across it: pixel 0 takes bits 7,3,5,1 and pixel 1 bits 6,2,4,0, least
;; significant first. A byte with both pixels set to the same pen is therefore
;; pen bit 0 -> #C0, bit 1 -> #0C, bit 2 -> #30, bit 3 -> #03, ORed together.
;;
;; There is no arithmetic shortcut here the way mode 1 had one, so the sixteen
;; values are simply written out and everything that fills a rectangle picks
;; one by pen number.
PEN0_BYTE       EQU #00
PEN1_BYTE       EQU #C0
PEN2_BYTE       EQU #0C
PEN3_BYTE       EQU #CC
PEN4_BYTE       EQU #30
PEN5_BYTE       EQU #F0
PEN6_BYTE       EQU #3C
PEN7_BYTE       EQU #FC
PEN8_BYTE       EQU #03
PEN9_BYTE       EQU #C3
PEN10_BYTE      EQU #0F
PEN11_BYTE      EQU #CF
PEN12_BYTE      EQU #33
PEN13_BYTE      EQU #F3
PEN14_BYTE      EQU #3F
PEN15_BYTE      EQU #FF

;; Mode 0 halves the horizontal resolution: 96 bytes is 192 pixels, not 384.
;; Each is twice as wide, so nothing changes size on the monitor - only how
;; finely it can be drawn. Everything laid out in bytes (the rooms, the
;; furniture, every collision box) is untouched by the change; only the font
;; and the sprites, which are drawn inside a byte, had to be redrawn.
PIXELS_PER_BYTE EQU 2
SCREEN_PIXELS   EQU BYTES_PER_LINE*PIXELS_PER_BYTE

;; --- Level geometry --------------------------------------------------------
;; Shared by the room tables and the playing code, so it lives here rather
;; than in either of them.
PLAY_TOP        EQU 20                  ; below the two-row HUD strip
FLOOR_Y         EQU 236
FLOOR_H         EQU DISPLAY_LINES-FLOOR_Y
SHELF_H         EQU 4

;; --- Text ------------------------------------------------------------------
;; Glyphs are 8x8 cells drawn 6 wide and 7 tall, so the spare column and row
;; are the letter spacing and text advances a whole cell.
;;
;; Small text is 1:1 - one cell is 6 mode 0 pixels, which is 3 bytes, so it
;; stays byte aligned and needs no shifting. That is 32 characters across the
;; screen rather than the 48 a mode 1 cell gave, which is why the HUD is two
;; rows. Big text scales a source pixel to (txt_xs) whole bytes across and
;; (txt_ys) scanlines down:
;;   txt_xs = 1 -> 24 px per letter,  txt_xs = 2 -> 48 px per letter.
SMALL_W_BYTES   EQU 3                   ; 6 mode 0 pixels
GLYPH_MAX_BYTES EQU 24                  ; widest expanded row: 6 px * 4 bytes

;; Centring: x = (BYTES_PER_LINE - len*width) / 2, which for these two widths
;; is 48 - len and 48 - len*4.
CENTRE_HALF     EQU BYTES_PER_LINE/2    ; 48

STACK_TOP       EQU #7FFE   ; safely below the screen at #8000

;; --- What a room is lit by --------------------------------------------------
;; A room's palette is one byte: the hardware colour pen 0 and the border are
;; set to. Everything else keeps its meaning in every room - the cat is butter
;; yellow whatever is behind it - so the whole of a room's light is the colour
;; of the empty space in it, which is exactly what changes between a wall at
;; three in the morning, a school playground at nine, and a roof at midnight.
PAL_INDOOR      EQU 4       ; deep navy - a wall, or a garden before dawn
PAL_DAY         EQU 23      ; sky blue
PAL_NIGHT       EQU 20      ; black - the rooftops, at the end of it all

;; --- Where the level data lives --------------------------------------------
;; The screen is 32 KB at #8000-#FFFF and the code has to load somewhere the
;; lower ROM is not, which leaves #4000-#7FFF - sixteen kilobytes for the
;; engine, the font, the sprites, the furniture and twenty-nine rooms. That is
;; not enough, and #0000-#3FFF is sixteen more that nothing is using: with
;; both ROMs disabled it is plain RAM, and the only thing in it is the
;; interrupt jump at #0038.
;;
;; It cannot be *loaded* there - AMSDOS hands control over with the lower ROM
;; still enabled, so a program at #0100 would never execute - but it can be
;; loaded high and copied down. The tables are assembled to run at DATA_ORG
;; and stored at DATA_STORE, which is inside the file; the first thing the
;; game does after turning the ROMs off is move them. Nothing in the low block
;; is ever executed, only read, so it never has to be there before then.
DATA_ORG        EQU #0100   ; clear of the #0038 interrupt jump
DATA_STORE      EQU #7480   ; where the file carries it, until it is moved

;; The title screen is a picture of the whole overscan window: 96 bytes by 272
;; scanlines, 26,112 of them, and there is nowhere in this machine to keep
;; that. Packed it is about seven kilobytes, and unlike the tables it has to
;; stay where it is - the title is redrawn every time the player comes back to
;; it - so it sits between the workspace and the travelling copy of the tables
;; and is never moved. See tools/mkscreen.py and src/unpack.asm.
PIC_STORE       EQU #5800

;; Where the pickups keep the background they are standing on. Low RAM, above
;; the tables the game moved down there and below #4000: it is uninitialised,
;; so unlike anything declared in the #4000 block it costs nothing at all in
;; the file. See draw_sausages.
PICK_BUFS       EQU #3800

;; ---------------------------------------------------------------------------
;; Which room the game starts in. Always 0 in a build anyone plays; make check
;; passes -DSTARTROOM=n so a scripted run can be aimed at one room without
;; having to play through the nine in front of it.
;; ---------------------------------------------------------------------------
IFNDEF STARTROOM
STARTROOM   EQU 0
ENDIF

;; ---------------------------------------------------------------------------
;; Whether the title screen unpacks its picture. Always 1 in a build anyone
;; plays. The scripted runs in make check pass -DTITLEPIC=0, because unpacking
;; 26 KB takes about a second and a half and every frame number they pin would
;; otherwise be eighty frames later than it is. They are testing the game, not
;; the curtain; the curtain has a check of its own.
;; ---------------------------------------------------------------------------
IFNDEF TITLEPIC
TITLEPIC    EQU 1
ENDIF
