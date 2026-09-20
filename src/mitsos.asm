;; ===========================================================================
;; ΠΑΝΙΚΟΣ ΣΤΟ ΠΑΝΤΟΠΩΛΕΙΟ - MITSOS: THE GROCERY HEIST
;;
;; Amstrad CPC 6128, mode 1, 384x272 full overscan, no firmware.
;;
;; The first milestone, and it shows one thing: the same 32 KB overscan screen
;; the engine already drives, in mode 1 this time - four pens and 384 square
;; pixels across instead of sixteen pens and 192 wide ones - with the shop
;; floor painted on it and Mitsos walking along it.
;;
;; Everything under it is the engine as it stands: crtc.asm puts the picture
;; up, video.asm builds the line table and fills the rectangles, irq.asm keeps
;; the 50 Hz tick, keys.asm reads the matrix, and sprite.asm lifts Mitsos off
;; the background and puts him back. None of them needed changing for mode 1,
;; because every one of them works in bytes and a byte is a byte; only
;; config.asm, which says what a byte of a given pen looks like, has a second
;; half now.
;;
;; Build with TARGET=1 for a snapshot, 2 for a DSK, 3 for a raw binary.
;; See the Makefile.
;; ===========================================================================

    include "config.asm"

    IF TARGET==1
BUILDSNA
BANKSET 0
    ENDIF

;; --- The shop --------------------------------------------------------------
;; Scanlines, top of the screen down. The floor is the glossy tiling the
;; story is so pleased with; the shelves are what the fish is on.
FLOOR_TOP       EQU 240
FLOOR_EDGE      EQU 3                   ; white highlight along the top of it
SHELF_T         EQU 4                   ; how thick a shelf is drawn
SHELF1_Y        EQU 176
SHELF2_Y        EQU 112
SHELF3_Y        EQU 48

;; --- Mitsos ----------------------------------------------------------------
;; He is 24 pixels square, which in mode 1 is six bytes across, and he steps
;; a whole byte at a time - four pixels, half of what a mode 0 step moved,
;; because a mode 1 byte is half as wide.
MITSOS_W        EQU SPR_MITSOS_STAND_W
MITSOS_H        EQU SPR_MITSOS_STAND_H
MITSOS_Y        EQU FLOOR_TOP-MITSOS_H  ; standing on the floor
MITSOS_XMAX     EQU BYTES_PER_LINE-MITSOS_W
MITSOS_BYTES    EQU MITSOS_W*MITSOS_H
WALK_TICKS      EQU 5                   ; frames between the two walk frames

FACE_RIGHT      EQU 0
FACE_LEFT       EQU 1

    ORG #4000                           ; RAM whatever the ROMs are doing, and
                                        ; clear of the screen at #8000
;; ---------------------------------------------------------------------------
;; Entry point.
;; ---------------------------------------------------------------------------
mitsos_start
    di                                  ; the firmware's handler is about to go
    ld sp,STACK_TOP

    ld bc,#7F00+GA_MODE                 ; mode 1, upper and lower ROM disabled
    out (c),c

    ld hl,pal_blank                     ; build the screen unseen, so none of
    call set_pal                        ; the firmware's leftovers show

    call build_line_tab
    call draw_shop

    call setup_crtc                     ; only now switch the display over
    ld hl,pal_shop
    call set_pal

    call irq_init                       ; and the 50 Hz tick under everything

;; Mitsos starts halfway along the floor, facing right and standing still.
    ld a,MITSOS_XMAX/2
    ld (mitsos_x),a
    ld (mitsos_ox),a
    xor a
    ld (mitsos_face),a
    ld (mitsos_tick),a
    ld (mitsos_frame),a
    call mitsos_draw

;; ---------------------------------------------------------------------------
;; One pass per 50 Hz frame: read the keys, move him, lift him off the floor
;; and put him back down where he now is.
;; ---------------------------------------------------------------------------
main_loop
    call wait_frame                     ; irq.asm's, off the 50 Hz tick
    call read_controls                  ; the matrix, folded into ctl_now
    call mitsos_move
    ld a,(mitsos_redraw)                ; standing still costs nothing: what is
    or a                                ; on the screen is already right
    jr z,main_loop
    call mitsos_erase
    call mitsos_draw
    jr main_loop

;; ---------------------------------------------------------------------------
;; mitsos_move - left and right walk him along the floor, a byte a frame.
;;
;; Nothing here knows about the animation beyond which way he is going: the
;; walk counter runs while he is moving and stops when he is not, and the
;; frame it picks is the only thing mitsos_draw looks at.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
mitsos_move
    ld a,(mitsos_x)
    ld (mitsos_ox),a                    ; where he is about to stop being
    ld b,a
    xor a
    ld (mitsos_redraw),a

    ld a,(ctl_now)
    bit CTL_LEFT,a
    jr nz,mitsos_move_left
    bit CTL_RIGHT,a
    jr nz,mitsos_move_right

    ld a,(mitsos_frame)                 ; standing still: legs together, and
    or a                                ; the counter back to the top so the
    ret z                               ; first step out is always the same one
    xor a
    ld (mitsos_tick),a
    ld (mitsos_frame),a
    jr mitsos_move_again

mitsos_move_left
    ld a,FACE_LEFT
    ld (mitsos_face),a
    ld a,b
    or a
    jr z,mitsos_step                    ; already against the left wall
    dec b
    jr mitsos_step

mitsos_move_right
    xor a
    ld (mitsos_face),a
    ld a,b
    cp MITSOS_XMAX
    jr nc,mitsos_step
    inc b

;; Walking: keep the new x, and step the two-frame waddle every WALK_TICKS.
;; Either way he has moved, so the picture has to be rebuilt.
mitsos_step
    ld a,b
    ld (mitsos_x),a

    ld hl,mitsos_tick
    inc (hl)
    ld a,(hl)
    cp WALK_TICKS
    jr c,mitsos_move_again
    ld (hl),0
    ld a,(mitsos_frame)                 ; 0 or 2 -> 1, and 1 -> 2
    cp 1
    ld a,2
    jr z,mitsos_move_set
    ld a,1
mitsos_move_set
    ld (mitsos_frame),a

mitsos_move_again
    ld a,1
    ld (mitsos_redraw),a
    ret

;; ---------------------------------------------------------------------------
;; mitsos_erase - put the floor back where he was standing.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
mitsos_erase
    ld a,MITSOS_W
    ld (spr_w),a
    ld a,MITSOS_H
    ld (spr_h),a
    ld a,(mitsos_ox)
    ld (spr_x),a
    ld a,MITSOS_Y
    call spr_row_ptr
    ld hl,mitsos_buf
    jp spr_restore

;; ---------------------------------------------------------------------------
;; mitsos_draw - save the floor under him, then draw him over it.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
mitsos_draw
    ld a,(mitsos_frame)
    add a,a
    ld e,a
    ld d,0
    ld hl,mitsos_frames
    add hl,de
    ld a,(mitsos_face)
    or a
    jr z,mitsos_draw_pick
    inc hl                              ; the mirrored copy sits next to it
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
mitsos_draw_pick
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                            ; HL = the sprite
    call spr_size                       ; -> spr_w, spr_h, HL at the pixels

    ld a,(mitsos_x)
    ld (spr_x),a
    push hl
    ld a,MITSOS_Y
    call spr_row_ptr                    ; wants DE and HL for itself
    pop hl
    ld de,mitsos_buf
    jp spr_draw

;; The three frames facing right, then the same three facing left. Two bytes
;; each, so the frame number is an index and nothing has to be worked out.
mitsos_frames
    defw spr_mitsos_stand
    defw spr_mitsos_walk1
    defw spr_mitsos_walk2
    defw spr_mitsos_stand_l
    defw spr_mitsos_walk1_l
    defw spr_mitsos_walk2_l

;; ---------------------------------------------------------------------------
;; draw_shop - the background, once. Navy above, tiled floor below, three
;; shelves across it.
;;
;; It is painted rather than composed out of tables: one room, and the point
;; of this milestone is the screen, not the level. Everything a sprite walks
;; over is restored from the buffer it saved, so none of it has to be redrawn.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
draw_shop
    ld hl,line_tab                      ; the night outside the window
    ld de,DISPLAY_LINES
    ld a,PEN0_BYTE
    call clear_rows

    ld hl,line_tab+FLOOR_TOP*2          ; the floor he slides about on
    ld de,DISPLAY_LINES-FLOOR_TOP
    ld a,PEN1_BYTE
    call clear_rows

    ld hl,line_tab+FLOOR_TOP*2          ; and the shine along the top of it
    ld de,FLOOR_EDGE
    ld a,PEN3_BYTE
    call clear_rows

    ld hl,shelves
draw_shop_shelf
    ld e,(hl)                           ; scanline
    inc hl
    ld a,e
    cp 255
    ret z
    ld a,(hl)                           ; x, in bytes
    inc hl
    ld (fill_x),a
    ld a,(hl)                           ; width, in bytes
    inc hl
    push hl
    ld l,a
    ld h,0
    ld (fill_w),hl
    ld a,PEN3_BYTE
    ld (fill_b),a
    ld h,0
    ld l,e
    add hl,hl
    ld de,line_tab
    add hl,de
    ld de,SHELF_T
    call fill_rows
    pop hl
    jr draw_shop_shelf

;; y, x and width, all in the units the screen is in: scanlines and bytes.
shelves
    defb SHELF1_Y, 6,  34
    defb SHELF1_Y, 56, 34
    defb SHELF2_Y, 24, 48
    defb SHELF3_Y, 6,  30
    defb SHELF3_Y, 60, 30
    defb 255

;; ---------------------------------------------------------------------------
;; The four pens. Mode 1 shows four of them and the border, not sixteen.
;; Hardware colour numbers, not firmware INK numbers.
;; ---------------------------------------------------------------------------
;; pal_blank, the all-black one every game starts on, is in crtc.asm.
pal_shop
    defb 0,   #40+4                     ; navy - the night, and the ground
    defb 1,   #40+19                    ; bright cyan - tiles, sea, his eyes
    defb 2,   #40+14                    ; orange - Mitsos, the fish, the cheese
    defb 3,   #40+11                    ; bright white - shine and highlights
    defb #10, #40+4                     ; border, for the sliver that is left
    defb #FF

    include "crtc.asm"
    include "video.asm"
    include "irq.asm"
    include "keys.asm"
    include "mitsosart.asm"             ; in front of sprite.asm, which asserts
SPR_MAX_W       EQU ART_MAX_W           ; the widest of them fits its blit
    include "sprite.asm"

code_end

    include "workspace.asm"

;; Mitsos's own RAM, past the engine's. The buffer is the patch of shop he is
;; standing in front of, and it is his: nothing else is lifted off yet.
mitsos_x        defs 1              ; where he is, in bytes
mitsos_ox       defs 1              ; and where his picture still is
mitsos_face     defs 1              ; FACE_RIGHT / FACE_LEFT
mitsos_frame    defs 1              ; 0 standing, 1 and 2 the waddle
mitsos_tick     defs 1              ; frames until the next one
mitsos_redraw   defs 1              ; something moved, so he has to be rebuilt
mitsos_buf      defs MITSOS_BYTES

    IF TARGET==1
RUN mitsos_start
    ENDIF

    IF TARGET==2
    SAVE "MITSOS.BIN",mitsos_start,code_end-mitsos_start,DSK,"build/mitsos.dsk"
    ENDIF

    IF TARGET==3
    SAVE "build/out.bin",mitsos_start,code_end-mitsos_start
    ENDIF
