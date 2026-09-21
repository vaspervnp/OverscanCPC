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
FOE_COUNT       EQU 2

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

K_MOUSE         EQU 0
K_GULL          EQU 1

FOE_BUF         EQU SPR_SEAGULL_A_W*SPR_SEAGULL_A_H  ; the biggest of them

;; --- Grandma Evdoxia -------------------------------------------------------
;; Eighty scanlines of her, which is three and a third of him, and she is the
;; reason the floor of this shop is not a place to stand about on.
;;
;; She is not a sprite. At this size a masked blit of her would be most of a
;; frame on its own, and the rule this shop was built on says it anyway: a cat
;; is drawn, and anything the size of a person is boxes. So she is a box list
;; like the counter and the crates - except that she keeps the patch of shop
;; she is standing in front of, the way a sprite does, and puts it back before
;; she moves. Boxes in, LDIs out: about half what the same rectangle would
;; cost through the masked blit, and the reason she fits at all.
;;
;; She is also only rebuilt on the frames she actually changes on. An old
;; woman crossing a shop floor moves a byte every eighth frame and swings the
;; broom every twelfth, so seven pictures out of eight she is simply left
;; standing where she is, and costs nothing. The price of that is granny_off:
;; anything that changes the shop underneath her has to take her off the
;; screen first, or her buffer carries the old shop about with her.
GRANNY_W        EQU 7                   ; 28 pixels on the monitor
GRANNY_H        EQU 80
GRANNY_TOP      EQU FLOOR_TOP-GRANNY_H  ; she stands on the floor like he does
GRANNY_BYTES      EQU GRANNY_W*GRANNY_H

GRANNY_X0       EQU 30                  ; the beat she walks, in bytes
GRANNY_X1       EQU 56
GRANNY_WALK     EQU 8                   ; frames between her steps
GRANNY_HUNT     EQU 4                   ; and when she has seen him
GRANNY_SEE      EQU 16                  ; how far along the floor she can
GRANNY_SWEEP     EQU 12                  ; frames between the halves of a stroke

;; --- What he came for ------------------------------------------------------
;; Four mezedes on the shelves, and the basket by the top board does not open
;; until all four are off them. The catnip is not one of them - it is worth
;; five times as much and the way out does not wait for it, which is the
;; choice it exists to make.
PICK_COUNT      EQU 5
MEZE_COUNT      EQU 4
PICK_BUF        EQU SPR_FISH_W*SPR_FISH_H        ; they are all this size

P_SPR           EQU 0                   ; the picture, two bytes
P_X             EQU 2
P_Y             EQU 3
P_MEZE          EQU 4                   ; does the basket wait for this one
P_ALIVE         EQU 5
P_SIZE          EQU 6

BASKET_X        EQU 26                  ; standing on the top board
BASKET_Y        EQU SHELF_4-20
BASKET_W        EQU 8

SCORE_BYTES     EQU 3                   ; six BCD digits
MEZE_POINTS     EQU #01                 ; BCD, into the hundreds digit
CATNIP_POINTS   EQU #05

;; --- The catnip ------------------------------------------------------------
;; What the catnip is for, and the reason it is worth walking out of the way
;; for something the basket does not wait for: eight seconds of double speed,
;; of nothing in the shop being able to lay a hand on him, and of everything
;; he walks into going flat on its back instead.
;;
;; 384 frames of the 50 Hz the game thinks in is a shade under those eight
;; seconds, and it is that rather than 400 because it is twelve bars of 32 -
;; so the meter in the HUD comes off five shifts instead of a division, and
;; is exactly as many bytes wide as it has bars.
RUSH_TIME       EQU 384
RUSH_BAR        EQU 32                  ; frames to a bar of the meter
RUSH_WARN       EQU 100                 ; the border blinks over the last two
RUSH_MAX        EQU VX_MAX*2            ; two bytes a frame, and twice the
RUSH_ACCEL      EQU VX_ACCEL*2          ; push it takes to get there
RUSH_POINTS     EQU #01                 ; sweeping one aside is worth a meze

;; The border is the one thing on this machine that changes in a single byte
;; and cannot be missed, and a game with 384 pixels of picture has no border
;; left to lose - which makes it exactly the right place to say that the
;; rules have changed for a moment.
RUSH_COL        EQU #40+18              ; bright green, the catnip's own
SHOP_COL        EQU #40+7               ; and the coral of the wall after it

METER_X         EQU 40                  ; the gap between the score and LIVES
METER_W         EQU RUSH_TIME/RUSH_BAR
METER_H         EQU 6

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
METER_Y         EQU HUD_Y+2             ; the catnip meter, inside the strip

;; And the panel that goes up when they run out.
OVER_Y          EQU 96
OVER_H          EQU 56
OVER_SCALE      EQU 5                   ; scanlines per source row: 40 tall
SCORE_LABEL_X   EQU 3
SCORE_X         EQU 21
LIVES_LABEL_X   EQU 54
LIVES_X         EQU 72

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
    call granny_erase                   ; last off, because she goes on first

    ld b,FRAMES_PER_RENDER
main_loop_think
    push bc
    call mitsos_move
    call foes_move
    call granny_move
    pop bc
    djnz main_loop_think

    call granny_draw                    ; behind the lot of them
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
    ld hl,pickups_init                  ; and the shelves stocked again
    ld de,pickups
    ld bc,PICK_COUNT*P_SIZE
    ldir

    xor a
    ld (mitsos_over),a
    ld (mitsos_grace),a
    ld (mitsos_drawn),a
    ld (basket_open),a
    ld (rush_bars),a
    call rush_stop                      ; his own weight back, and the border
    ld h,a                              ; and nothing on the score
    ld l,a
    ld (score),hl
    ld (score+1),hl
    ld a,MEZE_COUNT
    ld (mezes_left),a
    call granny_reset
    call draw_pickups
    call draw_score
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
    dec a
    jp z,draw_over                      ; whichever panel is up is words too
    jp draw_done

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
    ld a,SCORE_LABEL_X
    ld (txt_x),a
    ld a,MSG_SCORE
    call msg_small

    ld hl,line_tab+(HUD_Y+1)*2
    ld (txt_row),hl
    ld a,LIVES_LABEL_X
    ld (txt_x),a
    ld a,MSG_LIVES
    call msg_small
    call draw_score
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
;; draw_score - six digits, straight out of three bytes of BCD. Solid, so it
;; goes over the ones that were there.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_score
    ld hl,line_tab+(HUD_Y+1)*2
    ld (txt_row),hl
    ld a,SCORE_X
    ld (txt_x),a
    ld a,1
    ld (txt_solid),a
    ld hl,score
    ld b,SCORE_BYTES
    call print_digits
    xor a
    ld (txt_solid),a
    ret

;; ---------------------------------------------------------------------------
;; add_score - A = hundreds to add, in BCD. The score is packed BCD most
;; significant byte first, so the hundreds are the low nibble of the middle
;; byte and DAA does the arithmetic - which is the whole reason it is kept
;; this way round rather than as a number that would need dividing to print.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
add_score
    ld hl,score+SCORE_BYTES-2           ; the hundreds digit lives in this one
    ld b,SCORE_BYTES-1
    or a
add_score_byte
    ld c,a
    ld a,(hl)
    adc a,c
    daa
    ld (hl),a
    dec hl
    ld a,0                              ; only the carry goes up
    djnz add_score_byte
    jp draw_score

;; ---------------------------------------------------------------------------
;; draw_done - the other way a shop ends.
;; Destroys everything.
;; ---------------------------------------------------------------------------
draw_done
    ld a,MSG_DONE
    ld b,PEN9_BYTE                      ; green, because it is good news
    jr draw_panel

;; ---------------------------------------------------------------------------
;; draw_over - GAME OVER across the middle of the shop, and how to start
;; again under it. The ground is cleared first: big text writes where the
;; letter is and skips where it is not, and small text blends.
;; Destroys everything.
;; ---------------------------------------------------------------------------
draw_over
    ld a,MSG_GAMEOVER
    ld b,PEN13_BYTE                     ; in red, which nothing else here is

;; A = the message to put up big, B = the pen to put it up in.
draw_panel
    push af
    push bc
    ld hl,line_tab+OVER_Y*2
    ld de,OVER_H
    ld a,PEN0_BYTE
    call clear_rows

    ld a,1
    ld (txt_xs),a                       ; 24 pixels to a letter
    ld a,OVER_SCALE
    ld (txt_ys),a
    pop bc
    ld a,b
    ld (txt_big_pen),a
    ld a,1
    ld (txt_big_solid),a
    ld hl,line_tab+(OVER_Y+4)*2
    ld (txt_row),hl
    pop af
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

    call mitsos_collect                 ; what he is standing in, and then
    call mitsos_escape                  ; whether it was the way out
    call rush_tick                      ; and how much catnip is left in him

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
    ld de,(vx_acc)
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
    ld de,(vx_top)
    or a
    sbc hl,de
    add hl,de
    jr c,mitsos_vx_store                ; under it
    ld hl,(vx_top)
    jr mitsos_vx_store
mitsos_vx_push_left
    ld de,(vx_bot)
    or a
    sbc hl,de
    add hl,de
    jr nc,mitsos_vx_store               ; over it
    ld hl,(vx_bot)
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

    call granny_hurt                    ; she is the biggest thing in the shop
    ld a,(mitsos_grace)
    or a
    ret nz                              ; and she has just had him

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

    ld hl,(mitsos_rush)                 ; full of catnip: it goes over, not him
    ld a,h
    or l
    jr nz,mitsos_hurt_sweep

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
    call rush_stop
    jp draw_over

;; Swept aside rather than walked into: it goes down for the same two seconds
;; the belly bounce costs it, and is worth the same as a meze. He does not
;; stop, which is the whole point of the catnip - the rest of the cast is
;; scenery until it wears off.
mitsos_hurt_sweep
    ld (iy+E_STUN),STUN_TIME
    ld a,RUSH_POINTS
    call add_score

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
    call granny_bounce                  ; her head is the highest thing that
    ret c                               ; can be landed on in here
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
    defw spr_mouse_a, spr_mouse_b, spr_mouse_a_l, spr_mouse_b_l
    defb SPR_MOUSE_A_W, SPR_MOUSE_A_H, 0
    defw spr_seagull_a, spr_seagull_b, spr_seagull_a_l, spr_seagull_b_l
    defb SPR_SEAGULL_A_W, SPR_SEAGULL_A_H, 1

;; kind, x, y, the line a flier bobs about, the two ends of its beat, which
;; way it is going, and then the eight bytes it keeps for itself. This is the
;; copy nothing writes to: the game runs on the one it puts in RAM, so a new
;; game gets them all back on their feet and where they started.
foes_init
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
    ld hl,(mitsos_rush)                 ; which of him is standing there
    ld a,h
    or l
    ld hl,mitsos_frames
    jr z,mitsos_draw_table
    ld hl,mitsos_rush_frames
mitsos_draw_table
    ld a,(mitsos_frame)
    add a,a
    ld e,a
    ld d,0
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

;; And the same six with his eyes out on stalks, which is what the catnip
;; looks like from the outside. Same size, same frame numbers, so nothing but
;; which table is read changes while it lasts.
mitsos_rush_frames
    defw spr_mitsos_rush
    defw spr_mitsos_rush1
    defw spr_mitsos_rush2
    defw spr_mitsos_rush_l
    defw spr_mitsos_rush1_l
    defw spr_mitsos_rush2_l

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
    jr z,draw_shop_props_done
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

;; The way out, shut. It opens when the last meze comes off a shelf.
draw_shop_props_done
    ld a,BASKET_X
    ld (prop_x),a
    ld a,BASKET_Y
    ld (prop_y),a
    ld hl,box_basket
    jp draw_boxes

;; ---------------------------------------------------------------------------
;; draw_pickups - the five things on the shelves, each keeping the patch of
;; shop it covers, so that picking it up is putting that patch back.
;; Destroys AF, BC, DE, HL, IX, IY.
;; ---------------------------------------------------------------------------
draw_pickups
    ld iy,pickups
    ld hl,pick_back
    ld b,PICK_COUNT
draw_pickups_one
    push bc
    push hl
    ld a,(iy+P_ALIVE)
    or a
    jr z,draw_pickups_next
    ld a,(iy+P_X)
    ld (spr_x),a
    ld l,(iy+P_SPR)
    ld h,(iy+P_SPR+1)
    call spr_size                       ; -> spr_w, spr_h, HL at the pixels
    push hl
    ld a,(iy+P_Y)
    call spr_row_ptr
    pop hl
    pop de                              ; its buffer
    push de
    call spr_draw
draw_pickups_next
    pop hl
    ld de,PICK_BUF
    add hl,de
    ld de,P_SIZE
    add iy,de
    pop bc
    djnz draw_pickups_one
    ret

;; ---------------------------------------------------------------------------
;; mitsos_collect - anything he is standing in that can be eaten.
;;
;; Putting the buffer back is what takes it off the shelf, and this runs with
;; the whole cast lifted off the screen, which is the only window where that
;; is safe: outside it a sprite's save buffer would either put back what was
;; just removed or capture it and carry it about the shop.
;; Destroys AF, BC, DE, HL, IX, IY.
;; ---------------------------------------------------------------------------
mitsos_collect
    ld iy,pickups
    ld hl,pick_back
    ld b,PICK_COUNT
mitsos_collect_one
    push bc
    push hl
    ld a,(iy+P_ALIVE)
    or a
    jr z,mitsos_collect_next

    ld b,(iy+P_X)                       ; the columns it covers
    ld a,SPR_FISH_W-1
    add a,b
    call mitsos_overlap
    jr nc,mitsos_collect_next

    ld a,(mitsos_y)                     ; and the scanlines
    add a,MITSOS_H-1
    cp (iy+P_Y)
    jr c,mitsos_collect_next
    ld a,(iy+P_Y)
    add a,SPR_FISH_H-1
    ld c,a
    ld a,(mitsos_y)
    cp c
    jr z,mitsos_collect_take
    jr nc,mitsos_collect_next

mitsos_collect_take
    call granny_off                     ; the shelf is about to change, and she
    ld (iy+P_ALIVE),0                   ; may be standing in front of it
    ld a,SPR_FISH_W
    ld (spr_w),a
    ld a,SPR_FISH_H
    ld (spr_h),a
    ld a,(iy+P_X)
    ld (spr_x),a
    ld a,(iy+P_Y)
    call spr_row_ptr
    pop hl
    push hl
    call spr_restore                    ; the shelf, back the way it was

    ld a,CATNIP_POINTS                  ; and what it was worth
    bit 0,(iy+P_MEZE)
    jr z,mitsos_collect_score
    ld a,MEZE_POINTS
mitsos_collect_score
    call add_score

    bit 0,(iy+P_MEZE)
    jr nz,mitsos_collect_meze
    call rush_start                     ; the catnip, and what it is really for
    jr mitsos_collect_next
mitsos_collect_meze
    ld hl,mezes_left
    dec (hl)
    jr nz,mitsos_collect_next
    call open_basket

mitsos_collect_next
    pop hl
    ld de,PICK_BUF
    add hl,de
    ld de,P_SIZE
    add iy,de
    pop bc
    djnz mitsos_collect_one
    ret

;; ---------------------------------------------------------------------------
;; open_basket - the lid comes off, and from then on it is a way out.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
open_basket
    call granny_off                     ; same again: the lid is background
    ld a,1
    ld (basket_open),a
    ld a,BASKET_X
    ld (prop_x),a
    ld a,BASKET_Y
    ld (prop_y),a
    ld hl,box_basket_open
    jp draw_boxes

;; ---------------------------------------------------------------------------
;; mitsos_escape - standing in an open basket is the end of the shop.
;; Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
mitsos_escape
    ld a,(basket_open)
    or a
    ret z
    ld b,BASKET_X
    ld a,BASKET_X+BASKET_W-1
    call mitsos_overlap
    ret nc
    ld a,(mitsos_y)
    add a,MITSOS_H-1
    cp BASKET_Y
    ret c
    ld a,2                              ; out through the basket, and done
    ld (mitsos_over),a
    call rush_stop
    jp draw_done


;; ===========================================================================
;; Grandma Evdoxia.
;;
;; Eighty scanlines of black, which is three and a third of him, sweeping a
;; stretch of the shop floor and picking up speed when she catches sight of
;; him. Touching her costs a life; coming down on her head from a shelf sits
;; her down for the two seconds anything else in here gets, and so does the
;; catnip. There is no getting past her on the floor otherwise, which is the
;; point of her: the shelves are the way through the shop.
;;
;; She is boxes over a saved rectangle rather than a masked sprite - see the
;; note with GRANNY_W - so drawing her is draw_boxes and lifting her off is
;; seven LDIs a scanline.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; granny_reset - back at the end of her beat, broom in hand.
;; Destroys AF.
;; ---------------------------------------------------------------------------
granny_reset
    ld a,GRANNY_X1                      ; the far end of her beat, walking
    ld (granny_x),a                     ; back towards the door - which is the
    ld (granny_ox),a                    ; length of the shop's worth of warning
    ld a,-1                             ; he gets at the start of a life
    ld (granny_dir),a
    ld a,1
    ld (granny_dirty),a                 ; draw_shop has just wiped her off
    xor a
    ld (granny_drawn),a
    ld (granny_frame),a
    ld (granny_stun),a
    ld a,GRANNY_WALK
    ld (granny_tick),a
    ld a,GRANNY_SWEEP
    ld (granny_anim),a
    ret

;; ---------------------------------------------------------------------------
;; granny_move - one 50 Hz step of her.
;;
;; She walks her beat a byte at a time and turns at either end of it. If he is
;; within GRANNY_SEE bytes she turns towards him and steps twice as often -
;; which is the whole of "if she spots you, she comes at you waving it".
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
granny_move
    ld hl,granny_stun
    ld a,(hl)
    or a
    jr z,granny_move_up
    dec (hl)
    ret nz
    ld a,1                              ; and she is back on her feet
    ld (granny_dirty),a
    ret

granny_move_up
    ld hl,granny_anim                   ; the broom goes back and forth
    dec (hl)                            ; whatever her feet are doing
    jr nz,granny_move_look
    ld (hl),GRANNY_SWEEP
    ld a,(granny_frame)
    xor 1
    ld (granny_frame),a
    ld a,1
    ld (granny_dirty),a

granny_move_look
    ld e,GRANNY_WALK                    ; the beat she keeps when she cannot
    ld d,0                              ; see him, and whether she can
    ld a,(granny_x)
    ld b,a
    ld a,(mitsos_x)
    sub b                               ; how far along he is from her
    jr z,granny_move_right
    jr nc,granny_move_ahead
    neg                                 ; he is behind her
    cp GRANNY_SEE
    jr nc,granny_move_step
    ld a,-1
    jr granny_move_seen
granny_move_ahead
    cp GRANNY_SEE
    jr nc,granny_move_step
granny_move_right
    ld a,1
granny_move_seen
    ld (granny_dir),a
    ld e,GRANNY_HUNT
    ld d,1

granny_move_step
    ld hl,granny_tick
    dec (hl)
    ret nz
    ld (hl),e                           ; the next step is E frames off
    ld a,(granny_dir)
    ld b,a
    ld a,(granny_x)
    add a,b
    cp GRANNY_X0
    jr c,granny_move_end
    cp GRANNY_X1+1
    jr nc,granny_move_end
    ld (granny_x),a
    ld a,1
    ld (granny_dirty),a
    ret

;; The end of her beat. Patrolling she turns round and walks back; with him
;; in sight she stays where she is and keeps facing him, because a woman who
;; has just seen a cat in the mezedes does not walk away from it - and because
;; turning round every four frames in the corner would have her jittering
;; there and repainting eighty scanlines of herself for nothing.
granny_move_end
    ld a,d
    or a
    ret nz
    ld a,(granny_dir)
    neg                                 ; and the broom changes hands with her
    ld (granny_dir),a
    ld a,1
    ld (granny_dirty),a
    ret

;; ---------------------------------------------------------------------------
;; granny_hurt - walking into eighty scanlines of grandmother.
;;
;; Her whole rectangle counts, broom and all, which is why a cat on the floor
;; near her is a cat about to lose something. Full of catnip he goes through
;; her instead and she sits down.
;; Destroys everything.
;; ---------------------------------------------------------------------------
granny_hurt
    ld a,(granny_stun)
    or a
    ret nz                              ; sitting down, and harmless
    ld a,(granny_x)
    ld b,a
    add a,GRANNY_W-1
    call mitsos_overlap
    ret nc
    ld a,(mitsos_y)
    add a,MITSOS_H-1                    ; his feet down to her head at all?
    cp GRANNY_TOP
    ret c

    ld hl,(mitsos_rush)
    ld a,h
    or l
    jp z,mitsos_lose
    ld a,STUN_TIME                      ; she goes over like everything else
    ld (granny_stun),a
    ld a,1
    ld (granny_dirty),a
    ld a,RUSH_POINTS
    jp add_score

;; ---------------------------------------------------------------------------
;; granny_bounce - the same test the shelves and the mice get, against the
;; top of her head. It is 80 scanlines up from the floor, so the only place he
;; can be falling from to meet it is the third board - which makes sitting her
;; down a thing that has to be set up rather than blundered into.
;; Carry set if it happened.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
granny_bounce
    ld a,(granny_stun)
    or a
    jr nz,granny_bounce_no
    ld a,(mitsos_ofeet)
    cp GRANNY_TOP
    jr z,granny_bounce_below
    jr nc,granny_bounce_no              ; his feet were already past her head
granny_bounce_below
    ld a,(mitsos_nfeet)
    cp GRANNY_TOP
    jr c,granny_bounce_no               ; and still are not down to it
    ld a,(granny_x)
    ld b,a
    add a,GRANNY_W-1
    call mitsos_overlap
    jr nc,granny_bounce_no

    ld a,STUN_TIME
    ld (granny_stun),a
    ld a,1
    ld (granny_dirty),a
    ld hl,BOUNCE_V
    ld (mitsos_vy),hl
    scf
    ret
granny_bounce_no
    or a
    ret

;; ---------------------------------------------------------------------------
;; granny_erase - her picture off the screen, but only if it is about to be
;; drawn again somewhere else. Standing still she is left exactly where she
;; is, and costs the frame nothing at all.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
granny_erase
    ld a,(granny_drawn)
    or a
    ret z
    ld a,(granny_dirty)
    or a
    ret z
    ;; fall through

;; ---------------------------------------------------------------------------
;; granny_off - her picture off the screen whatever she is doing, because
;; something is about to change the shop underneath her: a meze coming off a
;; shelf, or the lid coming off the basket. Her buffer would otherwise still
;; hold the old shop and hand it back the next time she moved.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
granny_off
    ld a,(granny_drawn)
    or a
    ret z
    call granny_place
    xor a
    ld (granny_drawn),a
    ld a,1
    ld (granny_dirty),a
    ret

;; ---------------------------------------------------------------------------
;; granny_draw - the shop she covers into her buffer, then her over it.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
granny_draw
    ld a,(granny_drawn)
    or a
    ret nz                              ; still standing where she was
    ld a,(granny_x)
    ld (granny_ox),a
    ld (prop_x),a
    call granny_lift
    ld a,GRANNY_TOP
    ld (prop_y),a

    ld a,(granny_stun)
    or a
    ld hl,granny_sat
    jr nz,granny_draw_list

    call granny_facing                  ; the body first, whichever way round
    ld a,e
    srl a                               ; one body a side against two brooms,
    ld e,a                              ; so the body index is half of it -
                                        ; and srl, not rra: granny_facing
                                        ; leaves the carry set on the way out
    ld hl,granny_bodies
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call draw_boxes

    call granny_facing                  ; and then the broom in her hands -
    ld a,(granny_frame)                 ; draw_boxes has had DE, so the side
    add a,a                             ; is worked out again rather than kept
    add a,e
    ld e,a
    ld hl,granny_brooms
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
granny_draw_list
    call draw_boxes
    ld a,1
    ld (granny_drawn),a
    xor a
    ld (granny_dirty),a
    ret

;; ---------------------------------------------------------------------------
;; granny_facing - DE = 0 if the broom is on her right, 4 if it is on her
;; left, which is where the mirrored pair of each list sits.
;; Destroys AF, DE.
;; ---------------------------------------------------------------------------
granny_facing
    ld d,0
    ld e,d
    ld a,(granny_dir)
    add a,a
    ret nc
    ld e,4
    ret

;; ---------------------------------------------------------------------------
;; granny_lift - the seven bytes of each of her eighty scanlines, out of the
;; screen and into her buffer.
;;
;; An unrolled run of LDIs rather than an LDIR: five microseconds a byte
;; against six, and no counter to set up every row. BC is scratch here - LDI
;; decrements it and nobody asks. The row counter lives in the alternate B,
;; the way sprite.asm does it, because LDI would eat any other.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
granny_lift
    ld ix,line_tab+GRANNY_TOP*2
    ld de,granny_buf
    exx
    ld b,GRANNY_H
    exx
granny_lift_row
    ld a,(granny_ox)
    ld l,(ix+0)
    ld h,(ix+1)
    inc ix
    inc ix
    add a,l
    ld l,a
    jr nc,granny_lift_go
    inc h
granny_lift_go
    REPEAT GRANNY_W
    ldi
    REND
    exx
    djnz granny_lift_more
    exx
    ret
granny_lift_more
    exx
    jr granny_lift_row

;; ---------------------------------------------------------------------------
;; granny_place - and the same the other way round, which is how she is
;; rubbed out.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
granny_place
    ld ix,line_tab+GRANNY_TOP*2
    ld hl,granny_buf
    exx
    ld b,GRANNY_H
    exx
granny_place_row
    ld a,(granny_ox)
    ld e,(ix+0)
    ld d,(ix+1)
    inc ix
    inc ix
    add a,e
    ld e,a
    jr nc,granny_place_go
    inc d
granny_place_go
    REPEAT GRANNY_W
    ldi
    REND
    exx
    djnz granny_place_more
    exx
    ret
granny_place_more
    exx
    jr granny_place_row

;; ---------------------------------------------------------------------------
;; What she is made of. Boxes, like the counter and the crates, and for the
;; same reason: a woman is furniture-sized and there is no such thing as a
;; bitmap of one in this machine.
;; ---------------------------------------------------------------------------
granny_bodies
    defw granny_body, granny_body_l

;; Two halves of a stroke facing right, then the same two facing left.
granny_brooms
    defw granny_broom_a, granny_broom_b
    defw granny_broom_a_l, granny_broom_b_l

;; Facing right: the body on the left five columns, the broom on the other two.
granny_body
    defb  1, 0, 3, 6, 4     ; the crown of the scarf
    defb  0, 3, 1,11, 4     ; and the sides of it, down past her ears
    defb  4, 3, 1,11, 4
    defb  1, 6, 3, 8,15     ; the face inside it
    defb  1, 8, 1, 2, 4     ; two eyes
    defb  3, 8, 1, 2, 4
    defb  2,11, 1, 2,12     ; and a mouth that is not a smile
    defb  1,14, 3, 3, 4     ; the knot under her chin
    defb  0,17, 5, 6, 4     ; shoulders
    defb  1,19, 3, 2, 3     ; with a white collar on them
    defb  1,23, 3,23, 4     ; the body
    defb  1,26, 3,14, 3     ; and the apron over it
    defb  0,46, 5,30, 4     ; the skirt, all the way to the floor
    defb  0,58, 5, 2,12     ; with two pleats in it
    defb  0,70, 5, 2,12
    defb  1,76, 1, 4, 5     ; and her shoes under the hem
    defb  3,76, 1, 4, 5
    defb #FF

;; And facing left, which is the same list read from the other end.
granny_body_l
    defb  3, 0, 3, 6, 4     ; the crown of the scarf
    defb  6, 3, 1,11, 4     ; and the sides of it, down past her ears
    defb  2, 3, 1,11, 4
    defb  3, 6, 3, 8,15     ; the face inside it
    defb  5, 8, 1, 2, 4     ; two eyes
    defb  3, 8, 1, 2, 4
    defb  4,11, 1, 2,12     ; and a mouth that is not a smile
    defb  3,14, 3, 3, 4     ; the knot under her chin
    defb  2,17, 5, 6, 4     ; shoulders
    defb  3,19, 3, 2, 3     ; with a white collar on them
    defb  3,23, 3,23, 4     ; the body
    defb  3,26, 3,14, 3     ; and the apron over it
    defb  2,46, 5,30, 4     ; the skirt, all the way to the floor
    defb  2,58, 5, 2,12     ; with two pleats in it
    defb  2,70, 5, 2,12
    defb  5,76, 1, 4, 5     ; and her shoes under the hem
    defb  3,76, 1, 4, 5
    defb #FF

;; The two halves of a stroke of the broom, each way round.
granny_broom_a
    defb  4,28, 1, 2,15     ; her hand on the handle
    defb  5,30, 1,18, 6     ; the handle
    defb  6,46, 1,20, 6
    defb  4,64, 3,14,15     ; and the straw of it, out at her feet
    defb #FF


granny_broom_b
    defb  4,26, 1, 2,15     ; the same, half a stroke later
    defb  5,28, 1,22, 6
    defb  5,50, 1,16, 6
    defb  3,62, 3,16,15
    defb #FF


granny_broom_a_l
    defb  2,28, 1, 2,15     ; her hand on the handle
    defb  1,30, 1,18, 6     ; the handle
    defb  0,46, 1,20, 6
    defb  0,64, 3,14,15     ; and the straw of it, out at her feet
    defb #FF


granny_broom_b_l
    defb  2,26, 1, 2,15     ; the same, half a stroke later
    defb  1,28, 1,22, 6
    defb  1,50, 1,16, 6
    defb  1,62, 3,16,15
    defb #FF

;; And sat down in a heap, which is what a cat landing on her head does.
granny_sat
    defb  1,30, 3, 6, 4     ; the scarf, a good deal closer to the floor
    defb  1,36, 3, 8,15     ; her face in it
    defb  1,38, 1, 2,12     ; and two eyes that are not focused on anything
    defb  3,38, 1, 2,12
    defb  0,44, 5, 6, 4     ; shoulders, hunched
    defb  0,50, 7,30, 4     ; and the whole of the skirt spread on the floor
    defb  2,54, 2,10, 3     ; the apron on her lap
    defb  0,66, 2, 4, 5     ; and two feet stuck out in front of her
    defb  0,74, 7, 4, 6     ; the broom, flat, where it fell
    defb  5,70, 2, 8,15
    defb #FF

;; ---------------------------------------------------------------------------
;; rush_start - the catnip is down him.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
rush_start
    ld hl,RUSH_TIME
    ld (mitsos_rush),hl
    ld a,1
    call set_speeds
    ld a,RUSH_COL
    call set_border
    jp draw_meter

;; ---------------------------------------------------------------------------
;; rush_stop - and out of him again, however that came about: it ran out, he
;; walked into the basket, or the shop is over.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
rush_stop
    ld hl,0
    ld (mitsos_rush),hl
    xor a
    call set_speeds
    ld a,SHOP_COL
    call set_border
    jp draw_meter

;; ---------------------------------------------------------------------------
;; rush_tick - one 50 Hz step of it.
;;
;; The border is solid green while there is more than two seconds in him and
;; blinks eight frames on, eight off after that, so the moment he stops being
;; able to walk through the broom is not a surprise.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
rush_tick
    ld hl,(mitsos_rush)
    ld a,h
    or l
    ret z
    dec hl
    ld (mitsos_rush),hl
    ld a,h
    or l
    jr z,rush_stop                      ; that was the last of it

    ld a,h                              ; over a second left: solid green
    or a
    jr nz,rush_tick_green
    ld a,l
    cp RUSH_WARN
    jr nc,rush_tick_green
    bit 3,l
    jr nz,rush_tick_green
    ld a,SHOP_COL
    jr rush_tick_border
rush_tick_green
    ld a,RUSH_COL
rush_tick_border
    call set_border
    ;; fall through

;; ---------------------------------------------------------------------------
;; draw_meter - how much of it is left, as a bar in the gap the HUD leaves
;; between the score and LIVES. A bar is 32 frames, so which bar it is on
;; comes off five shifts, and it is only painted on the frame one goes.
;;
;; Nothing is ever lifted off this strip - SHOP_TOP is below it and he cannot
;; rise past that - so unlike everything else that changes the background,
;; this does not have to wait for the window between the erase and the draw.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
draw_meter
    ld hl,(mitsos_rush)
    ld b,5                              ; /32 - RUSH_BAR frames to a bar
draw_meter_shift
    srl h
    rr l
    djnz draw_meter_shift
    ld a,l
    ld hl,rush_bars
    cp (hl)
    ret z                               ; still the same length as it was
    ld (hl),a

    ld b,a                              ; B = bars of catnip left
    ld a,METER_X
    ld (fill_x),a
    ld a,PEN9_BYTE                      ; the catnip's own green
    ld (fill_b),a
    ld a,b
    or a
    jr z,draw_meter_rest
    ld l,b
    ld h,0
    ld (fill_w),hl
    ld hl,line_tab+METER_Y*2
    ld de,METER_H
    push bc
    call fill_rows
    pop bc

draw_meter_rest
    ld a,METER_X                        ; and the dark the rest of it has
    add a,b                             ; already run down to
    ld (fill_x),a
    ld a,METER_W
    sub b
    ret z
    ld l,a
    ld h,0
    ld (fill_w),hl
    ld a,PEN0_BYTE
    ld (fill_b),a
    ld hl,line_tab+METER_Y*2
    ld de,METER_H
    jp fill_rows

;; ---------------------------------------------------------------------------
;; set_speeds - A = 0 for his own weight, 1 for what the catnip makes of it.
;; Six bytes: the two ends his velocity is held between and what a key adds.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
set_speeds
    ld hl,speed_tab
    or a
    jr z,set_speeds_copy
    ld de,6
    add hl,de
set_speeds_copy
    ld de,vx_top
    ld bc,6
    ldir
    ret

speed_tab
    defw VX_MAX,  -VX_MAX,  VX_ACCEL    ; a cat with a shop's worth of lunch in
    defw RUSH_MAX,-RUSH_MAX,RUSH_ACCEL  ; him, and one that has forgotten it

;; ---------------------------------------------------------------------------
;; set_border - A = the hardware colour, already with the #40 on it.
;; Destroys AF, BC, DE.
;; ---------------------------------------------------------------------------
set_border
    ld e,a
    ld bc,#7F10                         ; the Gate Array, border pen
    out (c),c
    out (c),e
    ret

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
;; What is standing on the shelves: the picture, where it is, whether the way
;; out waits for it, and whether it is still there. The last of those is why
;; this is copied into RAM at the top of a game rather than read where it lies.
;; ---------------------------------------------------------------------------
pickups_init
    defw spr_fish
    defb  8, SHELF_4-SPR_FISH_H, 1, 1
    defw spr_cheese
    defb 22, SHELF_3-SPR_FISH_H, 1, 1
    defw spr_sausage
    defb 62, SHELF_1-24-SPR_FISH_H, 1, 1     ; on the counter top
    defw spr_meatball
    defb 42, SHELF_1-8-SPR_FISH_H, 1, 1      ; on the lid of the crates
    defw spr_catnip
    defb 10, SHELF_2-SPR_FISH_H, 0, 1        ; and the one nothing waits for

;; 32 x 20 px: the basket by the top board, shut and then not.
box_basket
    defb  0,  0,  8, 20, 6
    defb  1,  2,  6, 16, 15
    defb  0,  0,  8,  4, 12             ; the lid, while there is one
    defb  1,  8,  6,  2, 6
    defb #FF

box_basket_open
    defb  0,  0,  8, 20, 6
    defb  1,  2,  6, 16, 0              ; the dark inside of it, and a way out
    defb  0,  0,  1,  4, 12             ; the lid, tipped off the side
    defb  7,  0,  1,  4, 12
    defb  1,  8,  6,  2, 6
    defb #FF

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

;; What the keys can push him to, and how hard. In RAM rather than in the
;; instructions because the catnip doubles both of them for eight seconds;
;; set_speeds writes all three at once and they have to stay in this order.
vx_top          defs 2              ; the fastest he is allowed to go right
vx_bot          defs 2              ; and left, which is the same signed
vx_acc          defs 2              ; and what a frame of a key adds to it

mitsos_rush     defs 2              ; frames of catnip left in him
rush_bars       defs 1              ; and how many of them the meter is showing

;; Grandma, who is boxes rather than a sprite and keeps her own patch of shop.
granny_x        defs 1              ; where she is, in bytes
granny_ox       defs 1              ; and where the picture of her still is
granny_dir      defs 1              ; 1 or -1, and which side the broom is on
granny_tick     defs 1              ; frames until her next step
granny_frame    defs 1              ; which half of the stroke
granny_anim     defs 1              ; frames until the other half
granny_stun     defs 1              ; frames left sitting on the floor
granny_drawn    defs 1              ; is her picture on the screen
granny_dirty    defs 1              ; and has anything about it changed
granny_buf      defs GRANNY_BYTES     ; the shop she is standing in front of

score           defs SCORE_BYTES    ; packed BCD, most significant byte first
mezes_left      defs 1              ; how many the basket is still waiting for
basket_open     defs 1              ; and whether it has stopped waiting
mitsos_lives    defs 1              ; three, and the HUD prints this one
mitsos_grace    defs 1              ; frames of blinking left after losing one
mitsos_over     defs 1              ; out of them, and waiting for fire

;; The cast as it stands, copied from foes_init at the top of a game, and one
;; patch of shop per enemy, all of them the size of the biggest.
foes            defs FOE_COUNT*E_SIZE
foe_bufs        defs FOE_COUNT*FOE_BUF

;; The shelves as they stand, and the patch of shop under each thing on them.
pickups         defs PICK_COUNT*P_SIZE
pick_back       defs PICK_COUNT*PICK_BUF

    IF TARGET==1
RUN mitsos_start
    ENDIF

    IF TARGET==2
    SAVE "MITSOS.BIN",mitsos_start,code_end-mitsos_start,DSK,"build/mitsos.dsk"
    ENDIF

    IF TARGET==3
    SAVE "build/out.bin",mitsos_start,code_end-mitsos_start
    ENDIF
