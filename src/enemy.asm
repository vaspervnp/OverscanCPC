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

E_TYPE          EQU 0           ; 0 for an empty slot, else an ET_* id
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
E_ODIR          EQU 14          ; which way it was facing when it was drawn
E_SIZE          EQU 15

;; How much of a record a room actually supplies: type, x, y, dx, x0, x1,
;; basey. The rest is run-time state and starts at zero. Both halves are
;; derived from E_SIZE, because writing the two lengths out by hand is how a
;; new field silently shifts every record after the first.
E_FROM_ROOM     EQU 7

SINE_LEN        EQU 32
SINE_MASK       EQU SINE_LEN-1
ENEMY_STUN      EQU 100         ; two seconds flat after a belly-flop
FLOP_REACH_Y    EQU 40          ; scanlines above and below the landing

;; ENEMY_BUF is checked against the actual sprite sizes in loukoumas.asm,
;; once the generated sprite data has been included.

;; ---------------------------------------------------------------------------
;; enemies_init - HL = a room's starting set, B = how many. Slots the room
;; does not use are blanked, so a quiet room really is quiet.
;; ---------------------------------------------------------------------------
enemies_init
    ld de,enemies
    ld a,b
    or a
    jr z,enemies_init_spare
    push bc
enemies_init_loop
    push bc
    ld bc,E_FROM_ROOM           ; type, x, y, dx, x0, x1, basey
    ldir
    xor a                       ; phase, stun, and the drawn-at record
    ld b,E_SIZE-E_FROM_ROOM
enemies_init_blank
    ld (de),a
    inc de
    djnz enemies_init_blank
    pop bc
    djnz enemies_init_loop
    pop bc

enemies_init_spare
    ld a,ENEMY_COUNT
    sub b
    ret z
    ld b,a
enemies_init_empty
    push bc
    ld b,E_SIZE
    xor a
enemies_init_empty_loop
    ld (de),a
    inc de
    djnz enemies_init_empty_loop
    pop bc
    djnz enemies_init_empty
    ret

;; ---------------------------------------------------------------------------
;; enemy_kind - HL = this enemy's row of enemy_kinds: sprite, then behaviour.
;; Type 0 is an empty slot and never gets here, so the ids start at 1.
;; ---------------------------------------------------------------------------
enemy_kind
    ld a,(iy+E_TYPE)
    dec a
    ld l,a
    ld h,0
    ld d,h
    ld e,l
    add hl,hl                   ; five bytes to the row
    add hl,hl
    add hl,de
    ld de,enemy_kinds
    add hl,de
    ret

;; ---------------------------------------------------------------------------
;; enemy_sprite - HL = the sprite for the enemy IY points at, facing whichever
;; way it is going.
;; ---------------------------------------------------------------------------
enemy_sprite
    call enemy_kind
    bit 7,(iy+E_DX)             ; a negative step is leftwards
    jr z,enemy_sprite_take
    inc hl
    inc hl
enemy_sprite_take
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
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
    call enemy_kind
    ld de,4
    add hl,de
    ld a,(hl)                   ; which of the two behaviours it is
    or a
    jr z,enemy_move_walk
    ;; fall through to the one that flies

;; ---------------------------------------------------------------------------
;; enemy_move_fly - a bounce across its patrol, plus a sine in y. The canary,
;; the pigeons, the wasps, the paper plane, the syringe and the bats.
;; ---------------------------------------------------------------------------
enemy_move_fly
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
;; enemy_move_walk - half the cat's speed, so it can be outrun. The robots,
;; the dog, the football, the caretaker's bucket, the blob and the stray.
;;
;; Counted per enemy rather than off the parity of frame_count. A free-running
;; interrupt counter looks like the same thing until the game loop overruns a
;; frame: frame_count then goes up by two, the parity does not change, and the
;; robot either steps every single update or none of them until the next
;; overrun flips it back. That reads as robots that stop dead and start again
;; for no reason, and it happened most often on the frame a sausage was
;; collected, because that is the frame that repaints the whole HUD.
;;
;; E_PHASE is free here - only the ones that fly use it, as a sine index.
;; ---------------------------------------------------------------------------
enemy_move_walk
    ld a,(iy+E_PHASE)
    xor 1
    ld (iy+E_PHASE),a
    ret nz                      ; step on every second update of this enemy
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
    call spr_row_ptr            ; A is still E_Y
    ld de,(e_bufp)
    pop hl                      ; the pixel data
    call spr_draw
    ld a,(iy+E_DX)
    ld (iy+E_ODIR),a            ; so a turn counts as a change even standing still
    ld a,1
    ld (iy+E_DRAWN),a
    ret

;; ---------------------------------------------------------------------------
;; enemy_moved - IY = an enemy -> NZ if it has to be lifted off and put back.
;;
;; A walking enemy steps on every second update, so on half the renders it is
;; exactly where it already is and rebuilding it is three thousand
;; microseconds spent to change nothing - and those microseconds are the ones
;; the beam is waiting for.
;; Destroys AF.
;; ---------------------------------------------------------------------------
enemy_moved
    ld a,(iy+E_DRAWN)
    or a
    jr z,enemy_moved_yes
    ld a,(iy+E_X)
    cp (iy+E_OX)
    jr nz,enemy_moved_yes
    ld a,(iy+E_Y)
    cp (iy+E_OY)
    jr nz,enemy_moved_yes
    ld a,(iy+E_DX)
    xor (iy+E_ODIR)
    and #80                     ; only the way it faces shows
    ret
enemy_moved_yes
    ld a,1
    or a                        ; NZ - ld a,n leaves the flags alone
    ret

;; ---------------------------------------------------------------------------
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
