;; ===========================================================================
;; enemy.asm - the robot vacuums and the canary.
;;
;; Enemies live in a fixed array of fourteen-byte records addressed through
;; IY, because IX is already the line_tab cursor inside the sprite routines.
;;
;; Ordering matters now that more than one thing moves. Everything is erased
;; in the exact reverse of the order it was drawn, so a sprite never restores
;; background that another sprite has since been drawn into. The cat is drawn
;; last and erased first, which is also what puts it on top.
;; ===========================================================================

ENEMY_COUNT     EQU 3
ENEMY_BUF       EQU 96          ; background under the largest enemy

E_TYPE          EQU 0           ; 0 empty, 1 robot, 2 canary
E_X             EQU 1
E_Y             EQU 2
E_DX            EQU 3
E_X0            EQU 4           ; patrol limits, in columns
E_X1            EQU 5
E_BASEY         EQU 6           ; canary: top of its arc
E_PHASE         EQU 7
E_STUN          EQU 8
E_OX            EQU 9           ; where its saved background came from
E_OY            EQU 10
E_OW            EQU 11
E_OH            EQU 12
E_DRAWN         EQU 13
E_SIZE          EQU 14

ET_ROBOT        EQU 1
ET_CANARY       EQU 2

SINE_LEN        EQU 32
SINE_MASK       EQU SINE_LEN-1
ENEMY_STUN      EQU 100         ; two seconds flat after a belly-flop
FLOP_REACH_Y    EQU 40          ; scanlines above and below the landing

;; ENEMY_BUF is checked against the actual sprite sizes in loukoumas.asm,
;; once the generated sprite data has been included.

;; ---------------------------------------------------------------------------
;; enemies_init - copy the level's starting set into the live array.
;; ---------------------------------------------------------------------------
enemies_init
    ld hl,enemy_start
    ld de,enemies
    ld b,ENEMY_COUNT
enemies_init_loop
    push bc
    ld bc,7                     ; type, x, y, dx, x0, x1, basey
    ldir
    xor a
    ld (de),a                   ; phase
    inc de
    ld (de),a                   ; stun
    inc de
    ld (de),a                   ; ox
    inc de
    ld (de),a                   ; oy
    inc de
    ld (de),a                   ; ow
    inc de
    ld (de),a                   ; oh
    inc de
    ld (de),a                   ; drawn
    inc de
    pop bc
    djnz enemies_init_loop
    ret

;; ---------------------------------------------------------------------------
;; enemy_sprite - HL = the sprite for the enemy IY points at.
;; ---------------------------------------------------------------------------
enemy_sprite
    ld a,(iy+E_TYPE)
    cp ET_ROBOT
    jr nz,enemy_sprite_canary
    ld hl,spr_robot
    ret
enemy_sprite_canary
    ld hl,spr_canary
    ret

;; ---------------------------------------------------------------------------
;; enemies_update
;; ---------------------------------------------------------------------------
enemies_update
    ld iy,enemies
    ld b,ENEMY_COUNT
enemies_update_loop
    push bc
    ld a,(iy+E_TYPE)
    or a
    call nz,enemy_update_one
    pop bc
    ld de,E_SIZE
    add iy,de
    djnz enemies_update_loop
    ret

enemy_update_one
    ld a,(iy+E_STUN)
    or a
    jr z,enemy_update_move
    dec a                       ; still seeing stars
    ld (iy+E_STUN),a
    ret
enemy_update_move
    ld a,(iy+E_TYPE)
    cp ET_ROBOT
    jr z,enemy_move_robot
    ;; fall through to the canary

;; ---------------------------------------------------------------------------
;; enemy_move_canary - a bounce across its patrol, plus a sine in y.
;; ---------------------------------------------------------------------------
enemy_move_canary
    call enemy_bounce
    ld a,(iy+E_PHASE)
    inc a
    and SINE_MASK
    ld (iy+E_PHASE),a
    ld e,a
    ld d,0
    ld hl,sine_tab
    add hl,de
    ld a,(iy+E_BASEY)
    add a,(hl)
    ld (iy+E_Y),a
    ret

;; ---------------------------------------------------------------------------
;; enemy_move_robot - half the cat's speed, so it can be outrun.
;; ---------------------------------------------------------------------------
enemy_move_robot
    ld a,(frame_count)
    and 1
    ret nz
    ;; fall through

;; ---------------------------------------------------------------------------
;; enemy_bounce - step E_X by E_DX, turning round at the patrol limits.
;; ---------------------------------------------------------------------------
enemy_bounce
    ld a,(iy+E_X)
    add a,(iy+E_DX)
    ld (iy+E_X),a
    cp (iy+E_X0)
    jr c,enemy_bounce_turn
    cp (iy+E_X1)
    ret z
    ret c
enemy_bounce_turn
    ld a,(iy+E_DX)
    bit 7,a
    jr z,enemy_bounce_high
    ld a,(iy+E_X0)
    jr enemy_bounce_clamp
enemy_bounce_high
    ld a,(iy+E_X1)
enemy_bounce_clamp
    ld (iy+E_X),a
    ld a,(iy+E_DX)
    neg
    ld (iy+E_DX),a
    ret

;; ---------------------------------------------------------------------------
;; enemies_stun - the belly-flop shockwave. Everything at roughly the height
;; the cat landed at stops dead and is harmless while it does, however far
;; along the shelf it is: the whole floor shook, not a patch of it. That makes
;; the flop the tool for getting past a robot that patrols a whole shelf.
;; ---------------------------------------------------------------------------
enemies_stun
    ld iy,enemies
    ld b,ENEMY_COUNT
enemies_stun_loop
    push bc
    ld a,(iy+E_TYPE)
    or a
    call nz,enemy_stun_one
    pop bc
    ld de,E_SIZE
    add iy,de
    djnz enemies_stun_loop
    ret

enemy_stun_one
    ld a,(iy+E_Y)               ; vertical distance only
    ld b,a
    ld a,(cat_y)
    sub b
    jp p,enemy_stun_dy
    neg
enemy_stun_dy
    cp FLOP_REACH_Y+1
    ret nc
    ld a,ENEMY_STUN
    ld (iy+E_STUN),a
    ret

;; ---------------------------------------------------------------------------
;; enemies_hit_cat - carry set if anything awake is touching the cat.
;; ---------------------------------------------------------------------------
enemies_hit_cat
    ld iy,enemies
    ld b,ENEMY_COUNT
enemies_hit_loop
    push bc
    ld a,(iy+E_TYPE)
    or a
    jr z,enemies_hit_next
    ld a,(iy+E_STUN)
    or a
    jr nz,enemies_hit_next
    call enemy_sprite
    ld a,(hl)
    ld (box_w),a
    inc hl
    ld a,(hl)
    ld (box_h),a
    ld a,(iy+E_X)
    ld (box_x),a
    ld a,(iy+E_Y)
    ld (box_y),a
    call cat_hits_box
    jr nc,enemies_hit_next
    pop bc
    scf
    ret
enemies_hit_next
    pop bc
    ld de,E_SIZE
    add iy,de
    djnz enemies_hit_loop
    or a
    ret

;; ---------------------------------------------------------------------------
;; enemies_draw / enemies_erase. Draw runs forwards, erase backwards, so the
;; whole scene unwinds in the reverse of the order it was laid down.
;; ---------------------------------------------------------------------------
enemies_draw
    ld hl,enemy_bufs
    ld (e_bufp),hl
    ld iy,enemies
    ld b,ENEMY_COUNT
enemies_draw_loop
    push bc
    ld a,(iy+E_TYPE)
    or a
    call nz,enemy_draw_one
    pop bc
    ld de,E_SIZE
    add iy,de
    ld hl,(e_bufp)
    ld de,ENEMY_BUF
    add hl,de
    ld (e_bufp),hl
    djnz enemies_draw_loop
    ret

enemy_draw_one
    call enemy_sprite
    call spr_size
    push hl                     ; the pixel data
    ld a,(spr_w)
    ld (iy+E_OW),a
    ld a,(spr_h)
    ld (iy+E_OH),a
    ld a,(iy+E_X)
    ld (spr_x),a
    ld (iy+E_OX),a
    ld a,(iy+E_Y)
    ld (iy+E_OY),a
    call spr_row_ptr
    ld hl,(e_bufp)
    call spr_save
    ld a,(iy+E_Y)
    call spr_row_ptr
    pop hl
    call spr_blit
    ld a,1
    ld (iy+E_DRAWN),a
    ret

enemies_erase
    ld hl,enemy_bufs+(ENEMY_COUNT-1)*ENEMY_BUF
    ld (e_bufp),hl
    ld iy,enemies+(ENEMY_COUNT-1)*E_SIZE
    ld b,ENEMY_COUNT
enemies_erase_loop
    push bc
    ld a,(iy+E_DRAWN)
    or a
    call nz,enemy_erase_one
    pop bc
    ld de,-E_SIZE
    add iy,de
    ld hl,(e_bufp)
    ld de,-ENEMY_BUF
    add hl,de
    ld (e_bufp),hl
    djnz enemies_erase_loop
    ret

enemy_erase_one
    ld a,(iy+E_OW)
    ld (spr_w),a
    ld a,(iy+E_OH)
    ld (spr_h),a
    ld a,(iy+E_OX)
    ld (spr_x),a
    ld a,(iy+E_OY)
    call spr_row_ptr
    ld hl,(e_bufp)
    jp spr_restore

;; ---------------------------------------------------------------------------
;; Sine table for the canary: 32 steps of an offset from 0 to 32 scanlines,
;; so the arithmetic stays unsigned. E_BASEY is the top of the arc.
;; ---------------------------------------------------------------------------
sine_tab
    defb 16,19,22,25,27,29,31,32,32,32,31,29,27,25,22,19
    defb 16,13,10, 7, 5, 3, 1, 0, 0, 0, 1, 3, 5, 7,10,13
