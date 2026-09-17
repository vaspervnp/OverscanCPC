;; ===========================================================================
;; play.asm - the play field: a floor, some sausages, and Loukoumas walking.
;;
;; No physics yet. This exists to exercise the sprite engine on a real
;; overscan screen: the cat walks over scenery and leaves it intact, because
;; what spr_save keeps is the background as drawn, sausages included.
;; ===========================================================================

PLAY_TOP        EQU 12
FLOOR_Y         EQU 236
FLOOR_H         EQU DISPLAY_LINES-FLOOR_Y

CAT_W           EQU SPR_CAT_STAND_W
CAT_H           EQU SPR_CAT_STAND_H
CAT_FLOOR_Y     EQU FLOOR_Y-CAT_H
CAT_X_MAX       EQU BYTES_PER_LINE-CAT_W
CAT_START_X     EQU 12
WALK_BIT        EQU #04                 ; animation cell changes every 4 frames

SAUSAGE_COUNT   EQU 3
SAUSAGE_Y       EQU FLOOR_Y-SPR_SAUSAGE_H

;; ---------------------------------------------------------------------------
;; play_screen - runs until Escape, then returns to the title.
;; ---------------------------------------------------------------------------
play_screen
    call play_setup
play_loop
    call wait_frame
    call read_controls
    ld a,(ctl_pressed)
    bit CTL_QUIT,a
    ret nz
    call cat_erase
    call cat_move
    call cat_draw
    jr play_loop

;; ---------------------------------------------------------------------------
;; play_setup - paint the room and place everything.
;; ---------------------------------------------------------------------------
play_setup
    ld hl,pal_play
    call set_pal

    xor a
    ld (cat_drawn),a
    ld (cat_anim),a
    ld a,CAT_START_X
    ld (cat_x),a
    ld a,CAT_FLOOR_Y
    ld (cat_y),a
    ld hl,spr_cat_stand
    ld (cat_spr),hl

    ld hl,line_tab
    ld de,DISPLAY_LINES
    ld a,PEN0_BYTE
    call clear_rows

    ld hl,line_tab+FLOOR_Y*2
    ld de,FLOOR_H
    ld a,PEN3_BYTE
    call clear_rows

    ld a,2                      ; the score caption sits on the background, not
    ld (txt_x),a                ; on a band: a glyph only sets pen bit 0, so it
    ld hl,line_tab+2*2          ; would be invisible over pen 1 or pen 3
    ld (txt_row),hl
    ld a,MSG_SCORE
    call msg_small

    ld hl,sausage_x
    ld b,SAUSAGE_COUNT
play_setup_sausage
    push bc
    ld a,(hl)
    ld (spr_x),a
    push hl
    ld hl,spr_sausage
    call spr_size
    push hl
    ld a,SAUSAGE_Y
    call spr_row_ptr
    pop hl
    call spr_blit
    pop hl
    inc hl
    pop bc
    djnz play_setup_sausage
    ret

sausage_x   defb 6,44,86

;; ---------------------------------------------------------------------------
;; cat_erase - put back the background the cat was covering. Skipped on the
;; first frame, when there is nothing saved yet.
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

;; ---------------------------------------------------------------------------
;; cat_move - one step per frame: 4 pixels across, 2 scanlines up or down.
;; C is set if the cat moved horizontally, which is what drives the waddle.
;; ---------------------------------------------------------------------------
cat_move
    ld a,(ctl_now)
    ld b,a
    ld c,0

    bit CTL_LEFT,b
    jr z,cat_move_right
    ld a,(cat_x)
    or a
    jr z,cat_move_right
    dec a
    ld (cat_x),a
    ld c,1

cat_move_right
    bit CTL_RIGHT,b
    jr z,cat_move_up
    ld a,(cat_x)
    cp CAT_X_MAX
    jr nc,cat_move_up
    inc a
    ld (cat_x),a
    ld c,1

cat_move_up
    bit CTL_UP,b
    jr z,cat_move_down
    ld a,(cat_y)
    cp PLAY_TOP+2
    jr c,cat_move_down
    sub 2
    ld (cat_y),a

cat_move_down
    bit CTL_DOWN,b
    jr z,cat_move_anim
    ld a,(cat_y)
    cp CAT_FLOOR_Y-1
    jr nc,cat_move_anim
    add a,2
    ld (cat_y),a

cat_move_anim
    ld a,c
    or a
    jr z,cat_move_stand
    ld a,(cat_anim)
    inc a
    ld (cat_anim),a
    and WALK_BIT
    jr z,cat_move_walk1
    ld hl,spr_cat_walk2
    jr cat_move_set
cat_move_walk1
    ld hl,spr_cat_walk1
    jr cat_move_set
cat_move_stand
    xor a
    ld (cat_anim),a
    ld hl,spr_cat_stand
cat_move_set
    ld (cat_spr),hl
    ret

;; ---------------------------------------------------------------------------
;; cat_draw - save the background at the new position, then blit.
;; ---------------------------------------------------------------------------
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
;; In-game palette, in loukoumas.md's own ink order: the sprite art is drawn
;; against it, so pen 2 has to be the fur.
;; ---------------------------------------------------------------------------
pal_play
    defb 0,   #40+4             ; pen 0 - deep navy, the room
    defb 1,   #40+7             ; pen 1 - coral: paws, nose, sausages, text
    defb 2,   #40+10            ; pen 2 - butter yellow: fur
    defb 3,   #40+11            ; pen 3 - white: eyes, belly, the floor
    defb #10, #40+4
    defb #FF
