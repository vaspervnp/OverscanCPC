;; ===========================================================================
;; ΠΑΝΙΚΟΣ ΣΤΟ ΠΑΝΤΟΠΩΛΕΙΟ - MITSOS: THE GROCERY HEIST
;;
;; Amstrad CPC 6128, mode 0, 384x272 full overscan, no firmware.
;;
;; The second milestone: the shop itself. Sixteen pens instead of four, a
;; background that is a grocery rather than a colour - whitewashed wall, a
;; window onto the harbour, shelving, a counter, crates - and the cast
;; standing about in it while Mitsos walks the floor in front of them.
;;
;; The furniture is boxes, the way the other game on this engine does it: a
;; fridge is a box and a counter is a box, and at the size furniture wants to
;; be - a counter is waist high on a person and three times the height of a
;; cat - bitmaps for a shop's worth do not exist in this machine. boxes.asm
;; paints them; the only thing here is the list.
;;
;; Everything else is the engine as it stands: crtc.asm puts the picture up,
;; video.asm builds the line table and fills the rectangles, irq.asm keeps the
;; 50 Hz tick, keys.asm reads the matrix, sprite.asm lifts Mitsos off the
;; background and puts him back.
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
;; Scanlines down and bytes across. A byte is two mode 0 pixels, which is four
;; pixels on the monitor, so the 96 bytes of a line are the full 384.
FLOOR_TOP       EQU 236                 ; the tiles start here
DADO_TOP        EQU 188                 ; and the painted lower wall here
GROUT_STEP      EQU 8                   ; a floor tile is this many bytes

;; The wall is brick, and at this scale a course is about
;; a hand's width: 16 scanlines to a course, 8 bytes to a brick - 32 pixels on
;; the monitor - and every other course offset by half a brick, which is what
;; makes it read as a wall rather than as a grid. The joints are a byte wide
;; because a byte is the narrowest thing a fill can put down: two mode 0
;; pixels, four on the tube.
BRICK_COURSE    EQU 16
BRICK_MORTAR    EQU 2
BRICK_W         EQU 8

;; The shelf boards, the counter top and the crate lids are all pen 2, and
;; they are 32 scanlines apart, because that is what a cat clears in a jump.
;; "Butter yellow means you can stand on it" is the visual grammar of both
;; games on this engine and it does not change from room to room.
SHELF_1         EQU 204
SHELF_2         EQU 172
SHELF_3         EQU 140
SHELF_4         EQU 108

;; --- Mitsos ----------------------------------------------------------------
;; Twelve mode 0 pixels across - six bytes, twenty-four on the monitor - and
;; twenty-four scanlines tall. He steps a byte at a time, which is four
;; monitor pixels.
MITSOS_W        EQU SPR_MITSOS_STAND_W
MITSOS_H        EQU SPR_MITSOS_STAND_H
MITSOS_Y0       EQU FLOOR_TOP-MITSOS_H  ; where he comes in, on the floor
MITSOS_XMAX     EQU BYTES_PER_LINE-MITSOS_W
MITSOS_BYTES    EQU MITSOS_W*MITSOS_H
WALK_TICKS      EQU 5                   ; frames between the two walk frames

FACE_RIGHT      EQU 0
FACE_LEFT       EQU 1

;; --- Gravity ---------------------------------------------------------------
;; Vertical position and velocity are 8.8 fixed point - a byte of scanline and
;; a byte of fraction - because whole-pixel gravity at 50 Hz has no usable
;; range between a brick and a balloon. 256 is one pixel a frame.
;;
;; These are the numbers the other game on this engine settled on, and they
;; are what the shelves are spaced against: a quarter of a pixel a frame of
;; gravity and four and a half up out of a jump clears about forty scanlines,
;; so a board 32 above the one below it is reachable and one 64 above it is
;; not. Change either and the shop stops being climbable.
GRAVITY         EQU #0040               ; 0.25 px/frame - apex in 18 frames
JUMP_V          EQU #FB80               ; -4.5 px/frame, about 40 px up
MAX_FALL        EQU #0600               ; +6.0 px/frame terminal velocity
SHOP_TOP        EQU 12                  ; he cannot rise past this scanline

ST_GROUND       EQU 0
ST_AIR          EQU 1

    ORG #4000                           ; RAM whatever the ROMs are doing, and
                                        ; clear of the screen at #8000
;; ---------------------------------------------------------------------------
;; Entry point.
;; ---------------------------------------------------------------------------
mitsos_start
    di                                  ; the firmware's handler is about to go
    ld sp,STACK_TOP

    ld bc,#7F00+GA_MODE                 ; mode 0, upper and lower ROM disabled
    out (c),c

    ld hl,pal_blank                     ; build the shop unseen, so none of
    call set_pal                        ; the firmware's leftovers show

    call build_line_tab
    call draw_shop

    call setup_crtc                     ; only now switch the display over
    ld hl,pal_shop
    call set_pal

    call irq_init                       ; and the 50 Hz tick under everything

;; Mitsos comes in from the left, facing right and standing on the floor.
    ld a,8
    ld (mitsos_x),a
    ld (mitsos_ox),a
    ld a,MITSOS_Y0
    ld (mitsos_y),a
    ld (mitsos_oy),a
    xor a
    ld (mitsos_yf),a
    ld (mitsos_face),a
    ld (mitsos_tick),a
    ld (mitsos_frame),a
    ld (mitsos_state),a                 ; ST_GROUND
    ld hl,0
    ld (mitsos_vy),hl
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
;; mitsos_move - one 50 Hz step of him: the keys, then the physics.
;;
;; Left and right walk him a byte a frame whether he is on something or in the
;; air, which is the air control every platform game of this shape has. Fire
;; or up leaves the ground. Everything after that is gravity.
;;
;; The picture is only rebuilt if something about it changed, so a cat
;; standing still on a shelf costs nothing at all.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_move
    ld a,(mitsos_x)                     ; where his picture still is
    ld (mitsos_ox),a
    ld a,(mitsos_y)
    ld (mitsos_oy),a
    ld a,(mitsos_frame)
    ld (mitsos_oframe),a

    call mitsos_walk
    ld a,(mitsos_state)
    or a
    call z,mitsos_ground
    ld a,(mitsos_state)
    or a
    call nz,mitsos_air

;; Anything that moved him, or changed which of him is being drawn, means the
;; picture has to be taken up and put down again.
    ld a,(mitsos_ox)
    ld hl,mitsos_x
    cp (hl)
    jr nz,mitsos_move_dirty
    ld a,(mitsos_oy)
    ld hl,mitsos_y
    cp (hl)
    jr nz,mitsos_move_dirty
    ld a,(mitsos_oframe)
    ld hl,mitsos_frame
    cp (hl)
    jr nz,mitsos_move_dirty
    xor a
    ld (mitsos_redraw),a
    ret
mitsos_move_dirty
    ld a,1
    ld (mitsos_redraw),a
    ret

;; ---------------------------------------------------------------------------
;; mitsos_walk - left and right, and the two-frame waddle that goes with them.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
mitsos_walk
    ld a,(mitsos_x)
    ld b,a

    ld a,(ctl_now)
    bit CTL_LEFT,a
    jr nz,mitsos_walk_left
    bit CTL_RIGHT,a
    jr nz,mitsos_walk_right

    xor a                               ; standing still: legs together, and
    ld (mitsos_tick),a                  ; the counter back to the top so the
    ld (mitsos_frame),a                 ; first step out is always the same one
    ret

mitsos_walk_left
    ld a,FACE_LEFT
    ld (mitsos_face),a
    ld a,b
    or a
    jr z,mitsos_walk_step               ; already against the left wall
    dec b
    jr mitsos_walk_step

mitsos_walk_right
    xor a
    ld (mitsos_face),a
    ld a,b
    cp MITSOS_XMAX
    jr nc,mitsos_walk_step
    inc b

mitsos_walk_step
    ld a,b
    ld (mitsos_x),a

    ld hl,mitsos_tick
    inc (hl)
    ld a,(hl)
    cp WALK_TICKS
    ret c
    ld (hl),0
    ld a,(mitsos_frame)                 ; 0 or 2 -> 1, and 1 -> 2
    cp 1
    ld a,2
    jr z,mitsos_walk_set
    ld a,1
mitsos_walk_set
    ld (mitsos_frame),a
    ret

;; ---------------------------------------------------------------------------
;; mitsos_ground - standing on something. Fire leaves it; walking off the end
;; of it does too, and the only difference between those is the velocity.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_ground
    ld a,(ctl_now)
    and (1<<CTL_FIRE)|(1<<CTL_UP)
    jr z,mitsos_ground_check
    ld hl,JUMP_V
    ld (mitsos_vy),hl
    ld a,ST_AIR
    ld (mitsos_state),a
    ret

;; Still over the thing he was standing on? Walking off the end of a shelf is
;; a fall with no push behind it, which is what leaving vy at zero means.
mitsos_ground_check
    ld a,(mitsos_y)
    add a,MITSOS_H
    ld b,a                              ; his feet
    ld hl,shop_plats
mitsos_ground_loop
    ld a,(hl)
    inc a
    jr z,mitsos_ground_off
    dec a
    ld c,a                              ; first column
    inc hl
    ld a,(hl)                           ; last column
    inc hl
    ld e,(hl)                           ; top scanline
    inc hl
    push hl
    push bc
    push de
    ld b,c
    call mitsos_overlap
    pop de
    pop bc
    pop hl
    jr nc,mitsos_ground_loop
    ld a,b
    cp e
    jr nz,mitsos_ground_loop
    ret                                 ; still standing on it

mitsos_ground_off
    ld hl,0
    ld (mitsos_vy),hl
    ld a,ST_AIR
    ld (mitsos_state),a
    ret

;; ---------------------------------------------------------------------------
;; mitsos_air - gravity, then whether anything caught him on the way down.
;;
;; Platforms are one-way: landing is only looked for while he is falling, by
;; asking whether a shelf top lies between where his feet were and where they
;; now are. Going up he passes straight through, which is what lets him climb
;; the shelving from underneath.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_air
    ld hl,(mitsos_vy)
    ld de,GRAVITY
    add hl,de
    bit 7,h
    jr nz,mitsos_air_velocity           ; still rising
    ld de,MAX_FALL
    push hl
    or a
    sbc hl,de
    pop hl
    jr c,mitsos_air_velocity
    ld hl,MAX_FALL                      ; terminal velocity
mitsos_air_velocity
    ld (mitsos_vy),hl

    ld a,(mitsos_y)                     ; remember where the feet were
    add a,MITSOS_H
    ld (mitsos_ofeet),a

    ld hl,(mitsos_yf)                   ; 8.8: L = fraction, H = scanline
    ld de,(mitsos_vy)
    add hl,de
    jr c,mitsos_air_moved               ; carry out, so no underflow
    bit 7,d
    jr z,mitsos_air_moved               ; DE was positive anyway
    ld hl,SHOP_TOP*256                  ; rose past the top of the shop
    ld de,0
    ld (mitsos_vy),de
mitsos_air_moved
    ld (mitsos_yf),hl
    ld a,h
    cp SHOP_TOP
    jr nc,mitsos_air_land
    ld hl,SHOP_TOP*256                  ; and stopped by the ceiling
    ld (mitsos_yf),hl
    ld hl,0
    ld (mitsos_vy),hl

mitsos_air_land
    ld hl,(mitsos_vy)
    bit 7,h
    ret nz                              ; rising: nothing to land on

    ld a,(mitsos_y)
    add a,MITSOS_H
    ld (mitsos_nfeet),a
    call mitsos_find_landing
    ret nc

    sub MITSOS_H                        ; A = the top it landed on
    ld (mitsos_y),a
    xor a
    ld (mitsos_yf),a
    ld hl,0
    ld (mitsos_vy),hl
    ld (mitsos_state),a                 ; ST_GROUND, and A is zero
    ret

;; ---------------------------------------------------------------------------
;; mitsos_find_landing - the highest shelf his feet crossed this step.
;; Carry set and A = its top scanline, or carry clear if he is still falling.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_find_landing
    ld hl,shop_plats
    ld c,#FF                            ; best so far
mitsos_find_loop
    ld a,(hl)
    inc a
    jr z,mitsos_find_done
    dec a
    ld b,a                              ; first column
    inc hl
    ld a,(hl)                           ; last column
    inc hl
    ld e,(hl)                           ; top scanline
    inc hl
    push hl
    push bc
    push de
    call mitsos_overlap
    pop de
    pop bc
    pop hl
    jr nc,mitsos_find_loop

    ld a,(mitsos_ofeet)
    cp e
    jr z,mitsos_find_below
    jr nc,mitsos_find_loop              ; the feet were already past it
mitsos_find_below
    ld a,(mitsos_nfeet)
    cp e
    jr c,mitsos_find_loop               ; still above it
    ld a,e
    cp c
    jr nc,mitsos_find_loop              ; something higher already found
    ld c,a
    jr mitsos_find_loop
mitsos_find_done
    ld a,c
    inc a
    jr z,mitsos_find_none
    ld a,c
    scf
    ret
mitsos_find_none
    or a
    ret

;; ---------------------------------------------------------------------------
;; mitsos_overlap - B = first column, A = last column. Carry set if he is over
;; that span at all.
;; Destroys AF, C.
;; ---------------------------------------------------------------------------
mitsos_overlap
    ld c,a
    ld a,(mitsos_x)
    cp c
    jr z,mitsos_overlap_left
    jr nc,mitsos_overlap_no             ; he starts past the end of it
mitsos_overlap_left
    ld a,(mitsos_x)
    add a,MITSOS_W-1
    cp b
    jr c,mitsos_overlap_no              ; and ends before the start of it
    scf
    ret
mitsos_overlap_no
    or a
    ret

;; ---------------------------------------------------------------------------
;; What he can stand on: first column, last column, top scanline - and #FF at
;; the end of it. The floor, the four boards of the shelving, the lid of the
;; crates and the counter top, which are the same rectangles the furniture is
;; drawn from and have to stay that way.
;; ---------------------------------------------------------------------------
shop_plats
    defb  0, 95, FLOOR_TOP
    defb  4, 33, SHELF_1
    defb  4, 33, SHELF_2
    defb  4, 33, SHELF_3
    defb  4, 33, SHELF_4
    defb 38, 51, SHELF_1-8              ; the lid of the crates
    defb 56, 87, SHELF_1-24             ; and the counter top
    defb #FF

;; ---------------------------------------------------------------------------
;; mitsos_erase - put the shop back where he was standing.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
mitsos_erase
    ld a,MITSOS_W
    ld (spr_w),a
    ld a,MITSOS_H
    ld (spr_h),a
    ld a,(mitsos_ox)
    ld (spr_x),a
    ld a,(mitsos_oy)
    call spr_row_ptr
    ld hl,mitsos_buf
    jp spr_restore

;; ---------------------------------------------------------------------------
;; mitsos_draw - save the shop under him, then draw him over it.
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
    ld de,6                             ; the mirrored copies sit behind them
    add hl,de
mitsos_draw_pick
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                            ; HL = the sprite
    call spr_size                       ; -> spr_w, spr_h, HL at the pixels

    ld a,(mitsos_x)
    ld (spr_x),a
    push hl
    ld a,(mitsos_y)
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
;; draw_shop - the background, once.
;;
;; Wall, then the painted dado along the bottom of it, then the tiled floor,
;; then the furniture, then the things standing on the furniture. Later boxes
;; draw over earlier ones, so an outline is a white box with a filled one
;; inside it and nothing has to know about edges.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_shop
    ld hl,line_tab                      ; the brick, wall to wall, to start
    ld de,DISPLAY_LINES
    ld a,PEN1_BYTE
    call clear_rows

    call draw_wall                      ; then the joints cut into it

    ld hl,line_tab+DADO_TOP*2           ; the painted lower half of it
    ld de,FLOOR_TOP-DADO_TOP
    ld a,PEN10_BYTE
    call clear_rows

    ld hl,line_tab+DADO_TOP*2           ; and the line where the paint stops
    ld de,2
    ld a,PEN3_BYTE
    call clear_rows

    ld hl,line_tab+FLOOR_TOP*2          ; the tiles
    ld de,DISPLAY_LINES-FLOOR_TOP
    ld a,PEN5_BYTE
    call clear_rows

    ld hl,line_tab+FLOOR_TOP*2
    ld de,2
    ld a,PEN3_BYTE
    call clear_rows

    ld hl,1                             ; and the grout between them
    ld (fill_w),hl
    ld a,PEN3_BYTE
    ld (fill_b),a
    ld c,0
draw_shop_grout
    ld a,c
    ld (fill_x),a
    push bc
    ld hl,line_tab+FLOOR_TOP*2
    ld de,DISPLAY_LINES-FLOOR_TOP
    call fill_rows
    pop bc
    ld a,c
    add a,GROUT_STEP
    ld c,a
    cp BYTES_PER_LINE
    jr c,draw_shop_grout

;; The furniture, in the order it stands in: the window is in the wall behind
;; everything, the shelving and the counter in front of it.
    ld hl,shop_props
draw_shop_prop
    ld a,(hl)
    inc a
    jr z,draw_shop_things
    dec a
    ld (prop_x),a
    inc hl
    ld a,(hl)
    ld (prop_y),a
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ex de,hl
    call draw_boxes
    pop hl
    jr draw_shop_prop

;; And the things standing on it. They go down through the masked blit and
;; stay there: nothing picks them up yet, so they are part of the shop, and
;; Mitsos walking in front of one puts it back for free.
draw_shop_things
    ld hl,shop_things
draw_shop_thing
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,d
    or e
    ret z
    ld a,(hl)                           ; x, in bytes
    inc hl
    ld (spr_x),a
    ld a,(hl)                           ; y, the top scanline
    inc hl
    push hl
    push af
    ex de,hl
    call spr_size                       ; -> spr_w, spr_h, HL at the pixels
    pop af
    push hl
    call spr_row_ptr
    pop hl
    call spr_blit
    pop hl
    jr draw_shop_thing

;; ---------------------------------------------------------------------------
;; draw_wall - the brickwork, course by course.
;;
;; The brick is already down; this puts the joints into it. A bed joint
;; runs the whole width, the perpends are a byte each and half a brick further
;; along on every other course, and the last course is allowed to run past the
;; bottom of the wall because the dado is painted over it afterwards.
;;
;; B is the stagger of the course being drawn and C its top scanline, and both
;; have to survive fill_rows, which does not keep anything.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
draw_wall
    ld a,PEN15_BYTE                     ; mortar, pale against the red
    ld (fill_b),a
    ld bc,0                             ; B = stagger, C = top of the course

draw_wall_course
    xor a                               ; the bed joint, all the way across
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    push bc
    ld a,c
    call wall_row_ptr
    ld de,BRICK_MORTAR
    call fill_rows
    pop bc

    ld hl,1                             ; and the perpends down the face
    ld (fill_w),hl
    ld a,b
draw_wall_perp
    ld (fill_x),a
    push bc
    push af
    ld a,c
    add a,BRICK_MORTAR
    call wall_row_ptr
    ld de,BRICK_COURSE-BRICK_MORTAR
    call fill_rows
    pop af
    pop bc
    add a,BRICK_W
    cp BYTES_PER_LINE
    jr c,draw_wall_perp

    ld a,b                              ; the next course, half a brick over
    xor BRICK_W/2
    ld b,a
    ld a,c
    add a,BRICK_COURSE
    ld c,a
    cp DADO_TOP
    jr c,draw_wall_course
    ret

;; A = scanline -> HL = its line_tab entry.
wall_row_ptr
    ld l,a
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ret

;; ---------------------------------------------------------------------------
;; The shop, as boxes. x and y, then the list: dx, dy, width in bytes, height
;; in scanlines, pen - and #FF at the end of it.
;; ---------------------------------------------------------------------------
shop_props
    defb 58, 24
    defw box_window
    defb 4, 76
    defw box_shelving
    defb 56, SHELF_1-24
    defw box_counter
    defb 38, SHELF_1-8
    defw box_crates
    defb 88, 212
    defw box_sacks
    defb 255

;; 116 x 64 px: the window onto the harbour, which is the only daylight in it.
box_window
    defb  0,  0, 29, 64, 3      ; frame
    defb  2,  4, 25, 30, 11     ; sky
    defb  2, 34, 25, 26, 10     ; and the sea under it
    defb 13,  0,  3, 64, 3      ; the bar down the middle
    defb  4,  8,  3,  6, 15     ; the sun, in the top corner
    defb  4, 40,  6,  2, 3      ; two lines of swell
    defb 18, 48,  7,  2, 3
    defb #FF

;; 120 x 160 px: the shelving along the back wall, four boards of it.
box_shelving
    defb  0,  0, 30,160, 6      ; the carcass
    defb  2,  4, 26,152, 12     ; the dark inside of it
    defb  0,  0,  2,160, 6      ; uprights
    defb 28,  0,  2,160, 6
    defb  0, SHELF_4-76, 30, 4, 2   ; and the boards, a jump apart
    defb  0, SHELF_3-76, 30, 4, 2
    defb  0, SHELF_2-76, 30, 4, 2
    defb  0, SHELF_1-76, 30, 4, 2
    defb #FF

;; 128 x 56 px: the counter, with the good stuff behind the glass.
box_counter
    defb  0,  0, 32, 56, 6      ; the body of it
    defb  1,  6, 30, 30, 11     ; the glass front
    defb  3,  8, 26, 26, 3      ; what is in it, in white trays
    defb  3, 10, 26,  6, 1
    defb  3, 22, 26,  6, 2
    defb  0,  0, 32,  6, 2      ; the top, which he can stand on
    defb  0, 40, 32, 16, 12     ; the panel under it
    defb  2, 44, 28,  8, 6
    defb #FF

;; 56 x 40 px: crates of something, stacked two high.
box_crates
    defb  0,  0, 14, 40, 12
    defb  0,  0, 14,  4, 2      ; the lid is a shelf like any other
    defb  1,  6, 12,  4, 6      ; slats
    defb  1, 14, 12,  4, 6
    defb  1, 22, 12,  4, 6
    defb  1, 30, 12,  4, 6
    defb #FF

;; 32 x 24 px: sacks in the corner, because a grocery has sacks in the corner.
box_sacks
    defb  0,  4,  8, 20, 15
    defb  1,  0,  6,  6, 15
    defb  2,  2,  4,  2, 6      ; the tie round the neck of it
    defb  0, 14,  8,  2, 6
    defb #FF

;; ---------------------------------------------------------------------------
;; What is standing on the shelves, and who is standing about in the shop.
;; Sprite, then x in bytes and the top scanline. Ends on a zero pointer.
;; ---------------------------------------------------------------------------
shop_things
    defw spr_fish
    defb  8, SHELF_4-12
    defw spr_cheese
    defb 22, SHELF_3-12
    defw spr_catnip
    defb 10, SHELF_2-12
    defw spr_meatball
    defb 42, SHELF_1-12
    defw spr_sausage
    defb 62, SHELF_1-24-12          ; on the counter top
    defw spr_seagull_a_l
    defb 64, 72                     ; perched on the window ledge
    defw spr_broom_a
    defb 52, FLOOR_TOP-28           ; leaning where she left it
    defw spr_mouse_a
    defb 80, FLOOR_TOP-12
    defw 0

;; ---------------------------------------------------------------------------
;; The sixteen pens. Hardware colour numbers, not firmware INK numbers - the
;; same sixteen the art is drawn in, which is what lets one converter feed
;; both games. pal_blank, the all-black one every game starts on, is in
;; crtc.asm.
;; ---------------------------------------------------------------------------
pal_shop
    defb 0,   #40+4             ; navy - shadow, and what a mask lets through
    defb 1,   #40+7             ; coral - the brick the shop is built of
    defb 2,   #40+10            ; butter yellow - you can stand on this
    defb 3,   #40+11            ; bright white
    defb 4,   #40+20            ; black
    defb 5,   #40+0             ; grey - the floor tiles
    defb 6,   #40+30            ; olive - wood
    defb 7,   #40+14            ; orange - Mitsos
    defb 8,   #40+22            ; dark green
    defb 9,   #40+18            ; bright green - catnip, and his eye
    defb 10,  #40+6             ; teal - the sea, and the painted dado
    defb 11,  #40+19            ; bright cyan - sky, glass, fish
    defb 12,  #40+28            ; dark red - shadow in the wood
    defb 13,  #40+12            ; bright red
    defb 14,  #40+24            ; purple
    defb 15,  #40+3             ; pale yellow - the mortar between it
    defb #10, #40+7             ; the border, so the sliver matches the wall
    defb #FF

    include "crtc.asm"
    include "video.asm"
    include "irq.asm"
    include "keys.asm"
    include "boxes.asm"
    include "mitsosart.asm"             ; in front of sprite.asm, which asserts
SPR_MAX_W       EQU ART_MAX_W           ; the widest of them fits its blit
    include "sprite.asm"

code_end

    include "workspace.asm"

;; Mitsos's own RAM, past the engine's. The buffer is the patch of shop he is
;; standing in front of, and it is his: nothing else is lifted off yet.
mitsos_x        defs 1              ; where he is, in bytes
mitsos_yf       defs 1              ; 8.8 fixed point: mitsos_yf then mitsos_y,
mitsos_y        defs 1              ; so "ld hl,(mitsos_yf)" loads the pair
mitsos_vy       defs 2              ; vertical velocity, same units, signed
mitsos_state    defs 1              ; ST_GROUND / ST_AIR
mitsos_ofeet    defs 1              ; where his feet were at the top of the
mitsos_nfeet    defs 1              ; step, and where they are now
mitsos_ox       defs 1              ; and where his picture still is
mitsos_oy       defs 1
mitsos_oframe   defs 1
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
