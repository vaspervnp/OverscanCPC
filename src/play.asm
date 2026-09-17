;; ===========================================================================
;; play.asm - playing a room: physics, collection, damage, and the way out.
;;
;; Nothing here knows the flat's layout. Every table it walks comes from the
;; room record loaded by room_load, which is what lets rooms.asm add a room
;; without touching this file.
;;
;; Vertical position is 8.8 fixed point: a byte of scanline and a byte of
;; fraction, with velocity in the same units. Whole-pixel gravity on a 50 Hz
;; machine either falls like a brick or floats, and neither suits a cat the
;; design document insists is overweight.
;;
;; Platforms are one-way: you land on them coming down and pass through going
;; up, which is what a single-screen platform puzzle wants and costs one
;; comparison rather than a swept-box intersection.
;; ===========================================================================

;; 8.8 fixed point, so 256 is one pixel per frame.
GRAVITY         EQU #0040       ; 0.25 px/frame - apex in 18 frames
JUMP_V          EQU #FB80       ; -4.5 px/frame, about 40 px up: a low jump
FLOP_V          EQU #0800       ; +8.0 px/frame once the belly commits
MAX_FALL        EQU #0600       ; +6.0 px/frame terminal velocity

WALK_STEP       EQU 1           ; bytes per frame - 4 px
ROLL_STEP       EQU 2           ; rolling is the fast way to travel
WALK_BIT        EQU #04         ; animation cell changes every 4 frames
FLOP_STUN       EQU 14          ; frames flat on the floor after a landing

ST_GROUND       EQU 0
ST_AIR          EQU 1
ST_FLOP         EQU 2
ST_ROLL         EQU 3

SHAKE_LEN       EQU 6

;; HUD, in the twelve scanlines above the play area. The captions come from the
;; string table, so the columns leave room for the longer language.
HUD_Y           EQU 2
HUD_H           EQU 8
SCORE_LABEL_X   EQU 2
SCORE_X         EQU 14
SAUS_LABEL_X    EQU 34
SAUS_COUNT_X    EQU 54
LIVES_LABEL_X   EQU 66
LIVES_X         EQU 78
ROOM_NAME_X     EQU 82

SCORE_BYTES     EQU 3           ; six BCD digits
SAUSAGE_POINTS  EQU #01         ; BCD, added to the hundreds digit

WELLDONE_Y      EQU 40
WELLDONE_YS     EQU 3

LIVES_START     EQU 3
INVUL_FRAMES    EQU 100         ; two seconds of grace after a respawn

;; ---------------------------------------------------------------------------
;; play_screen - walk the flat, one room at a time. Returns on Escape.
;; ---------------------------------------------------------------------------
play_screen
    xor a
    ld (cur_room),a
    ld (score),a
    ld (score+1),a
    ld (score+2),a
    ld (game_over),a
    ld a,LIVES_START
    ld (cat_lives),a

play_room
    call room_load

play_loop
    call wait_frame
    call read_controls
    ld a,(ctl_pressed)
    bit CTL_QUIT,a
    jr nz,play_quit

    call cat_erase              ; unwind the scene in reverse draw order
    call enemies_erase

    ld a,(game_over)
    or a
    jr nz,play_draw

    call cat_update
    call enemies_update
    call check_sausages         ; between erase and draw: a sausage has to
    call check_enemies          ; leave the background before it is saved again
    call check_exit
    jr nc,play_draw

    ld a,(cur_room)             ; through the door
    inc a
    cp ROOM_COUNT
    jr nc,play_finished
    ld (cur_room),a
    jr play_room

play_finished
    ld a,1
    ld (game_over),a
    ld a,1
    ld (txt_xs),a
    ld a,WELLDONE_YS
    ld (txt_ys),a
    ld hl,line_tab+WELLDONE_Y*2
    ld (txt_row),hl
    ld a,MSG_WELLDONE
    call msg_big_centre

play_draw
    call update_hud
    call enemies_draw
    call cat_draw               ; last, so the cat is on top
    call shake_update
    jr play_loop

play_quit
    xor a                       ; leave the screen centred again
    ld (shake_timer),a
    ld e,CRTC_R7
    ld a,7
    jp crtc_set

;; ===========================================================================
;; Loading a room
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; room_load - pull cur_room's tables out of rooms.asm and paint it.
;; ---------------------------------------------------------------------------
room_load
    ld hl,rooms
    ld a,(cur_room)
    or a
    jr z,room_load_found
    ld b,a
    ld de,R_SIZE
room_load_step
    add hl,de
    djnz room_load_step
room_load_found
    push hl
    pop iy

    ld a,(iy+R_NAME)
    ld (room_name),a
    ld l,(iy+R_PLAT)
    ld h,(iy+R_PLAT+1)
    ld (cur_plat),hl
    ld l,(iy+R_SAUS)
    ld h,(iy+R_SAUS+1)
    ld (cur_saus),hl
    ld a,(iy+R_NSAUS)
    ld (cur_nsaus),a
    ld l,(iy+R_PROPS)
    ld h,(iy+R_PROPS+1)
    ld (cur_props),hl
    ld a,(iy+R_EXITX)
    ld (exit_x),a
    ld a,(iy+R_EXITPX)
    ld (exit_px),a
    ld a,(iy+R_EXITPY)
    ld (exit_py),a
    ld a,(iy+R_EXITY)
    ld (exit_y),a
    ld a,(iy+R_EXITW)
    ld (exit_w),a
    ld a,(iy+R_EXITH)
    ld (exit_h),a
    ld a,(iy+R_EXITSHUT)
    ld (exit_shut),a
    ld a,(iy+R_EXITOPEN)
    ld (exit_open),a

    ld hl,spr_cat_stand         ; set the sprite first: cat_set_sprite shifts y
    call cat_set_sprite         ; to keep the feet, and we are about to move it
    ld a,(iy+R_STARTX)
    ld (cat_x),a
    ld (cat_startx),a
    ld a,(iy+R_STARTY)
    ld (cat_y),a
    ld (cat_starty),a

    xor a
    ld (cat_yf),a
    ld (cat_stun),a
    ld (cat_state),a
    ld (cat_drawn),a
    ld (cat_anim),a
    ld (cat_invul),a
    ld (level_done),a
    ld (sausages_got),a
    ld (shake_timer),a
    ld (hud_dirty),a
    ld hl,0
    ld (cat_vy),hl

    ld hl,sausage_alive         ; a full larder
    ld a,(cur_nsaus)
    ld b,a
    ld a,1
room_load_alive
    ld (hl),a
    inc hl
    djnz room_load_alive

    ld l,(iy+R_ENEM)
    ld h,(iy+R_ENEM+1)
    ld a,(iy+R_NENEM)
    ld b,a
    call enemies_init

    ld hl,pal_play
    call set_pal

    ld hl,line_tab
    ld de,DISPLAY_LINES
    ld a,PEN0_BYTE
    call clear_rows

    call draw_props             ; furniture first, everything else on top
    call draw_platforms
    call draw_exit
    call draw_sausages
    jp draw_hud

;; ---------------------------------------------------------------------------
;; Furniture. A prop is a list of filled rectangles rather than a bitmap: at
;; the size furniture wants to be, masked sprites for a flat's worth came to
;; about 30 KB. Later boxes draw over earlier ones, so an outline is a white
;; box with a navy one inside it.
;; ---------------------------------------------------------------------------
pen_bytes
    defb PEN0_BYTE, PEN1_BYTE, PEN2_BYTE, PEN3_BYTE

;; ---------------------------------------------------------------------------
;; prop_boxes_at - A = prop id -> HL = its box list.
;; ---------------------------------------------------------------------------
prop_boxes_at
    add a,a
    ld l,a
    ld h,0
    ld de,prop_boxes
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ret

;; ---------------------------------------------------------------------------
;; draw_boxes - HL = box list, drawn relative to (prop_x),(prop_y).
;; ---------------------------------------------------------------------------
draw_boxes
    ld a,(hl)
    inc a
    ret z
    dec a
    ld b,a                      ; dx
    ld a,(prop_x)
    add a,b
    ld (fill_x),a
    inc hl

    ld b,(hl)                   ; dy
    inc hl
    ld a,(prop_y)
    add a,b
    ld (box_top),a
    ld a,0                      ; ld does not touch the carry
    adc a,0                     ; 1 if the top ran past scanline 255
    ld (box_over),a

    ld a,(hl)                   ; width in bytes
    inc hl
    ld c,a
    ld b,0
    push hl
    ld h,b
    ld l,c
    ld (fill_w),hl
    pop hl

    ld a,(hl)                   ; height in scanlines
    inc hl
    ld (box_high),a

    ld a,(hl)                   ; pen
    inc hl
    push hl
    ld l,a
    ld h,0
    ld de,pen_bytes
    add hl,de
    ld a,(hl)
    ld (fill_b),a

    ;; Clip. line_tab has one entry per displayed scanline and the workspace
    ;; follows it, so a box that runs past the bottom would index off the end
    ;; and fill variables instead of screen. Do not trust the table.
    ld a,(box_over)
    or a
    jr nz,draw_boxes_next
    ld a,(box_top)
    ld c,a
    ld a,(box_high)
    ld b,a
    ld a,c
    add a,b
    jr nc,draw_boxes_fill
    xor a
    sub c                       ; only what fits above scanline 255
    ld b,a
    or a
    jr z,draw_boxes_next
draw_boxes_fill
    ld l,c                      ; line_tab entry for the top scanline
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ld e,b
    ld d,0
    call fill_rows
draw_boxes_next
    pop hl
    jr draw_boxes

;; ---------------------------------------------------------------------------
;; draw_props - the room's furniture, painted once into the background.
;; ---------------------------------------------------------------------------
draw_props
    ld hl,(cur_props)
draw_props_loop
    ld a,(hl)
    inc a
    ret z
    dec a
    ld e,a                      ; prop id
    inc hl
    ld a,(hl)
    ld (prop_x),a
    inc hl
    ld a,(hl)
    ld (prop_y),a
    inc hl
    push hl                     ; the prop list
    ld a,e
    call prop_boxes_at
    call draw_boxes
    pop hl
    jr draw_props_loop

;; ---------------------------------------------------------------------------
;; draw_exit - the way out, shut or open. Outlined like the rest of the
;; furniture rather than solid, because solid white means a platform; only
;; the light behind it changes.
;; ---------------------------------------------------------------------------
draw_exit
    ld a,(exit_px)              ; where the prop is drawn, which is not where
    ld (prop_x),a               ; the collision box is: the Pitsos is 136
    ld a,(exit_py)              ; scanlines tall but only its lower half counts
    ld (prop_y),a
    ld a,(level_done)
    or a
    jr z,draw_exit_shut
    ld a,(exit_open)
    jr draw_exit_boxes
draw_exit_shut
    ld a,(exit_shut)
draw_exit_boxes
    call prop_boxes_at
    jp draw_boxes

;; ---------------------------------------------------------------------------
;; check_exit - carry set once the cat has stepped into an open way out.
;; ---------------------------------------------------------------------------
check_exit
    ld a,(level_done)
    or a
    ret z                       ; sausages still to find
    ld a,(exit_x)
    ld (box_x),a
    ld a,(exit_y)
    ld (box_y),a
    ld a,(exit_w)
    ld (box_w),a
    ld a,(exit_h)
    ld (box_h),a
    jp cat_hits_box

;; ---------------------------------------------------------------------------
;; draw_platforms - the floor as a solid band, the rest as shelves. Every
;; room's first platform is its floor.
;; ---------------------------------------------------------------------------
draw_platforms
    ld hl,line_tab+FLOOR_Y*2
    ld de,FLOOR_H
    ld a,PEN3_BYTE
    call clear_rows

    ld hl,(cur_plat)
    inc hl
    inc hl
    inc hl                      ; skip the floor, already painted
draw_platforms_loop
    ld a,(hl)
    inc a
    ret z
    dec a
    ld (fill_x),a
    ld b,a
    inc hl
    ld a,(hl)                   ; last column
    sub b
    inc a                       ; width in bytes
    push hl
    ld l,a
    ld h,0
    ld (fill_w),hl
    pop hl
    inc hl
    ld a,(hl)                   ; top scanline
    inc hl
    push hl
    ld l,a
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ld de,SHELF_H
    ld a,PEN2_BYTE
    ld (fill_b),a
    call fill_rows
    pop hl
    jr draw_platforms_loop

;; ---------------------------------------------------------------------------
;; draw_sausages
;; ---------------------------------------------------------------------------
draw_sausages
    ld hl,(cur_saus)
    ld a,(cur_nsaus)
    ld b,a
draw_sausages_loop
    push bc
    ld a,(hl)
    ld (spr_x),a
    inc hl
    ld c,(hl)                   ; y - spr_size leaves C alone
    inc hl
    push hl                     ; the list
    ld hl,spr_sausage
    call spr_size
    push hl                     ; the pixel data: spr_row_ptr would trample DE
    ld a,c
    call spr_row_ptr
    pop hl
    call spr_blit
    pop hl
    pop bc
    djnz draw_sausages_loop
    ret

;; ---------------------------------------------------------------------------
;; draw_hud - score, larder, lives and which room this is.
;; The captions sit on the background rather than a coloured band: a glyph
;; only sets pen bit 0, so text is invisible over pen 1 or pen 3.
;; ---------------------------------------------------------------------------
draw_hud
    xor a
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab+HUD_Y*2
    ld de,HUD_H
    call fill_rows

    ld hl,line_tab+HUD_Y*2
    ld (txt_row),hl

    ld a,SCORE_LABEL_X
    ld (txt_x),a
    ld a,MSG_SCORE
    call msg_small

    ld a,SCORE_X
    ld (txt_x),a
    ld hl,score
    ld b,SCORE_BYTES
    call print_digits

    ld a,SAUS_LABEL_X
    ld (txt_x),a
    ld a,MSG_SAUSAGES
    call msg_small

    ld a,SAUS_COUNT_X
    ld (txt_x),a
    ld a,(sausages_got)
    call print_digit
    ld a,GL_SLASH
    call print_glyph
    ld a,(cur_nsaus)
    call print_digit

    ld a,LIVES_LABEL_X
    ld (txt_x),a
    ld a,MSG_LIVES
    call msg_small

    ld a,LIVES_X
    ld (txt_x),a
    ld a,(cat_lives)
    call print_digit

    ld a,ROOM_NAME_X
    ld (txt_x),a
    ld a,(room_name)
    jp msg_small

update_hud
    ld a,(hud_dirty)
    or a
    ret z
    xor a
    ld (hud_dirty),a
    jp draw_hud

;; ---------------------------------------------------------------------------
;; score_add - A = a BCD byte added to the hundreds digit. The score is kept
;; as packed BCD, most significant byte first, so DAA does the arithmetic and
;; printing needs no division.
;; ---------------------------------------------------------------------------
score_add
    ld hl,score+1
    add a,(hl)
    daa
    ld (hl),a
    dec hl
    ld a,(hl)
    adc a,0
    daa
    ld (hl),a
    ret

;; ===========================================================================
;; Sausages
;; ===========================================================================

check_sausages
    ld a,(level_done)
    or a
    ret nz
    ld hl,(cur_saus)
    ld de,sausage_alive
    ld a,(cur_nsaus)
    ld b,a
check_sausages_loop
    push bc
    ld a,(de)
    or a
    jr z,check_sausages_next
    ld a,(hl)
    ld (saus_x),a
    inc hl
    ld a,(hl)
    ld (saus_y),a
    dec hl

    ld a,SPR_SAUSAGE_W
    ld (box_w),a
    ld a,SPR_SAUSAGE_H
    ld (box_h),a
    ld a,(saus_x)
    ld (box_x),a
    ld a,(saus_y)
    ld (box_y),a
    push hl
    push de
    call cat_hits_box
    pop de
    pop hl
    jr nc,check_sausages_next

    xor a
    ld (de),a                   ; eaten
    push hl
    push de
    call erase_sausage
    ld a,(sausages_got)
    inc a
    ld (sausages_got),a
    ld a,SAUSAGE_POINTS
    call score_add
    ld a,1
    ld (hud_dirty),a
    pop de
    pop hl

check_sausages_next
    inc hl
    inc hl
    inc de
    pop bc
    djnz check_sausages_loop

    ld a,(sausages_got)
    ld hl,cur_nsaus
    cp (hl)
    ret nz
    ld a,1
    ld (level_done),a
    jp draw_exit                ; the way out opens

;; ---------------------------------------------------------------------------
;; erase_sausage - paint over it. Sausages sit on the background above a
;; platform, never on one, so plain pen 0 is the right thing to leave behind.
;; ---------------------------------------------------------------------------
erase_sausage
    ld a,(saus_x)
    ld (fill_x),a
    ld hl,SPR_SAUSAGE_W
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld a,(saus_y)
    ld l,a
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ld de,SPR_SAUSAGE_H
    jp fill_rows

;; ---------------------------------------------------------------------------
;; cat_hits_box - carry set if the cat overlaps the box in box_x / box_y /
;; box_w / box_h. Sausages, enemies and the exit all come through here.
;; ---------------------------------------------------------------------------
cat_hits_box
    ld a,(box_x)
    ld b,a
    ld a,(box_w)
    add a,b
    dec a                       ; rightmost column of the box
    ld c,a
    ld a,(cat_x)
    cp c
    jr z,cat_hits_h2
    jr nc,cat_hits_no           ; cat starts past the right of it
cat_hits_h2
    ld a,(cat_x)
    ld b,a
    ld a,(cat_w)
    add a,b
    dec a                       ; rightmost column the cat covers
    ld b,a
    ld a,(box_x)
    cp b
    jr z,cat_hits_v
    jr nc,cat_hits_no

cat_hits_v
    ld a,(box_y)
    ld b,a
    ld a,(box_h)
    add a,b
    dec a
    ld c,a
    ld a,(cat_y)
    cp c
    jr z,cat_hits_v2
    jr nc,cat_hits_no
cat_hits_v2
    ld a,(cat_y)
    ld b,a
    ld a,(cat_h)
    add a,b
    dec a
    ld b,a
    ld a,(box_y)
    cp b
    jr z,cat_hits_yes
    jr nc,cat_hits_no
cat_hits_yes
    scf
    ret
cat_hits_no
    or a
    ret

;; ---------------------------------------------------------------------------
;; check_enemies - lose a life on contact, unless the grace period from the
;; last one is still running.
;; ---------------------------------------------------------------------------
check_enemies
    ld a,(cat_invul)
    or a
    jr z,check_enemies_scan
    dec a
    ld (cat_invul),a
    ret
check_enemies_scan
    call enemies_hit_cat
    ret nc
    ;; fall through

;; ---------------------------------------------------------------------------
;; cat_dies - one life gone. Back to the start of the room with a moment of
;; grace, or the end of the game.
;; ---------------------------------------------------------------------------
cat_dies
    ld a,(cat_lives)
    dec a
    ld (cat_lives),a
    ld c,a
    ld a,1
    ld (hud_dirty),a
    ld a,c
    or a
    jr z,cat_game_over

    ld hl,spr_cat_stand
    call cat_set_sprite
    ld a,(cat_startx)
    ld (cat_x),a
    ld a,(cat_starty)
    ld (cat_y),a
    xor a
    ld (cat_yf),a
    ld (cat_stun),a
    ld (cat_state),a
    ld hl,0
    ld (cat_vy),hl
    ld a,INVUL_FRAMES
    ld (cat_invul),a
    ret

cat_game_over
    ld a,1
    ld (game_over),a
    ld a,1
    ld (txt_xs),a
    ld a,WELLDONE_YS
    ld (txt_ys),a
    ld hl,line_tab+WELLDONE_Y*2
    ld (txt_row),hl
    ld a,MSG_GAMEOVER
    jp msg_big_centre

;; ===========================================================================
;; The cat
;; ===========================================================================

cat_update
    ld a,(cat_stun)
    or a
    jr z,cat_update_live
    dec a                       ; flat on the floor, no input
    ld (cat_stun),a
    ret
cat_update_live
    ld a,(cat_state)
    cp ST_ROLL
    jp z,cat_roll
    cp ST_GROUND
    jp z,cat_ground
    jp cat_air

;; ---------------------------------------------------------------------------
;; cat_ground - walking, rolling, jumping, or stepping off an edge.
;; ---------------------------------------------------------------------------
cat_ground
    ld a,WALK_STEP
    call cat_step_h

    ld a,(ctl_now)
    bit CTL_DOWN,a
    jr z,cat_ground_jump
    ld hl,spr_cat_roll          ; curl up
    call cat_set_sprite
    ld a,ST_ROLL
    ld (cat_state),a
    ret

cat_ground_jump
    ld a,(ctl_pressed)
    bit CTL_FIRE,a
    jr nz,cat_ground_leap
    bit CTL_UP,a
    jr z,cat_ground_support
cat_ground_leap
    ld hl,JUMP_V
    ld (cat_vy),hl
    ld a,ST_AIR
    ld (cat_state),a
    ld hl,spr_cat_stand
    jp cat_set_sprite

cat_ground_support
    call cat_has_support
    jr c,cat_ground_anim
    ld a,ST_AIR                 ; walked off the edge
    ld (cat_state),a
    ld hl,0
    ld (cat_vy),hl
    ret

cat_ground_anim
    ld a,(cat_moved)
    or a
    jr z,cat_ground_stand
    ld a,(cat_anim)
    inc a
    ld (cat_anim),a
    and WALK_BIT
    jr z,cat_ground_walk1
    ld hl,spr_cat_walk2
    jp cat_set_sprite
cat_ground_walk1
    ld hl,spr_cat_walk1
    jp cat_set_sprite
cat_ground_stand
    xor a
    ld (cat_anim),a
    ld hl,spr_cat_stand
    jp cat_set_sprite

;; ---------------------------------------------------------------------------
;; cat_roll - faster, and short enough to fit under things.
;; ---------------------------------------------------------------------------
cat_roll
    ld a,ROLL_STEP
    call cat_step_h

    ld a,(ctl_now)
    bit CTL_DOWN,a
    jr nz,cat_roll_support
    ld hl,spr_cat_stand         ; stand back up
    call cat_set_sprite
    xor a
    ld (cat_state),a            ; ST_GROUND
    ret

cat_roll_support
    call cat_has_support
    ret c
    ld a,ST_AIR
    ld (cat_state),a
    ld hl,0
    ld (cat_vy),hl
    ret

;; ---------------------------------------------------------------------------
;; cat_air - gravity, air control, the belly-flop, and landing.
;; ---------------------------------------------------------------------------
cat_air
    ld a,WALK_STEP
    call cat_step_h

    ld a,(cat_state)            ; Down plus fire commits to the belly
    cp ST_FLOP
    jr z,cat_air_gravity
    ld a,(ctl_now)
    bit CTL_DOWN,a
    jr z,cat_air_gravity
    ld a,(ctl_pressed)
    bit CTL_FIRE,a
    jr z,cat_air_gravity
    ld hl,FLOP_V
    ld (cat_vy),hl
    ld a,ST_FLOP
    ld (cat_state),a
    ld hl,spr_cat_flat
    call cat_set_sprite

cat_air_gravity
    ld hl,(cat_vy)
    ld de,GRAVITY
    add hl,de
    bit 7,h
    jr nz,cat_air_velocity      ; still rising
    ld de,MAX_FALL
    push hl
    or a
    sbc hl,de
    pop hl
    jr c,cat_air_velocity
    ld hl,MAX_FALL
cat_air_velocity
    ld (cat_vy),hl

    ld a,(cat_y)                ; remember where the feet were
    ld b,a
    ld a,(cat_h)
    add a,b
    ld (cat_ofeet),a

    ld hl,(cat_yf)              ; 8.8: L = fraction, H = scanline
    ld de,(cat_vy)
    add hl,de
    jr c,cat_air_moved          ; carry out, so no underflow
    bit 7,d
    jr z,cat_air_moved          ; DE was positive anyway
    ld hl,PLAY_TOP*256          ; rose past the top of the play area
    ld de,0
    ld (cat_vy),de
cat_air_moved
    ld (cat_yf),hl
    ld a,h
    cp PLAY_TOP
    jr nc,cat_air_land
    ld hl,PLAY_TOP*256
    ld (cat_yf),hl
    ld hl,0
    ld (cat_vy),hl

cat_air_land
    ld hl,(cat_vy)
    bit 7,h
    ret nz                      ; rising, so nothing to land on

    ld a,(cat_y)
    ld b,a
    ld a,(cat_h)
    add a,b
    ld (cat_nfeet),a
    call cat_find_landing
    ret nc

    ld b,a                      ; platform top
    ld a,(cat_h)
    ld c,a
    ld a,b
    sub c
    ld (cat_y),a
    xor a
    ld (cat_yf),a
    ld hl,0
    ld (cat_vy),hl

    ld a,(cat_state)
    cp ST_FLOP
    jr nz,cat_air_upright
    ld a,SHAKE_LEN              ; the whole room feels it
    ld (shake_timer),a
    ld a,FLOP_STUN
    ld (cat_stun),a
    ld a,ST_GROUND
    ld (cat_state),a
    jp enemies_stun
cat_air_upright
    ld a,ST_GROUND
    ld (cat_state),a
    ld hl,spr_cat_stand
    jp cat_set_sprite

;; ---------------------------------------------------------------------------
;; cat_step_h - A = steps of one byte. Sets cat_moved if anything happened.
;; ---------------------------------------------------------------------------
cat_step_h
    ld b,a
    xor a
    ld (cat_moved),a
cat_step_h_loop
    push bc
    call cat_step_one
    pop bc
    djnz cat_step_h_loop
    ret

cat_step_one
    ld a,(ctl_now)
    bit CTL_LEFT,a
    jr z,cat_step_one_right
    ld a,(cat_x)
    or a
    ret z
    dec a
    ld (cat_x),a
    ld a,1
    ld (cat_moved),a
    ret
cat_step_one_right
    ld a,(ctl_now)
    bit CTL_RIGHT,a
    ret z
    ld a,(cat_w)
    ld b,a
    ld a,BYTES_PER_LINE
    sub b                       ; rightmost column this sprite fits at
    ld b,a
    ld a,(cat_x)
    cp b
    ret nc
    inc a
    ld (cat_x),a
    ld a,1
    ld (cat_moved),a
    ret

;; ---------------------------------------------------------------------------
;; cat_set_sprite - HL = sprite. Keeps the feet where they are when the height
;; changes, so curling up and standing back up do not sink or hop.
;; ---------------------------------------------------------------------------
cat_set_sprite
    ld (cat_spr),hl
    ld a,(hl)
    ld (cat_w),a
    inc hl
    ld b,(hl)                   ; new height
    ld a,(cat_h)
    cp b
    jr z,cat_set_sprite_done
    sub b                       ; old - new, signed
    ld c,a
    ld a,(cat_y)
    add a,c
    ld (cat_y),a
cat_set_sprite_done
    ld a,b
    ld (cat_h),a
    ret

;; ---------------------------------------------------------------------------
;; cat_has_support - carry set if a platform is directly under the feet.
;; ---------------------------------------------------------------------------
cat_has_support
    ld a,(cat_y)
    ld b,a
    ld a,(cat_h)
    add a,b
    ld (cat_ofeet),a
    ld (cat_nfeet),a
    ;; fall through

;; ---------------------------------------------------------------------------
;; cat_find_landing - the highest platform whose top lies between where the
;; feet were and where they are now, and that the cat overlaps horizontally.
;; Carry set and A = its top scanline, or carry clear.
;; ---------------------------------------------------------------------------
cat_find_landing
    ld hl,(cur_plat)
    ld c,#FF                    ; best so far
cat_find_landing_loop
    ld a,(hl)
    inc a
    jr z,cat_find_landing_done
    dec a
    ld b,a                      ; first column
    inc hl
    ld a,(hl)                   ; last column
    inc hl
    ld e,(hl)                   ; top scanline
    inc hl
    push hl
    push bc
    push de
    call cat_overlap
    pop de
    pop bc
    pop hl
    jr nc,cat_find_landing_loop

    ld a,(cat_ofeet)
    cp e
    jr z,cat_find_landing_below
    jr nc,cat_find_landing_loop ; the feet were already past it
cat_find_landing_below
    ld a,(cat_nfeet)
    cp e
    jr c,cat_find_landing_loop  ; still above it
    ld a,e
    cp c
    jr nc,cat_find_landing_loop ; something higher already found
    ld c,a
    jr cat_find_landing_loop
cat_find_landing_done
    ld a,c
    inc a
    jr z,cat_find_landing_none
    ld a,c
    scf
    ret
cat_find_landing_none
    or a
    ret

;; ---------------------------------------------------------------------------
;; cat_overlap - B = first column, A = last column. Carry set if the cat
;; overlaps that span horizontally.
;; ---------------------------------------------------------------------------
cat_overlap
    ld c,a
    ld a,(cat_x)
    cp c
    jr z,cat_overlap_right
    jr nc,cat_overlap_none      ; starts past the right end
cat_overlap_right
    ld a,(cat_x)
    ld d,a
    ld a,(cat_w)
    add a,d
    dec a                       ; rightmost column the cat covers
    cp b
    jr c,cat_overlap_none       ; ends before the left end
    scf
    ret
cat_overlap_none
    or a
    ret

;; ---------------------------------------------------------------------------
;; cat_erase / cat_draw
;; ---------------------------------------------------------------------------
cat_erase
    ld a,(cat_drawn)
    or a
    ret z
    ld a,(cat_ow)
    ld (spr_w),a
    ld a,(cat_oh)
    ld (spr_h),a
    ld a,(cat_ox)
    ld (spr_x),a
    ld a,(cat_oy)
    call spr_row_ptr
    ld hl,cat_buf
    jp spr_restore

cat_draw
    ld hl,(cat_spr)
    call spr_size
    push hl                     ; the pixel data

    ld a,(spr_w)
    ld (cat_ow),a
    ld a,(spr_h)
    ld (cat_oh),a
    ld a,(cat_x)
    ld (spr_x),a
    ld (cat_ox),a
    ld a,(cat_y)
    ld (cat_oy),a

    call spr_row_ptr
    ld hl,cat_buf
    call spr_save

    ld a,(cat_y)
    call spr_row_ptr
    pop hl
    call spr_blit

    ld a,1
    ld (cat_drawn),a
    ret

;; ---------------------------------------------------------------------------
;; shake_update - the belly-flop jolt.
;;
;; R7 is the VSYNC position, so moving it slides the whole picture up or down
;; against the monitor without touching a byte of screen memory. It can only
;; go up from 34: below R6 the VSYNC would start inside the display. Shifting
;; R12/R13 instead would have been the obvious trick and is wrong here - the
;; screen base is chosen so the page 2 to page 3 crossing lands exactly on a
;; character row, and moving it scrambles the row where the pages meet.
;;
;; Untested on a real monitor: a CTM may take a frame to re-lock.
;; ---------------------------------------------------------------------------
shake_update
    ld a,(shake_timer)
    or a
    ret z
    dec a
    ld (shake_timer),a
    ld e,a
    ld d,0
    ld hl,shake_tab
    add hl,de
    ld a,(hl)
    add a,CRTC_R7
    ld e,a
    ld a,7
    jp crtc_set

shake_tab                       ; indexed by the timer counting down
    defb 0,1,1,2,2,1

;; ---------------------------------------------------------------------------
;; In-game palette, in loukoumas.md's own ink order: the sprite art is drawn
;; against it, so pen 2 has to be the fur.
;; ---------------------------------------------------------------------------
pal_play
    defb 0,   #40+4             ; pen 0 - deep navy: the wall, and inside furniture
    defb 1,   #40+7             ; pen 1 - coral: paws, nose, sausages, robots, text
    defb 2,   #40+10            ; pen 2 - butter yellow: fur, shelves, light
    defb 3,   #40+11            ; pen 3 - white: eyes, the floor, furniture outlines
    defb #10, #40+4
    defb #FF
