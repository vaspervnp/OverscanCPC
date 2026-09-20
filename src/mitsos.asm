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
SOAP_H          EQU 10                  ; how deep a puddle of it looks

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

;; --- Weight ----------------------------------------------------------------
;; He does not start and stop, he gets going and then goes on going, which is
;; the one thing the design document is insistent about: he is overweight.
;; Sideways position and velocity are 8.8 fixed point like the vertical ones,
;; so a frame can move him a fraction of a byte and the fractions add up.
;;
;; Top speed is what a step used to be - one byte, four pixels a frame - and
;; it takes eight frames to get there and a bit over ten to lose it. On soap
;; he can barely push at all and nothing slows him down, so the only thing
;; that stops him is a wall.
VX_MAX          EQU #0100               ; 1 byte a frame
VX_ACCEL        EQU #0020               ; eight frames to reach it
VX_BRAKE        EQU #0018               ; and eleven to lose it
VX_SOAP         EQU #0008               ; what a paw can do on wet tiles

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

;; --- The belly bounce ------------------------------------------------------
;; Landing on something that moves, from above and falling, flattens it and
;; throws him back up higher than his own jump can reach - which is how a
;; board out of reach of the floor gets reached. It is the mechanic the game
;; is built round, so it is worth more than a jump and costs a mouse two
;; seconds on its back.
BOUNCE_V        EQU #FA80               ; -5.5 px/frame, about 60 scanlines
STUN_TIME       EQU 100                 ; two seconds flat, at 50 Hz
FOE_TICK        EQU 3                   ; frames between an enemy's steps
FOE_ANIM        EQU 6                   ; and between its two pictures
FOE_COUNT       EQU 3

;; One enemy. IY addresses these, because IX is the line table cursor inside
;; the sprite routines and there is only one of each.
E_KIND          EQU 0                   ; index into foe_kinds
E_X             EQU 1                   ; where it is, in bytes
E_Y             EQU 2                   ; and scanlines
E_Y0            EQU 3                   ; the line a flier bobs about
E_X0            EQU 4                   ; the ends of its beat
E_X1            EQU 5
E_DIR           EQU 6                   ; 1 or -1
E_TICK          EQU 7                   ; frames until its next step
E_FRAME         EQU 8                   ; which of its two pictures
E_ANIM          EQU 9                   ; frames until the other one
E_STUN          EQU 10                  ; frames left flat on its back
E_PHASE         EQU 11                  ; where it is in the bob
E_DRAWN         EQU 12                  ; is the buffer under it worth anything
E_OX            EQU 13                  ; and where its picture still is
E_OY            EQU 14
E_SIZE          EQU 15

;; What a kind of enemy is: two pictures each way round, a size, and whether
;; it flies. Three bytes and its art is what a new one costs.
K_SPR           EQU 0                   ; four words: A and B, right then left
K_W             EQU 8
K_H             EQU 9
K_FLY           EQU 10
K_SIZE          EQU 11

K_BROOM         EQU 0
K_MOUSE         EQU 1
K_GULL          EQU 2

FOE_BUF         EQU SPR_BROOM_A_W*SPR_BROOM_A_H  ; the biggest of them

;; --- Lives -----------------------------------------------------------------
;; Three, and two seconds of grace after each one goes: walking back into the
;; broom on the frame he reappears would be a way of losing all three without
;; touching a key. He blinks while it lasts, which is the only way anyone can
;; tell.
START_LIVES     EQU 3
GRACE           EQU 100                 ; frames, at the 50 Hz the game thinks

;; The HUD is one row of small text across the top of the wall, above
;; everything the game does - SHOP_TOP is the ceiling and it is below this.
HUD_Y           EQU 2
HUD_H           EQU 10

;; And the panel that goes up when they run out.
OVER_Y          EQU 96
OVER_H          EQU 56
OVER_SCALE      EQU 5                   ; scanlines per source row: 40 tall
LIVES_LABEL_X   EQU 3
LIVES_X         EQU 21

;; Which string table it starts on. L switches it while it runs, and only the
;; text is repainted - the shop does not know what language it is in.
    IFNDEF LANG
LANG            EQU 0
    ENDIF

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

    ld a,LANG
    ld (txt_lang),a
    ld a,START_LIVES
    ld (mitsos_lives),a
    call game_start

;; ---------------------------------------------------------------------------
;; One pass per 50 Hz frame: read the keys, move him, lift him off the floor
;; and put him back down where he now is.
;; ---------------------------------------------------------------------------
;; ---------------------------------------------------------------------------
;; The picture is rebuilt twenty-five times a second and the game thinks
;; fifty, which is FRAMES_PER_RENDER logic steps inside one picture. Nothing
;; about the jump arc or the beat of a patrol changes - they are still counted
;; in 50 Hz steps - only how often the cast is lifted off the screen and put
;; back. Lifting this lot off is ten milliseconds and a frame is twenty, of
;; which two and a half are blanked: at twice the budget it is finished long
;; before the beam comes round again.
;; ---------------------------------------------------------------------------
main_loop
    call wait_render                    ; two ticks of irq.asm's 50 Hz
    call read_controls                  ; the matrix, folded into ctl_now

    ld a,(ctl_pressed)                  ; L, in either screen
    bit CTL_LANG,a
    call nz,switch_language

    ld a,(mitsos_over)
    or a
    jr nz,main_over

;; Everything comes off the screen before anything goes back on it. One at a
;; time would keep each of them off for less of the frame, but then a save
;; can catch another sprite's picture instead of the shop and hand it back
;; where nothing will ever erase it again. With the whole cast lifted first,
;; every save is of the shop and nothing else, and the room stays clean.
    call mitsos_erase
    call foes_erase

    ld b,FRAMES_PER_RENDER
main_loop_think
    push bc
    call mitsos_move
    call foes_move
    pop bc
    djnz main_loop_think

    call foes_draw
    call mitsos_draw                    ; last, so he is the one in front
    jr main_loop

;; Out of lives: the shop stands where it stopped with GAME OVER across it,
;; and fire puts the whole thing back.
main_over
    ld a,(ctl_pressed)
    bit CTL_FIRE,a
    jr z,main_loop
    ld a,START_LIVES
    ld (mitsos_lives),a
    call game_start
    jr main_loop

;; ---------------------------------------------------------------------------
;; game_start - the shop as it was and everybody back where they came in.
;; Destroys everything.
;; ---------------------------------------------------------------------------
game_start
    call draw_shop
    call draw_hud

    ld hl,foes_init                     ; the cast, unflattened and back on
    ld de,foes                          ; their marks
    ld bc,FOE_COUNT*E_SIZE
    ldir

    xor a
    ld (mitsos_over),a
    ld (mitsos_grace),a
    ld (mitsos_drawn),a
    ;; fall through

;; ---------------------------------------------------------------------------
;; mitsos_spawn - him, on the floor by the door, facing the shop.
;; Destroys AF, HL.
;; ---------------------------------------------------------------------------
mitsos_spawn
    ld a,8
    ld (mitsos_x),a
    ld a,MITSOS_Y0
    ld (mitsos_y),a
    xor a
    ld (mitsos_xf),a
    ld (mitsos_yf),a
    ld (mitsos_face),a
    ld (mitsos_tick),a
    ld (mitsos_frame),a
    ld (mitsos_state),a                 ; ST_GROUND
    ld hl,0
    ld (mitsos_vx),hl
    ld (mitsos_vy),hl
    ret

;; ---------------------------------------------------------------------------
;; switch_language - L, and only the words are repainted.
;; Destroys everything.
;; ---------------------------------------------------------------------------
switch_language
    ld a,(txt_lang)
    xor 1
    ld (txt_lang),a
    call draw_hud
    ld a,(mitsos_over)
    or a
    ret z
    jp draw_over                        ; the panel is words too

;; ---------------------------------------------------------------------------
;; draw_hud - the strip along the top. Cleared first, because small text
;; blends rather than overwrites and brick would show through it.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_hud
    ld hl,line_tab+HUD_Y*2
    ld de,HUD_H
    ld a,PEN0_BYTE
    call clear_rows

    ld hl,line_tab+(HUD_Y+1)*2
    ld (txt_row),hl
    ld a,LIVES_LABEL_X
    ld (txt_x),a
    ld a,MSG_LIVES
    call msg_small
    ;; fall through

;; ---------------------------------------------------------------------------
;; draw_lives - just the digit. It is written solid, so it goes straight over
;; the one that was there without clearing anything.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_lives
    ld hl,line_tab+(HUD_Y+1)*2
    ld (txt_row),hl
    ld a,LIVES_X
    ld (txt_x),a
    ld a,1
    ld (txt_solid),a
    ld a,(mitsos_lives)
    call print_digit
    xor a
    ld (txt_solid),a
    ret

;; ---------------------------------------------------------------------------
;; draw_over - GAME OVER across the middle of the shop, and how to start
;; again under it. The ground is cleared first: big text writes where the
;; letter is and skips where it is not, and small text blends.
;; Destroys everything.
;; ---------------------------------------------------------------------------
draw_over
    ld hl,line_tab+OVER_Y*2
    ld de,OVER_H
    ld a,PEN0_BYTE
    call clear_rows

    ld a,1
    ld (txt_xs),a                       ; 24 pixels to a letter
    ld a,OVER_SCALE
    ld (txt_ys),a
    ld a,PEN13_BYTE                     ; in red, which nothing else here is
    ld (txt_big_pen),a
    ld a,1
    ld (txt_big_solid),a
    ld hl,line_tab+(OVER_Y+4)*2
    ld (txt_row),hl
    ld a,MSG_GAMEOVER
    call msg_big_centre

    ld hl,line_tab+(OVER_Y+OVER_H-10)*2
    ld (txt_row),hl
    ld a,MSG_AGAIN
    jp msg_small_centre

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
    call mitsos_walk
    ld a,(mitsos_state)
    or a
    call z,mitsos_ground
    ld a,(mitsos_state)
    or a
    call nz,mitsos_air

    ld hl,mitsos_grace                  ; the blinking runs itself down
    ld a,(hl)
    or a
    jp z,mitsos_hurt
    dec (hl)
    ret

;; ---------------------------------------------------------------------------
;; mitsos_walk - left and right push, they do not place.
;;
;; A key adds to his sideways velocity and letting go takes it away again, so
;; he leans into a walk and slides out of it. How hard each of those is
;; depends on what he is standing on: on soap the push is a quarter of what it
;; was and there is nothing at all taking it away, which is what makes a
;; soapy floor a floor you have to plan for rather than walk across.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_walk
    call mitsos_slippery
    ld de,VX_SOAP                       ; what he can push with, and
    ld bc,0                             ; what the floor takes back
    jr c,mitsos_walk_keys
    ld de,VX_ACCEL
    ld a,(mitsos_state)
    or a
    jr nz,mitsos_walk_keys              ; in the air nothing is rubbing
    ld bc,VX_BRAKE

mitsos_walk_keys
    ld a,(ctl_now)
    bit CTL_LEFT,a
    jr nz,mitsos_walk_left
    bit CTL_RIGHT,a
    jr nz,mitsos_walk_right

    ld d,b                              ; nothing held: the floor does the rest
    ld e,c
    call mitsos_vx_brake
    jr mitsos_walk_move

mitsos_walk_left
    ld a,FACE_LEFT
    ld (mitsos_face),a
    ld a,d                              ; -DE, the other way
    cpl
    ld d,a
    ld a,e
    cpl
    ld e,a
    inc de
    call mitsos_vx_push
    jr mitsos_walk_move

mitsos_walk_right
    xor a
    ld (mitsos_face),a
    call mitsos_vx_push

;; Move him by whatever that came to, and stop dead at either wall - which on
;; soap is the only thing that does stop him.
mitsos_walk_move
    ld hl,(mitsos_xf)
    ld de,(mitsos_vx)
    add hl,de
    jr c,mitsos_walk_moved              ; carry out, so no underflow
    bit 7,d
    jr z,mitsos_walk_moved              ; DE was positive anyway
    ld hl,0                             ; into the left wall
    ld (mitsos_vx),hl
mitsos_walk_moved
    ld a,h
    cp MITSOS_XMAX+1
    jr c,mitsos_walk_store
    ld hl,MITSOS_XMAX*256               ; and into the right one
    push hl
    ld hl,0
    ld (mitsos_vx),hl
    pop hl
mitsos_walk_store
    ld (mitsos_xf),hl

;; The waddle runs while he is moving at all, however he came to be moving.
    ld hl,(mitsos_vx)
    ld a,h
    or l
    jr nz,mitsos_walk_anim
    xor a                               ; stopped: legs together, and the
    ld (mitsos_tick),a                  ; counter back to the top so the first
    ld (mitsos_frame),a                 ; step out is always the same one
    ret

mitsos_walk_anim
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
;; mitsos_vx_push - add DE to his sideways velocity, held to VX_MAX either way.
;; Destroys AF, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_vx_push
    ld hl,(mitsos_vx)
    add hl,de
    bit 7,h
    jr nz,mitsos_vx_push_left
    ld de,VX_MAX
    or a
    sbc hl,de
    add hl,de
    jr c,mitsos_vx_store                ; under it
    ld hl,VX_MAX
    jr mitsos_vx_store
mitsos_vx_push_left
    ld de,-VX_MAX
    or a
    sbc hl,de
    add hl,de
    jr nc,mitsos_vx_store               ; over it
    ld hl,-VX_MAX
mitsos_vx_store
    ld (mitsos_vx),hl
    ret

;; ---------------------------------------------------------------------------
;; mitsos_vx_brake - take DE off his velocity, towards standing still and no
;; further. DE of zero is soap, and does nothing at all.
;; Destroys AF, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_vx_brake
    ld a,d
    or e
    ret z
    ld hl,(mitsos_vx)
    ld a,h
    or l
    ret z
    bit 7,h
    jr nz,mitsos_vx_brake_left
    or a
    sbc hl,de
    jr nc,mitsos_vx_store               ; still going right
    ld hl,0
    jr mitsos_vx_store
mitsos_vx_brake_left
    add hl,de
    bit 7,h
    jr nz,mitsos_vx_store               ; still going left
    ld hl,0
    jr mitsos_vx_store

;; ---------------------------------------------------------------------------
;; mitsos_slippery - carry set if the tiles he is standing on have been
;; mopped and not rinsed. In the air, nothing is underfoot and nothing is
;; slippery.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
mitsos_slippery
    ld a,(mitsos_state)
    or a
    ret nz
    ld a,(mitsos_y)
    add a,MITSOS_H
    ld b,a                              ; his feet
    ld hl,shop_soap
mitsos_slippery_loop
    ld a,(hl)
    inc a
    jr z,mitsos_slippery_no
    dec a
    ld c,a                              ; first column
    inc hl
    ld a,(hl)                           ; last column
    inc hl
    ld e,(hl)                           ; the surface it is on
    inc hl
    push hl
    push bc
    push de
    ld b,c
    call mitsos_overlap
    pop de
    pop bc
    pop hl
    jr nc,mitsos_slippery_loop
    ld a,b
    cp e
    jr nz,mitsos_slippery_loop
    scf
    ret
mitsos_slippery_no
    or a
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

    call mitsos_bounce                  ; anything alive under him first
    ret c

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
;; mitsos_hurt - anything he is standing in that is still on its feet.
;;
;; A plain rectangle overlap, which is the other half of the belly bounce:
;; come down on one and it goes flat, walk into one and it costs a life.
;; Something already flat is scenery and cannot hurt anybody.
;; Destroys AF, BC, DE, HL, IY.
;; ---------------------------------------------------------------------------
mitsos_hurt
    ld a,(mitsos_grace)                 ; still blinking from the last one
    or a
    ret nz

    ld iy,foes
    ld b,FOE_COUNT
mitsos_hurt_one
    push bc
    ld a,(iy+E_STUN)
    or a
    jr nz,mitsos_hurt_next              ; flat on its back, and harmless

    call foe_kind_ptr
    ld a,K_W
    call foe_kind_byte
    ld b,(iy+E_X)
    dec a
    add a,b                             ; the columns it covers
    call mitsos_overlap
    jr nc,mitsos_hurt_next

    ld a,K_H                            ; and the scanlines
    call foe_kind_byte
    ld b,(iy+E_Y)
    dec a
    add a,b
    ld c,a                              ; C = its bottom
    ld a,(mitsos_y)                     ; his top past its bottom?
    cp c
    jr z,mitsos_hurt_rows
    jr nc,mitsos_hurt_next
mitsos_hurt_rows
    ld a,(mitsos_y)
    add a,MITSOS_H-1                    ; his bottom short of its top?
    cp (iy+E_Y)
    jr c,mitsos_hurt_next

    pop bc
    ;; fall through

;; ---------------------------------------------------------------------------
;; mitsos_lose - one gone. Back to the door with two seconds of grace, or the
;; end of it if that was the last.
;; Destroys everything.
;; ---------------------------------------------------------------------------
mitsos_lose
    ld hl,mitsos_lives
    ld a,(hl)
    or a
    jr z,mitsos_lose_over
    dec (hl)
    call draw_lives
    ld a,(mitsos_lives)
    or a
    jr z,mitsos_lose_over
    call mitsos_spawn
    ld a,GRACE
    ld (mitsos_grace),a
    ret

mitsos_lose_over
    ld a,1
    ld (mitsos_over),a
    jp draw_over

mitsos_hurt_next
    pop bc
    ld de,E_SIZE
    add iy,de
    djnz mitsos_hurt_one
    ret

;; ---------------------------------------------------------------------------
;; mitsos_bounce - did his feet come down on something that moves?
;;
;; The same test the shelves get - was the top of it between where his feet
;; were and where they are now, and is he over it at all - except that what
;; it lands on goes flat for two seconds and he comes off it higher than he
;; went on. Carry set if it happened, and then nothing else catches him this
;; step.
;; Destroys AF, BC, DE, HL, IY.
;; ---------------------------------------------------------------------------
mitsos_bounce
    ld iy,foes
    ld b,FOE_COUNT
mitsos_bounce_one
    push bc
    ld a,(mitsos_ofeet)
    cp (iy+E_Y)
    jr z,mitsos_bounce_below
    jr nc,mitsos_bounce_next            ; his feet were already past it
mitsos_bounce_below
    ld a,(mitsos_nfeet)
    cp (iy+E_Y)
    jr c,mitsos_bounce_next             ; and still are not down to it

    call foe_kind_ptr                   ; HL = its kind, for the width
    ld a,K_W
    call foe_kind_byte
    ld c,a
    ld b,(iy+E_X)
    dec a
    add a,b                             ; last column it covers
    call mitsos_overlap
    jr nc,mitsos_bounce_next

    ld (iy+E_STUN),STUN_TIME            ; flat on its back, and harmless
    ld hl,BOUNCE_V
    ld (mitsos_vy),hl
    pop bc
    scf
    ret
mitsos_bounce_next
    pop bc
    ld de,E_SIZE
    add iy,de
    djnz mitsos_bounce_one
    or a
    ret

;; ---------------------------------------------------------------------------
;; foe_kind_ptr - HL = the kind record of the enemy at IY.
;; foe_kind_byte - A = an offset into it -> A = that byte of it. HL survives.
;; Destroys AF, DE.
;; ---------------------------------------------------------------------------
foe_kind_ptr
    push bc
    ld a,(iy+E_KIND)
    ld b,a
    add a,a
    add a,a
    add a,a                             ; x8
    add a,b
    add a,b
    add a,b                             ; and three more makes x11, which is
                                        ; K_SIZE - one multiply nobody misses
    ld l,a
    ld h,0
    ld de,foe_kinds
    add hl,de
    pop bc
    ret

foe_kind_byte
    push hl
    ld e,a
    ld d,0
    add hl,de
    ld a,(hl)
    pop hl
    ret

;; ---------------------------------------------------------------------------
;; foes_erase - the cast, off the screen in the reverse of the order it went
;; on. An enemy that has never been drawn has nothing under it worth keeping.
;; Destroys AF, BC, DE, HL, IX, IY.
;; ---------------------------------------------------------------------------
foes_erase
    ld iy,foes+(FOE_COUNT-1)*E_SIZE
    ld hl,foe_bufs+(FOE_COUNT-1)*FOE_BUF
    ld b,FOE_COUNT
foes_erase_one
    push bc
    push hl
    ld a,(iy+E_DRAWN)
    or a
    jr z,foes_erase_next
    call foe_kind_ptr
    ld a,K_W
    call foe_kind_byte
    ld (spr_w),a
    ld a,K_H
    call foe_kind_byte
    ld (spr_h),a
    ld a,(iy+E_OX)
    ld (spr_x),a
    ld a,(iy+E_OY)
    call spr_row_ptr
    pop hl
    push hl
    call spr_restore
foes_erase_next
    pop hl
    ld de,-FOE_BUF
    add hl,de
    ld de,-E_SIZE
    add iy,de
    pop bc
    djnz foes_erase_one
    ret

;; ---------------------------------------------------------------------------
;; foes_draw - and back on, the near ones last.
;; Destroys AF, BC, DE, HL, IX, IY.
;; ---------------------------------------------------------------------------
foes_draw
    ld iy,foes
    ld hl,foe_bufs
    ld b,FOE_COUNT
foes_draw_one
    push bc
    push hl
    call foe_kind_ptr                   ; the picture it is showing
    ld a,(iy+E_FRAME)
    add a,a
    ld c,a
    ld a,(iy+E_DIR)
    inc a
    jr nz,foes_draw_right
    ld a,c
    add a,4                             ; the mirrored pair sits behind
    ld c,a
foes_draw_right
    ld b,0
    push hl
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
    push de                             ; the sprite
    ld a,K_W
    call foe_kind_byte
    ld (spr_w),a
    ld a,K_H
    call foe_kind_byte
    ld (spr_h),a
    ld a,(iy+E_X)
    ld (spr_x),a
    ld (iy+E_OX),a
    ld a,(iy+E_Y)
    ld (iy+E_OY),a
    call spr_row_ptr
    pop hl                              ; the sprite
    call spr_size                       ; HL to its pixels; w and h again
    pop de                              ; its buffer
    push de
    call spr_draw
    ld (iy+E_DRAWN),1
    pop hl
    ld de,FOE_BUF
    add hl,de
    ld de,E_SIZE
    add iy,de
    pop bc
    djnz foes_draw_one
    ret

;; ---------------------------------------------------------------------------
;; foes_move - a beat between two columns, and a bob for the one that flies.
;; Two seconds of being sat on stops all of it.
;; Destroys AF, BC, DE, HL, IY.
;; ---------------------------------------------------------------------------
foes_move
    ld iy,foes
    ld b,FOE_COUNT
foes_move_one
    push bc
    ld a,(iy+E_STUN)
    or a
    jr z,foes_move_awake
    dec (iy+E_STUN)                     ; still seeing stars
    jr foes_move_next

foes_move_awake
    dec (iy+E_ANIM)                     ; its two pictures
    jr nz,foes_move_step
    ld (iy+E_ANIM),FOE_ANIM
    ld a,(iy+E_FRAME)
    xor 1
    ld (iy+E_FRAME),a

foes_move_step
    dec (iy+E_TICK)
    jr nz,foes_move_next
    ld (iy+E_TICK),FOE_TICK
    ld a,(iy+E_X)
    add a,(iy+E_DIR)
    ld (iy+E_X),a
    cp (iy+E_X0)
    jr z,foes_move_turn
    cp (iy+E_X1)
    jr nz,foes_move_bob
foes_move_turn
    ld a,(iy+E_DIR)                     ; the end of the beat: about turn
    neg
    ld (iy+E_DIR),a

foes_move_bob
    call foe_kind_ptr
    ld a,K_FLY
    call foe_kind_byte
    or a
    jr z,foes_move_next
    ld a,(iy+E_PHASE)
    inc a
    and 15
    ld (iy+E_PHASE),a
    ld e,a
    ld d,0
    ld hl,foe_bob
    add hl,de
    ld a,(iy+E_Y0)
    add a,(hl)
    ld (iy+E_Y),a

foes_move_next
    ld de,E_SIZE
    add iy,de
    pop bc
    djnz foes_move_one
    ret

;; Sixteen steps of a lazy arc, in scanlines off the line it flies along.
foe_bob
    defb 0, 1, 2, 3, 4, 5, 5, 6, 6, 6, 5, 5, 4, 3, 2, 1

;; ---------------------------------------------------------------------------
;; The three kinds, and the three of them in the shop. A kind is two pictures
;; each way round, how big it is, and whether it flies.
;; ---------------------------------------------------------------------------
foe_kinds
    defw spr_broom_a, spr_broom_b, spr_broom_a_l, spr_broom_b_l
    defb SPR_BROOM_A_W, SPR_BROOM_A_H, 0
    defw spr_mouse_a, spr_mouse_b, spr_mouse_a_l, spr_mouse_b_l
    defb SPR_MOUSE_A_W, SPR_MOUSE_A_H, 0
    defw spr_seagull_a, spr_seagull_b, spr_seagull_a_l, spr_seagull_b_l
    defb SPR_SEAGULL_A_W, SPR_SEAGULL_A_H, 1

;; kind, x, y, the line a flier bobs about, the two ends of its beat, which
;; way it is going, and then the eight bytes it keeps for itself. This is the
;; copy nothing writes to: the game runs on the one it puts in RAM, so a new
;; game gets them all back on their feet and where they started.
foes_init
    defb K_BROOM, 40, FLOOR_TOP-SPR_BROOM_A_H, 0, 34, 52, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0
    defb K_MOUSE, 80, FLOOR_TOP-SPR_MOUSE_A_H, 0, 56, 92, -1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0
    defb K_GULL, 64, 72, 72, 58, 84, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0

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
;; And where somebody has been mopping: the same three bytes, and the surface
;; has to be one a line of shop_plats names or nothing will ever be standing
;; on it. Both of these are on the floor, which is where a bucket gets put
;; down.
;; ---------------------------------------------------------------------------
shop_soap
    defb 34, 50, FLOOR_TOP              ; one at the foot of the crates
    defb 58, 74, FLOOR_TOP              ; and one in front of the counter
    defb #FF

;; ---------------------------------------------------------------------------
;; mitsos_erase - put the shop back where he was standing.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
mitsos_erase
    ld a,(mitsos_drawn)                 ; nothing under him the first time
    or a
    ret z
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
    ld a,(mitsos_grace)                 ; blinking: every other picture he is
    and 4                               ; simply not drawn, and then there is
    jr z,mitsos_draw_on                 ; nothing under him to put back either
    xor a
    ld (mitsos_drawn),a
    ret
mitsos_draw_on
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
    ld (mitsos_ox),a                    ; where his picture will be standing
    push hl
    ld a,(mitsos_y)
    ld (mitsos_oy),a
    call spr_row_ptr                    ; wants DE and HL for itself
    pop hl
    ld de,mitsos_buf
    ld a,1
    ld (mitsos_drawn),a
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

;; The soap, over the tiles and the line between them, because a puddle does
;; not respect grouting.
    ld hl,shop_soap
draw_shop_soap
    ld a,(hl)
    inc a
    jr z,draw_shop_props
    dec a
    ld (fill_x),a
    ld c,a
    inc hl
    ld a,(hl)                           ; last column
    inc hl
    sub c
    inc a
    ld e,a
    ld d,0
    push hl
    ex de,hl
    ld (fill_w),hl
    pop hl
    ld e,(hl)                           ; the surface it is lying on
    inc hl
    push hl
    ld a,PEN11_BYTE                     ; the water
    ld (fill_b),a
    ld a,e
    push de
    call wall_row_ptr
    ld de,SOAP_H
    call fill_rows
    pop de

    ld a,PEN3_BYTE                      ; the foam where it meets the tiles
    ld (fill_b),a
    ld a,e
    push de
    call wall_row_ptr
    ld de,2
    call fill_rows
    pop de

    ld a,(fill_x)                       ; and the shine across the middle of
    add a,2                             ; it, held off both ends
    ld (fill_x),a
    ld hl,(fill_w)
    dec hl
    dec hl
    dec hl
    dec hl
    ld (fill_w),hl
    ld a,e
    add a,SOAP_H/2
    call wall_row_ptr
    ld de,2
    call fill_rows
    pop hl
    jr draw_shop_soap

;; The furniture, in the order it stands in: the window is in the wall behind
;; everything, the shelving and the counter in front of it.
draw_shop_props
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
    include "text.asm"
    include "font.asm"
    include "mitsosstr.asm"
    include "mitsosart.asm"             ; in front of sprite.asm, which asserts
SPR_MAX_W       EQU ART_MAX_W           ; the widest of them fits its blit
    include "sprite.asm"

code_end

    include "workspace.asm"

;; Mitsos's own RAM, past the engine's. The buffer is the patch of shop he is
;; standing in front of, and it is his: nothing else is lifted off yet.
mitsos_xf       defs 1              ; 8.8 again, and the same trick: mitsos_xf
mitsos_x        defs 1              ; then mitsos_x, so the pair loads at once
mitsos_vx       defs 2              ; sideways velocity, signed
mitsos_yf       defs 1              ; 8.8 fixed point: mitsos_yf then mitsos_y,
mitsos_y        defs 1              ; so "ld hl,(mitsos_yf)" loads the pair
mitsos_vy       defs 2              ; vertical velocity, same units, signed
mitsos_state    defs 1              ; ST_GROUND / ST_AIR
mitsos_ofeet    defs 1              ; where his feet were at the top of the
mitsos_nfeet    defs 1              ; step, and where they are now
mitsos_ox       defs 1              ; and where his picture still is
mitsos_oy       defs 1
mitsos_drawn    defs 1              ; is there anything in his buffer yet
mitsos_face     defs 1              ; FACE_RIGHT / FACE_LEFT
mitsos_frame    defs 1              ; 0 standing, 1 and 2 the waddle
mitsos_tick     defs 1              ; frames until the next one
mitsos_buf      defs MITSOS_BYTES

mitsos_lives    defs 1              ; three, and the HUD prints this one
mitsos_grace    defs 1              ; frames of blinking left after losing one
mitsos_over     defs 1              ; out of them, and waiting for fire

;; The cast as it stands, copied from foes_init at the top of a game, and one
;; patch of shop per enemy, all of them the size of the biggest.
foes            defs FOE_COUNT*E_SIZE
foe_bufs        defs FOE_COUNT*FOE_BUF

    IF TARGET==1
RUN mitsos_start
    ENDIF

    IF TARGET==2
    SAVE "MITSOS.BIN",mitsos_start,code_end-mitsos_start,DSK,"build/mitsos.dsk"
    ENDIF

    IF TARGET==3
    SAVE "build/out.bin",mitsos_start,code_end-mitsos_start
    ENDIF
