;; ===========================================================================
;; rooms.asm - the flat: which platforms, sausages, enemies and furniture each
;; room has, and where the way out is.
;;
;; Rooms are composed, not painted. A full 384x272 mode 1 background is 26 KB,
;; so even two rooms of bitmap art would not fit, let alone a flat's worth.
;; Each room is instead a handful of tables: solid platforms, then furniture
;; blitted once as ordinary masked sprites. A room costs a few dozen bytes
;; plus whatever props it names, and props are shared between rooms.
;; ===========================================================================

R_NAME          EQU 0           ; message id for the HUD
R_PLAT          EQU 1           ; platform table
R_SAUS          EQU 3
R_NSAUS         EQU 5
R_ENEM          EQU 6
R_NENEM         EQU 8
R_PROPS         EQU 9           ; furniture, drawn once
R_EXITX         EQU 11
R_EXITY         EQU 12
R_EXITSHUT      EQU 13          ; prop drawn while the room is unfinished
R_EXITOPEN      EQU 14          ; and once every sausage is gone
R_STARTX        EQU 15
R_STARTY        EQU 16
R_SIZE          EQU 17

ROOM_COUNT      EQU 2
SAUSAGE_MAX     EQU 6

;; Prop ids index prop_sprites.
PROP_SOFA       EQU 0
PROP_TV         EQU 1
PROP_COOKER     EQU 2
PROP_SINK       EQU 3
PROP_FRIDGE     EQU 4
PROP_FRIDGEOPEN EQU 5
PROP_DOOR       EQU 6
PROP_DOOROPEN   EQU 7
PROP_WINDOW     EQU 8

prop_sprites
    defw spr_sofa, spr_tv, spr_cooker, spr_sink
    defw spr_fridge, spr_fridgeopen, spr_door, spr_dooropen
    defw spr_window

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
    defb 86, SHELF4-SPR_DOOR_H, PROP_DOOR, PROP_DOOROPEN
    defb 4, FLOOR_Y-SPR_CAT_STAND_H

    ;; --- 2: the kitchen ----------------------------------------------------
    defb MSG_ROOM2
    defw r2_plat, r2_saus
    defb 5
    defw r2_enem
    defb 3
    defw r2_props
    defb 86, 208, PROP_FRIDGE, PROP_FRIDGEOPEN
    defb 4, FLOOR_Y-SPR_CAT_STAND_H

;; ---------------------------------------------------------------------------
;; Room 1 - the living room. Bookshelves up the wall, a sofa and the telly.
;; Its geometry is frozen: the scripted playthrough in make check depends on
;; every shelf, sausage and patrol being exactly where they are.
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
    defb PROP_WINDOW, 26, 28
    defb PROP_TV,     26, FLOOR_Y-SPR_TV_H
    defb PROP_SOFA,   58, FLOOR_Y-SPR_SOFA_H
    defb #FF

;; ---------------------------------------------------------------------------
;; Room 2 - the kitchen. Counters either side, the table in the middle, a wall
;; cupboard, and the Pitsos itself in the corner.
;; ---------------------------------------------------------------------------
K_COUNTER       EQU 200
K_TABLE         EQU 160
K_CUPBOARD      EQU 120

r2_plat
    defb 0,  95, FLOOR_Y
    defb 0,  28, K_COUNTER
    defb 58, 95, K_COUNTER
    defb 30, 56, K_TABLE
    defb 6,  34, K_CUPBOARD
    defb 62, 92, K_CUPBOARD
    defb #FF

r2_saus
    defb 44, FLOOR_Y-SPR_SAUSAGE_H
    defb 10, K_COUNTER-SPR_SAUSAGE_H
    defb 76, K_COUNTER-SPR_SAUSAGE_H
    defb 40, K_TABLE-SPR_SAUSAGE_H
    defb 74, K_CUPBOARD-SPR_SAUSAGE_H

r2_enem
    defb ET_ROBOT,  60, FLOOR_Y-SPR_ROBOT_H, -1,  0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  40, K_TABLE-SPR_ROBOT_H,  1, 30, 56-SPR_ROBOT_W+1,            0
    defb ET_CANARY, 40, 44,                  -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r2_props
    defb PROP_WINDOW, 38, 28
    defb PROP_SINK,    2, K_COUNTER-SPR_SINK_H
    defb PROP_COOKER, 70, K_COUNTER-SPR_COOKER_H
    defb #FF
