;; ===========================================================================
;; rooms.asm - the flat: which platforms, sausages, enemies and furniture each
;; room has, and where the way out is.
;;
;; Rooms are composed, not painted. A full 384x272 mode 1 background is 26 KB,
;; so even two rooms of bitmap art would not fit, let alone a flat's worth.
;;
;; Furniture is not sprites either. Drawn at the size it should be - a sofa is
;; two metres long, a fridge is taller than a person - masked sprites for this
;; lot came to about 30 KB. Each piece is instead a short list of filled
;; rectangles, which costs some fifty bytes however large the thing is, and
;; scales for free. A box is dx, dy, width in bytes, height in scanlines, pen;
;; later boxes draw over earlier ones, so an outline is a white box with a
;; navy one inside it.
;;
;; The scale is about 80 pixels to the metre, which is what makes the cat
;; twenty-four pixels tall.
;; ===========================================================================

R_NAME          EQU 0           ; message id for the HUD
R_PLAT          EQU 1           ; platform table
R_SAUS          EQU 3
R_NSAUS         EQU 5
R_ENEM          EQU 6
R_NENEM         EQU 8
R_PROPS         EQU 9           ; furniture, drawn once
R_EXITPX        EQU 11          ; where the prop is drawn
R_EXITPY        EQU 12
R_EXITX         EQU 13          ; and the box that counts as going through it
R_EXITY         EQU 14
R_EXITW         EQU 15
R_EXITH         EQU 16
R_EXITSHUT      EQU 17          ; prop drawn while the room is unfinished
R_EXITOPEN      EQU 18          ; and once every sausage is gone
R_STARTX        EQU 19
R_STARTY        EQU 20
R_SIZE          EQU 21

ROOM_COUNT      EQU 2
SAUSAGE_MAX     EQU 6

;; Prop ids index prop_boxes.
PROP_SOFA       EQU 0
PROP_TV         EQU 1
PROP_WINDOW     EQU 2
PROP_COOKER     EQU 3
PROP_WORKTOP    EQU 4
PROP_FRIDGE     EQU 5
PROP_FRIDGEOPEN EQU 6
PROP_VENT       EQU 7
PROP_VENTOPEN   EQU 8

prop_boxes
    defw box_sofa, box_tv, box_window, box_cooker, box_worktop
    defw box_fridge, box_fridgeopen, box_vent, box_ventopen

;; ---------------------------------------------------------------------------
;; The furniture. Sizes are in bytes across (4 pixels each) and scanlines down.
;; ---------------------------------------------------------------------------

;; 128 x 58 px: a two-seater against the wall.
box_sofa
    defb  0,  0, 32, 24, 3      ; back
    defb  2,  3, 28, 18, 0
    defb  0, 24, 32, 22, 3      ; seat
    defb  2, 27, 28, 16, 2      ; cushions
    defb  0, 10,  5, 38, 3      ; arms
    defb  1, 14,  3, 30, 0
    defb 27, 10,  5, 38, 3
    defb 28, 14,  3, 30, 0
    defb  3, 48,  4, 10, 3      ; feet
    defb 25, 48,  4, 10, 3
    defb #FF

;; 56 x 56 px: the telly, switched on.
box_tv
    defb  5, 44,  4, 10, 3      ; stand
    defb  2, 52, 10,  4, 3      ; base
    defb  0,  0, 14, 44, 3      ; case
    defb  1,  2, 12, 40, 0
    defb  2,  5, 10, 32, 2      ; picture
    defb #FF

;; 96 x 96 px: a window on the back wall.
box_window
    defb  0,  0, 24, 96, 3
    defb  2,  4, 20, 88, 0
    defb  3,  6,  8, 38, 2
    defb 13,  6,  8, 38, 2
    defb  3, 50,  8, 38, 2
    defb 13, 50,  8, 38, 2
    defb #FF

;; 48 x 72 px: a freestanding cooker.
box_cooker
    defb  0,  0, 12, 72, 3
    defb  1,  4, 10, 64, 0
    defb  0,  0, 12,  6, 3      ; hob
    defb  2,  1,  3,  4, 1      ; rings
    defb  7,  1,  3,  4, 1
    defb  2, 14,  8,  3, 3      ; handle
    defb  1, 22, 10, 42, 3      ; oven door
    defb  2, 25,  8, 36, 0
    defb  3, 30,  6, 26, 2      ; the light inside
    defb #FF

;; 100 x 80 px: worktop with a sink and a tap.
box_worktop
    defb 16,  0,  1, 10, 3      ; tap
    defb 15,  0,  4,  3, 3
    defb  0, 10, 25,  6, 3      ; worktop
    defb  3, 11, 10,  4, 0      ; basin
    defb  0, 16, 25, 64, 3      ; unit
    defb  1, 19, 23, 58, 0
    defb  2, 22, 10, 52, 3      ; doors
    defb  3, 25,  8, 46, 0
    defb 13, 22, 10, 52, 3
    defb 14, 25,  8, 46, 0
    defb #FF

;; 48 x 136 px: the vintage Pitsos, two doors and four digital locks.
box_fridge
    defb  0,  0, 12,136, 3
    defb  1,  3, 10,130, 0
    defb  0, 58, 12,  4, 3      ; between the doors
    defb  9, 20,  2, 16, 3      ; handles
    defb  9, 76,  2, 16, 3
    defb  2, 70,  2,  6, 1      ; the four locks
    defb  2, 82,  2,  6, 1
    defb  2, 94,  2,  6, 1
    defb  2,106,  2,  6, 1
    defb #FF

box_fridgeopen
    defb  0,  0, 12,136, 3
    defb  1,  3, 10,130, 2      ; the light is on
    defb  0, 58, 12,  4, 3
    defb  9, 20,  2, 16, 3
    defb  9, 76,  2, 16, 3
    defb #FF

;; 24 x 24 px. A vent is not furniture; it is cat sized on purpose.
box_vent
    defb  0,  0,  6, 24, 3
    defb  1,  2,  4, 20, 0
    defb  1,  5,  4,  2, 3
    defb  1, 11,  4,  2, 3
    defb  1, 17,  4,  2, 3
    defb #FF

box_ventopen
    defb  0,  0,  6, 24, 3
    defb  1,  2,  4, 20, 2      ; light from the next room
    defb #FF

;; ===========================================================================
;; The flat
;; ===========================================================================

rooms
    ;; --- 1: the living room ------------------------------------------------
    defb MSG_ROOM1
    defw r1_plat, r1_saus
    defb 5
    defw r1_enem
    defb 3
    defw r1_props
    ;; the way out is the vent at the top of the bookshelf, not a door on the
    ;; floor: the last sausage is up there, and sending the player all the way
    ;; back down to leave is just walking
    defb 86, SHELF4-24
    defb 86, SHELF4-24, 6, 24, PROP_VENT, PROP_VENTOPEN
    defb 4, FLOOR_Y-SPR_CAT_STAND_H

    ;; --- 2: the kitchen ----------------------------------------------------
    defb MSG_ROOM2
    defw r2_plat, r2_saus
    defb 5
    defw r2_enem
    defb 3
    defw r2_props
    ;; only the lower half of the Pitsos counts, so standing on top of it is
    ;; not the same as getting into it
    defb 82, FLOOR_Y-136
    defb 82, 168, 12, 68, PROP_FRIDGE, PROP_FRIDGEOPEN
    defb 4, FLOOR_Y-SPR_CAT_STAND_H

;; ---------------------------------------------------------------------------
;; Room 1 - the living room. A wall of bookshelves, the sofa tucked under them
;; and the telly in the gap between.
;;
;; Its collision geometry is frozen: the scripted run in make check depends on
;; every shelf, sausage and patrol being exactly where it is. Furniture is
;; decoration and can move freely.
;; ---------------------------------------------------------------------------
SHELF1          EQU FLOOR_Y-32
SHELF2          EQU FLOOR_Y-64
SHELF3          EQU FLOOR_Y-96
SHELF4          EQU FLOOR_Y-128

r1_plat
    defb 0,  95, FLOOR_Y
    defb 4,  34, SHELF1
    defb 54, 86, SHELF2
    defb 14, 44, SHELF3
    defb 60, 90, SHELF4
    defb #FF

r1_saus
    defb 46, FLOOR_Y-SPR_SAUSAGE_H
    defb 10, SHELF1-SPR_SAUSAGE_H
    defb 78, SHELF2-SPR_SAUSAGE_H
    defb 20, SHELF3-SPR_SAUSAGE_H
    defb 84, SHELF4-SPR_SAUSAGE_H

r1_enem
    ;; type, x, y, dx, first column, last column, top of the canary's arc
    defb ET_ROBOT,  40, FLOOR_Y-SPR_ROBOT_H,  1,  0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    ;; the shelf 2 robot patrols only the right half, so there is always a
    ;; safe place to land coming up from shelf 1
    defb ET_ROBOT,  70, SHELF2-SPR_ROBOT_H,  -1, 64, 86-SPR_ROBOT_W+1,            0
    defb ET_CANARY, 20, 44,                   1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r1_props
    defb PROP_WINDOW, 18, 20
    defb PROP_SOFA,   54, FLOOR_Y-58
    defb PROP_TV,     38, FLOOR_Y-56
    defb #FF

;; ---------------------------------------------------------------------------
;; Room 2 - the kitchen. The units are the platforms here: you climb the
;; worktop, the cooker and finally the Pitsos.
;; ---------------------------------------------------------------------------
K_WORKTOP       EQU FLOOR_Y-72          ; the tops of the floor units
K_SHELF         EQU 140
K_CUPBOARD      EQU 116
K_FRIDGETOP     EQU FLOOR_Y-136

r2_plat
    defb 0,  95, FLOOR_Y
    defb 0,  24, K_WORKTOP
    defb 50, 61, K_WORKTOP
    defb 62, 78, K_SHELF
    defb 26, 48, K_CUPBOARD
    defb 82, 93, K_FRIDGETOP
    defb #FF

r2_saus
    defb 30, FLOOR_Y-SPR_SAUSAGE_H
    defb 8,  K_WORKTOP-SPR_SAUSAGE_H
    defb 52, K_WORKTOP-SPR_SAUSAGE_H
    defb 68, K_SHELF-SPR_SAUSAGE_H
    defb 34, K_CUPBOARD-SPR_SAUSAGE_H

r2_enem
    defb ET_ROBOT,  60, FLOOR_Y-SPR_ROBOT_H, -1, 26, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  30, K_CUPBOARD-SPR_ROBOT_H, 1, 26, 48-SPR_ROBOT_W+1,          0
    defb ET_CANARY, 40, 44,                  -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r2_props
    defb PROP_WINDOW,  30, 16
    defb PROP_WORKTOP,  0, FLOOR_Y-80
    defb PROP_COOKER,  50, FLOOR_Y-72
    defb #FF
