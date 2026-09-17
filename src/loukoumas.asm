;; ===========================================================================
;; ΛΟΥΚΟΥΜΑΣ / LOUKOUMAS - title screen, 384x272 full overscan, mode 0.
;;
;; Both languages live in the same binary: tools/mktext.py builds a string
;; table per language from text/loukoumas.*.txt and every line drawn here goes
;; through a message id, never a literal. LANG picks which table txt_lang
;; starts on, so switching language at run time is one byte.
;;
;; L switches language on the title screen, FIRE starts the play field,
;; Escape comes back.
;;
;; Build with TARGET=1 snapshot, 2 DSK, 3 raw binary; LANG=0 English, 1 Greek.
;; ===========================================================================

    include "config.asm"

    IF TARGET==1
BUILDSNA
BANKSET 0
    ENDIF

TITLE_YS        EQU 6           ; big text: 8 source rows * 6 = 48 px tall
BAND_H          EQU 12          ; the coral bands top and bottom

Y_LANGNAME      EQU 2           ; inside the top band
Y_TITLE         EQU 60
Y_SUBTITLE      EQU 120
Y_PRESS         EQU 180
Y_LANGHINT      EQU DISPLAY_LINES-BAND_H+2

H_SMALL         EQU 8                   ; one small text row
H_TITLE         EQU TITLE_YS*8
BLINK_BIT       EQU #20                 ; frame_count bit: ~0.64 s each way

    ORG #4000

;; ---------------------------------------------------------------------------
loukoumas_start
    di
    ld sp,STACK_TOP

    ld bc,#7F8C                 ; mode 0, both ROMs disabled
    out (c),c

    ld hl,pal_blank             ; build the screen unseen
    call set_pal

    ld a,LANG
    ld (txt_lang),a

    call build_line_tab
    call draw_title_background
    call draw_title_text

    call setup_crtc             ; now switch the display to overscan
    ld hl,pal_title
    call set_pal

    call irq_init

;; ---------------------------------------------------------------------------
;; Title, then play, then back to the title. The screen is already drawn on
;; the way in, so only the return trip has to repaint it.
;; ---------------------------------------------------------------------------
main_loop
    call title_loop
    call play_screen
    ld hl,pal_title
    call set_pal
    call draw_title_background
    call draw_title_text
    jr main_loop

;; ---------------------------------------------------------------------------
;; title_loop - one pass per 50 Hz frame; returns when FIRE is pressed.
;; ---------------------------------------------------------------------------
title_loop
    call wait_frame
    call read_controls

    ld a,(ctl_pressed)
    bit CTL_FIRE,a
    ret nz

    bit CTL_LANG,a
    jr z,title_no_lang
    ld a,(txt_lang)             ; L cycles to the next language
    inc a
    cp LANG_COUNT
    jr c,title_lang_store
    xor a
title_lang_store
    ld (txt_lang),a
    call draw_title_text

title_no_lang
    call blink_press
    jr title_loop

;; ---------------------------------------------------------------------------
;; blink_press - flash the "press fire" line, and prove the heartbeat runs at
;; the right rate while it is at it.
;;
;; This routine owns that row: draw_title_text only clears it and leaves
;; press_state disagreeing with the current phase, so the next call repaints
;; whichever state the blink is actually in. Having both routines draw there
;; is what made the line vanish the frame after a language change.
;; ---------------------------------------------------------------------------
blink_press
    ld a,(frame_count)
    and BLINK_BIT
    ld b,a
    ld a,(press_state)
    cp b
    ret z
    ld a,b
    ld (press_state),a
    or a
    jr nz,blink_press_hide      ; visible for the first half of the cycle
    ld hl,line_tab+Y_PRESS*2
    ld (txt_row),hl
    ld a,MSG_PRESS
    jp msg_small_centre
blink_press_hide
    ld hl,line_tab+Y_PRESS*2
    ld de,H_SMALL
    ld a,PEN0_BYTE
    jp clear_rows

;; ---------------------------------------------------------------------------
;; draw_title_background - navy everywhere, with a coral band across the top
;; and bottom of the overscan window.
;;
;; The bands sit at the very edges of the 384x272 picture, well outside the
;; 320x200 a stock CPC would show, so they only exist because of the overscan.
;; Text crossing them comes out white rather than yellow for free - see the
;; note about OR blending at the top of text.asm.
;; ---------------------------------------------------------------------------
draw_title_background
    ld hl,line_tab
    ld de,DISPLAY_LINES
    ld a,PEN0_BYTE
    call clear_rows

    ld hl,line_tab
    ld de,BAND_H
    ld a,PEN2_BYTE
    call clear_rows

    ld hl,line_tab+(DISPLAY_LINES-BAND_H)*2
    ld de,BAND_H
    ld a,PEN2_BYTE
    jp clear_rows

;; ---------------------------------------------------------------------------
;; draw_title_text - every line, in whichever language txt_lang is on.
;; Each row is repainted first so this doubles as the language-change redraw
;; without having to rebuild the whole screen.
;; ---------------------------------------------------------------------------
draw_title_text
    ld hl,line_tab+Y_LANGNAME*2
    ld de,H_SMALL
    ld a,PEN2_BYTE
    call clear_rows
    ld hl,line_tab+Y_LANGNAME*2
    ld (txt_row),hl
    ld a,MSG_LANGNAME
    call msg_small_centre

    ld hl,line_tab+Y_TITLE*2
    ld de,H_TITLE
    ld a,PEN0_BYTE
    call clear_rows
    ld a,1                      ; 1 byte per source pixel = 24 px per letter
    ld (txt_xs),a
    ld a,TITLE_YS
    ld (txt_ys),a
    ld hl,line_tab+Y_TITLE*2
    ld (txt_row),hl
    ld a,MSG_TITLE1
    call msg_big_centre

    ld hl,line_tab+Y_SUBTITLE*2
    ld de,H_SMALL
    ld a,PEN0_BYTE
    call clear_rows
    ld hl,line_tab+Y_SUBTITLE*2
    ld (txt_row),hl
    ld a,MSG_TITLE2
    call msg_small_centre

    ;; The "press fire" row belongs to blink_press. Clear it and leave
    ;; press_state disagreeing with the current phase so it repaints next frame.
    ld hl,line_tab+Y_PRESS*2
    ld de,H_SMALL
    ld a,PEN0_BYTE
    call clear_rows
    ld a,(frame_count)
    and BLINK_BIT
    xor BLINK_BIT
    ld (press_state),a

    ld hl,line_tab+Y_LANGHINT*2
    ld de,H_SMALL
    ld a,PEN2_BYTE
    call clear_rows
    ld hl,line_tab+Y_LANGHINT*2
    ld (txt_row),hl
    ld a,MSG_LANGHINT
    jp msg_small_centre

;; ---------------------------------------------------------------------------
;; Palette.
;;
;; The four colours are the ones loukoumas.md asks for, but the ink order is
;; not the document's. A glyph pixel only ever sets pen bit 0, so text lands on
;; pen 1 over the background and pen 3 over a band - the inks are assigned to
;; put a readable colour on each of those, which the document's order would
;; not (it would leave white text on bright yellow).
;;
;; The document's own Gate Array values are also not the colours it names:
;; &54 is hardware 20, black, not deep navy, and &5C is hardware 28, dark red,
;; not coral. These are the named colours.
;; ---------------------------------------------------------------------------
pal_title
    defb 0,   #40+4             ; pen 0 - deep navy, background
    defb 1,   #40+10            ; pen 1 - butter yellow, text on the background
    defb 2,   #40+7             ; pen 2 - coral, the overscan bands
    defb 3,   #40+11            ; pen 3 - white, text crossing a band
    defb 4,   #40+20            ; the rest are the play palette, so that coming
    defb 5,   #40+0             ; back to the title does not have to reload
    defb 6,   #40+30            ; anything the game already set
    defb 7,   #40+14
    defb 8,   #40+22
    defb 9,   #40+18
    defb 10,  #40+6
    defb 11,  #40+19
    defb 12,  #40+28
    defb 13,  #40+12
    defb 14,  #40+24
    defb 15,  #40+3
    defb #10, #40+4             ; border - navy, blends into the picture
    defb #FF

    include "crtc.asm"
    include "video.asm"
    include "irq.asm"
    include "keys.asm"
    include "text.asm"
    ;; Data first: rooms.asm names sprites and messages in table entries, and
    ;; play.asm indexes room records with IY, both of which rasm resolves as it
    ;; reads them rather than on a later pass.
    include "sprite.asm"
    include "font.asm"
    include "strings.asm"
    include "sprites.asm"
    include "enemy.asm"
    include "rooms.asm"
    include "play.asm"

;; ASSERT evaluates immediately, so this has to come after the generated
;; sprite sizes exist.
    ASSERT SPR_ROBOT_W*SPR_ROBOT_H <= ENEMY_BUF
    ASSERT SPR_CANARY_W*SPR_CANARY_H <= ENEMY_BUF

code_end

    include "workspace.asm"

;; ---------------------------------------------------------------------------
;; The cat's own workspace: sized from the sprite data, so it cannot live in
;; the shared engine workspace.
;; ---------------------------------------------------------------------------
cat_x       defs 1              ; column, in bytes
cat_yf      defs 1              ; 8.8 fixed point: cat_yf then cat_y, so
cat_y       defs 1              ; "ld hl,(cat_yf)" loads the pair
cat_vy      defs 2              ; vertical velocity, same units, signed
cat_state   defs 1              ; ST_GROUND / ST_AIR / ST_FLOP / ST_ROLL
cat_stun    defs 1              ; frames left flat after a belly-flop
cat_w       defs 1              ; current sprite size
cat_h       defs 1
cat_moved   defs 1              ; did it move horizontally this frame?
cat_ofeet   defs 1              ; feet before and after the vertical step
cat_nfeet   defs 1
shake_timer defs 1
cat_ox      defs 1              ; where the saved background came from
cat_oy      defs 1
cat_ow      defs 1
cat_oh      defs 1
cat_spr     defs 2              ; sprite for this frame
cat_drawn   defs 1              ; is there a background to put back?
cat_anim    defs 1
cat_buf     defs SPR_MAX_BYTES
cat_startx  defs 1                  ; where this room puts the cat
cat_starty  defs 1

;; rooms.asm - whichever room is loaded
cur_room    defs 1
room_name   defs 1                  ; message id for the HUD
cur_plat    defs 2
cur_saus    defs 2
cur_nsaus   defs 1
cur_props   defs 2
exit_x      defs 1
exit_y      defs 1
exit_w      defs 1
exit_h      defs 1
exit_shut   defs 1                  ; prop ids for the two states
exit_open   defs 1
exit_px     defs 1                  ; where the exit prop is drawn
exit_py     defs 1
prop_x      defs 1                  ; origin of the prop being drawn
prop_y      defs 1
box_top     defs 1                  ; the box draw_boxes is filling
box_high    defs 1
box_over    defs 1                  ; did its top run off the bottom?

;; play.asm - score and larder
score         defs SCORE_BYTES      ; packed BCD, most significant byte first
sausages_got  defs 1
sausage_alive defs SAUSAGE_MAX
saus_x        defs 1                ; the sausage being tested
saus_y        defs 1
hud_dirty     defs 1
level_done    defs 1                ; every sausage in this room found
game_over     defs 1                ; out of lives, or the fridge is open
cat_lives     defs 1
cat_invul     defs 1                ; frames of grace after a respawn
box_x         defs 1                ; the box cat_hits_box is testing against
box_y         defs 1
box_w         defs 1
box_h         defs 1

;; enemy.asm
enemies       defs ENEMY_COUNT*E_SIZE
enemy_bufs    defs ENEMY_COUNT*ENEMY_BUF
e_bufp        defs 2                ; buffer cursor while walking the array

;; The order the sprites are laid down in, worked out fresh every frame from
;; where they are on screen. See sprites_order in play.asm.
SPRITE_MAX    EQU ENEMY_COUNT+1
ord_n         defs 1
ord_y         defs SPRITE_MAX
draw_order    defs SPRITE_MAX       ; ids: 0 is the cat, an enemy is index+1
draw_n        defs 1                ; how many of them were drawn last frame

    IF TARGET==1
RUN loukoumas_start
    ENDIF

    IF TARGET==2
      IF LANG==0
    SAVE "LOUK.BIN",loukoumas_start,code_end-loukoumas_start,DSK,"build/loukoumas_en.dsk"
      ENDIF
      IF LANG==1
    SAVE "LOUK.BIN",loukoumas_start,code_end-loukoumas_start,DSK,"build/loukoumas_el.dsk"
      ENDIF
    ENDIF
