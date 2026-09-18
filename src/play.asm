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

;; HUD, in the twenty scanlines above the play area. A mode 0 cell is three
;; bytes, so a row holds 32 characters rather than the 48 mode 1 gave, and the
;; captions no longer fit beside the numbers on one line - so there are two.
;; The captions come from the string table, so the columns leave room for the
;; longer language: SCORE/ΣΚΟΡ, LIVES/ΖΩΕΣ, SAUSAGES/ΛΟΥΚΑΝΙΚΑ.
HUD_Y           EQU 2
HUD_ROW2        EQU HUD_Y+8
HUD_H           EQU 16
SCORE_LABEL_X   EQU 3
SCORE_X         EQU 21
LIVES_LABEL_X   EQU 48
LIVES_X         EQU 66
SAUS_LABEL_X    EQU 3
SAUS_COUNT_X    EQU 33
ROOM_NAME_X     EQU 48

SCORE_BYTES     EQU 3           ; six BCD digits
SAUSAGE_POINTS  EQU #01         ; BCD, added to the hundreds digit

WELLDONE_Y      EQU 40
BANNER_PAD      EQU 6           ; clear space above and below the message
WELLDONE_YS     EQU 3

LIVES_START     EQU 3
LIVES_MAX       EQU 5           ; the HUD has one digit, and five is generous
INVUL_FRAMES    EQU 100         ; two seconds of grace after a respawn

;; A saucer of milk, in every third room. Twenty-nine rooms on three lives is
;; not a game, it is an endurance test, so there is a way to earn them back -
;; but it is only ever one, it is always on the awkward shelf, and the room
;; still has five sausages to find whether the cat goes for it or not.
MILK_POINTS     EQU #05         ; BCD, into the hundreds digit
MILK_FLASH_LEN  EQU 12          ; frames the border flashes to say it counted
MILK_FLASH_COL  EQU 3           ; pale yellow, hardware colour 3

;; ---------------------------------------------------------------------------
;; play_screen - walk the flat, one room at a time. Returns on Escape.
;; ---------------------------------------------------------------------------
play_screen
    call sfx_init               ; whatever was playing when it ended stops here
    xor a
    ld (score),a
    ld (score+1),a
    ld (score+2),a
    ld (game_over),a
    ld a,LIVES_START
    ld (cat_lives),a
    ld a,STARTROOM              ; 0 in a real build; the tests start elsewhere
    ld (cur_room),a

play_room
    call room_load
    call sprites_order          ; a fresh room has nobody on the screen yet

;; The screen work comes first and the thinking comes after it, which is the
;; other way round from how it reads.
;;
;; wait_frame returns on the interrupt inside VSYNC, and there are forty
;; blanked scanlines - two and a half milliseconds - between that and the top
;; of the picture. Everything the beam is about to draw has to be back on the
;; screen before it gets there, and the only thing that decides whether it is
;; is what happens in those two and a half milliseconds and the microseconds
;; after. The erase runs bottom to top and fits inside the border; the draw
;; runs top to bottom from there and stays ahead of the beam all the way down.
;; Six milliseconds of keys, physics and collisions in front of that pushed
;; the whole thing a hundred scanlines into the picture, and the beam caught
;; the draw somewhere in the middle of the screen every single frame.
;;
;; The cost is that a sprite is drawn where it was worked out to be one frame
;; earlier. At fifty frames a second nobody can see that. The flicker it
;; replaces was unmissable.
play_loop
    call wait_render            ; two VSYNCs - the picture is rebuilt 25 times
                                ; a second, the game still thinks 50

    ld a,(game_over)
    or a
    jr nz,play_think            ; the cast has been lifted off the screen

    call sprites_update

;; The picture is on the screen and the beam is past it. Everything from here
;; down is for the next one.
play_think
    call read_controls
    ld a,(ctl_pressed)
    bit CTL_QUIT,a
    jr nz,play_quit

    ld a,(game_over)
    or a
    jr z,play_alive

    ld a,(ctl_pressed)          ; the banner is up: fire starts a new game, and
    bit CTL_FIRE,a              ; it has to be a press, so holding fire through
    jp nz,play_screen           ; the last life does not restart it at once
    jr play_over

play_alive
    ld b,FRAMES_PER_RENDER
play_step
    push bc
    call cat_update
    call enemies_update
    call check_sausages         ; what has been eaten is worked out here; the
                                ; hole it leaves is filled in by sprites_update
    call check_enemies
    call shake_update           ; both are 50 Hz timers, so they are stepped
    call flash_update           ; with the logic, not with the picture
    ld a,(game_over)            ; a robot may just have ended it
    or a
    jr nz,play_step_over
    call check_exit
    jr c,play_step_exit
    xor a
    ld (ctl_pressed),a          ; a key going down belongs to one step, not to
    pop bc                      ; both of them
    djnz play_step

    call update_hud             ; above the play area, so it is never in the way
    call sprites_order          ; who is where, before the clock starts running
    jr play_over

play_step_over
    pop bc
    jr play_over

play_step_exit
    pop bc
    ld a,(cur_room)             ; through the door
    inc a
    cp ROOM_COUNT
    jr nc,play_finished
    ld (cur_room),a
    jr play_room

play_finished
    ld a,1
    ld (game_over),a
    ld a,MSG_WELLDONE
    call big_banner
;; The sound is stepped here and not with the rest of the logic, because this
;; is the one place every path through a rendered frame goes past. The logic
;; steps are skipped once the game is over, and an effect that stops being
;; stepped never reaches its last frame - which is the frame that shuts the
;; channel up. The death effect would then hold its note for ever, which is
;; exactly what it did.
play_over
    ld b,FRAMES_PER_RENDER
play_over_sfx
    push bc
    call sfx_update
    pop bc
    djnz play_over_sfx
    jr play_loop

play_quit
    call sfx_init               ; nothing carries on into the menu
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
    ld a,(iy+R_MILKX)
    ld (milk_x),a
    ld a,(iy+R_MILKY)
    ld (milk_y),a
    ld a,(iy+R_PAL)
    ld (room_pal),a
    ld a,(iy+R_FLOOR)
    ld (room_floor),a

    xor a
    ld (draw_n),a               ; nothing on screen to unwind yet
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

    ld a,(milk_x)               ; 255 in the two rooms out of three that
    inc a                       ; have none
    jr z,room_load_nomilk
    ld a,1
room_load_nomilk
    ld (milk_alive),a
    xor a
    ld (milk_flash),a

    call set_room_pal

    ld hl,line_tab
    ld de,DISPLAY_LINES
    ld a,PEN0_BYTE
    call clear_rows

    call draw_props             ; scenery and furniture, everything else on top
    call draw_platforms
    call draw_exit
    call draw_sausages
    call draw_milk
    jp draw_hud

;; ---------------------------------------------------------------------------
;; set_room_pal - pal_play, then the one pen that makes a room what it is.
;;
;; Every room is lit by the same sixteen colours but one: pen 0, which is the
;; background and the border both, and is therefore the whole of the light in
;; a room. Navy is a wall at three in the morning and a garden before dawn,
;; sky blue is nine o'clock outside a school, black is a roof at midnight.
;; Nothing else moves, so the cat stays butter yellow and every piece of
;; furniture keeps the colour it was drawn in.
;; ---------------------------------------------------------------------------
set_room_pal
    ld hl,pal_play
    call set_pal
    ld a,(room_pal)
    add a,#40                   ; Gate Array: #40 + hardware colour
    ld e,a
    ld bc,#7F00                 ; pen 0
    out (c),c
    ld a,e
    out (c),a
    ld c,#10                    ; and the border with it
    out (c),c
    ld a,e
    out (c),a
    ret

;; ---------------------------------------------------------------------------
;; Furniture. A prop is a list of filled rectangles rather than a bitmap: at
;; the size furniture wants to be, masked sprites for a flat's worth came to
;; about 30 KB. Later boxes draw over earlier ones, so an outline is a white
;; box with a navy one inside it.
;; ---------------------------------------------------------------------------
pen_bytes
    defb PEN0_BYTE,  PEN1_BYTE,  PEN2_BYTE,  PEN3_BYTE
    defb PEN4_BYTE,  PEN5_BYTE,  PEN6_BYTE,  PEN7_BYTE
    defb PEN8_BYTE,  PEN9_BYTE,  PEN10_BYTE, PEN11_BYTE
    defb PEN12_BYTE, PEN13_BYTE, PEN14_BYTE, PEN15_BYTE

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
    bit 7,a
    jr z,draw_props_boxes
    and #7F                     ; a decal: scenery that is not a rectangle
    call draw_decal
    pop hl
    jr draw_props_loop
draw_props_boxes
    call prop_boxes_at
    call draw_boxes
    pop hl
    jr draw_props_loop

;; ---------------------------------------------------------------------------
;; draw_decal - A = decal id, painted at (prop_x),(prop_y).
;;
;; Furniture is boxes because boxes are almost free, and a fridge is a box.
;; A tree is not, and neither is a cloud, a slide or a street lamp, so the
;; scenery that has to curve is a bitmap after all - see tools/mkart.py.
;;
;; No mask: the room has just been cleared to pen 0 and these go down before
;; anything else, so ORing the picture on leaves pen 0 wherever the art is
;; transparent and the background shows through by itself. That is half the
;; bytes of a masked sprite, and the whole cost is paid once, when the room
;; loads - nothing here runs while the game is being played.
;; ---------------------------------------------------------------------------
draw_decal
    add a,a
    ld e,a
    ld d,0
    ld hl,decal_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                    ; HL = width, height, then the pixels
    ld a,(hl)
    inc hl
    ld (dec_w),a
    ld a,(hl)
    inc hl
    ld b,a                      ; rows to go
    ld a,(prop_y)
    ld c,a                      ; the scanline it is on
draw_decal_row
    push bc
    push hl
    ld l,c
    ld h,0
    add hl,hl
    ld de,line_tab
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,(prop_x)
    add a,e
    ld e,a
    jr nc,draw_decal_set
    inc d
draw_decal_set
    pop hl
    ld a,(dec_w)
    ld b,a
draw_decal_col
    ld a,(de)
    or (hl)
    ld (de),a
    inc hl
    inc de
    djnz draw_decal_col
    pop bc
    inc c
    ret z                       ; past scanline 255: the line table is indexed
                                ; by a byte here, the same limit draw_boxes
                                ; works to. The floor is at 236 and no scenery
                                ; hangs below it.
    djnz draw_decal_row
    ret

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
    ld a,(room_floor)           ; boards, grass, tarmac or a roof
    ld l,a
    ld h,0
    ld de,pen_bytes
    add hl,de
    ld a,(hl)
    ld hl,line_tab+FLOOR_Y*2
    ld de,FLOOR_H
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
;; draw_sausages - and, more to the point, keep what is behind each of them.
;;
;; A sausage used to be blitted down and rubbed out with pen 0 when it was
;; eaten, on the grounds that it stands on the background and never on a
;; platform. That is true of the platform and untrue of everything else: a
;; sausage on the crates, on the bus, up the tree or against a wall has
;; furniture behind it, and pen 0 through the middle of that is a hole - navy
;; indoors and sky blue out. So they save what they cover, exactly as the
;; sprites do, and put it back when they go.
;;
;; Six of them at four bytes by eight scanlines is 192 bytes, and it lives in
;; the low RAM above the tables where it costs nothing in the file.
;; ---------------------------------------------------------------------------
draw_sausages
    ld hl,PICK_BUFS
    ld (pick_bufp),hl
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
    ld de,(pick_bufp)
    call spr_draw               ; saves the background, then draws over it
    ld hl,(pick_bufp)
    ld de,PICK_BUF
    add hl,de
    ld (pick_bufp),hl
    pop hl
    pop bc
    djnz draw_sausages_loop
    ret

;; ---------------------------------------------------------------------------
;; draw_milk - the saucer, if this room has one. Blitted into the background
;; like a sausage, and like a sausage it is masked: it stands on a shelf.
;; ---------------------------------------------------------------------------
draw_milk
    ld a,(milk_alive)
    or a
    ret z
    ld a,(milk_x)
    ld (spr_x),a
    ld a,(milk_y)
    ld c,a
    ld hl,spr_milk
    call spr_size
    push hl
    ld a,c
    call spr_row_ptr
    pop hl
    ld de,milk_buf              ; and what it is standing on, to put back
    jp spr_draw

;; ---------------------------------------------------------------------------
;; flash_update - the border, for a moment, when a life comes back.
;;
;; The lives digit going from 3 to 4 in a corner of a two-row HUD is not
;; something anyone notices while they are being chased. The border is the
;; one thing on a CPC that can be changed in a single byte and cannot be
;; missed, and this game has 384 pixels of picture and no border left to
;; speak of - which makes the frame around it exactly the right place.
;; ---------------------------------------------------------------------------
flash_update
    ld a,(milk_flash)
    or a
    ret z
    dec a
    ld (milk_flash),a
    ld a,MILK_FLASH_COL
    jr nz,flash_set
    ld a,(room_pal)             ; done - back to whatever the room is lit by
flash_set
    add a,#40
    ld e,a
    ld bc,#7F10                 ; border
    out (c),c
    ld a,e
    out (c),a
    ret

;; ---------------------------------------------------------------------------
;; draw_hud - score, larder, lives and which room this is.
;; The captions sit on the background rather than a coloured band: a glyph
;; only sets pen bit 0, so text is invisible over pen 1 or pen 3.
;; ---------------------------------------------------------------------------
draw_hud
    xor a
    ld (txt_solid),a            ; the captions blend; the strip is cleared first
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab+HUD_Y*2
    ld de,HUD_H
    call fill_rows

    ;; --- first row: what the player has, and how long they keep it ---------
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

    ld a,LIVES_LABEL_X
    ld (txt_x),a
    ld a,MSG_LIVES
    call msg_small

    ld a,LIVES_X
    ld (txt_x),a
    ld a,(cat_lives)
    call print_digit

    ;; --- second row: what is left to find, and which room it is in ---------
    ld hl,line_tab+HUD_ROW2*2
    ld (txt_row),hl

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

    ld a,ROOM_NAME_X
    ld (txt_x),a
    ld a,(room_name)
    jp msg_small

;; Only the numbers move, so only the numbers are redrawn, and they are written
;; straight over where they stand. Repainting the whole strip meant clearing 96
;; bytes by 16 scanlines and laying the captions down again - about 9 ms, half
;; a frame, every time a sausage was collected. That was what pushed the frame
;; over and made the robots stutter, and it took the sprites with it.
update_hud
    ld a,(hud_dirty)
    or a
    ret z
    xor a
    ld (hud_dirty),a
    inc a
    ld (txt_solid),a

    ld hl,line_tab+HUD_Y*2
    ld (txt_row),hl
    ld a,SCORE_X
    ld (txt_x),a
    ld hl,score
    ld b,SCORE_BYTES
    call print_digits
    ld a,LIVES_X
    ld (txt_x),a
    ld a,(cat_lives)
    call print_digit

    ld hl,line_tab+HUD_ROW2*2
    ld (txt_row),hl
    ld a,SAUS_COUNT_X
    ld (txt_x),a
    ld a,(sausages_got)
    call print_digit
    ld a,GL_SLASH
    call print_glyph
    ld a,(cur_nsaus)
    call print_digit

    xor a
    ld (txt_solid),a
    ret

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
    call check_milk             ; before the early-out: the milk is still
    ld a,(level_done)           ; there to be had after the last sausage
    or a
    ret nz
    ld hl,PICK_BUFS
    ld (pick_bufp),hl
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
    ld a,SFX_EAT
    call sfx_play
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
    push hl
    ld hl,(pick_bufp)
    push de
    ld de,PICK_BUF
    add hl,de
    ld (pick_bufp),hl
    pop de
    pop hl
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
;; check_milk - a life back, up to five, and nothing else changes: the milk
;; is not one of the sausages and the way out does not wait for it.
;; ---------------------------------------------------------------------------
check_milk
    ld a,(milk_alive)
    or a
    ret z
    ld a,(milk_x)
    ld (box_x),a
    ld a,(milk_y)
    ld (box_y),a
    ld a,SPR_MILK_W
    ld (box_w),a
    ld a,SPR_MILK_H
    ld (box_h),a
    call cat_hits_box
    ret nc

    xor a
    ld (milk_alive),a
    call erase_milk
    ld a,(cat_lives)
    cp LIVES_MAX
    jr nc,check_milk_score      ; already full: it is worth points instead
    inc a
    ld (cat_lives),a
check_milk_score
    ld a,MILK_POINTS
    call score_add
    ld a,1
    ld (hud_dirty),a
    ld a,MILK_FLASH_LEN
    ld (milk_flash),a
    ret


;; ---------------------------------------------------------------------------
;; erase_sausage / erase_milk - put back what it was standing in front of.
;; ---------------------------------------------------------------------------
;; A pickup is not rubbed out where it is found. Working out what the cat has
;; eaten is a walk over every sausage in the room, and that walk has no
;; business inside the handful of scanlines the sprites are racing the beam
;; through - but the change to the background does, because it has to happen
;; while the cat is off the screen. So the check leaves a note here and
;; sprites_update acts on it.
;;
;; The saucer is the same four bytes by eight scanlines as a sausage, so one
;; note fits both.
    ASSERT SPR_MILK_W == SPR_SAUSAGE_W
    ASSERT SPR_MILK_H == SPR_SAUSAGE_H
PICK_PEND_MAX   EQU 4

erase_sausage
    ld a,(saus_x)
    ld b,a
    ld a,(saus_y)
    ld c,a
    ld hl,(pick_bufp)
    jr pick_defer

erase_milk
    ld a,(milk_x)
    ld b,a
    ld a,(milk_y)
    ld c,a
    ld hl,milk_buf
    ;; fall through

;; ---------------------------------------------------------------------------
;; pick_defer - B = x, C = y, HL = its saved background. Note one down.
;; Destroys AF, DE, HL.
;; ---------------------------------------------------------------------------
pick_defer
    push hl
    ld hl,pick_pend_n
    ld a,(hl)
    cp PICK_PEND_MAX
    jr nc,pick_defer_full
    inc (hl)
    add a,a
    add a,a                     ; four bytes a note
    ld e,a
    ld d,0
    ld hl,pick_pend
    add hl,de
    ld (hl),b
    inc hl
    ld (hl),c
    inc hl
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    ret
pick_defer_full
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; pickups_erase - act on the notes. Called with the cat off the screen.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
pickups_erase
    ld a,(pick_pend_n)
    or a
    ret z
    ld b,a
    xor a
    ld (pick_pend_n),a
    ld a,SPR_SAUSAGE_W
    ld (spr_w),a
    ld a,SPR_SAUSAGE_H
    ld (spr_h),a
    ld hl,pick_pend
pickups_erase_loop
    push bc
    ld a,(hl)
    ld (spr_x),a
    inc hl
    ld c,(hl)                   ; the scanline it sat on
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    push de                     ; spr_row_ptr is about to want DE and HL
    ld a,c
    call spr_row_ptr
    pop hl
    call spr_restore
    pop hl
    pop bc
    djnz pickups_erase_loop
    ret

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
    ld a,SFX_DIE
    call sfx_play
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
    ld a,MSG_GAMEOVER
    ;; fall through

;; ---------------------------------------------------------------------------
;; big_banner - A = message id. Lifts the sprites off, clears a band right
;; across the screen and puts the message in it.
;;
;; Big text ORs itself onto whatever is underneath, which sets pen bit 0 and
;; leaves the other three pen bits alone. Over the navy background that makes
;; coral and reads perfectly, and on the title screen, where the only other
;; pen is 2, it is the whole trick that lets the letters cross the bands. Over
;; a pen that already has bit 0 set it changes nothing at all - and eight of
;; the sixteen do, now that the rooms are furnished in colour. The game ends
;; on a room full of furniture, so the band is cleared rather than trusted.
;;
;; The sprites come off first and stay off: their saved backgrounds are from
;; before the banner, so leaving them to erase themselves next frame would
;; punch a cat-shaped and a canary-shaped hole straight through it.
;; ---------------------------------------------------------------------------
big_banner
    push af
    call update_hud             ; the life that just went still has to show
    call sprites_erase
    xor a
    ld (draw_n),a
    ld (fill_x),a
    ld hl,BYTES_PER_LINE
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab+(WELLDONE_Y-BANNER_PAD)*2
    ld de,WELLDONE_YS*8+BANNER_PAD*2
    call fill_rows
    ld a,1
    ld (txt_xs),a
    ld a,WELLDONE_YS
    ld (txt_ys),a
    ld hl,line_tab+WELLDONE_Y*2
    ld (txt_row),hl
    pop af
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
    ld a,SFX_JUMP
    call sfx_play
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
    ld a,SFX_FLOP
    call sfx_play
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

    call spr_row_ptr            ; A is still cat_y
    ld de,cat_buf
    pop hl                      ; the pixel data
    call spr_draw

    ld a,1
    ld (cat_drawn),a
    ret

;; ===========================================================================
;; Laying the sprites down in the order the beam will meet them.
;;
;; There is no double buffer, so every sprite is erased and then redrawn, and
;; the CRTC is reading the screen the whole time it is missing. The frame tick
;; is phase-locked to VSYNC and the display has 40 blanked scanlines after it -
;; about 2.5 ms - while the sprite work is five times that: the cat alone is
;; 144 bytes to restore, 144 to save and 144 to blit, and a masked blit costs
;; something like 18 us a byte against 6 for an LDIR.
;;
;; So the sprites cannot all be finished before the picture starts. What they
;; can be is finished before the beam reaches each of them, and that only
;; needs them done in the order it meets them: topmost first. Drawn that way
;; every sprite has the whole of its own depth down the screen to be redrawn
;; in, and the one with the least time - the canary, which flies near the top -
;; is also the smallest. Drawn the other way round, which is what the fixed
;; order did, the canary was redrawn about 4 ms after the beam had already
;; passed it, and it flickered every frame it moved.
;;
;; Erasing has to unwind in the exact reverse of the order things were drawn,
;; so it runs from the bottom of the screen up, over the order that was
;; actually used last frame rather than a freshly computed one.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; enemy_ptr - A = enemy index -> IY = its record, e_bufp = its save buffer.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
enemy_ptr
    ld iy,enemies
    ld hl,enemy_bufs
    or a
    jr z,enemy_ptr_done
    ld b,a
enemy_ptr_step
    ld de,E_SIZE
    add iy,de
    ld de,ENEMY_BUF
    add hl,de
    djnz enemy_ptr_step
enemy_ptr_done
    ld (e_bufp),hl
    ret

;; ---------------------------------------------------------------------------
;; sprite_erase_id / sprite_draw_id - A = id. 0 is the cat, anything else is
;; an enemy index plus one.
;; ---------------------------------------------------------------------------
sprite_erase_id
    or a
    jp z,cat_erase
    dec a
    call enemy_ptr
    ld a,(iy+E_DRAWN)
    or a
    ret z
    jp enemy_erase_one

sprite_draw_id
    or a
    jp z,cat_draw
    dec a
    call enemy_ptr
    ld a,(iy+E_TYPE)
    or a
    ret z
    jp enemy_draw_one

;; ---------------------------------------------------------------------------
;; ord_add - A = scanline, C = id. Appends one sprite to the list.
;; Destroys DE, HL.
;; ---------------------------------------------------------------------------
ord_add
    ld hl,ord_n
    ld e,(hl)
    inc (hl)
    ld d,0
    ld hl,ord_y
    add hl,de
    ld (hl),a
    ld hl,draw_order
    add hl,de
    ld (hl),c
    ret

;; ---------------------------------------------------------------------------
;; sprites_order - fill draw_order with what is on screen, topmost first.
;; Destroys AF, BC, DE, HL, IY.
;; ---------------------------------------------------------------------------
sprites_order
    xor a
    ld (ord_n),a

    ld a,(cat_y)                ; the cat is always there
    ld c,0
    call ord_add

    ld iy,enemies
    ld b,ENEMY_COUNT
    ld c,1
sprites_order_loop
    push bc
    ld a,(iy+E_TYPE)
    or a
    jr z,sprites_order_next
    ld a,(iy+E_Y)
    call ord_add
sprites_order_next
    ld de,E_SIZE
    add iy,de
    pop bc
    inc c
    djnz sprites_order_loop
    ;; fall through

;; Four entries at most, so the simplest sort that works is also the one that
;; is quickest to read.
ord_sort
    ld a,(ord_n)
    cp 2
    ret c
    dec a
    ld b,a
ord_sort_pass
    push bc
    ld a,(ord_n)
    dec a
    ld b,a
    ld hl,ord_y
    ld de,draw_order
ord_sort_cmp
    ld a,(hl)
    inc hl
    cp (hl)
    jr c,ord_sort_next
    jr z,ord_sort_next
    ld c,(hl)                   ; swap the pair, in both lists at once
    dec hl
    ld a,(hl)
    ld (hl),c
    inc hl
    ld (hl),a
    ex de,hl
    ld a,(hl)
    inc hl
    ld c,(hl)
    ld (hl),a
    dec hl
    ld (hl),c
    ex de,hl
ord_sort_next
    inc de
    djnz ord_sort_cmp
    pop bc
    djnz ord_sort_pass
    ret

;; ---------------------------------------------------------------------------
;; sprites_erase - unwind last frame's picture, bottom of the screen first.
;; ---------------------------------------------------------------------------
sprites_erase
    ld a,(draw_n)
    or a
    ret z
    ld b,a
    ld e,a
    ld d,0
    ld hl,draw_order
    add hl,de
    dec hl                      ; the last one that was laid down
sprites_erase_loop
    push bc
    push hl
    ld a,(hl)
    call sprite_erase_id
    pop hl
    dec hl
    pop bc
    djnz sprites_erase_loop
    ret

;; ---------------------------------------------------------------------------
;; sprites_update - lift each sprite off and put it straight back, one at a
;; time, from the top of the screen down.
;;
;; The frame tick arrives thirty-eight scanlines before the picture does, and
;; the beam reaches scanline y another 64y microseconds after that. Erasing
;; everything and then drawing everything leaves every sprite off the screen
;; for the whole gap between the two passes - with this cast the erase alone
;; is seventy scanlines and the draw a hundred and forty - and the beam walks
;; through the middle of that every single frame. Whichever interrupt the
;; frame was started on only moved which part of the screen it happened to.
;;
;; Doing one sprite at a time closes the gap to that sprite's own erase and
;; draw, and going from the top of the screen down spends the head start on
;; the sprite that has the least of it: the beam gets to the top first.
;; tools/z80check.py --beam is what says whether each one made it.
;;
;; The cost is that two sprites which overlap can take a bite out of each
;; other for a frame - the lower one's erase puts back a background captured
;; before the upper one was drawn. Overlapping in this game means the cat has
;; just been caught, which costs a life and moves it anyway.
;; ---------------------------------------------------------------------------
sprites_update
    ld a,(ord_n)                ; sprites_order ran at the end of the thinking,
    ld (draw_n),a               ; where it costs the beam nothing
    or a
    ret z
    ld b,a
    ld hl,draw_order
sprites_update_loop
    push bc
    push hl
    ld a,(hl)
    or a
    jr nz,sprites_update_enemy

    call cat_erase
    call pickups_erase          ; while the cat is off the screen and before it
                                ; saves what it is standing on again: that is
                                ; the only moment the background may change
    call cat_draw
    jr sprites_update_next

sprites_update_enemy
    dec a
    call enemy_ptr              ; once, where it used to be worked out three
    ld a,(iy+E_TYPE)            ; times over for the same enemy
    or a
    jr z,sprites_update_next
    call enemy_moved
    jr z,sprites_update_next    ; already where it belongs, facing the way it
                                ; was facing - leave it alone
    call enemy_erase_one
    call enemy_draw_one

sprites_update_next
    pop hl
    inc hl
    pop bc
    djnz sprites_update_loop
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
    ;; Sixteen pens. The first four are the ones the game was built in and keep
    ;; their meaning, so everything drawn before mode 0 still reads the same;
    ;; the twelve after them are what mode 0 bought, and are what the rooms get
    ;; painted with. Hardware colour numbers, not firmware INK numbers.
    defb 0,   #40+4             ; deep navy: the wall, and inside furniture
    defb 1,   #40+7             ; coral: paws, nose, sausages, text
    defb 2,   #40+10            ; butter yellow: fur, light, brass
    defb 3,   #40+11            ; white: eyes, the floor, furniture outlines
    defb 4,   #40+20            ; black: shadow, pupils, the back of a cupboard
    defb 5,   #40+0             ; grey: steel - shelving, the car, appliances
    defb 6,   #40+30            ; olive: wood in shadow
    defb 7,   #40+14            ; orange: wood in the light, brick, rust
    defb 8,   #40+22            ; dark green: leaves, painted metal
    defb 9,   #40+18            ; bright green: grass, new growth
    defb 10,  #40+6             ; teal: deep water, glazed tile
    defb 11,  #40+19            ; bright cyan: water, glass, porcelain
    defb 12,  #40+28            ; dark red: the robots' bodies
    defb 13,  #40+12            ; bright red: hobs, warning lamps, danger
    defb 14,  #40+24            ; purple: night through a window, the wardrobe
    defb 15,  #40+3             ; pale yellow: lamplight
    defb #10, #40+4             ; border - navy, blends into the picture
    defb #FF
