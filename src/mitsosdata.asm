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
pickups_init                                 ; picture, x, y, meze, alive, ox, oy
    defw spr_fish
    defb  8, SHELF_4-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_cheese
    defb 22, SHELF_3-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_sausage
    defb 62, SHELF_1-24-SPR_FISH_H, 1, 1, #FF, 0  ; on the counter top
    defw spr_meatball
    defb 42, SHELF_1-8-SPR_FISH_H, 1, 1, #FF, 0   ; on the lid of the crates
    defw spr_catnip
    defb 10, SHELF_2-SPR_FISH_H, 0, 1, #FF, 0     ; the one nothing waits for

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