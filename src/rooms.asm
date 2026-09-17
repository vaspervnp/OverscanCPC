;; ===========================================================================
;; rooms.asm - the flat: which platforms, sausages, enemies and furniture each
;; room has, and where the way out is.
;;
;; Rooms are composed, not painted. A full 192x272 mode 0 background is 26 KB,
;; so even two rooms of bitmap art would not fit, let alone a flat's worth.
;;
;; Furniture is not sprites either. Drawn at the size it should be - a sofa is
;; two metres long, a fridge is taller than a person - masked sprites for this
;; lot came to about 30 KB. Each piece is instead a short list of filled
;; rectangles, which costs some fifty bytes however large the thing is, and
;; scales for free. A box is dx, dy, width in bytes, height in scanlines, pen;
;; later boxes draw over earlier ones, so an outline is a light box with a
;; darker one inside it.
;;
;; The pen is an index into pal_play's sixteen, and that is what mode 0 bought:
;; the inside of a piece of furniture used to be pen 0, the same navy as the
;; wall behind it, so everything was an outline drawn on nothing. Now a door is
;; wood, a bath is porcelain with water in it, the car is a car. The white
;; outline stays where the level's grammar needs it - outlined means scenery,
;; solid means something the cat can stand on.
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
R_MILKX         EQU 21          ; the saucer, or NO_MILK
R_MILKY         EQU 22
R_PAL           EQU 23          ; hardware colour for pen 0 - what lights it
R_FLOOR         EQU 24          ; pen the floor band is painted in
R_SIZE          EQU 25

ROOM_COUNT      EQU 10
SAUSAGE_MAX     EQU 6

;; Every room is a jump apart top to bottom: the cat clears 32 scanlines, so
;; platforms sit on the 32-scanline grid below the floor and the furniture that
;; stands in for them - shelving, bookcase, the car - is drawn to match.
SHELF_1         EQU FLOOR_Y-32
SHELF_2         EQU FLOOR_Y-64
SHELF_3         EQU FLOOR_Y-96
SHELF_4         EQU FLOOR_Y-128

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
PROP_DOOR       EQU 9
PROP_DOOROPEN   EQU 10
PROP_WARDROBE   EQU 11
PROP_WARDROBEOPEN EQU 12
PROP_RACK       EQU 13
PROP_CRATES     EQU 14
PROP_BOILER     EQU 15
PROP_CAR        EQU 16
PROP_TYRES      EQU 17
PROP_TOOLBOARD  EQU 18
PROP_TREE       EQU 19
PROP_FENCE      EQU 20
PROP_BUSH       EQU 21
PROP_STAIRS     EQU 22
PROP_SHOES      EQU 23
PROP_COATS      EQU 24
PROP_BED        EQU 25
PROP_DRAWERS    EQU 26
PROP_RAIL       EQU 27
PROP_CASES      EQU 28
PROP_SHOEBOX    EQU 29
PROP_BATH       EQU 30
PROP_BASIN      EQU 31
PROP_TOILET     EQU 32
PROP_DESK       EQU 33
PROP_BOOKCASE   EQU 34
PROP_BIN        EQU 35

prop_boxes
    defw box_sofa, box_tv, box_window, box_cooker, box_worktop
    defw box_fridge, box_fridgeopen, box_vent, box_ventopen
    defw box_door, box_dooropen, box_wardrobe, box_wardrobeopen
    defw box_rack, box_crates, box_boiler
    defw box_car, box_tyres, box_toolboard
    defw box_tree, box_fence, box_bush
    defw box_stairs, box_shoes, box_coats
    defw box_bed, box_drawers, box_rail, box_cases, box_shoebox
    defw box_bath, box_basin, box_toilet
    defw box_desk, box_bookcase, box_bin

;; ---------------------------------------------------------------------------
;; The furniture. Sizes are in bytes across (4 pixels each) and scanlines down.
;; ---------------------------------------------------------------------------

;; 128 x 58 px: a two-seater against the wall.
box_sofa
    defb  0,  0, 32, 24, 3      ; back
    defb  2,  3, 28, 18, 12
    defb  0, 24, 32, 22, 3      ; seat
    defb  2, 27, 28, 16, 13      ; cushions
    defb  0, 10,  5, 38, 3      ; arms
    defb  1, 14,  3, 30, 12
    defb 27, 10,  5, 38, 3
    defb 28, 14,  3, 30, 12
    defb  3, 48,  4, 10, 3      ; feet
    defb 25, 48,  4, 10, 3
    defb #FF

;; 56 x 56 px: the telly, switched on.
box_tv
    defb  5, 44,  4, 10, 3      ; stand
    defb  2, 52, 10,  4, 3      ; base
    defb  0,  0, 14, 44, 3      ; case
    defb  1,  2, 12, 40, 4
    defb  2,  5, 10, 32, 11      ; picture
    defb #FF

;; 96 x 96 px: a window on the back wall.
box_window
    defb  0,  0, 24, 96, 3
    defb  2,  4, 20, 88, 6
    defb  3,  6,  8, 38, 15
    defb 13,  6,  8, 38, 15
    defb  3, 50,  8, 38, 15
    defb 13, 50,  8, 38, 15
    defb #FF

;; 48 x 70 px: a freestanding cooker, hob level with the worktop.
box_cooker
    defb  0,  0, 12, 70, 3
    defb  1,  4, 10, 62, 5
    defb  0,  0, 12,  6, 3      ; hob
    defb  2,  1,  3,  4, 13      ; rings
    defb  7,  1,  3,  4, 13
    defb  2, 14,  8,  3, 3      ; handle
    defb  1, 22, 10, 42, 3      ; oven door
    defb  2, 25,  8, 36, 5
    defb  3, 30,  6, 26, 7      ; the light inside
    defb #FF

;; 100 x 70 px: worktop with a sink and a tap. Its surface is six scanlines
;; down, so standing it on the floor puts the top exactly one jump above the
;; bin - which is the only way up onto it.
box_worktop
    defb 16,  0,  1,  6, 3      ; tap
    defb 15,  0,  4,  3, 3
    defb  0,  6, 25,  6, 3      ; the worktop
    defb  3,  7, 10,  4, 11      ; basin
    defb  0, 12, 25, 58, 3      ; unit
    defb  1, 15, 23, 52, 6
    defb  2, 18, 10, 46, 3      ; doors
    defb  3, 21,  8, 40, 6
    defb 13, 18, 10, 46, 3
    defb 14, 21,  8, 40, 6
    defb #FF

;; 48 x 32 px: the pedal bin, and the way up onto the worktop.
box_bin
    defb  0,  0, 12,  5, 3      ; lid
    defb  1,  5, 10, 27, 3
    defb  2,  8,  8, 21, 5
    defb  5,  0,  2,  3, 13      ; pedal linkage
    defb #FF

;; 48 x 136 px: the vintage Pitsos, two doors and four digital locks.
box_fridge
    defb  0,  0, 12,136, 3
    defb  1,  3, 10,130, 5
    defb  0, 58, 12,  4, 3      ; between the doors
    defb  9, 20,  2, 16, 3      ; handles
    defb  9, 76,  2, 16, 3
    defb  2, 70,  2,  6, 13      ; the four locks
    defb  2, 82,  2,  6, 13
    defb  2, 94,  2,  6, 13
    defb  2,106,  2,  6, 13
    defb #FF

box_fridgeopen
    defb  0,  0, 12,136, 3
    defb  1,  3, 10,130, 15      ; the light is on
    defb  0, 58, 12,  4, 3
    defb  9, 20,  2, 16, 3
    defb  9, 76,  2, 16, 3
    defb #FF

;; 24 x 24 px. A vent is not furniture; it is cat sized on purpose.
box_vent
    defb  0,  0,  6, 24, 3
    defb  1,  2,  4, 20, 4
    defb  1,  5,  4,  2, 3
    defb  1, 11,  4,  2, 3
    defb  1, 17,  4,  2, 3
    defb #FF

box_ventopen
    defb  0,  0,  6, 24, 3
    defb  1,  2,  4, 20, 15      ; light from the next room
    defb #FF

;; ---------------------------------------------------------------------------
;; Doors. The same pair serves most of the flat: 80 x 720 px, which is a door
;; a person walks through and four times the height of the cat.
;; ---------------------------------------------------------------------------
box_door
    defb  0,  0, 20,180, 3      ; frame
    defb  1,  4, 18,176, 6
    defb  2,  6, 16,174, 3      ; the leaf
    defb  3,  9, 14,168, 6
    defb  4, 18,  5, 52, 3      ; upper panels
    defb  5, 21,  3, 46, 6
    defb 12, 18,  5, 52, 3
    defb 13, 21,  3, 46, 6
    defb  4, 92,  5, 64, 3      ; lower panels
    defb  5, 95,  3, 58, 6
    defb 12, 92,  5, 64, 3
    defb 13, 95,  3, 58, 6
    defb 15, 84,  2,  6, 2      ; handle
    defb #FF

box_dooropen
    defb  0,  0, 20,180, 3
    defb  1,  4, 18,176, 15      ; the next room, lit
    defb 14,  4,  5,176, 3      ; the leaf swung back against the jamb
    defb 15,  8,  3,168, 6
    defb #FF

;; 120 x 176 px: the bedroom wardrobe, and the way through to inside it.
box_wardrobe
    defb  0,  0, 30,176, 3
    defb  1,  4, 28,168, 6
    defb  1,  0, 28,  6, 3      ; cornice
    defb  2,  8, 12,160, 3      ; the two doors
    defb  3, 11, 10,154, 6
    defb 16,  8, 12,160, 3
    defb 17, 11, 10,154, 6
    defb 13, 78,  2, 16, 2      ; handles
    defb 16, 78,  2, 16, 2
    defb  1,172, 28,  4, 3      ; plinth
    defb #FF

box_wardrobeopen
    defb  0,  0, 30,176, 3
    defb  1,  4, 28,168, 15      ; lit inside
    defb  1,  0, 28,  6, 3
    defb  2, 10, 26,  3, 3      ; the rail
    defb  4, 13,  4, 90, 12      ; and what hangs off it
    defb  9, 13,  5,104, 11
    defb 15, 13,  4, 84, 14
    defb 20, 13,  5, 96, 13
    defb  1,172, 28,  4, 3
    defb #FF

;; ---------------------------------------------------------------------------
;; The basement
;; ---------------------------------------------------------------------------

;; 96 x 160 px: steel shelving. Its shelves are 32 scanlines apart, which is
;; exactly one jump, so the platforms line up with the bars that are drawn.
box_rack
    defb  0,  0,  2,160, 5      ; uprights
    defb 22,  0,  2,160, 5
    defb  0,  0, 24,  4, 5      ; five shelves
    defb  0, 32, 24,  4, 5
    defb  0, 64, 24,  4, 5
    defb  0, 96, 24,  4, 5
    defb  0,128, 24,  4, 5
    defb  3,  8, 18, 22, 7      ; tins and jars nobody has touched in years
    defb  5, 40, 12, 22, 7
    defb  4,104, 16, 22, 7
    defb #FF

;; 96 x 64 px: two packing crates, one on the other.
box_crates
    defb  0, 32, 24, 32, 7
    defb  1, 35, 22, 26, 6
    defb  1, 46, 22,  3, 7
    defb  0,  0, 24, 32, 7
    defb  1,  3, 22, 26, 6
    defb  1, 14, 22,  3, 7
    defb #FF

;; 72 x 96 px: the water heater, still lit.
box_boiler
    defb  0,  0, 18, 96, 3
    defb  1,  4, 16, 88, 5
    defb  2,  8, 14,  8, 13      ; the burner
    defb  3, 24, 12, 40, 3      ; tank face
    defb  4, 27, 10, 34, 5
    defb  7, 74,  4,  6, 15      ; dial
    defb  6, 84,  2, 12, 3      ; pipes
    defb 12, 84,  2, 12, 3
    defb #FF

;; ---------------------------------------------------------------------------
;; The garage
;; ---------------------------------------------------------------------------

;; 192 x 56 px: the family estate, nose to the left. The bonnet is a step up
;; to the roof, so the car is the climb as well as the scenery.
box_car
    defb  0, 26, 48, 14, 3      ; body
    defb  1, 29, 46,  8, 12
    defb 16,  0, 30, 28, 3      ; cabin, over the back half
    defb 17,  3, 28, 22, 12
    defb 18,  6, 11, 16, 11      ; windows
    defb 31,  6, 13, 16, 11
    defb  0, 30, 48,  3, 13      ; the trim line down the side
    defb  1, 22,  5,  4, 15      ; headlamp, on the nose of the bonnet
    defb  5, 40, 10, 14, 4      ; wheels, clear of the body
    defb  8, 43,  4,  8, 5
    defb 33, 40, 10, 14, 4
    defb 36, 43,  4,  8, 5
    defb #FF

;; 48 x 32 px: three tyres nobody got round to taking to the tip.
box_tyres
    defb  0,  0, 12, 10, 4
    defb  3,  2,  6,  6, 5
    defb  0, 11, 12, 10, 4
    defb  3, 13,  6,  6, 5
    defb  0, 22, 12, 10, 4
    defb  3, 24,  6,  6, 5
    defb #FF

;; 80 x 44 px: the tool board on the wall.
box_toolboard
    defb  0,  0, 20, 44, 3
    defb  1,  3, 18, 38, 6
    defb  3,  6,  2, 20, 5
    defb  7,  6,  3, 14, 5
    defb 12,  6,  2, 24, 5
    defb 15,  6,  3, 18, 5
    defb  3, 32, 14,  4, 5
    defb #FF

;; ---------------------------------------------------------------------------
;; The garden
;; ---------------------------------------------------------------------------

;; 112 x 160 px: the lemon tree. Its branches are the platforms.
box_tree
    defb 12, 56,  4,104, 6      ; trunk
    defb 13, 60,  2, 96, 7
    defb  6,  0, 16, 24, 8      ; canopy, three tiers
    defb  7,  3, 14, 18, 9
    defb  2, 18, 24, 26, 8
    defb  3, 21, 22, 20, 9
    defb  8, 40, 12, 22, 8
    defb  9, 43, 10, 16, 9
    defb  4, 62,  8,  3, 6      ; branch stubs
    defb 16, 78, 10,  3, 6
    defb  2, 96, 10,  3, 6
    defb #FF

;; 96 x 32 px: the garden fence.
box_fence
    defb  0,  0, 24,  4, 7      ; rails
    defb  0, 14, 24,  4, 7
    defb  1,  0,  2, 32, 7      ; pickets
    defb  6,  0,  2, 32, 7
    defb 11,  0,  2, 32, 7
    defb 16,  0,  2, 32, 7
    defb 21,  0,  2, 32, 7
    defb #FF

;; 64 x 36 px: a shrub by the back door.
box_bush
    defb  2,  0, 12, 16, 8
    defb  3,  3, 10, 12, 9
    defb  0, 12, 16, 24, 8
    defb  1, 15, 14, 18, 9
    defb  7, 30,  2,  6, 8
    defb #FF

;; ---------------------------------------------------------------------------
;; The entrance hall
;; ---------------------------------------------------------------------------

;; 144 x 64 px: the flight up, top step on the right.
box_stairs
    defb 30,  0,  6, 64, 3
    defb 31,  3,  4, 58, 6
    defb 24, 12,  6, 52, 3
    defb 25, 15,  4, 46, 6
    defb 18, 24,  6, 40, 3
    defb 19, 27,  4, 34, 6
    defb 12, 36,  6, 28, 3
    defb 13, 39,  4, 22, 6
    defb  6, 48,  6, 16, 3
    defb  7, 51,  4, 10, 6
    defb  0, 58,  6,  6, 3
    defb #FF

;; 80 x 32 px: the shoe rack by the front door.
box_shoes
    defb  0,  0, 20,  4, 3
    defb  0, 28, 20,  4, 3
    defb  0,  0,  2, 32, 3
    defb 18,  0,  2, 32, 3
    defb  3,  6,  5,  8, 12
    defb 10,  6,  5,  8, 12
    defb  3, 18,  5,  8, 13
    defb 11, 18,  5,  8, 13
    defb #FF

;; 56 x 88 px: the coat stand, fully loaded as always.
box_coats
    defb  6,  0,  2, 88, 5      ; pole
    defb  2,  4, 10,  3, 5      ; hooks
    defb  0,  8, 14,  3, 5
    defb  0, 11,  4, 40, 12      ; three coats on it
    defb  5, 11,  4, 48, 13
    defb 10, 11,  4, 36, 14
    defb  4, 78,  6, 10, 5      ; foot
    defb #FF

;; ---------------------------------------------------------------------------
;; The bedroom and the wardrobe
;; ---------------------------------------------------------------------------

;; 144 x 32 px: the bed, headboard to the left.
box_bed
    defb  0,  4, 36, 24, 3      ; base
    defb  1,  7, 34, 18, 6
    defb  0,  0,  5, 32, 3      ; headboard
    defb  1,  3,  3, 26, 6
    defb  5,  4, 10,  6, 3      ; pillow
    defb  5, 10, 30,  8, 11      ; quilt
    defb  2, 28,  3,  4, 3      ; legs
    defb 31, 28,  3,  4, 3
    defb #FF

;; 64 x 60 px: the bedside chest.
box_drawers
    defb  0,  0, 16, 60, 3
    defb  1,  3, 14, 54, 6
    defb  2,  6, 12, 14, 3
    defb  3,  9, 10,  8, 6
    defb  2, 24, 12, 14, 3
    defb  3, 27, 10,  8, 6
    defb  2, 42, 12, 14, 3
    defb  3, 45, 10,  8, 6
    defb  7, 12,  2,  2, 2      ; handles
    defb  7, 30,  2,  2, 2
    defb  7, 48,  2,  2, 2
    defb #FF

;; 128 x 52 px: the hanging rail, seen from inside the wardrobe.
box_rail
    defb  0,  0, 32,  4, 5
    defb  2,  4,  5, 40, 12
    defb  8,  4,  6, 46, 13
    defb 15,  4,  5, 36, 11
    defb 21,  4,  6, 48, 14
    defb 28,  4,  4, 42, 7
    defb #FF

;; 72 x 40 px: the suitcases that live at the bottom of it.
box_cases
    defb  0, 22, 18, 18, 3      ; the big one, underneath
    defb  1, 25, 16, 12, 12
    defb  1, 30, 16,  2, 3      ; its lid seam
    defb  8, 19,  2,  3, 3      ; handle
    defb  3,  0, 12, 17, 3      ; and a smaller one on top
    defb  4,  3, 10, 11, 7
    defb  4,  8, 10,  2, 3
    defb  8, 16,  2,  3, 2
    defb #FF

;; 80 x 32 px: shoe boxes, stacked.
box_shoebox
    defb  0, 16, 20, 16, 3
    defb  1, 19, 18, 10, 7
    defb  0, 16, 20,  4, 15
    defb  2,  0, 16, 16, 3
    defb  3,  3, 14, 10, 7
    defb  2,  0, 16,  4, 15
    defb #FF

;; ---------------------------------------------------------------------------
;; The bathroom
;; ---------------------------------------------------------------------------

;; 128 x 40 px: the bath, still half full.
box_bath
    defb  0,  0, 32, 30, 3
    defb  3,  5, 26, 22, 3
    defb  3, 17, 26, 10, 11      ; still half full
    defb  0,  0, 32,  5, 3      ; the rim
    defb  0, 27, 32,  3, 3      ; and the skirt
    defb  2, 30,  5, 10, 3      ; feet
    defb 25, 30,  5, 10, 3
    defb 29,  1,  2,  4, 2      ; tap
    defb #FF

;; 72 x 64 px: pedestal basin.
box_basin
    defb  0,  0, 18, 12, 3
    defb  1,  3, 16,  6, 3
    defb  6, 12,  6, 44, 3      ; pedestal
    defb  7, 15,  4, 38, 3
    defb  2, 56, 14,  8, 3      ; foot
    defb  8,  0,  2,  4, 2      ; tap
    defb #FF

;; 48 x 32 px.
box_toilet
    defb  0,  0, 12,  6, 3      ; lid
    defb  1,  6, 10, 12, 3
    defb  2,  9,  8,  6, 3
    defb  3, 18,  6, 10, 3
    defb  1, 28, 10,  4, 3
    defb #FF

;; ---------------------------------------------------------------------------
;; The study
;; ---------------------------------------------------------------------------

;; 120 x 32 px: the desk.
box_desk
    defb  0,  0, 30,  5, 3      ; the top
    defb  1,  5,  3, 27, 3      ; legs
    defb 26,  5,  3, 27, 3
    defb 14,  5, 14, 16, 3      ; drawer unit
    defb 15,  8, 12, 10, 6
    defb 19, 12,  4,  2, 2
    defb #FF

;; 128 x 160 px: the bookcase. Like the basement rack its shelves are one
;; jump apart, so what is drawn is what the cat can stand on.
box_bookcase
    defb  0,  0, 32,160, 3
    defb  2,  4, 28,152, 6
    defb  2, 32, 28,  4, 3      ; shelves
    defb  2, 64, 28,  4, 3
    defb  2, 96, 28,  4, 3
    defb  2,128, 28,  4, 3
    defb  4,  8,  3, 24, 12      ; books
    defb  8,  8,  2, 24, 9
    defb 11,  8,  3, 24, 13
    defb  4, 40,  2, 24, 7
    defb  7, 40,  3, 24, 14
    defb 20, 40,  4, 24, 11
    defb  5,104,  3, 24, 12
    defb 10,104,  2, 24, 9
    defb 22,104,  4, 24, 13
    defb  6,136,  3, 20, 15
    defb #FF
;; ===========================================================================
;; The flat. Ten rooms, bottom to top: the cat works its way up from the
;; basement to the kitchen, where the fridge is.
;;
;; Every room is the same shape underneath - a floor, four or five platforms a
;; jump apart, five sausages, three enemies and a way out - and different on
;; top, because the furniture that dresses it is different. tools/roomcheck.py
;; walks these tables and refuses a room the cat cannot climb.
;; ===========================================================================

CAT_FLOOR       EQU FLOOR_Y-SPR_CAT_STAND_H
SAUS_ON         EQU SPR_SAUSAGE_H       ; a sausage sits this far above its shelf
MILK_ON         EQU SPR_MILK_H          ; and so does a saucer
ROBOT_ON        EQU SPR_ROBOT_H

rooms
    ;; --- 1: the basement ---------------------------------------------------
    defb MSG_ROOM1
    defw r1_plat, r1_saus
    defb 5
    defw r1_enem
    defb 3
    defw r1_props
    defb 76, 56                     ; the door out, against the right wall
    defb 78, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 4, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

    ;; --- 2: the garage -----------------------------------------------------
    defb MSG_ROOM2
    defw r2_plat, r2_saus
    defb 5
    defw r2_enem
    defb 3
    defw r2_props
    defb 0, 56                      ; back into the house, on the left
    defb 2, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 88, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 5               ; concrete

    ;; --- 3: the garden -----------------------------------------------------
    defb MSG_ROOM3
    defw r3_plat, r3_saus
    defb 5
    defw r3_enem
    defb 3
    defw r3_props
    defb 76, 56
    defb 78, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 4, CAT_FLOOR
    defb 54, SHELF_2-MILK_ON        ; the saucer, out on the low branch
    defb PAL_INDOOR, 8               ; a garden at three in the morning

    ;; --- 4: the entrance hall ----------------------------------------------
    defb MSG_ROOM4
    defw r4_plat, r4_saus
    defb 5
    defw r4_enem
    defb 3
    defw r4_props
    defb 0, 56
    defb 2, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 88, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

    ;; --- 5: the bedroom ----------------------------------------------------
    defb MSG_ROOM5
    defw r5_plat, r5_saus
    defb 5
    defw r5_enem
    defb 3
    defw r5_props
    defb 66, 60                     ; the way on is through the wardrobe
    defb 68, 176, 26, 60, PROP_WARDROBE, PROP_WARDROBEOPEN
    defb 4, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

    ;; --- 6: inside the wardrobe --------------------------------------------
    defb MSG_ROOM6
    defw r6_plat, r6_saus
    defb 5
    defw r6_enem
    defb 3
    defw r6_props
    defb 80, 84                     ; a vent in the back panel, up on the shelf
    defb 80, 84, 6, 24, PROP_VENT, PROP_VENTOPEN
    defb 4, CAT_FLOOR
    defb 70, SHELF_4-MILK_ON        ; the saucer, up where the robot is
    defb PAL_INDOOR, 3

    ;; --- 7: the bathroom ---------------------------------------------------
    defb MSG_ROOM7
    defw r7_plat, r7_saus
    defb 5
    defw r7_enem
    defb 3
    defw r7_props
    defb 0, 56
    defb 2, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 88, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

    ;; --- 8: the study ------------------------------------------------------
    defb MSG_ROOM8
    defw r8_plat, r8_saus
    defb 5
    defw r8_enem
    defb 3
    defw r8_props
    defb 76, 56
    defb 78, 176, 16, 60, PROP_DOOR, PROP_DOOROPEN
    defb 4, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

    ;; --- 9: the living room ------------------------------------------------
    defb MSG_ROOM9
    defw r9_plat, r9_saus
    defb 5
    defw r9_enem
    defb 3
    defw r9_props
    ;; the way out is the vent at the top of the bookshelf, not a door on the
    ;; floor: the last sausage is up there, and sending the player all the way
    ;; back down to leave is just walking
    defb 86, SHELF4-24
    defb 86, SHELF4-24, 6, 24, PROP_VENT, PROP_VENTOPEN
    defb 4, CAT_FLOOR
    defb 36, SHELF3-MILK_ON         ; the saucer, along from the sausage
    defb PAL_INDOOR, 3

    ;; --- 10: the kitchen ---------------------------------------------------
    defb MSG_ROOM10
    defw r10_plat, r10_saus
    defb 5
    defw r10_enem
    defb 3
    defw r10_props
    ;; only the lower half of the Pitsos counts: the whole game ends with the
    ;; cat walking into it, not standing on top of it
    defb 78, FLOOR_Y-136
    defb 78, 170, 12, 66, PROP_FRIDGE, PROP_FRIDGEOPEN
    defb 4, CAT_FLOOR
    defb NO_MILK, 0
    defb PAL_INDOOR, 3

;; ---------------------------------------------------------------------------
;; 1 - the basement. Steel shelving on the left, packing crates in the middle,
;; the water heater on the right, and the stairs are a door you have to climb
;; back down to. Everything the flat has stopped using lives here.
;; ---------------------------------------------------------------------------
r1_plat
    defb  0, 95, FLOOR_Y
    defb  2, 26, SHELF_1                ; the rack's lower shelf
    defb 28, 52, SHELF_2                ; on top of the crates
    defb  2, 26, SHELF_3                ; the rack's upper shelf
    defb 56, 74, SHELF_3                ; and the top of the heater
    defb #FF

r1_saus
    defb 46, FLOOR_Y-SAUS_ON
    defb  8, SHELF_1-SAUS_ON
    defb 36, SHELF_2-SAUS_ON
    defb 10, SHELF_3-SAUS_ON
    defb 60, SHELF_3-SAUS_ON

r1_enem
    ;; type, x, y, dx, first column, last column, top of the canary's arc
    defb ET_ROBOT,  44, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  60, SHELF_3-ROBOT_ON, -1, 56, 74-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 20, 44,                1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r1_props
    defb PROP_RACK,    2, FLOOR_Y-160
    defb PROP_CRATES, 28, SHELF_2
    defb PROP_BOILER, 56, SHELF_3
    defb #FF

;; ---------------------------------------------------------------------------
;; 2 - the garage. The car is the staircase: bonnet, then roof, then the shelf
;; under the tool board. You go back into the house by the side door, so this
;; room runs right to left.
;; ---------------------------------------------------------------------------
G_ROOF          EQU 182                 ; the car's cabin, and its bonnet is
G_BONNET        EQU G_ROOF+26           ; the step up onto it
G_SHELF         EQU G_ROOF-32
G_HIGH          EQU G_SHELF-32

r2_plat
    defb  0, 95, FLOOR_Y
    defb 24, 36, SHELF_1                ; the tyre stack
    defb 40, 56, G_BONNET
    defb 56, 88, G_ROOF
    defb 26, 54, G_SHELF
    defb 56, 88, G_HIGH
    defb #FF

r2_saus
    defb 66, FLOOR_Y-SAUS_ON
    defb 28, SHELF_1-SAUS_ON
    defb 70, G_ROOF-SAUS_ON
    defb 34, G_SHELF-SAUS_ON
    defb 70, G_HIGH-SAUS_ON

r2_enem
    defb ET_ROBOT,  50, FLOOR_Y-ROBOT_ON, -1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  30, G_SHELF-ROBOT_ON,  1, 26, 54-SPR_ROBOT_W+1,          0
    defb ET_CANARY, 60, 44,               -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r2_props
    defb PROP_DOOR,       0, 56
    defb PROP_TYRES,     24, SHELF_1
    defb PROP_CAR,       40, G_ROOF
    defb PROP_TOOLBOARD, 28, G_SHELF-46
    defb #FF

;; ---------------------------------------------------------------------------
;; 3 - the garden. Over the fence and up the lemon tree; the back door is on
;; the right, past the shrub.
;; ---------------------------------------------------------------------------
r3_plat
    defb  0, 95, FLOOR_Y
    defb  4, 28, SHELF_1                ; the top of the fence
    defb 30, 64, SHELF_2                ; the low branch
    defb 14, 44, SHELF_3
    defb 46, 78, SHELF_4
    defb #FF

r3_saus
    defb 52, FLOOR_Y-SAUS_ON
    defb 10, SHELF_1-SAUS_ON
    defb 36, SHELF_2-SAUS_ON
    defb 20, SHELF_3-SAUS_ON
    defb 60, SHELF_4-SAUS_ON

r3_enem
    defb ET_ROBOT,  40, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  50, SHELF_2-ROBOT_ON, -1, 30, 64-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 30, 60,                1,  4, BYTES_PER_LINE-SPR_CANARY_W, 60

r3_props
    defb PROP_FENCE,  4, SHELF_1
    defb PROP_TREE,  30, FLOOR_Y-160
    defb PROP_BUSH,  60, FLOOR_Y-36
    defb PROP_DOOR,  76, 56
    defb #FF

;; ---------------------------------------------------------------------------
;; 4 - the entrance hall. In off the street: shoe rack, the stairs, the coat
;; stand, and the door into the flat proper on the left.
;; ---------------------------------------------------------------------------
r4_plat
    defb  0, 95, FLOOR_Y
    defb 66, 86, SHELF_1                ; the shoe rack
    defb 46, 82, SHELF_2                ; the half landing
    defb 22, 48, SHELF_3
    defb 50, 76, SHELF_4
    defb #FF

r4_saus
    defb 40, FLOOR_Y-SAUS_ON
    defb 72, SHELF_1-SAUS_ON
    defb 60, SHELF_2-SAUS_ON
    defb 28, SHELF_3-SAUS_ON
    defb 58, SHELF_4-SAUS_ON

r4_enem
    defb ET_ROBOT,  40, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  60, SHELF_2-ROBOT_ON, -1, 46, 82-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 70, 50,               -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 50

r4_props
    defb PROP_DOOR,    0, 56
    defb PROP_SHOES,  66, SHELF_1
    defb PROP_STAIRS, 46, SHELF_2
    defb PROP_COATS,  24, FLOOR_Y-88
    defb #FF

;; ---------------------------------------------------------------------------
;; 5 - the bedroom. Up the bed to the window ledge, and out through the
;; wardrobe rather than the door: the cat knows a short cut.
;; ---------------------------------------------------------------------------
r5_plat
    defb  0, 95, FLOOR_Y
    defb  8, 44, SHELF_1                ; the bed
    defb 14, 42, SHELF_2                ; the window ledge
    defb 44, 64, SHELF_3
    defb 20, 46, SHELF_4
    defb #FF

r5_saus
    defb 44, FLOOR_Y-SAUS_ON
    defb 20, SHELF_1-SAUS_ON
    defb 26, SHELF_2-SAUS_ON
    defb 50, SHELF_3-SAUS_ON
    defb 30, SHELF_4-SAUS_ON

r5_enem
    defb ET_ROBOT,  50, FLOOR_Y-ROBOT_ON, -1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  20, SHELF_1-ROBOT_ON,  1, 8, 44-SPR_ROBOT_W+1,           0
    defb ET_CANARY, 60, 48,               -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 48

r5_props
    defb PROP_BED,      8, SHELF_1
    defb PROP_WINDOW,  14, SHELF_2-96
    defb PROP_DRAWERS, 48, FLOOR_Y-60
    defb #FF

;; ---------------------------------------------------------------------------
;; 6 - inside the wardrobe. Shoe boxes, the hanging rail, the shelf above it,
;; and a vent in the back panel that nobody has noticed in twenty years.
;; ---------------------------------------------------------------------------
r6_plat
    defb  0, 95, FLOOR_Y
    defb  8, 28, SHELF_1                ; the shoe boxes
    defb 30, 62, SHELF_2                ; the hanging rail
    defb 10, 40, SHELF_3
    defb 42, 80, SHELF_4
    defb #FF

r6_saus
    defb 88, FLOOR_Y-SAUS_ON
    defb 14, SHELF_1-SAUS_ON
    defb 44, SHELF_2-SAUS_ON
    defb 20, SHELF_3-SAUS_ON
    defb 60, SHELF_4-SAUS_ON

r6_enem
    defb ET_ROBOT,  40, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  50, SHELF_4-ROBOT_ON, -1, 42, 80-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 20, 56,                1,  4, BYTES_PER_LINE-SPR_CANARY_W, 56

r6_props
    defb PROP_SHOEBOX,  8, SHELF_1
    defb PROP_RAIL,    30, SHELF_2
    defb PROP_CASES,   64, FLOOR_Y-40
    defb #FF

;; ---------------------------------------------------------------------------
;; 7 - the bathroom. The floor is too far from the bath to jump, so the route
;; is the toilet lid first, then the rim, then the basin.
;; ---------------------------------------------------------------------------
B_BATH          EQU 196
B_BASIN         EQU 172
B_MIRROR        EQU 140
B_HIGH          EQU 108

r7_plat
    defb  0, 95, FLOOR_Y
    defb 24, 36, SHELF_1                ; the toilet lid
    defb 40, 72, B_BATH                 ; the rim of the bath
    defb 74, 92, B_BASIN
    defb 66, 92, B_MIRROR
    defb 38, 66, B_HIGH
    defb #FF

r7_saus
    defb 20, FLOOR_Y-SAUS_ON
    defb 28, SHELF_1-SAUS_ON
    defb 52, B_BATH-SAUS_ON
    defb 78, B_BASIN-SAUS_ON
    defb 46, B_HIGH-SAUS_ON

r7_enem
    defb ET_ROBOT,  50, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  80, B_BASIN-ROBOT_ON, -1, 74, 92-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 40, 52,                1,  4, BYTES_PER_LINE-SPR_CANARY_W, 52

r7_props
    defb PROP_DOOR,    0, 56
    defb PROP_TOILET, 24, SHELF_1
    defb PROP_BATH,   40, B_BATH
    defb PROP_BASIN,  74, B_BASIN
    defb #FF

;; ---------------------------------------------------------------------------
;; 8 - the study. Desk, the shelf over it, then the bookcase.
;; ---------------------------------------------------------------------------
r8_plat
    defb  0, 95, FLOOR_Y
    defb 12, 42, SHELF_1                ; the desk
    defb 16, 44, SHELF_2                ; the shelf above it
    defb 46, 74, SHELF_3                ; bookcase, third shelf down
    defb 46, 74, SHELF_4
    defb #FF

r8_saus
    defb 56, FLOOR_Y-SAUS_ON
    defb 20, SHELF_1-SAUS_ON
    defb 24, SHELF_2-SAUS_ON
    defb 52, SHELF_3-SAUS_ON
    defb 64, SHELF_4-SAUS_ON

r8_enem
    defb ET_ROBOT,  50, FLOOR_Y-ROBOT_ON, 1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  60, SHELF_3-ROBOT_ON, -1, 46, 74-SPR_ROBOT_W+1,         0
    defb ET_CANARY, 30, 48,                1,  4, BYTES_PER_LINE-SPR_CANARY_W, 48

r8_props
    defb PROP_DESK,     12, SHELF_1
    defb PROP_BOOKCASE, 44, FLOOR_Y-160
    defb PROP_DOOR,     76, 56
    defb #FF

;; ---------------------------------------------------------------------------
;; 9 - the living room. A wall of bookshelves, the sofa tucked under them and
;; the telly in the gap between.
;;
;; Its collision geometry is frozen: the scripted run in make check depends on
;; every shelf, sausage and patrol being exactly where it is. Furniture is
;; decoration and can move freely.
;; ---------------------------------------------------------------------------
SHELF1          EQU FLOOR_Y-32
SHELF2          EQU FLOOR_Y-64
SHELF3          EQU FLOOR_Y-96
SHELF4          EQU FLOOR_Y-128

r9_plat
    defb 0,  95, FLOOR_Y
    defb 4,  34, SHELF1
    defb 54, 86, SHELF2
    defb 14, 44, SHELF3
    defb 60, 90, SHELF4
    defb #FF

r9_saus
    defb 46, FLOOR_Y-SPR_SAUSAGE_H
    defb 10, SHELF1-SPR_SAUSAGE_H
    defb 78, SHELF2-SPR_SAUSAGE_H
    defb 20, SHELF3-SPR_SAUSAGE_H
    defb 84, SHELF4-SPR_SAUSAGE_H

r9_enem
    ;; type, x, y, dx, first column, last column, top of the canary's arc
    defb ET_ROBOT,  40, FLOOR_Y-SPR_ROBOT_H,  1,  0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    ;; the shelf 2 robot patrols only the right half, so there is always a
    ;; safe place to land coming up from shelf 1
    defb ET_ROBOT,  70, SHELF2-SPR_ROBOT_H,  -1, 64, 86-SPR_ROBOT_W+1,            0
    defb ET_CANARY, 20, 44,                   1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r9_props
    defb PROP_WINDOW, 18, 24
    defb PROP_SOFA,   54, FLOOR_Y-58
    defb PROP_TV,     38, FLOOR_Y-56
    defb #FF

;; ---------------------------------------------------------------------------
;; 10 - the kitchen, and the fridge. A worktop is 90 cm off the floor, which
;; is two jumps, so the bin is not decoration: it is the only way up. The hob
;; sits level with the worktop, the way a freestanding cooker does.
;; ---------------------------------------------------------------------------
K_BIN           EQU SHELF_1
K_WORKTOP       EQU SHELF_2
K_SHELF         EQU SHELF_3
K_FRIDGE        EQU FLOOR_Y-136

r10_plat
    defb  0, 95, FLOOR_Y
    defb 28, 40, K_BIN
    defb  0, 25, K_WORKTOP              ; the run of units
    defb 44, 56, K_WORKTOP              ; and the hob, level with it
    defb  4, 30, K_SHELF                ; the wall cupboard
    defb 46, 74, K_SHELF                ; and the shelf beside it
    defb #FF

r10_saus
    defb 60, FLOOR_Y-SAUS_ON
    defb 32, K_BIN-SAUS_ON
    defb 16, K_WORKTOP-SAUS_ON
    defb 12, K_SHELF-SAUS_ON
    defb 58, K_SHELF-SAUS_ON

r10_enem
    defb ET_ROBOT,  60, FLOOR_Y-ROBOT_ON, -1, 0, BYTES_PER_LINE-SPR_ROBOT_W, 0
    defb ET_ROBOT,  50, K_SHELF-ROBOT_ON,  1, 46, 74-SPR_ROBOT_W+1,          0
    defb ET_CANARY, 40, 44,               -1,  4, BYTES_PER_LINE-SPR_CANARY_W, 44

r10_props
    defb PROP_WINDOW,  52, 24
    defb PROP_BIN,     28, K_BIN
    defb PROP_WORKTOP,  0, K_WORKTOP-6
    defb PROP_COOKER,  44, K_WORKTOP
    defb #FF
