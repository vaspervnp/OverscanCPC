;; ===========================================================================
;; mitsosdata.asm - the shop's sounds, furniture, stock and palette.
;;
;; None of this is ever written to and none of it is ever executed, which is
;; the only property that matters here: it rides down to #0100 with the
;; sprites and the tune, packed, instead of sitting in the sixteen kilobytes
;; between #4000 and #8000 that the code and the title picture are fighting
;; over. Eight hundred bytes of box lists is eight hundred bytes of picture,
;; and the picture is the thing anyone looks at.
;;
;; Included twice: by the game, at ORG ART_ORG for its labels, and by
;; mitsoslow.asm, which assembles the low block on its own so tools/mkpack.py
;; can pack it. Both include mitsosshop.asm first, because every number in
;; here is a shelf.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; The sound effects: mixer, starting period, period step, length in 50 Hz
;; frames. The volume is whatever is left of the length, so everything fades
;; out without costing a byte of state, and a noise effect carries its pitch
;; in the period's low byte and steps by nothing.
;;
;; A mixer bit is 0 to enable. Bit 1 is tone B and it is 0 in both of these,
;; because channel B is the melody and the tune goes on through every one of
;; them; bit 6 is 0 because it is the PSG's port A direction and the key
;; matrix is read through that port. src/mitsossfx.asm is the engine.
;; ---------------------------------------------------------------------------
MIX_TONE        EQU %00111100   ; tone on A, and the melody still on B
MIX_NOISE       EQU %00110101   ; noise on A, and the melody still on B

sfx_tab
    defb MIX_TONE               ; jump: he is a heavy cat, so it starts low -
    defw 500                    ; 250 Hz, up to about 480 in eight frames
    defw -30
    defb 8

    defb MIX_TONE               ; a meze off the shelf: a short bright blip
    defw 160
    defw -10
    defb 4

    defb MIX_TONE               ; the catnip: the same blip that will not stop,
    defw 700                    ; most of a second of it, 180 Hz to 1.2 kHz
    defw -30
    defb 20

    defb MIX_NOISE              ; the belly bounce: a thud, the noise pitch low
    defw 22
    defw 0
    defb 10

    defb MIX_NOISE              ; the broom going past him: a swish, and the
    defw 6                      ; pitch high, because it is bristles
    defw 0
    defb 5

    defb MIX_TONE               ; a life gone: 400 Hz sliding a long way down
    defw 300
    defw 48
    defb 25

    defb MIX_TONE               ; the basket: the lid coming off, rising fast
    defw 900
    defw -55
    defb 14

    defb MIX_TONE               ; and out through it with the shopping: the
    defw 1000                   ; same climb, longer and slower, because it
    defw -36                    ; is the last thing the game says
    defb 26

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