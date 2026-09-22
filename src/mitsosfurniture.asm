;; ===========================================================================
;; mitsosfurniture.asm - what the rooms are furnished with.
;;
;; A box list is dx, dy, width in bytes, height in scanlines, pen, and #FF at
;; the end of it, drawn relative to the x and y a room's prop list gives it.
;; Later boxes draw over earlier ones, so an outline is a light box with a
;; darker one inside it and nothing has to know about edges.
;;
;; **This stays below #4000 while the rooms themselves live in bank 4**, and
;; that is not an accident: a room's prop list is four bytes an entry, two of
;; which are the address of one of these, and an address is only any use if
;; what it points at is there when the bank is paged out. Furniture is shared
;; across rooms anyway - a crate is a crate in the store room and in the yard
;; - so a new room is usually a few pointers and no new pictures at all.
;;
;; Anything he is meant to stand on is pen 2, in this game as in the other
;; one, and the room's platform table has to name the same rectangle.
;; ===========================================================================

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

;; 56 x 40 px: a barrel on its side, chocked so it does not roll. The flat of
;; the top is a shelf, which is what a cellar has instead of shelving.
box_barrel
    defb  0,  4, 14, 36, 6      ; the staves
    defb  0,  0, 14,  6, 2      ; and the flat he can stand on
    defb  0, 12, 14,  4, 12     ; two hoops
    defb  0, 30, 14,  4, 12
    defb  5, 18,  4,  6, 4      ; the bung
    defb #FF

;; 96 x 32 px: a board of jars up on the wall. The board is the platform and
;; the jars are what it is for - a shelf with nothing behind it, which reads
;; as a cellar wall rather than as a grocer's shelving.
box_jars
    defb  0, 28, 24,  4, 2      ; the board
    defb  2, 12,  4, 16, 11     ; and four jars of something each
    defb  8, 14,  4, 14, 15
    defb 14, 10,  4, 18, 9
    defb 20, 16,  4, 12, 7
    defb #FF

;; 48 x 96 px: the stone steps down. Scenery - the way between rooms is the
;; basket here as everywhere - but a cellar with no way into it is a hole.
box_steps
    defb  0, 64, 12, 32, 6      ; olive rather than the grey of a stone wall,
    defb  0, 64, 12,  4, 15     ; because two of the three cellars these are
    defb  2, 32, 10, 32, 6      ; in have grey walls and steps that are the
    defb  2, 32, 10,  4, 15     ; colour of the wall behind them are a few
    defb  4,  0,  8, 32, 6      ; white lines and nothing else
    defb  4,  0,  8,  4, 15
    defb #FF

;; 384 x 20 px: a roof beam right across the loft, with the dark of the tiles
;; above it. Nothing stands on it; it is what tells you which way is up, and
;; a beam that stops a quarter of the way over is a black bar in the corner.
box_beam
    defb  0,  0, 96, 12, 4      ; the tiles
    defb  0, 12, 96,  8, 6      ; the beam
    defb  0, 12, 96,  2, 15     ; and the light along the top edge of it
    defb #FF

;; 64 x 48 px: the dormer, which is the only daylight in a loft.
box_dormer
    defb  0,  0, 16, 48, 3      ; the frame
    defb  2,  4, 12, 24, 11     ; sky
    defb  2, 28, 12, 16, 15     ; and the roofs of the town under it
    defb  7,  0,  2, 48, 3      ; the bar down the middle
    defb  3, 32,  4,  4, 7
    defb 10, 34,  4,  4, 7
    defb #FF
