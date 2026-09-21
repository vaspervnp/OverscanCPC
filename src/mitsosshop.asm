;; ===========================================================================
;; mitsosshop.asm - where the shop's shelves are, in scanlines.
;;
;; Its own file because two assemblies need it: the game, and the pass in
;; mitsoslow.asm that weighs the low block. The box lists that draw the
;; shelving and the table that stocks it are down there now, and they are
;; written in these numbers.
;; ===========================================================================

;; --- The shop --------------------------------------------------------------
;; Scanlines down and bytes across. A byte is two mode 0 pixels, which is four
;; pixels on the monitor, so the 96 bytes of a line are the full 384.
FLOOR_TOP       EQU 236                 ; the tiles start here
DADO_TOP        EQU 188                 ; and the painted lower wall here
GROUT_STEP      EQU 8                   ; a floor tile is this many bytes
SOAP_H          EQU 10                  ; how deep a puddle of it looks

;; The wall is brick, and at this scale a course is about
;; a hand's width: 16 scanlines to a course, 8 bytes to a brick - 32 pixels on
;; the monitor - and every other course offset by half a brick, which is what
;; makes it read as a wall rather than as a grid. The joints are a byte wide
;; because a byte is the narrowest thing a fill can put down: two mode 0
;; pixels, four on the tube.
BRICK_COURSE    EQU 16
BRICK_MORTAR    EQU 2
BRICK_W         EQU 8

;; The shelf boards, the counter top and the crate lids are all pen 2, and
;; they are 32 scanlines apart, because that is what a cat clears in a jump.
;; "Butter yellow means you can stand on it" is the visual grammar of both
;; games on this engine and it does not change from room to room.
SHELF_1         EQU 204
SHELF_2         EQU 172
SHELF_3         EQU 140
SHELF_4         EQU 108