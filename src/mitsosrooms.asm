;; ===========================================================================
;; mitsosrooms.asm - the shop, room by room.
;;
;; The first game composes its rooms out of tables and this one now does the
;; same, for the same reason: a 192x272 mode 0 background is 26 KB and two of
;; them would not fit, let alone four. A room is a handful of pointers - what
;; he can stand on, what the furniture is, what is standing on it, what is
;; after him - and five pens.
;;
;; **The five pens are how a room gets its own light, and they cost no code at
;; all.** The painter draws the same five things in every room: the wall, the
;; joints cut into it, the painted lower half of it, the floor band, and the
;; grout between its tiles. Give any of them the same pen as the thing behind
;; it and it stops being there - mortar the colour of the wall is plaster,
;; grout the colour of the floor is tarmac - so a back room is not a special
;; case in draw_shop, it is four bytes.
;;
;; Everything else about a room is where things are. Every room has the same
;; three of them after him and the same five things to pick up, four of which
;; the basket waits for: that is the game's grammar and not something a room
;; gets to change, and it means the arrays in RAM are one size and the loops
;; over them are one instruction.
;; ===========================================================================

;; A room, as the record room_load copies into RAM.
R_PLAT          EQU 0           ; defw - what he can stand on
R_PROPS         EQU 2           ; defw - the furniture, drawn once
R_SOAP          EQU 4           ; defw - and where somebody has been mopping
R_PICKS         EQU 6           ; defw - what is standing on the furniture
R_FOES          EQU 8           ; defw - and what is after him
R_STARTX        EQU 10          ; where he comes in
R_BASKX         EQU 11          ; the way out, which opens on the last meze
R_BASKY         EQU 12
R_GRANX0        EQU 13          ; the two ends of Grandma's beat
R_GRANX1        EQU 14
R_WALL          EQU 15          ; the five pens, as solid mode 0 bytes
R_MORTAR        EQU 16          ; joints, and the lines under the dado and at
                                ; the top of the floor
R_DADO          EQU 17          ; the painted lower wall
R_FLOOR         EQU 18
R_GROUT         EQU 19          ; between the floor tiles
R_BORDER        EQU 20          ; hardware colour for the frame round the lot
R_SIZE          EQU 21

ROOM_COUNT      EQU 4

;; ---------------------------------------------------------------------------
;; The rooms themselves: five pointers, where things stand, and five pens.
;; The order of the pens is wall, mortar, dado, floor, grout.
;; ---------------------------------------------------------------------------
rooms
    ;; --- 1: the shop ------------------------------------------------------
    ;; Brick, a teal dado, grey tiles with white grout: a Greek grocery with
    ;; the harbour out of the window.
    defw r1_plat, r1_props, r1_soap, r1_picks, r1_foes
    defb 8                              ; he comes in by the door
    defb 26, SHELF_4-20                 ; the basket, on the top board
    defb 30, 50                         ; her beat, in front of the shelving
    defb PEN1_BYTE, PEN15_BYTE, PEN10_BYTE, PEN5_BYTE, PEN3_BYTE
    defb #40+7                          ; coral, so the border matches the wall

    ;; --- 2: the store room ------------------------------------------------
    ;; Teal plaster wall to ceiling - the mortar and the dado are both the pen
    ;; of the wall, so neither the joints nor the dado are there at all - and
    ;; wooden boards underfoot, the grout left showing to be the gap between
    ;; the planks.
    defw r2_plat, r2_props, r2_soap, r2_picks, r2_foes
    defb 8
    defb 66, SHELF_4-20                 ; the basket, on the top board again
    defb 24, 56                         ; her beat, across the middle of it
    defb PEN10_BYTE, PEN10_BYTE, PEN10_BYTE, PEN6_BYTE, PEN15_BYTE
    defb #40+6                          ; teal

    ;; --- 3: the cold room -------------------------------------------------
    ;; White with grey joints, which is the brick painter drawing wall tiles
    ;; and not knowing the difference, and cyan for everything cold.
    ;;
    ;; He comes in at the right-hand end, so the mouse's beat and the gull's
    ;; both stop short of it: a room that walks something into him while he
    ;; is still standing where it put him is not difficult, it is rude.
    defw r3_plat, r3_props, r3_soap, r3_picks, r3_foes
    defb 88                             ; in at the far end for once
    defb  4, SHELF_4-20
    defb 36, 66
    defb PEN3_BYTE, PEN5_BYTE, PEN10_BYTE, PEN5_BYTE, PEN11_BYTE
    defb #40+19                         ; bright cyan

    ;; --- 4: the yard ------------------------------------------------------
    ;; Sky for a wall with nothing cut into it, the yard wall for a dado, and
    ;; tarmac: the grout is the pen of the floor, so there are no tiles.
    defw r4_plat, r4_props, r4_soap, r4_picks, r4_foes
    defb 4                              ; out of the back door, in the corner
    defb 76, SHELF_3-20                 ; the basket, on the right-hand tower
    defb 28, 64
    defb PEN11_BYTE, PEN11_BYTE, PEN6_BYTE, PEN5_BYTE, PEN5_BYTE
    defb #40+19                         ; sky

;; ---------------------------------------------------------------------------
;; What he can stand on: first column, last column, top scanline - and #FF at
;; the end of it. The floor, the four boards of the shelving, the lid of the
;; crates and the counter top, which are the same rectangles the furniture is
;; drawn from and have to stay that way.
;; ---------------------------------------------------------------------------
r1_plat
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
;; has to be one a line of r1_plat names or nothing will ever be standing
;; on it. Both of these are on the floor, which is where a bucket gets put
;; down.
;; ---------------------------------------------------------------------------
r1_soap
    defb 34, 50, FLOOR_TOP              ; one at the foot of the crates
    defb 58, 74, FLOOR_TOP              ; and one in front of the counter
    defb #FF
;; kind, x, y, the line a flier bobs about, the two ends of its beat, which
;; way it is going, and then the eight bytes it keeps for itself. This is the
;; copy nothing writes to: the game runs on the one it puts in RAM, so a new
;; game gets them all back on their feet and where they started.
r1_foes                                 ; kind, x, y, y0, x0, x1, dir
                                        ; tick, frame, anim, stun, phase,
                                        ; drawn, ox, oy, dive, rest, carry,
                                        ; and the pose its picture is showing
    defb K_MOUSE, 80, FLOOR_TOP-SPR_MOUSE_A_H, 0, 56, 92, -1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
    ;; and the one that walks the counter, which is where the sausage is
    defb K_MOUSE, 58, SHELF_1-24-SPR_MOUSE_A_H, 0, 58, 84, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, STEAL_START, 0, 0
    defb K_GULL, 64, 72, 72, 58, 84, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
r1_foes_end
    ASSERT r1_foes_end-r1_foes == FOE_COUNT*E_SIZE

;; ---------------------------------------------------------------------------
;; The shop, as boxes. x and y, then the list: dx, dy, width in bytes, height
;; in scanlines, pen - and #FF at the end of it.
;; ---------------------------------------------------------------------------
r1_props
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
r1_picks                                     ; picture, x, y, meze, alive, ox, oy
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
;; Furniture the shop floor does not have. Same rules: dx, dy, width in bytes,
;; height in scanlines, pen, and #FF at the end - and anything he is meant to
;; stand on is pen 2, in this game as in the other one.
;; ---------------------------------------------------------------------------

;; 120 x 160 px: open metal racking. The same four boards a jump apart as the
;; grocery's shelving, with nothing behind them - the wall shows through, and
;; that is most of what makes a cold room read as a cold room.
box_rack
    defb  0,  0,  2,160, 5      ; the two uprights
    defb 28,  0,  2,160, 5
    defb  0,  2,  2,  4, 3      ; and the light down the near edge of them
    defb 28,  2,  2,  4, 3
    defb  0, SHELF_4-76, 30, 4, 2   ; the boards, on the same grid as ever
    defb  0, SHELF_3-76, 30, 4, 2
    defb  0, SHELF_2-76, 30, 4, 2
    defb  0, SHELF_1-76, 30, 4, 2
    defb #FF

;; 96 x 40 px: a chest freezer, white enamel with a frosted lid, and the lid
;; is a shelf like any other.
box_icebox
    defb  0,  0, 24, 40, 3
    defb  2,  6, 20, 26, 11     ; the frost on the glass
    defb  4,  8, 16,  6, 3      ; and two streaks of it
    defb  4, 20, 16,  4, 3
    defb  0,  0, 24,  4, 2      ; the top he can stand on
    defb  0, 34, 24,  6, 5      ; the motor housing along the bottom
    defb #FF

;; 56 x 96 px: a tower of crates in the yard, with a lid to stand on every
;; thirty-two scanlines - which is the jump a shelf board is, so a yard with
;; no shelves in it climbs exactly like a shop with them.
box_stack
    defb  0,  0, 14, 96, 12
    defb  0,  0, 14,  4, 2      ; three lids
    defb  0, 32, 14,  4, 2
    defb  0, 64, 14,  4, 2
    defb  1,  8, 12,  4, 6      ; and the slats between them
    defb  1, 16, 12,  4, 6
    defb  1, 24, 12,  4, 6
    defb  1, 40, 12,  4, 6
    defb  1, 48, 12,  4, 6
    defb  1, 56, 12,  4, 6
    defb  1, 72, 12,  4, 6
    defb  1, 80, 12,  4, 6
    defb  1, 88, 12,  4, 6
    defb #FF

;; 64 x 28 px: the yard gate, shut. Nothing stands on it and nothing goes
;; through it - the way on is the basket, the same as everywhere else - but a
;; yard wants a gate in the wall at the back of it.
box_gate
    defb  0,  0, 16, 28, 12     ; the frame, dark against the yard wall
    defb  1,  2, 14, 24, 4      ; and the dark of the alley beyond it
    defb  2,  4,  2, 20, 12     ; palings
    defb  6,  4,  2, 20, 12
    defb 10,  4,  2, 20, 12
    defb  0,  0, 16,  2, 15     ; the lintel over it
    defb #FF

;; ===========================================================================
;; 2: the store room. Plaster instead of brick - the mortar is the pen of the
;; wall, so the joints are not there - and bare boards instead of tiles, with
;; the grout left showing to be the gap between the planks.
;;
;; The climb is the shelving on the right, straight off the floor; the crates
;; on the left are a little pyramid with two of the mezedes on it, so both
;; halves of the room have to be walked. Three mice and no gull: there is no
;; window in a store room.
;; ===========================================================================
r2_plat
    defb  0, 95, FLOOR_TOP
    defb 66, 95, SHELF_1
    defb 66, 95, SHELF_2
    defb 66, 95, SHELF_3
    defb 66, 95, SHELF_4
    defb  8, 21, SHELF_1-8              ; the pyramid of crates
    defb 24, 37, SHELF_2-8
    defb 40, 53, SHELF_1-8
    defb #FF

r2_props
    defb 66, 76
    defw box_shelving
    defb  8, SHELF_1-8
    defw box_crates
    defb 24, SHELF_2-8
    defw box_crates
    defb 40, SHELF_1-8
    defw box_crates
    defb 56, 212
    defw box_sacks
    defb 255

r2_soap
    defb 54, 66, FLOOR_TOP              ; the gap between the crates and the
    defb #FF                            ; shelving, which is the one bit of
                                        ; floor he has to cross at speed

r2_picks                                ; picture, x, y, meze, alive, ox, oy
    defw spr_sausage
    defb 10, SHELF_1-8-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_meatball
    defb 26, SHELF_2-8-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_fish
    defb 70, SHELF_2-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_cheese
    defb 86, SHELF_4-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_catnip
    defb 78, SHELF_3-SPR_FISH_H, 0, 1, #FF, 0

r2_foes
    defb K_MOUSE, 30, FLOOR_TOP-SPR_MOUSE_A_H, 0, 24, 62, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, STEAL_START, 0, 0
    defb K_MOUSE, 70, SHELF_1-SPR_MOUSE_A_H, 0, 66, 90, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
    defb K_MOUSE, 84, SHELF_3-SPR_MOUSE_A_H, 0, 66, 90, -1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, STEAL_REST, 0, 0
r2_foes_end
    ASSERT r2_foes_end-r2_foes == FOE_COUNT*E_SIZE

;; ===========================================================================
;; 3: the cold room. The wall is white with grey joints, which is the brick
;; painter drawing wall tiles instead of bricks and not knowing the
;; difference, and the floor is grey with cyan grout. A cyan dado for the
;; cold, and a border to match.
;;
;; The climb is open racking on the left; the two chest freezers in the
;; middle are a step up to nothing in particular, which is where the catnip
;; is. A gull got in with a delivery and cannot get out.
;; ===========================================================================
r3_plat
    defb  0, 95, FLOOR_TOP
    defb  4, 33, SHELF_1
    defb  4, 33, SHELF_2
    defb  4, 33, SHELF_3
    defb  4, 33, SHELF_4
    defb 42, 65, SHELF_1-8              ; the two freezers, butted together
    defb 66, 89, SHELF_1-8              ; so there is no gap to fall down
    defb #FF

r3_props
    defb  4, 76
    defw box_rack
    defb 42, SHELF_1-8
    defw box_icebox
    defb 66, SHELF_1-8
    defw box_icebox
    defb 255

r3_soap
    defb #FF                            ; nothing melts in here

r3_picks                                ; picture, x, y, meze, alive, ox, oy
    defw spr_fish
    defb  6, SHELF_3-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_meatball
    defb 22, SHELF_2-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_cheese
    defb  8, SHELF_4-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_sausage
    defb 78, SHELF_1-8-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_catnip
    defb 46, SHELF_1-8-SPR_FISH_H, 0, 1, #FF, 0

r3_foes
    defb K_MOUSE, 52, FLOOR_TOP-SPR_MOUSE_A_H, 0, 36, 70, -1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, STEAL_START, 0, 0
    defb K_MOUSE, 10, SHELF_2-SPR_MOUSE_A_H, 0, 4, 30, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
    defb K_GULL, 56, 64, 64, 40, 76, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
r3_foes_end
    ASSERT r3_foes_end-r3_foes == FOE_COUNT*E_SIZE

;; ===========================================================================
;; 4: the yard. Sky for a wall with no joints cut into it, the yard wall for
;; a dado, and tarmac - the grout is the pen of the floor, so there are no
;; tiles in it. Out of doors at last, and the last of them.
;;
;; Nothing to climb but two towers of crates, one at each end, and each of
;; them climbs on its own off the floor - so there is no jump across the
;; middle to get wrong. Two gulls, because gulls belong in a yard, and they
;; dive the whole height of it.
;; ===========================================================================
r4_plat
    defb  0, 95, FLOOR_TOP
    defb  6, 19, SHELF_3                ; the left tower, three lids
    defb  6, 19, SHELF_2
    defb  6, 19, SHELF_1
    defb 76, 89, SHELF_3                ; and the right one
    defb 76, 89, SHELF_2
    defb 76, 89, SHELF_1
    defb 38, 51, SHELF_1-8              ; a single crate in the middle
    defb #FF

r4_props
    defb 20, DADO_TOP                   ; set into the yard wall, and clear of
    defw box_gate                       ; everything standing in front of it
    defb  6, SHELF_3
    defw box_stack
    defb 76, SHELF_3
    defw box_stack
    defb 38, SHELF_1-8
    defw box_crates
    defb 60, 212
    defw box_sacks
    defb 255

r4_soap
    defb 22, 36, FLOOR_TOP              ; it rained in the night
    defb 62, 74, FLOOR_TOP
    defb #FF

r4_picks                                ; picture, x, y, meze, alive, ox, oy
    defw spr_fish
    defb  8, SHELF_2-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_sausage
    defb 40, SHELF_1-8-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_cheese
    defb 78, SHELF_2-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_meatball
    defb 78, SHELF_1-SPR_FISH_H, 1, 1, #FF, 0
    defw spr_catnip
    defb  8, SHELF_1-SPR_FISH_H, 0, 1, #FF, 0

r4_foes
    defb K_MOUSE, 46, FLOOR_TOP-SPR_MOUSE_A_H, 0, 22, 70, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, STEAL_START, 0, 0
    defb K_GULL, 34, 60, 60, 24, 66, 1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 0, 0, 0
    defb K_GULL, 70, 92, 92, 52, 88, -1
    defb FOE_TICK, 0, FOE_ANIM, 0, 0, 0, 0, 0, D_NONE, 100, 0, 0            ; and this one waits two seconds
                                        ; before its first dive, so they do
                                        ; not come down together
r4_foes_end
    ASSERT r4_foes_end-r4_foes == FOE_COUNT*E_SIZE
